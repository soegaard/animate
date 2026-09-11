#lang racket/base
(require rackunit racket/list "../core.rkt" "../private/drawing.rkt" "fixtures.rkt")
(module+ test
  (test-case "dash lengths are converted from cosmetic to world units"
    (define runs (dash-polylines (list (point 0 0) (point 10 0)) '(2 2) 1))
    (check-equal? (map (lambda (run) (distance (car run) (last run))) runs) '(2 2 2))
    (check-equal? (map point-x (map car runs)) '(0 4 8)))
  (test-case "dashes retain their phase across polyline vertices"
    (define runs (dash-polylines (list (point 0 0) (point 1 0) (point 1 3)) '(2 2) 1))
    (check-equal? (length runs) 1)
    (check-equal? (car (car runs)) (point 0 0))
    (check-equal? (last (car runs)) (point 1 1)))
  (test-case "clipping does not connect unrelated visible pieces"
    (define v (make-geometry-view #:world-width 2 #:aspect 1 #:margin 0))
    (define runs (clipped-polylines (list (point -2 0) (point 0 0) (point 2 0)
                                         (point 2 2) (point 0 2) (point 0 0)) v))
    (check-equal? (length runs) 2)
    (check-= (distance (car (car runs)) (point -1 0)) 0 1e-9))
  (test-case "labels are placed deterministically from the whole diagram"
    (define r (realize-construction triangle))
    (check-equal? (label-positions r default-geometry-theme) (label-positions r default-geometry-theme))
    (check-equal? (hash-ref (label-positions r default-geometry-theme #:labels (hash 'C (point 0 4))) 'C)
                  (point 0 4)))
  (test-case "helper label spelling does not leak qualified identifiers"
    (check-equal? (display-label '$m/1/C) "C")))
