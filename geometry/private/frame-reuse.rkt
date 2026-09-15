#lang racket/base

;;;
;;; Geometry Static-Frame Reuse
;;;

;; Computes geometry's semantic identical-frame relation without importing an
;; Animate renderer, filesystem API, or process adapter.  Generic rendering
;; consumes the resulting data; geometry remains responsible for its meaning.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "math.rkt"
         "data.rkt"
         "../timeline.rkt")

;; Exports
(provide geometry-frame-count
         geometry-frame-reuse-representatives)


;;;
;;; Frame Identity Planning
;;;

; geometry-frame-count : geometry-timeline? exact-positive-integer?
;                         -> exact-positive-integer?
;;   Returns the complete source-frame grid size using geometry's existing timing rule.
(define (geometry-frame-count timeline fps)
  (unless (and (geometry-timeline? timeline) (exact-positive-integer? fps))
    (geometry-error 'geometry-frame-count
                    "expected a geometry timeline and positive fps"))
  (max 1 (inexact->exact
          (ceiling (* fps (geometry-timeline-duration timeline))))))

; geometry-frame-reuse-representatives : geometry-timeline?
;                                        (listof exact-nonnegative-integer?)
;                                        exact-positive-integer? boolean?
;                                        -> (listof (list/c exact-nonnegative-integer?
;                                                            exact-nonnegative-integer?))
;;   Maps each requested source frame to its first equal visual representative.
(define (geometry-frame-reuse-representatives timeline frame-indices fps captions?)
  (unless (and (geometry-timeline? timeline)
               (list? frame-indices)
               (andmap exact-nonnegative-integer? frame-indices)
               (exact-positive-integer? fps)
               (boolean? captions?))
    (geometry-error 'geometry-frame-reuse-representatives
                    "invalid timeline, source frame indices, fps, or caption mode"))
  (define first-frame-by-key (make-hash))
  (define representatives '())
  (for ([frame-index (in-list frame-indices)])
    ;; `geometry-timeline->scene` drives its sampler through one linear
    ;; Animate parameter from zero to this timeline duration.  Preserve that
    ;; interpolation arithmetic here: sampling plain frame-index/fps can fall
    ;; on the opposite side of an inexact authored action boundary from the
    ;; actual rendered scene (for example, 15.8 versus 15.800000000000002).
    ;; This remains a pure geometry calculation while agreeing with the scene
    ;; clock that workers and the in-process renderer both use.
    (define grid-time (/ frame-index fps))
    (define duration (geometry-timeline-duration timeline))
    (define scene-clock-time
      (if (zero? duration)
          0
          (+ 0 (* (- duration 0) (/ grid-time duration)))))
    (define frame
      (sample-geometry-timeline timeline scene-clock-time))
    ;; Narration is a visual input only when geometry's caption layer is shown.
    ;; Subtitle metadata intentionally never participates in this key.
    (define visual-key
      (list (geometry-frame-appearances frame)
            (and captions? (geometry-frame-narration frame))))
    (define representative
      (hash-ref first-frame-by-key visual-key #f))
    (cond
      [representative
       (set! representatives
             (cons (list frame-index representative) representatives))]
      [else
       (hash-set! first-frame-by-key visual-key frame-index)
       (set! representatives
             (cons (list frame-index frame-index) representatives))]))
  (reverse representatives))
