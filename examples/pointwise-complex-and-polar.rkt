#lang racket/base

;;;
;;; SCENE-CY-C/DA/DB: Pointwise, Complex, and Polar Maps
;;;

;; A compact progression: a Cartesian complex grid is pointwise mapped by
;; z -> z^2, then the same scene introduces a polar grid and a rose curve.

(require (only-in racket/math pi)
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CY-C/DA/DB: pointwise, complex, and polar maps"
                #:id 'title #:center (vec2 0 12/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define complex-caption
    (plain-text "A complex grid under z ↦ z²"
                #:id 'complex-caption #:center (vec2 0 -12/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (define polar-caption
    (plain-text "r = 2 cos(3θ)"
                #:id 'polar-caption #:center (vec2 0 -12/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (define domain
    (complex-plane #:id 'domain
                   #:x-range (axis-range -1 1 1/2)
                   #:y-range (axis-range -1 1 1/2)
                   #:x-length 2 #:y-length 2
                   #:labels? #f
                   #:grid-stroke "lightsteelblue" #:axes-stroke "navy"))
  (define polar-grid
    (polar-plane #:id 'polar-grid
                 #:radii '(1 2)
                 #:angles (list 0 (/ pi 4) (/ pi 2) (* 3 (/ pi 4)) pi
                                (* 5 (/ pi 4)) (* 3 (/ pi 2)) (* 7 (/ pi 4)))
                 #:labels? #f))
  (define rose
    (polar-graph (lambda (theta) (* 2 (cos (* 3 theta))))
                 #:id 'rose #:samples 240
                 #:stroke "crimson" #:stroke-width 3))
  (define initial
    (scene-wait
     (scene-add (make-scene #:camera (make-camera #:world-width 10))
                title complex-caption domain)
     1))
  (define mapped
    (scene-wait
     (scene-play initial
                 (apply-complex-function 'domain (lambda (z) (* z z))
                                         #:samples 16)
                 #:duration 3)
     1))
  (scene-wait
   (scene-play mapped
               (fade-out 'domain)
               (fade-out 'complex-caption)
               (fade-in polar-grid)
               (create rose)
               (fade-in polar-caption)
               #:duration 3)
   2))

(module+ main
  (run-demo "pointwise-complex-and-polar.rkt" make-demo-scene))
