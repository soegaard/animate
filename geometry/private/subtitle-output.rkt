#lang racket/base

;; Common output planning for one-process renders, process-sharded renders,
;; and subtitle-only CLI exports. Never invoked in a frame-rendering worker.
(require racket/list racket/path "../subtitles.rkt")
(provide geometry-subtitle-output-plan geometry-mp4-subtitle-path
         write-geometry-subtitle-outputs!)

(define (canonical path) (simplify-path (path->complete-path path)))

;; The SRT used for the selectable MP4 subtitle track.  An explicit --srt path
;; is authoritative; otherwise MP4 output gets the adjacent same-basename SRT.
(define (geometry-mp4-subtitle-path mp4 [srt #f])
  (unless (or (not mp4) (path-string? mp4))
    (raise-argument-error 'geometry-mp4-subtitle-path "path-string? or #f" mp4))
  (unless (or (not srt) (path-string? srt))
    (raise-argument-error 'geometry-mp4-subtitle-path "path-string? or #f" srt))
  (and mp4 (canonical (or srt (path-replace-extension mp4 #".srt")))))

;; Return distinct (path . format) pairs. A legacy narration.srt in the frame
;; folder coexists with an MP4 sidecar. An explicit SRT path replaces the default
;; MP4 companion, NOT the legacy narration.srt. VTT is opt-in and additive.
(define (geometry-subtitle-output-plan #:directory [directory #f] #:mp4 [mp4 #f]
                                       #:srt [srt #f] #:vtt [vtt #f])
  (define who 'geometry-subtitles)
  (for ([value (in-list (list directory mp4 srt vtt))])
    (unless (or (not value) (path-string? value))
      (raise-argument-error who "path-string? or #f" value)))
  (define requests
    (append (if directory (list (cons (build-path directory "narration.srt") 'srt)) '())
            (cond [srt (list (cons srt 'srt))]
                  [mp4 (list (cons (path-replace-extension mp4 #".srt") 'srt))]
                  [else '()])
            (if vtt (list (cons vtt 'webvtt)) '())))
  (define seen (make-hash))
  (reverse
   (for/fold ([out '()]) ([entry (in-list requests)])
     (define path (canonical (car entry)))
     (define format (cdr entry))
     (when (and mp4 (equal? path (canonical mp4)))
       (raise-arguments-error who "subtitle file must not overwrite the MP4" "path" path))
     (when (or (directory-exists? path) (link-exists? path))
       (raise-arguments-error who "subtitle destination must be a regular file, not a directory or link" "path" path))
     (when (and directory (equal? (path-only path) (path->directory-path (canonical directory)))
                (let ([leaf (path->string (file-name-from-path path))])
                  (or (regexp-match? #rx"^frame-[0-9]+[.]png$" leaf) (equal? leaf "stills.tsv"))))
       (raise-arguments-error who "subtitle destination must not overwrite frame output" "path" path))
     (define previous (hash-ref seen path #f))
     (cond [(and previous (not (eq? previous format)))
            (raise-arguments-error who "SRT and WebVTT must use different files" "path" path)]
           [previous out]
           [else (hash-set! seen path format) (cons (cons path format) out)]))))

(define (write-geometry-subtitle-outputs! timeline plan)
  (for/list ([entry (in-list plan)])
    (write-geometry-subtitles! timeline (car entry) #:format (cdr entry))))
