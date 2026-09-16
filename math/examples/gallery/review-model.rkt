#lang racket/base

;;;
;;; Mathematical Gallery Review Schedule
;;;
;; Selects read, during, and settled times from existing mathematical schedules.
;; The native scene engine still owns every actual frame sample.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list append-map)
         "../../main.rkt" "model.rkt")
(provide gallery-review-points gallery-probe? gallery-probe-entry gallery-probe-kind
         gallery-probe-local-time gallery-probe-time gallery-probe-phase
         gallery-probe-fraction gallery-probe-checkpoint)

(struct gallery-probe (entry kind local-time time phase fraction checkpoint) #:transparent)
;; gallery-probe identifies one sample without rendering or changing mathematical state.
;;  - entry  gallery-entry?  original plate, replay, and chronological offset.
;;  - kind  symbol?  read, during, settled, or result review category.
;;  - local-time  nonnegative-real?  sample time relative to the replay's math plan.
;;  - time  nonnegative-real?  absolute native gallery scene time.
;;  - phase  (or/c #f scheduled-phase?)  active native-plan phase, not a new phase.
;;  - fraction  (or/c #f rational?)  position inside a sampled transition.
;;  - checkpoint  math-checkpoint?  last settled mathematical state at the local time.

; gallery-review-points : (listof gallery-entry?) [#:dense? boolean?] -> list?
;;   Samples each phase and checkpoint, including both atomic-replacement visibility barriers.
(define (gallery-review-points entries #:dense? [dense? #t])
  (append-map
    (lambda (entry)
      (define plan (gallery-view-plan (gallery-entry-view entry)))
      (define (point kind time phase fraction)
        (gallery-probe entry kind time (+ (gallery-entry-start entry) time) phase fraction
                       (checkpoint-at plan (min time (plan-duration plan)))))
      (define checkpoints (plan-checkpoints plan))
      (define initial (point 'read 2/5 #f #f))
      (define during
        (if dense?
          (for*/list ([phase (in-list (plan-schedule plan))]
                       #:when (and (positive? (scheduled-phase-duration phase))
                                   (memq (scheduled-phase-kind phase)
                                     '(prepare-space reveal-created retire-cancelled retire-removed compact
                                       transition explain copy-group)))
                       [fraction (in-list (if (eq? (scheduled-phase-kind phase) 'transition)
                                               '(1/4 9/20 1/2 11/20 3/4) '(1/2)))])
            (point 'during (+ (scheduled-phase-start phase) (* fraction (scheduled-phase-duration phase)))
                   phase fraction))
          '()))
      (define settled
        (for/list ([checkpoint (in-vector checkpoints)])
          (point 'settled (math-checkpoint-time checkpoint) #f #f)))
      (sort (append (list initial) during settled
                    (list (point 'result (+ (plan-duration plan) (/ gallery-settle-time 2)) #f #f)))
            < #:key gallery-probe-time))
    entries))
