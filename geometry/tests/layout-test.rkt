#lang racket/base
(require rackunit racket/list "../core.rkt" "../private/compiler.rkt" "fixtures.rkt")
(module+ test
  (test-case "the three classical constructions realize valid geometry"
    (define t (realize-construction triangle))
    (check-= (distance (construction-ref t 'A) (construction-ref t 'C)) 4 1e-8)
    (define b (realize-construction bisector-demo))
    (check-= (distance (construction-ref b 'M)
                       (midpoint (construction-ref b 'A) (construction-ref b 'B))) 0 1e-8)
    (define p (realize-construction perpendicular))
    (check-true (on (construction-ref p 'P) (construction-ref p 'm)))
    (check-= (dot (point- (curve-end (construction-ref p 'l)) (curve-start (construction-ref p 'l)))
                   (point- (curve-end (construction-ref p 'm)) (curve-start (construction-ref p 'm)))) 0 1e-8))
  (test-case "whole-construction realization is deterministic"
    (check-equal? (realize-construction perpendicular) (realize-construction perpendicular))
    (check-equal? (realize-construction bisector-demo) (realize-construction bisector-demo)))
  (test-case "an explicit choice is retained, checked, and never randomized"
    (define r (realize-construction perpendicular #:choices (hash 'A (point -1.4 0))))
    (check-equal? (construction-ref r 'A) (point -1.4 0))
    (check-= (distance (construction-ref r 'B) (point 1.4 0)) 0 1e-8)
    (check-exn exn:fail:geometry? (lambda () (realize-construction perpendicular #:choices (hash 'A (point 0 1)))))
    (check-exn exn:fail:geometry? (lambda () (realize-construction perpendicular #:choices (hash 'A (point 0 0))))))
  (test-case "layout pins cannot alter derived geometry"
    (check-exn exn:fail:geometry?
               (lambda () (make-construction-program
                           'bad '((given [A (point 0 0)] [B (point 2 0)])
                                  (step [M (midpoint A B)]) (layout (pin M (point 7 8)))) (hash) "test"))))
  (test-case "a fixed view rejects insufficient room instead of clipping required anchors silently"
    (define v (make-geometry-view #:world-width 2))
    (check-exn exn:fail:geometry? (lambda () (realize-construction triangle #:view v))))
  (test-case "semantic fitting does not require entire helper circles in frame"
    (define v (make-geometry-view #:world-width 8 #:aspect 1 #:margin 0.05))
    (define r (realize-construction perpendicular #:view v #:padding 0.2 #:choices (hash 'A (point -1.5 0))))
    (check-true (andmap (lambda (p) (point-in-view? p v 0.2)) (realization-anchor-points r)))
    (define c (construction-ref r 'cA))
    (check-false (point-in-view? (point+ (circle-center c) (point (- (circle-radius c)) 0)) v)))
  (test-case "helper choices share one outer realization; hidden intermediates do not add extents"
    (define r (realize-construction collapsed))
    (define o (construction-ref r 'O))
    (check-= (distance o (construction-ref r 'A)) (distance o (construction-ref r 'B)) 1e-8)
    (check-= (distance o (construction-ref r 'B)) (distance o (construction-ref r 'C)) 1e-8)
    (check-equal? (hash-ref (geometry-realization-diagnostics r) 'candidates-tested) 1))
  (test-case "hidden enormous given geometry does not force a zoom out"
    (define p
      (make-construction-program
       'hidden '((given [A (point 0 0)] [B (point 2 0)]
                        [huge (circle (point 1000 1000) (point 5000 1000))])
                 (initially (hide huge)) (step [s (segment A B)])) (hash) "test"))
    (define r (realize-construction p))
    (check-true (< (geometry-view-width (geometry-realization-view r)) 10)))
  (test-case "pins can concretize free givens and remain mathematically checked"
    (define p
      (make-construction-program
       'pin-demo '((given [A (point)] [B (point)])
                   (require (distinct? A B))
                   (layout (pin A (point -2 0)) (pin B (point 2 0)))
                   (step [s (segment A B)])) (hash) "test"))
    (define r (realize-construction p))
    (check-equal? (construction-ref r 'A) (point -2 0))
    (check-equal? (hash-ref (geometry-realization-diagnostics r) 'candidates-tested) 1)))
