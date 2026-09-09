#lang racket/base

;;;
;;; FX-C1 Pure Reveal-Front Geometry Tests
;;;

(require rackunit
         "../main.rkt")

(define (geometry-bounds geometry)
  (define-values (left bottom right top) (path-geometry-bounds geometry))
  (list left bottom right top))

(module+ test
  (define box (layout-box -2 -1 2 1))
  (define linear-x (linear-reveal-front (vec2 1 0) #:padding 0))
  (define linear-reverse (linear-reveal-front (vec2 -1 0) #:padding 0))

  ;; A hard front has a valid empty start, a full frozen-box endpoint, and no
  ;; dependence on sampling history. Cardinal and reversed sweeps agree on
  ;; which side is visible at half progress.
  (check-true (reveal-front? linear-x))
  (check-true (linear-reveal-front? linear-x))
  (check-true (path-geometry-empty? (reveal-front-path linear-x box 0)))
  (check-equal? (geometry-bounds (reveal-front-path linear-x box 1))
                '(-2 -1 2 1))
  (check-equal? (geometry-bounds (reveal-front-path linear-x box 1/2))
                '(-2 -1 0 1))
  (check-equal? (geometry-bounds (reveal-front-path linear-reverse box 1/2))
                '(0 -1 2 1))
  (check-equal? (reveal-front-path linear-x box 3/10)
                (reveal-front-path linear-x box 3/10))

  ;; Padding is measured as a frozen-box fraction. Oblique fronts and explicit
  ;; origins still begin with an empty path and end covering the expanded box.
  (define padded (linear-reveal-front (vec2 1 1) #:padding 1/20))
  (check-true (path-geometry-empty? (reveal-front-path padded box 0)))
  (check-equal? (geometry-bounds (reveal-front-path padded box 1))
                '(-11/5 -6/5 11/5 6/5))
  (define offset-origin
    (linear-reveal-front (vec2 1 0) #:origin (vec2 7 0) #:padding 0))
  (check-true (path-geometry-empty? (reveal-front-path offset-origin box 0)))
  (check-equal? (geometry-bounds (reveal-front-path offset-origin box 1))
                '(-2 -1 2 1))

  ;; Radial fronts use a deterministic circumscribed polygon: no zero-radius
  ;; polygon is constructed at the empty start, and the final polygon covers
  ;; every frozen box corner.
  (define radial (radial-reveal-front))
  (check-true (radial-reveal-front? radial))
  (check-true (path-geometry-empty? (reveal-front-path radial box 0)))
  (define radial-full-bounds (geometry-bounds (reveal-front-path radial box 1)))
  (check-true (<= (list-ref radial-full-bounds 0) -2))
  (check-true (<= (list-ref radial-full-bounds 1) -1))
  (check-true (>= (list-ref radial-full-bounds 2) 2))
  (check-true (>= (list-ref radial-full-bounds 3) 1))
  (define radial-started (radial-reveal-front #:center origin #:start-radius 1))
  (check-false (path-geometry-empty? (reveal-front-path radial-started box 0)))

  (check-exn exn:fail:contract?
             (lambda () (linear-reveal-front origin)))
  (check-exn exn:fail:contract?
             (lambda () (linear-reveal-front (vec2 1 0) #:padding -1)))
  (check-exn exn:fail:contract?
             (lambda () (radial-reveal-front #:start-radius -1)))
  (check-exn exn:fail:contract?
             (lambda () (reveal-front-path linear-x box 2))))
