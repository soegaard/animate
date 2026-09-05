#lang racket/base

;;;
;;; Authored Section Rendering
;;;

;; The immutable authoring timeline deliberately stops at section selection.
;; This module owns the file-system and bitmap effects required to materialize
;; that selection as PNG frames, subtitle files, and cache manifests.


;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/format
         racket/list
         racket/path
         file/sha1
         "../version.rkt"
         "authoring-timeline.rkt"
         "png-renderer.rkt"
         "shape-pict-renderers.rkt")

(provide write-subtitles!
         automatic-section-cache-key
         render-timeline-section!
         render-timeline-section/report!
         (struct-out section-render-report))


;;;
;;; Render Reports
;;;

(struct section-render-report
  (paths source-frame-indices cache-hit? diagnostics)
  #:transparent)

;; section-render-report records one selected-section render. diagnostics is a
;; render-diagnostics value on a fresh render and #f for a validated cache hit.


;;;
;;; Subtitle Output
;;;

;; write-subtitles! : authored-timeline? path-string?
;;                    [#:format (or/c 'srt 'webvtt)] -> path-string?
;; Writes portable subtitles for a later FFmpeg mux step. Text is stored
;; verbatim except that CRLF is normalized to LF, preserving intended line
;; breaks in both SRT and WebVTT.
(define (write-subtitles! timeline output-file #:format [format 'srt])
  (unless (authored-timeline? timeline)
    (raise-argument-error 'write-subtitles! "authored-timeline?" timeline))
  (unless (path-string? output-file)
    (raise-argument-error 'write-subtitles! "path-string?" output-file))
  (unless (memq format '(srt webvtt))
    (raise-argument-error 'write-subtitles! "'srt or 'webvtt" format))
  (call-with-output-file
   output-file
   (lambda (output)
     (when (eq? format 'webvtt)
       (display "WEBVTT\n\n" output))
     (for ([entry (in-list (authored-timeline-subtitles timeline))]
           [index (in-naturals 1)])
       (when (eq? format 'srt)
         (fprintf output "~a\n" index))
       (fprintf output "~a --> ~a\n"
                (subtitle-timestamp (subtitle-start entry) format)
                (subtitle-timestamp (subtitle-end entry) format))
       (display (normalize-subtitle-text (subtitle-text entry)) output)
       (display "\n\n" output)))
   #:exists 'truncate/replace)
  output-file)

(define (subtitle-timestamp seconds subtitle-format)
  (define milliseconds
    (inexact->exact (round (* 1000 seconds))))
  (define-values (whole-milliseconds ms)
    (quotient/remainder milliseconds 1000))
  (define-values (whole-seconds second)
    (quotient/remainder whole-milliseconds 60))
  (define-values (hour minute)
    (quotient/remainder whole-seconds 60))
  (format "~a:~a:~a~a~a"
          (~r hour #:min-width 2 #:pad-string "0")
          (~r minute #:min-width 2 #:pad-string "0")
          (~r second #:min-width 2 #:pad-string "0")
          (if (eq? subtitle-format 'srt) "," ".")
          (~r ms #:min-width 3 #:pad-string "0")))

(define (normalize-subtitle-text text)
  (regexp-replace* #px"\r\n?" text "\n"))


;;;
;;; Selected Rendering and Semantic Cache Keys
;;;

(define cache-file-name ".animate-section-cache.rktd")

;; Renders one named section to locally numbered PNGs. The default 'auto key
;; fingerprints serializable scene data, camera/renderers, release identity,
;; runtime, and declared asset files. Opaque procedures deliberately disable
;; automatic caching because their source cannot be fingerprinted reliably.
(define (render-timeline-section! timeline section-or-name output-directory
                                  #:fps [fps 30]
                                  #:camera [camera #f]
                                  #:renderers [renderers default-pict-renderers]
                                  #:clean? [clean? #t]
                                  #:workers [workers 1]
                                  #:cache-key [cache-key 'auto]
                                  #:asset-files [asset-files '()])
  (section-render-report-paths
   (render-timeline-section/report!
    timeline section-or-name output-directory
    #:fps fps
    #:camera camera
    #:renderers renderers
    #:clean? clean?
    #:workers workers
    #:cache-key cache-key
    #:asset-files asset-files)))

;; Renders a section or returns a validated cache hit. Output frames are named
;; from zero for direct use by encode-mp4!, while source-frame-indices records
;; their exact positions in the full scene timeline.
(define (render-timeline-section/report! timeline section-or-name output-directory
                                         #:fps [fps 30]
                                         #:camera [camera #f]
                                         #:renderers [renderers default-pict-renderers]
                                         #:clean? [clean? #t]
                                         #:workers [workers 1]
                                         #:cache-key [cache-key 'auto]
                                         #:asset-files [asset-files '()])
  (unless (path-string? output-directory)
    (raise-argument-error
     'render-timeline-section/report!
     "path-string?"
     output-directory))
  (check-cache-key 'render-timeline-section/report! cache-key)
  (check-asset-files 'render-timeline-section/report! asset-files)
  (define entry
    (timeline-section timeline section-or-name))
  (define source-indices
    (timeline-section-frame-indices timeline entry #:fps fps))
  (define effective-cache-key
    (if (eq? cache-key 'auto)
        (automatic-section-cache-key timeline entry
                                     #:fps fps #:camera camera
                                     #:renderers renderers
                                     #:asset-files asset-files)
        cache-key))
  (define expected-cache
    (section-cache-datum entry fps source-indices effective-cache-key))
  (define expected-paths
    (local-frame-paths output-directory (length source-indices)))
  (define cache-path
    (build-path output-directory cache-file-name))
  (cond
    [(and effective-cache-key
          (section-cache-valid? cache-path expected-cache expected-paths))
     (section-render-report expected-paths source-indices #t #f)]
    [else
     (when (and (not effective-cache-key)
                (file-exists? cache-path))
       (delete-file cache-path))
     (define diagnostics
       (render-frame-indices/report!
        (authored-timeline-scene timeline)
        source-indices
        output-directory
        #:fps fps
        #:camera camera
        #:renderers renderers
        #:clean? clean?
        #:workers workers))
     (when effective-cache-key
       (write-section-cache! cache-path expected-cache))
     (section-render-report
      (render-diagnostics-paths diagnostics)
      source-indices
      #f
      diagnostics)]))

;; Stores the resolved cache fingerprint. Automatic and explicit keys share one
;; manifest form, so changing modes cannot accidentally reuse stale PNGs.
(define (section-cache-datum entry fps source-indices cache-key)
  (list 'animate-section-cache-v3
        animate-version
        animate-stage
        cache-key
        fps
        (authoring-section-name entry)
        (authoring-section-start entry)
        (authoring-section-end entry)
        source-indices))

;; Reads a cache manifest conservatively; malformed/unreadable cache data is a
;; miss rather than an authoring error.
(define (section-cache-valid? cache-path expected expected-paths)
  (and (file-exists? cache-path)
       (with-handlers ([exn:fail? (lambda (_exception) #f)])
         (and (equal?
               (call-with-input-file cache-path read)
               expected)
              (andmap file-exists? expected-paths)))))

;; Writes one small, replaceable metadata datum after all PNG jobs succeed.
(define (write-section-cache! cache-path datum)
  (call-with-output-file
   cache-path
   (lambda (output)
     (write datum output)
     (newline output))
   #:exists 'truncate/replace)
  (void))

;; Mirrors png-renderer's local output filenames without exporting its internal
;; naming helper.
(define (local-frame-paths output-directory count)
  (for/list ([local-index (in-range count)])
    (build-path
     output-directory
     (format "frame-~a.png"
             (~r local-index #:min-width 6 #:pad-string "0")))))


;;;
;;; Automatic Semantic Fingerprints
;;;

;; Returns a stable content fingerprint when the compiled scene has no opaque
;; noncanonical procedure. A #f result is deliberate: caching a closure whose
;; source cannot be inspected would be worse than a predictable fresh render.
(define (automatic-section-cache-key timeline entry
                                     #:fps fps
                                     #:camera camera
                                     #:renderers renderers
                                     #:asset-files asset-files)
  (define scene-representation
    (format "~s" (authored-timeline-scene timeline)))
  (if (scene-representation-has-opaque-procedure? scene-representation)
      #f
      (let* ([asset-representation
              (for/list ([asset (in-list asset-files)])
                (list (path-string->portable-string asset)
                      (file-fingerprint asset)))]
             [payload
              (list 'animate-semantic-cache-v2
                    animate-version
                    animate-stage
                    scene-representation
                    (authoring-section-name entry)
                    (authoring-section-start entry)
                    (authoring-section-end entry)
                    fps
                    (format "~s" camera)
                    (format "~s" renderers)
                    (version)
                    asset-representation)])
        (string-append
         "auto:"
         (sha1 (open-input-string (format "~s" payload)))))))

;; Built-in rate functions are transparent semantic values, so their scene
;; representation has no procedure token. A printed name alone cannot prove the
;; implementation of a caller procedure, so any remaining procedure invalidates
;; rather than creating a cache key that could survive a source edit incorrectly.
(define (scene-representation-has-opaque-procedure? representation)
  (not (null?
        (regexp-match* #px"#<procedure(?::[^>]*)?>" representation))))

(define (file-fingerprint path-string)
  (if (file-exists? path-string)
      (call-with-input-file path-string sha1)
      'missing))

(define (path-string->portable-string value)
  (cond
    [(path? value) (path->string value)]
    [(string? value) value]
    [else (bytes->string/utf-8 value)]))


;;;
;;; Validation Helpers
;;;

(define (check-cache-key who cache-key)
  (unless (or (not cache-key)
              (eq? cache-key 'auto)
              (symbol? cache-key)
              (string? cache-key))
    (raise-argument-error
     who
     "(or/c false/c 'auto symbol? string?)"
     cache-key)))

(define (check-asset-files who asset-files)
  (unless (and (list? asset-files)
               (andmap path-string? asset-files))
    (raise-argument-error who "list of path-string?" asset-files)))
