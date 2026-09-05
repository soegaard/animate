#lang racket/base

;;;
;;; Shared Authored-Audio Filter Graph
;;;

(require racket/list
         racket/string
         "audio-plan.rkt")

(provide preview-audio-filter-graph)

;; Produces the FFmpeg filter expression for the normalized preview plan.  It
;; is deliberately shared-model friendly: final assembly can adopt it without
;; reinterpreting authored audio placement metadata.
(define (preview-audio-filter-graph plan)
  (unless (preview-audio-plan? plan)
    (raise-argument-error 'preview-audio-filter-graph "preview-audio-plan?" plan))
  (define cues (preview-audio-plan-cue-plan plan))
  (cond
    [(null? cues) #f]
    [else
     (define chains
       (for/list ([cue (in-list cues)] [index (in-naturals)])
         (string-append
          (format "[~a:a]" index)
          "asetpts=PTS-STARTPTS"
          (format ",volume=~a" (number->string (preview-audio-cue-gain cue)))
          (if (positive? (preview-audio-cue-fade-in cue))
              (format ",afade=t=in:st=0:d=~a"
                      (number->string (preview-audio-cue-fade-in cue)))
              "")
          (if (positive? (preview-audio-cue-fade-out cue))
              (format ",afade=t=out:st=~a:d=~a"
                      (number->string
                       (- (preview-audio-cue-duration cue)
                          (preview-audio-cue-fade-out cue)))
                      (number->string (preview-audio-cue-fade-out cue)))
              "")
          (format ",adelay=~a:all=1[a~a]"
                  (inexact->exact (round (* 1000 (preview-audio-cue-start cue)))) index))))
     ;; FFmpeg filter chains are separated by semicolons. Concatenating the
     ;; output label of one chain directly with the next input label happens
     ;; to look plausible as a string but is invalid filtergraph syntax.
     (string-append (string-join chains ";") ";"
                    (apply string-append
                           (for/list ([index (in-range (length cues))])
                             (format "[a~a]" index)))
                    ;; A proxy is a seekable representation of the complete
                    ;; authored timeline. Pad a short final cue with silence
                    ;; before trimming, rather than making ffplay's duration
                    ;; accidentally depend on its last audible sample.
                    (format "amix=inputs=~a:duration=longest,apad,atrim=duration=~a[mix]"
                            (length cues)
                            (number->string (preview-audio-plan-duration plan))))]))
