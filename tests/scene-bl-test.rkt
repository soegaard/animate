#lang racket/base

;;;
;;; SCENE-BL Implicit Curve Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define axes-value
    (axes #:id 'axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:x-tip? #f
          #:y-tip? #f))
  ;; The zero level set of f(x,y)=x is the y axis. Its cells create stable
  ;; local contour segments with no renderer or callback retained.
  (define vertical
    (sample-implicit-path axes-value (lambda (x _y) x)
                          #:x-count 3 #:y-count 3))
  (check-equal?
   (path-geometry-subpath-points vertical)
   (list (list (vec2 0 -1) (vec2 0 0) (vec2 0 1))))
  (define curve
    (implicit-curve axes-value
                    (lambda (x y) (- (+ (* x x) (* y y)) 1))
                    #:id 'circle
                    #:x-count 5
                    #:y-count 5))
  (check-true (path-visual? curve))
  (check-equal? (visual-id curve) 'circle)
  (check-true (positive? (length (path-geometry-subpaths (path-visual-path curve)))))
  (check-true
   (ormap path-subpath-closed?
          (path-geometry-subpaths (path-visual-path curve))))
  ;; Axes geometry is local while the resulting Visual retains its complete
  ;; transform. Contours therefore align with translated/scaled axes.
  (define transformed-axes
    (axes #:id 'transformed
          #:center (vec2 3 4)
          #:scale 2
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 8
          #:y-length 6))
  (define transformed-contour
    (implicit-curve transformed-axes (lambda (x _y) x)
                    #:id 'transformed-contour #:x-count 3 #:y-count 3))
  (check-equal? (visual-transform transformed-contour)
                (visual-transform transformed-axes))
  (check-equal?
   (path-geometry-subpath-points (path-visual-path transformed-contour))
   (list (list (vec2 0 -3) (vec2 0 0) (vec2 0 3))))
  (check-equal?
   (sample-implicit-path axes-value (lambda (x y) (if (and (zero? x) (zero? y)) +inf.0 1))
                         #:x-count 3 #:y-count 3)
   empty-path-geometry)
  (check-exn exn:fail:contract?
             (lambda ()
               (sample-implicit-path axes-value (lambda (_x _y) 'bad)
                                     #:x-count 3 #:y-count 3))))
