#lang racket/base

;;;
;;; Pure composition span arithmetic
;;;

;; Scene compilation owns request admissibility and converts schedule entries
;; into stateful compilation work. This module owns only immutable intrinsic
;; spans and proportional interval scaling, so composition clients do not need
;; to import scene.rkt merely to reason about timing.

(require "composition-model.rkt"
         "geometry.rkt")

(provide composition-direct-child-span
         composition-scale)

; composition-direct-child-span : any/c -> positive-real?
;; A direct timed child consumes its author-time delay plus duration. Every
;; other direct child has one intrinsic timing unit.
(define (composition-direct-child-span request)
  (if (timed-animation-request? request)
      (+ (timed-animation-request-start request)
         (timed-animation-request-duration request))
      1))

; composition-scale : symbol? positive-real? positive-real? -> positive-real?
;; Produces a finite scale factor, retaining the precise diagnostic used by the
;; scene-level scheduler when an invalid parent interval is encountered.
(define (composition-scale who duration intrinsic-duration)
  (define scale (/ duration intrinsic-duration))
  (unless (and (finite-real? scale) (positive? scale))
    (raise-arguments-error
     'scene-play
     "composition duration scale must be positive and finite"
     "composition" who
     "duration" duration
     "intrinsic-duration" intrinsic-duration))
  scale)
