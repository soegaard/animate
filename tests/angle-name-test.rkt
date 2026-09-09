#lang racket/base

;;;
;;; Public Angle-Name Boundary Tests
;;;

;; Animate's geometric annotation must coexist with racket/base's numeric
;; angle procedure. The annotation therefore has a specific, non-shadowing
;; name.

(require rackunit
         "../main.rkt")

(module+ test
  (check-equal? (angle 1) 0)
  (check-true
   (path-visual?
    (angle-marker (vec2 1 0) origin (vec2 0 1) #:id 'angle-mark))))
