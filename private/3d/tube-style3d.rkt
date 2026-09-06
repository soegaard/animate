#lang racket/base

;;;
;;; Physical Tube Style
;;;

;; `tube-style3d` is intentionally separate from `stroke3d`.  A tube is
;; actual world-space geometry, so its apparent width responds to perspective;
;; a stroke is a mathematical mark resolved in screen space by a renderer.

(require "../color-style.rkt"
         "../geometry.rkt")

(provide tube-style3d
         tube-style3d?
         tube-style3d-radius
         tube-style3d-sides
         tube-style3d-color)

(struct tube-style3d-value (radius sides color) #:transparent)

(define tube-style3d? tube-style3d-value?)
(define tube-style3d-radius tube-style3d-value-radius)
(define tube-style3d-sides tube-style3d-value-sides)
(define tube-style3d-color tube-style3d-value-color)

(define (tube-style3d #:radius [radius 1/20]
                      #:sides [sides 8]
                      #:color [color "steelblue"])
  (unless (and (finite-real? radius) (positive? radius))
    (raise-argument-error 'tube-style3d "positive finite radius" radius))
  (unless (and (exact-integer? sides) (>= sides 3))
    (raise-argument-error 'tube-style3d "exact integer at least 3" sides))
  (unless (color-spec? color)
    (raise-argument-error 'tube-style3d "color-spec?" color))
  (tube-style3d-value radius sides color))
