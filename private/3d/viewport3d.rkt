#lang racket/base

;; The renderer boundary owns one viewport convention.  Screen coordinates
;; describe the half-open rectangle [0,width) × [0,height), with a top-left
;; origin; integer pixel (x,y) is sampled at its centre (x+1/2,y+1/2).
;; Keeping these conversions shared prevents software strokes, billboards, and
;; their OpenGL triangle submissions from acquiring one-pixel disagreements.

(require "../geometry.rkt")

(provide ndc3d->screen
         screen3d->ndc
         pixel3d-center)

(define (ndc3d->screen point width height)
  (check-viewport 'ndc3d->screen width height)
  (cons (* width (/ (+ (vec2-x point) 1) 2))
        (* height (/ (- 1 (vec2-y point)) 2))))

(define (screen3d->ndc x y width height)
  (check-viewport 'screen3d->ndc width height)
  (cons (- (* 2 (/ x width)) 1)
        (- 1 (* 2 (/ y height)))))

(define (pixel3d-center x y)
  (unless (and (exact-nonnegative-integer? x)
               (exact-nonnegative-integer? y))
    (raise-arguments-error 'pixel3d-center
                           "nonnegative exact pixel coordinates"
                           "x" x "y" y))
  (cons (+ x 1/2) (+ y 1/2)))

(define (check-viewport who width height)
  (unless (and (exact-positive-integer? width)
               (exact-positive-integer? height))
    (raise-arguments-error who "positive exact viewport dimensions"
                           "width" width "height" height)))
