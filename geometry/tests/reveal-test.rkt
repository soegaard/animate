#lang racket/base
(require rackunit racket/list (only-in racket/math pi)
         "../core.rkt" "../private/reveal.rkt" "../private/marker-shapes.rkt" "../private/compiler.rkt")
(define view (make-geometry-view #:world-width 2 #:aspect 1 #:margin 0))
(define (near p q) (check-= (distance p q) 0 1e-8))
(define (compile clauses) (make-construction-program 'reveal-test clauses (hash) "test"))
(module+ test
  (test-case "reveal modes are checked by object kind"
    (check-true (reveal-mode-valid? 'Segment 'from-end))
    (check-true (reveal-mode-valid? 'Circle 'clockwise))
    (check-false (reveal-mode-valid? 'Point 'clockwise))
    (check-equal? (default-reveal-mode 'Line) 'from-center))
  (test-case "segment starts offscreen, not at the viewport edge"
    (define s (segment (point -3 0) (point 3 0)))
    (check-equal? (curve-reveal-strokes s view 0.2) '())
    (define strokes (curve-reveal-strokes s view 0.5))
    (near (caar strokes) (point -1 0))
    (near (cadar strokes) (point 0 0)))
  (test-case "reverse and centre segment reveals preserve the endpoints"
    (define s (segment (point -0.8 0) (point 0.8 0)))
    (near (caar (curve-reveal-strokes s view 0.5 'from-end)) (point 0.8 0))
    (near (cadar (curve-reveal-strokes s view 0.5 'from-end)) (point 0 0))
    (define fronts (curve-reveal-strokes s view 0.5 'from-center))
    (check-equal? (length fronts) 2)
    (for ([front (in-list fronts)]) (near (car front) (point 0 0))))
  (test-case "rays grow from their finite origins"
    (define r (ray (point 0 0) (point 2 0)))
    (define part (car (curve-reveal-strokes r view 0.5)))
    (near (car part) (point 0 0)) (near (cadr part) (point 0.5 0)))
  (test-case "an offscreen defining midpoint cannot reverse a line"
    (define l (line (point 10 0) (point 12 0)))
    (for* ([t (in-list '(0.1 0.4 1))] [stroke (in-list (curve-reveal-strokes l view t))]
           [p (in-list stroke)])
      (check-true (<= -1 (point-x p) 1))))
  (test-case "a line tangent to a viewport corner is harmless"
    (check-equal? (curve-reveal-strokes (line (point 0 2) (point 2 0)) view 0.5) '()))
  (test-case "circle fronts both start at the through-point"
    (define c (circle (point 0 0) (point 0.8 0)))
    (define arcs (curve-reveal-strokes c view 0.25))
    (check-equal? (length arcs) 2)
    (check-= (reveal-arc-sweep (car arcs)) (/ pi 4) 1e-8)
    (check-= (reveal-arc-sweep (cadr arcs)) (- (/ pi 4)) 1e-8)
    (for ([arc (in-list arcs)])
      (near (car (reveal-arc-points arc)) (circle-through c))
      (for ([p (in-list (reveal-arc-points arc))]) (check-true (on p c)))))
  (test-case "clockwise and counterclockwise circles have opposite sweeps"
    (define c (circle (point 0 0) (point 0.8 0)))
    (check-true (< (reveal-arc-sweep (car (curve-reveal-strokes c view 0.5 'clockwise))) 0))
    (check-true (> (reveal-arc-sweep (car (curve-reveal-strokes c view 0.5 'counterclockwise))) 0)))
  (test-case "zero reveals are empty; fade uses complete geometry"
    (define s (segment (point -1 0) (point 1 0)))
    (check-equal? (curve-reveal-strokes s view 0) '())
    (check-equal? (curve-reveal-strokes s view 0 'fade) (curve-reveal-strokes s view 1)))
  (test-case "stroke prefixes use arclength rather than vertex count"
    (define ps (list (point 0 0) (point 1 0) (point 1 3)))
    (near (last (polyline-prefix ps 0.5)) (point 1 1))
    (check-equal? (polyline-prefix ps 1) ps)
    (check-equal? (polyline-prefix ps 0) '()))
  (test-case "markers draw progressively with unchanged square and tick sizes"
    (define horizontal (segment (point -1 0) (point 1 0)))
    (define vertical (segment (point 0 -1) (point 0 1)))
    (define m (perpendicular-marker horizontal vertical (point 0 0)))
    (define s (resolve-geometry-style default-geometry-theme 'right-angle-marker 'normal))
    (define placement (car (marker-placement-candidates m s view (hash))))
    (define full (car (marker-strokes m s placement 1 view)))
    (check-equal? (marker-strokes m s placement 1 view 0) '())
    (check-= (distance (car full) (cadr full)) 0.18 1e-8)
    (near (last (car (marker-strokes m s placement 1 view 0.5))) (cadr full))
    (define tick (car (marker-strokes (equal-length-marker (list horizontal horizontal)) s placement 1 view)))
    (check-= (distance (car tick) (cadr tick)) (* 0.8 0.18) 1e-8))
  (test-case "right-angle orientation respects finite arms"
    (define m (perpendicular-marker (segment (point 0 0) (point 1 0))
                                    (segment (point 0 0) (point 0 1)) (point 0 0)))
    (define s (resolve-geometry-style default-geometry-theme 'right-angle-marker 'normal))
    (check-equal? (map marker-placement-quadrant (marker-placement-candidates m s view (hash))) '(1))
    (check-exn exn:fail:geometry?
               (lambda () (marker-placement-candidates m s view (hash 'marker-quadrant 3)))))
  (test-case "reveal metadata permits forward references and rejects invalid modes"
    (define p (compile '((given [A (point -1 0)] [B (point 1 0)])
                         (reveal [s from-end]) (step [s (segment A B)]))))
    (check-equal? (geometry-program-reveals p) '((s from-end)))
    (check-equal? (resolve-reveal-mode p 's 'Segment) 'from-end)
    (check-exn exn:fail:geometry? (lambda () (compile '((given [A (point 0 0)]) (reveal [A clockwise]))))))
  (test-case "helper reveal metadata follows the result alias"
    (define-construction h (given [A : Point] [B : Point]) (results Segment)
      (reveal [s from-end]) (step [s (segment A B)]) (result s))
    (construction p (given [A (point -1 0)] [B (point 1 0)])
      (step (expand [AB (h A B)])))
    (check-equal? (resolve-reveal-mode p 'AB 'Segment) 'from-end))
  (test-case "caller reveal metadata overrides helper defaults"
    (define-construction h (given [A : Point] [B : Point]) (results Segment)
      (reveal [s from-end]) (step [s (segment A B)]) (result s))
    (construction p (given [A (point -1 0)] [B (point 1 0)])
      (reveal [AB from-start]) (step (expand [AB (h A B)])))
    (check-equal? (resolve-reveal-mode p 'AB 'Segment) 'from-start)))
