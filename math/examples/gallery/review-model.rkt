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
(provide gallery-review-points gallery-probe? gallery-probe-id gallery-probe-regression-key
         gallery-probe-entry gallery-probe-kind
         gallery-probe-local-time gallery-probe-time gallery-probe-phase
         gallery-probe-fraction gallery-probe-checkpoint)

(struct gallery-probe (id regression-key entry kind local-time time phase fraction checkpoint) #:transparent)
;; gallery-probe identifies one sample without rendering or changing mathematical state.
;;  - id  immutable-string?  stable human-readable review identity for this exact sample.
;;  - regression-key  list?  plate/view/case/phase/fraction address for automated comparison.
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
      (define segments (presentation-plan-segments plan))
      (define (phase-occurrence phase)
        (for/sum ([prior (in-list (plan-schedule plan))]
                  #:break (eq? prior phase)
                  #:when (and (= (scheduled-phase-segment prior) (scheduled-phase-segment phase))
                              (equal? (scheduled-phase-step prior) (scheduled-phase-step phase))
                              (eq? (scheduled-phase-kind prior) (scheduled-phase-kind phase))))
          1))
      (define (point kind time phase fraction)
        (define case-path
          (and phase (plan-segment-path (list-ref segments (scheduled-phase-segment phase)))))
        (define checkpoint (checkpoint-at plan (min time (plan-duration plan))))
        (define key
          (list (gallery-plate-id (gallery-entry-plate entry))
                (gallery-view-id (gallery-entry-view entry))
                (or case-path '())
                (and phase (scheduled-phase-step phase))
                (and phase (scheduled-phase-kind phase))
                (and phase (phase-occurrence phase)) fraction kind))
        (define id
          (string->immutable-string
           (format "~a/~a/~s/~s/~s/~s"
                   (list-ref key 0) (list-ref key 1) (or case-path 'root)
                   (or (and phase (scheduled-phase-step phase))
                       (math-checkpoint-step checkpoint) kind)
                   (or (and phase (scheduled-phase-kind phase)) kind)
                   (or fraction 'end))))
        (gallery-probe id key entry kind time (+ (gallery-entry-start entry) time) phase fraction
                       checkpoint))
      (define checkpoints (plan-checkpoints plan))
      (define initial (point 'read 2/5 #f #f))
      (define during
        (if dense?
          (for*/list ([phase (in-list (plan-schedule plan))]
                       #:when (and (positive? (scheduled-phase-duration phase))
                                   (memq (scheduled-phase-kind phase)
                                     '(prepare-space reveal-created retire-cancelled retire-removed compact
                                       transition explain copy-group)))
                       [fraction
                        (in-list
                         (case (scheduled-phase-kind phase)
                           [(transition) '(1/4 9/20 1/2 11/20 3/4)]
                           [(compact reveal-created) '(1/20 3/20 1/4 1/2 3/4 17/20 19/20)]
                           [else '(1/2)]))])
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
