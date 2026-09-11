#lang racket/base
(require rackunit racket/list "../core.rkt" "../private/compiler.rkt" "../private/marker-shapes.rkt")
(define fixed-view (make-geometry-view #:world-width 10 #:aspect 1 #:margin 0.05))
(define (compile cs) (make-construction-program 'annotations cs (hash) "test"))
(define (timeline p) (construction->timeline p #:view fixed-view))
(module+ test
  (test-case "annotation metadata can precede the geometry"
    (construction p
      (given [A (point 0 0)])
      (layout (label-side M 'above) (label-text M "midpoint"))
      (step [M (point 2 0)]))
    (check-equal? (hash-ref (annotation-hints p 'M) 'label-side) 'above)
    (check-equal? (annotation-text p 'M) "midpoint"))
  (test-case "bad layout hints have early diagnostics"
    (for ([hint (in-list '((label-side A 'northish) (marker-quadrant A 2)
                           (label-at Z (point 0 0)) (label-text A "") (label-text A "two\nlines")))])
      (check-exn exn:fail:geometry?
                 (lambda () (compile `((given [A (point 0 0)]) (layout ,hint)))))))
  (test-case "fixed label placement and procedural override precedence"
    (construction source (given [A (point 0 0)]) (layout (label-at A (point -1 1))))
    (define t (timeline source))
    (check-equal? (hash-ref (annotation-plan-labels (prepare-geometry-annotations t)) 'A) (point -1 1))
    (define p (prepare-geometry-annotations t #:labels (hash 'A (point 1 1))))
    (check-equal? (hash-ref (annotation-plan-labels p) 'A) (point 1 1)))
  (test-case "provided label metrics are honored"
    (construction source (given [A (point 0 0)]) (layout (label-text A "long name")))
    (define p (prepare-geometry-annotations (timeline source) #:metrics 'test
                   #:measure-label (lambda (text style) (values 2 0.5))))
    (define b (hash-ref (annotation-plan-label-boxes p) 'A))
    (check-true (> (- (cadr b) (car b)) 2))
    (check-equal? (annotation-plan-metrics p) 'test)
    (check-equal? (hash-ref (annotation-plan-texts p) 'A) "long name"))
  (test-case "later gallery plates do not displace an earlier label"
    (define first '((given [origin (point 0 0)]) (initially (hide origin))
                    (step [A (point 0 0)]) (step (hide A))))
    (define later '((step [Z (circle (point 0 0) (point 0.4 0))])))
    (define t1 (timeline (compile first)))
    (define t2 (timeline (compile (append first later))))
    (check-equal? (hash-ref (annotation-plan-labels (prepare-geometry-annotations t1)) 'A)
                  (hash-ref (annotation-plan-labels (prepare-geometry-annotations t2)) 'A)))
  (test-case "disjoint marker plates can reuse a single tick"
    (construction source (given [A (point -2 0)] [B (point 2 0)])
      (step [s (segment A B)] [m1 (marker (equal-length s s))])
      (step (hide s m1))
      (step [u (segment (point -1 1) (point 1 1))] [m2 (marker (equal-length u u))]))
    (define p (prepare-geometry-annotations (timeline source)))
    (check-equal? (hash-ref (annotation-plan-marker-counts p) 'm1) 1)
    (check-equal? (hash-ref (annotation-plan-marker-counts p) 'm2) 1))
  (test-case "co-visible independent classes get distinct counts"
    (construction source (given [A (point -2 0)] [B (point 2 0)])
      (step [s (segment A B)] [m1 (marker (equal-length s s))])
      (step [u (segment (point -1 1) (point 1 1))] [m2 (marker (equal-length u u))]))
    (define p (prepare-geometry-annotations (timeline source)))
    (check-not-equal? (hash-ref (annotation-plan-marker-counts p) 'm1)
                     (hash-ref (annotation-plan-marker-counts p) 'm2)))
  (test-case "hidden helper aliases do not consume marker classes"
    (define-construction h (given [A : Point] [B : Point]) (results Marker)
      (step [s (segment A B)] [ticks (marker (equal-length s s))]) (result ticks))
    (construction p (given [A (point -1 0)] [B (point 1 0)]) (step [mark (h A B)]))
    (check-equal? (hash-ref (annotation-plan-marker-counts (prepare-geometry-annotations (timeline p))) 'mark) 1))
  (test-case "marker placement does not change mathematical geometry"
    (construction source (given [A (point -2 0)] [B (point 2 0)] [M (point 0 0)])
      (layout (marker-position ticks 0.4) (marker-quadrant square 3))
      (step [s (segment A B)] [l (line (point 0 -2) (point 0 2))]
            [ticks (marker (midpoint-of M s))]
            [square (marker (perpendicular s l #:at M))]))
    (define t (timeline source))
    (define p (prepare-geometry-annotations t))
    (check-equal? (marker-placement-position (hash-ref (annotation-plan-marker-placements p) 'ticks)) 0.4)
    (check-equal? (marker-placement-quadrant (hash-ref (annotation-plan-marker-placements p) 'square)) 3)
    (check-equal? (construction-ref (geometry-timeline-realization t) 'M) (point 0 0)))
  (test-case "impossible fixed labels are reported rather than silently moved"
    (construction source (given [A (point -1 0)] [B (point 1 0)])
      (layout (label-at A (point 0 1)) (label-at B (point 0 1))))
    (define p (prepare-geometry-annotations (timeline source)))
    (check-true (ormap (lambda (w) (eq? (car w) 'annotation-overlap)) (annotation-plan-warnings p))))
  (test-case "the caption band is reserved for pinned labels too"
    (construction source (given [A (point 0 0)]) (layout (label-at A (point 0 -3.8))))
    (define p (prepare-geometry-annotations (timeline source) #:caption-height 2))
    (check-true (ormap (lambda (w) (eq? (car w) 'outside-safe-area)) (annotation-plan-warnings p))))
  (test-case "layout stays immutable under out-of-order sampling"
    (construction source (given [A (point -1 0)] [B (point 1 0)])
      (step [s (segment A B)]) (step (hide-label A)) (step (show-label A)))
    (define t (timeline source))
    (define first (prepare-geometry-annotations t))
    (for ([time (in-list '(5 1 0 3))]) (sample-geometry-timeline t time))
    (check-equal? first (prepare-geometry-annotations t))
    (check-true (immutable? (annotation-plan-labels first))))
  (test-case "specific marker themes inherit the generic marker"
    (define theme (geometry-theme (marker (stroke [width 3]))
                                 (right-angle-marker [size 0.18]) (length-marker [size 0.14])))
    (check-equal? (hash-ref (resolve-geometry-style theme 'right-angle-marker 'normal) 'stroke-width) 3)
    (check-equal? (hash-ref (resolve-geometry-style theme 'right-angle-marker 'normal) 'size) 0.18)
    (check-equal? (hash-ref (resolve-geometry-style theme 'length-marker 'normal) 'size) 0.14)))
