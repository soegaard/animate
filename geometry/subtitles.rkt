#lang racket/base

;; Adapter to Animate's public authoring/render APIs. Geometry determines the
;; effective narration; Animate owns subtitle values, time formatting, SRT/VTT
;; syntax, and MP4 mov_text muxing. Native modules are loaded only when the
;; corresponding API is used.
(require racket/file racket/path racket/runtime-path racket/string racket/system
         "private/data.rkt" "captions.rkt")
(provide geometry-timeline->subtitles geometry-timeline->authored-timeline
         write-geometry-subtitles! mux-geometry-subtitles-into-mp4!)

(define-runtime-path authoring-module "../authoring.rkt")
(define-runtime-path animate-module "../main.rkt")
(define-runtime-path render-module "../render.rkt")
(define-runtime-path geometry-adapter "animate.rkt")

(define (check-timeline who timeline)
  (unless (geometry-timeline? timeline)
    (raise-argument-error who "geometry-timeline?" timeline)))

;; Exact seconds are retained here. Millisecond rounding is Animate's writer's
;; job; the conversion never rounds to a movie frame grid. Blank captions leave
;; silent gaps instead of creating invalid empty SRT/WebVTT blocks.
(define (geometry-timeline->subtitles timeline)
  (check-timeline 'geometry-timeline->subtitles timeline)
  (define cues (geometry-caption-cues timeline))
  (define subtitle (dynamic-require authoring-module 'subtitle))
  (for/list ([c (in-list cues)]
             #:unless (string=? (string-trim (geometry-cue-text c)) ""))
    (subtitle (geometry-cue-start c) (geometry-cue-end c) (geometry-cue-text c))))

;; A real Animate authored timeline containing the geometry scene AND its
;; narration metadata. Captions remain ON unless explicitly switched off.
(define (geometry-timeline->authored-timeline timeline
                                             #:width [width 1280] #:height [height 720]
                                             #:captions? [captions? #t]
                                             #:labels [labels (hash)])
  (check-timeline 'geometry-timeline->authored-timeline timeline)
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height)
               (boolean? captions?) (hash? labels))
    (raise-arguments-error 'geometry-timeline->authored-timeline "invalid scene options"
                           "width" width "height" height "captions?" captions? "labels" labels))
  (define subtitles (geometry-timeline->subtitles timeline))
  (define make-authored-timeline (dynamic-require authoring-module 'make-authored-timeline))
  (define make-scene (dynamic-require geometry-adapter 'geometry-timeline->scene))
  (make-authored-timeline
   (make-scene timeline #:width width #:height height #:captions? captions? #:labels labels)
   #:subtitles subtitles))

;; A timing-only authored timeline is sufficient for subtitle serialization and
;; muxing. It deliberately avoids rebuilding the geometry visual/layout just to
;; attach metadata to an already encoded MP4.
(define (geometry-timeline->subtitle-metadata-timeline timeline)
  (check-timeline 'geometry-timeline->subtitle-metadata-timeline timeline)
  (define make-scene (dynamic-require animate-module 'make-scene))
  (define scene-wait (dynamic-require animate-module 'scene-wait))
  (define make-authored-timeline (dynamic-require authoring-module 'make-authored-timeline))
  (make-authored-timeline
   (scene-wait (make-scene) (geometry-timeline-duration timeline))
   #:subtitles (geometry-timeline->subtitles timeline)))

;; Preserve the original geometry writer name, now delegating to Animate.
;; Write to a sibling temporary file, then publish; failed writes leave the old
;; sidecar intact. This wraps (rather than duplicates) Animate's serializer.
(define (write-geometry-subtitles! timeline path #:format [format 'srt])
  (check-timeline 'write-geometry-subtitles! timeline)
  (unless (path-string? path)
    (raise-argument-error 'write-geometry-subtitles! "path-string?" path))
  (unless (memq format '(srt webvtt))
    (raise-argument-error 'write-geometry-subtitles! "'srt or 'webvtt" format))
  (define authored (geometry-timeline->subtitle-metadata-timeline timeline))
  (define write-subtitles! (dynamic-require render-module 'write-subtitles!))
  (define destination (simplify-path (path->complete-path path)))
  (when (or (directory-exists? destination) (link-exists? destination))
    (raise-arguments-error 'write-geometry-subtitles!
                           "destination must be a regular file, not a directory or link"
                           "path" path))
  (define parent (path-only destination))
  (make-directory* parent)
  (define temporary (make-temporary-file ".geometry-subtitles-~a" #f parent))
  (dynamic-wind
   void
   (lambda ()
     (write-subtitles! authored temporary #:format format)
     (rename-file-or-directory temporary destination #t)
     path)
   (lambda () (when (file-exists? temporary) (delete-file temporary)))))

#| mux-geometry-subtitles-into-mp4! : geometry-timeline? path-string? path-string?
                                      [#:language (or/c #f ISO-639-2-string?)]
                                      -> path-string?
Replaces MP4 with the same video stream plus an MP4 mov_text subtitle track.
The separate SRT remains untouched for YouTube upload. Animate still owns the
actual subtitle mux. Geometry then performs one stream-copy metadata pass so
players such as QuickTime can identify the subtitle language. No video or audio
stream is re-encoded. The replacement is atomic at the geometry boundary.
|#
(define (normalize-subtitle-language who language)
  (cond
    [(not language) #f]
    [(and (string? language) (regexp-match? #px"^[A-Za-z]{3}$" language))
     (string-downcase language)]
    [else
     (raise-argument-error who "#f or a three-letter ISO 639-2 language code" language)]))

(define (tag-mp4-subtitle-language! input output language)
  (define ffmpeg (find-executable-path "ffmpeg"))
  (unless ffmpeg
    (raise-arguments-error 'mux-geometry-subtitles-into-mp4!
                           "FFmpeg was not found on PATH"
                           "executable" "ffmpeg"))
  (unless
   (system* ffmpeg "-loglevel" "error" "-y"
            "-i" (path->string input)
            "-map" "0" "-c" "copy"
            "-metadata:s:s:0" (string-append "language=" language)
            "-movflags" "+faststart"
            (path->string output))
    (raise-arguments-error 'mux-geometry-subtitles-into-mp4!
                           "FFmpeg failed to tag the subtitle language"
                           "language" language
                           "input" input
                           "output" output)))

(define (mux-geometry-subtitles-into-mp4! timeline mp4-path srt-path
                                         #:language [language "eng"])
  (check-timeline 'mux-geometry-subtitles-into-mp4! timeline)
  (unless (path-string? mp4-path)
    (raise-argument-error 'mux-geometry-subtitles-into-mp4! "path-string?" mp4-path))
  (unless (path-string? srt-path)
    (raise-argument-error 'mux-geometry-subtitles-into-mp4! "path-string?" srt-path))
  (define normalized-language
    (normalize-subtitle-language 'mux-geometry-subtitles-into-mp4! language))
  (define mp4 (simplify-path (path->complete-path mp4-path)))
  (define srt (simplify-path (path->complete-path srt-path)))
  (unless (and (file-exists? mp4) (not (link-exists? mp4)))
    (raise-arguments-error 'mux-geometry-subtitles-into-mp4!
                           "an existing regular MP4 file" "mp4" mp4-path))
  (unless (and (file-exists? srt) (not (link-exists? srt)))
    (raise-arguments-error 'mux-geometry-subtitles-into-mp4!
                           "an existing regular SRT file" "srt" srt-path))
  (cond
    [(null? (geometry-timeline->subtitles timeline)) mp4-path]
    [else
     (define parent (path-only mp4))
     (define temporary-mux (make-temporary-file ".geometry-subtitled-~a.mp4" #f parent))
     (define temporary-tagged
       (and normalized-language
            (make-temporary-file ".geometry-subtitle-language-~a.mp4" #f parent)))
     (define mux-authored-video! (dynamic-require render-module 'mux-authored-video!))
     (define authored (geometry-timeline->subtitle-metadata-timeline timeline))
     (dynamic-wind
      void
      (lambda ()
        (mux-authored-video! authored mp4 temporary-mux #:subtitle-file srt)
        (define published
          (if normalized-language
              (begin
                (tag-mp4-subtitle-language! temporary-mux temporary-tagged normalized-language)
                temporary-tagged)
              temporary-mux))
        (rename-file-or-directory published mp4 #t)
        mp4-path)
      (lambda ()
        (when (file-exists? temporary-mux) (delete-file temporary-mux))
        (when (and temporary-tagged (file-exists? temporary-tagged))
          (delete-file temporary-tagged))))]))
