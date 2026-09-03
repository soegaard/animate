#lang racket/base

;;;
;;; SCENE-DB Polar Coordinates and Graphs Tests
;;;

(require rackunit
         (only-in racket/math pi)
         "../main.rkt")

(module+ test
  (define point (polar->point 2 (/ pi 2)))
  (check-= (vec2-x point) 0 1e-10)
  (check-= (vec2-y point) 2 1e-10)
  ;; Signed radii are useful to polar graphs, whereas readings produced by
  ;; point->polar retain a nonnegative radius and normalized atan angle.
  (check-equal? (polar->point -2 0) (vec2 -2 0))
  (define reading (point->polar (vec2 -3 0)))
  (check-equal? (polar-coordinate-radius reading) 3)
  (check-= (polar-coordinate-angle reading) pi 1e-10)
  (define origin-reading (point->polar origin))
  (check-equal? (polar-coordinate-radius origin-reading) 0)
  (check-equal? (polar-coordinate-angle origin-reading) 0)

  (define grid
    (polar-plane #:id 'grid #:radii '(1 2) #:angles '(0 1/2) #:labels? #f))
  (check-true (group-visual? grid))
  (check-equal? (map visual-id (group-visual-children grid)) '(rings rays))
  (check-equal? (length (group-visual-children
                         (car (group-visual-children grid))))
                2)

  (define rose
    (polar-graph (lambda (theta) (* 2 (cos (* 2 theta))))
                 #:id 'rose #:samples 12))
  (check-true (path-visual? rose))
  (check-equal? (length (car (path-geometry-subpath-points
                              (path-visual-path rose))))
                13)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (polar-graph (lambda (theta) 'bad) #:id 'bad))))
