#lang racket/base
(require racket/file racket/path racket/port racket/system json
         "data.rkt" "check.rkt")
(provide resolve-asset-path prepare-narration)
(define (resolve-asset-path source base fallback)
  (define p (if (path? source) source (string->path source)))
  (cond [(complete-path? p) p]
        [(or base fallback) (path->complete-path p (or base fallback))]
        [else (slides-error 'asset-base-required (list source)
                            "relative assets need a source module or an explicit #:asset-base")]))
(define (audio-duration! path)
  (unless (file-exists? path) (slides-error 'missing-asset (list (path->string path)) "audio file does not exist"))
  (define ffprobe (find-executable-path "ffprobe"))
  (unless ffprobe (slides-error 'missing-tool '(ffprobe) "recorded narration preparation requires ffprobe"))
  (define out (open-output-string)) (define err (open-output-string))
  (define code
    (parameterize ([current-output-port out] [current-error-port err])
      (system*/exit-code ffprobe "-v" "error" "-select_streams" "a:0"
                        "-show_entries" "stream=codec_type,duration:format=duration" "-of" "json" path)))
  (unless (zero? code) (slides-error 'audio-probe (list (path->string path)) "ffprobe could not read audio" (get-output-string err)))
  (define data (string->jsexpr (get-output-string out)))
  (define streams (hash-ref data 'streams '()))
  (unless (pair? streams) (slides-error 'missing-audio (list (path->string path)) "asset has no audio stream"))
  (define d (or (let ([x (hash-ref (car streams) 'duration #f)]) (and (string? x) (string->number x)))
                (let ([x (hash-ref (hash-ref data 'format (hash)) 'duration #f)]) (and (string? x) (string->number x)))))
  (unless (positive-number? d) (slides-error 'audio-duration (list (path->string path)) "audio has no finite positive duration"))
  d)
(define (prepare-narration n effects? base)
  (cond [(not n) #f]
        [else
         (define audio (narration-value-audio n))
         (when (and audio (not effects?))
           (slides-error 'preparation-required '(narration) "recorded narration requires prepare-slide! or prepare-storyboard!"))
         (define path (and audio (resolve-asset-path audio (narration-value-asset-base n) base)))
         (define length (if path (audio-duration! path) (narration-value-draft-duration n)))
         (define duration (or (narration-value-duration n) (- length (narration-value-source-start n))))
         (unless (and (positive-number? duration)
                      (<= (+ duration (narration-value-source-start n)) (+ length 1e-7)))
           (slides-error 'audio-trim '() "narration trim lies outside the recorded asset"))
         (define captions
           (or (narration-value-captions n)
               (if (string=? (narration-value-text n) "") '()
                   (list (list 0 duration (narration-value-text n))))))
         (for ([c (in-list captions)])
           (when (> (cadr c) (+ duration 1e-7))
             (slides-error 'caption-duration '() "caption extends beyond narration")))
         (prepared-narration (narration-value-text n) (and path (path->string path))
                             (narration-value-at n) duration (narration-value-source-start n) captions)]))
