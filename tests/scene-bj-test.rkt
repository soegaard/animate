#lang racket/base

;;;
;;; SCENE-BJ Logarithmic Axes Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define tolerance 1e-10)
  (define logarithmic-axes
    (axes #:id 'logarithmic
          #:center (vec2 2 -3)
          #:x-range (axis-range 1 1000 1)
          #:y-range (axis-range 1 1000 1)
          #:x-scale 'log
          #:y-scale 'log
          #:x-log-base 10
          #:y-log-base 10
          #:x-length 3
          #:y-length 3
          #:x-tip? #f
          #:y-tip? #f))
  (check-true (axis-scale? 'linear))
  (check-true (axis-scale? 'log))
  (check-false (axis-scale? 'power))
  (check-eq? (axes-visual-x-scale logarithmic-axes) 'log)
  (check-eq? (axes-visual-y-scale logarithmic-axes) 'log)
  (check-equal? (axes-visual-x-log-base logarithmic-axes) 10)
  (check-equal? (axes-visual-y-log-base logarithmic-axes) 10)
  ;; Decades are equally spaced in local geometry and the full affine transform
  ;; is still applied exactly once by coordinate conversion.
  (check-= (axes-x-unit-length logarithmic-axes) 1 tolerance)
  (check-= (axes-y-unit-length logarithmic-axes) 1 tolerance)
  (define decade-point
    (axes-coordinates->point logarithmic-axes 10 100))
  (check-= (vec2-x decade-point) 3 tolerance)
  (check-= (vec2-y decade-point) -1 tolerance)
  (define recovered
    (axes-point->coordinates logarithmic-axes decade-point))
  (check-= (vec2-x recovered) 10 tolerance)
  (check-= (vec2-y recovered) 100 tolerance)
  ;; Major ticks, grid lines, and numeric labels use powers of the configured
  ;; base rather than the linear range tick constructor.
  (check-equal?
   (length (path-geometry-subpaths
            (path-visual-path
             (axes-grid-lines logarithmic-axes #:id 'log-grid))))
   8)
  (check-equal?
   (length (axes-number-labels logarithmic-axes #:id-prefix 'log-label))
   8)
  ;; Default function-graph samples are uniformly spaced in log display space.
  (define sampled-xs '())
  (define graph
    (function-graph
     logarithmic-axes
     (lambda (x)
       (set! sampled-xs (cons x sampled-xs))
       x)
     #:id 'identity
     #:sample-count 4))
  (for ([actual (in-list (reverse sampled-xs))]
        [expected (in-list '(1 10 100 1000))])
    (check-= actual expected tolerance))
  (define graph-points
    (path-geometry-subpath-points (path-visual-path graph)))
  (check-equal? (length graph-points) 1)
  (for ([actual (in-list (car graph-points))]
        [expected (in-list '(0 1 2 3))])
    (check-= (vec2-x actual) expected tolerance)
    (check-= (vec2-y actual) expected tolerance))
  ;; Explicit sampling bounds retain the same display-space distribution.
  (define bounded-xs '())
  (define bounded-path
    (sample-function-path
     logarithmic-axes
     (lambda (x)
       (set! bounded-xs (cons x bounded-xs))
       x)
     #:x-min 10
     #:x-max 1000
     #:sample-count 3))
  (check-true (path-geometry? bounded-path))
  (for ([actual (in-list (reverse bounded-xs))]
        [expected (in-list '(10 100 1000))])
    (check-= actual expected tolerance))
  ;; Vector-field sampling follows both log axes as well, and it terminates
  ;; after the requested finite grid.
  (define field-xs '())
  (define log-field
    (vector-field
     logarithmic-axes
     (lambda (x _y)
       (set! field-xs (cons x field-xs))
       origin)
     #:id 'log-field
     #:x-count 4
     #:y-count 1))
  (check-equal? (group-visual-children log-field) '())
  (for ([actual (in-list (reverse field-xs))]
        [expected (in-list '(1 10 100 1000))])
    (check-= actual expected tolerance))
  ;; Implicit-curve grids likewise use log display spacing before converting the
  ;; resulting numeric contour back to local path geometry.
  (define log-contour
    (sample-implicit-path logarithmic-axes
                          (lambda (x _y) (- x 10))
                          #:x-count 4
                          #:y-count 2))
  (define contour-points
    (apply append (path-geometry-subpath-points log-contour)))
  (check-true (pair? contour-points))
  (for ([point (in-list contour-points)])
    (check-= (vec2-x point) 1 tolerance))
  ;; A numeric zero cannot be converted onto a logarithmic axis. The default
  ;; linear scale retains the historical zero-containing range invariant.
  (check-exn exn:fail:contract?
             (lambda ()
               (axes-coordinates->point logarithmic-axes 0 1)))
  (check-exn exn:fail?
             (lambda ()
               (sample-function-path logarithmic-axes (lambda (_x) 0)
                                     #:x-min 0 #:x-max 10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (axes #:id 'not-log-range
                     #:x-range (axis-range 1 10 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (axes #:id 'nonpositive-log-range
                     #:x-scale 'log
                     #:x-range (axis-range 0 10 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (axes #:id 'unit-log-base
                     #:x-scale 'log
                     #:x-log-base 1
                     #:x-range (axis-range 1 10 1)))))
