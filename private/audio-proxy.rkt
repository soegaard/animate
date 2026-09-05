#lang racket/base

;;;
;;; Cached Preview-Audio Proxy Preparation
;;;

;; The plan is pure. This adapter is the only layer that invokes FFmpeg and
;; writes a proxy/Waveform cache. It gives preview and final assembly a shared
;; cue interpretation while keeping missing tools/files diagnosable before a
;; preview window opens.

(require racket/file
         racket/list
         racket/path
         racket/system
         file/sha1
         "audio-filter-graph.rkt"
         "audio-plan.rkt"
         "waveform.rkt")

(provide (struct-out audio-proxy-report)
         preview-audio-proxy-cache-key
         prepare-preview-audio-proxy!)

(struct audio-proxy-report (plan proxy-path waveform-path reused? diagnostics)
  #:transparent)

(define (prepare-preview-audio-proxy! plan
                                      #:ffmpeg [ffmpeg (find-executable-path "ffmpeg")]
                                      #:force? [force? #f])
  (unless (preview-audio-plan? plan)
    (raise-argument-error 'prepare-preview-audio-proxy! "preview-audio-plan?" plan))
  (unless (or (not ffmpeg) (path-string? ffmpeg))
    (raise-argument-error 'prepare-preview-audio-proxy! "#f or path-string?" ffmpeg))
  (unless (boolean? force?)
    (raise-argument-error 'prepare-preview-audio-proxy! "boolean?" force?))
  (define proxy (preview-audio-plan-proxy-path plan))
  (unless proxy
    (raise-arguments-error 'prepare-preview-audio-proxy!
                           "a preview-audio-plan with #:proxy-path"
                           "plan" plan))
  (define waveform (preview-audio-plan-waveform-path plan))
  (define cues (preview-audio-plan-cue-plan plan))
  (cond
    [(null? cues)
     ;; Avoid inventing a silent proxy for a timeline with no authored audio.
     ;; A client can distinguish this usable visual-only state through the
     ;; explicit diagnostic.
     (audio-proxy-report plan #f #f #t
                         (list "timeline declares no authored audio cues"))]
    [else
     (unless ffmpeg
       (raise-arguments-error 'prepare-preview-audio-proxy!
                              "FFmpeg available on PATH" "executable" "ffmpeg"))
     (for ([cue (in-list cues)])
       (unless (file-exists? (preview-audio-cue-source cue))
         (raise-arguments-error 'prepare-preview-audio-proxy!
                                "an existing authored audio source"
                                "source" (preview-audio-cue-source cue))))
     (define cache-key (preview-audio-proxy-cache-key plan))
     (define cache-key-path (preview-audio-proxy-cache-key-path proxy))
     (cond
       [(and (not force?)
             (file-exists? proxy)
             (or (not waveform) (file-exists? waveform))
             (preview-audio-proxy-cache-key-valid? cache-key-path cache-key))
        (audio-proxy-report plan proxy waveform #t '())]
       [else
     (make-directory* (or (path-only proxy) (current-directory)))
     ;; Leave a valid old proxy alone until its replacement has been fully
     ;; mixed and decoded for waveform generation. A failed FFmpeg run then
     ;; produces a cache miss next time, not a partially written WAV accepted
     ;; as fresh audio.
     (define proxy-partial (preview-audio-proxy-partial-path proxy))
     (when (file-exists? proxy-partial) (delete-file proxy-partial))
     (define arguments
       (append (list "-y")
               (audio-input-arguments cues)
               (list "-filter_complex" (preview-audio-filter-graph plan)
                     "-map" "[mix]"
                     "-ar" (number->string (preview-audio-plan-sample-rate plan))
                     "-ac" (number->string (preview-audio-plan-channels plan))
                     "-c:a" "pcm_s16le"
                     ;; The atomic staging name intentionally ends in
                     ;; `.partial`, so select the documented WAV container
                     ;; explicitly instead of asking FFmpeg to infer it from
                     ;; a filename extension.
                     "-f" "wav"
                     (path-string->string proxy-partial))))
     (unless (apply system* ffmpeg arguments)
       (raise-arguments-error 'prepare-preview-audio-proxy!
                              "FFmpeg completed audio proxy preparation"
                              "proxy-path" proxy))
     ;; The proxy format above is fixed PCM s16le WAV, so peak extraction is
     ;; deterministic and does not need to invoke a second decoder. The
     ;; persisted datum contains multiple resolutions chosen by the timeline
     ;; according to its current zoom.
     (when waveform
       (write-waveform-file (waveform-from-wav-file proxy-partial) waveform))
     (rename-file-or-directory proxy-partial proxy #t)
     (write-preview-audio-proxy-cache-key! cache-key-path cache-key)
     (audio-proxy-report plan proxy waveform #f '())])]))

;; The pure plan records the cue declarations. This adapter adds source-content
;; hashes at preparation time, when reading files is permitted, so replacing a
;; WAV in place cannot reuse a stale mixed proxy.
(define (preview-audio-proxy-cache-key plan)
  (unless (preview-audio-plan? plan)
    (raise-argument-error 'preview-audio-proxy-cache-key "preview-audio-plan?" plan))
  (list 'animate-preview-audio-proxy-cache-v2
        (preview-audio-plan-fingerprint plan)
        (for/list ([cue (in-list (preview-audio-plan-cue-plan plan))])
          (define source (preview-audio-cue-source cue))
          (unless (file-exists? source)
            (raise-arguments-error 'preview-audio-proxy-cache-key
                                   "an existing authored audio source"
                                   "source" source))
          (list (path-string->string source)
                (call-with-input-file source sha1)))))

(define (preview-audio-proxy-cache-key-path proxy)
  (string->path
   (string-append (path-string->string proxy) ".animate-audio-cache.rktd")))

(define (preview-audio-proxy-partial-path proxy)
  (define path (if (path? proxy) proxy (string->path proxy)))
  (build-path (or (path-only path) (current-directory))
              (string-append "."
                             (path->string (file-name-from-path path))
                             ".partial")))

(define (preview-audio-proxy-cache-key-valid? path key)
  (and (file-exists? path)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (equal? (call-with-input-file path read) key))))

(define (write-preview-audio-proxy-cache-key! path key)
  (define partial (string->path (string-append (path-string->string path) ".partial")))
  (when (file-exists? partial) (delete-file partial))
  (call-with-output-file partial
    (lambda (out) (write key out) (newline out))
    #:exists 'truncate/replace)
  (rename-file-or-directory partial path #t))

(define (audio-input-arguments cues)
  (append*
   (for/list ([cue (in-list cues)])
     (append (list "-ss" (number->string (preview-audio-cue-source-start cue)))
             (if (preview-audio-cue-duration cue)
                 (list "-t" (number->string (preview-audio-cue-duration cue)))
                 '())
             (list "-i" (path-string->string (preview-audio-cue-source cue)))))))

(define (path-string->string value)
  (if (path? value) (path->string value) value))
