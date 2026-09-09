#lang racket/base

;;;
;;; Paint Color Characterization Tests
;;;

;; Locks down the distinction between no paint and transparent color, and the
;; semantic paint interpolation behavior.

(require rackunit
         "../private/color-style.rkt"
         "../private/geometry.rkt"
         "../private/paint.rkt")

(module+ test
  ;; #f is structural absence, while transparent black is still a valid paint.
  (check-false (paint? #f))
  (check-true (paint? (rgba-color 0 0 0 0)))
  (check-exn exn:fail:contract?
             (lambda () (paint-stop 0 #f)))
  (check-exn exn:fail:contract?
             (lambda () (checker-pattern #f "white")))

  ;; Solid interpolation now retains declared color semantics.  Exact solid
  ;; endpoints normalize their literal values, and an interior sample is an
  ;; unresolved expression rather than a prematurely resolved RGBA value.
  (define source "#00000000")
  (define destination "#ff8040ff")
  (check-equal? (paint-lerp source destination 0) (rgba-color 0 0 0 0))
  (check-equal? (paint-lerp source destination 1) (rgba-color 255 128 64 1))
  (check-equal? (paint-lerp source destination 1/2)
                (color-mix source destination 1/2))

  ;; Structured paints preserve their kind and geometry while their literal
  ;; stops are numerically interpolated.
  (define first-gradient
    (linear-gradient
     (vec2 -1 0) (vec2 1 0)
     (list (paint-stop 0 "#000000")
           (paint-stop 1 "#ff0000"))))
  (define second-gradient
    (linear-gradient
     (vec2 0 -1) (vec2 0 1)
     (list (paint-stop 0 "#ffffff")
           (paint-stop 1 "#0000ff"))))
  (define middle-gradient (paint-lerp first-gradient second-gradient 1/2))
  (check-true (linear-gradient-paint? middle-gradient))
  (check-equal? (linear-gradient-paint-start middle-gradient) (vec2 -1/2 -1/2))
  (check-equal? (linear-gradient-paint-end middle-gradient) (vec2 1/2 1/2))
  (check-equal? (paint-stop-color (car (linear-gradient-paint-stops middle-gradient)))
                (color-mix "#000000" "#ffffff" 1/2))
  (check-equal? (paint-stop-color (cadr (linear-gradient-paint-stops middle-gradient)))
                (color-mix "#ff0000" "#0000ff" 1/2))
  (check-exn exn:fail:contract?
             (lambda () (paint-lerp first-gradient "red" 1/2))))
