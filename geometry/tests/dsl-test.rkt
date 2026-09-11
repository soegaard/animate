#lang racket/base
(require rackunit racket/list "../core.rkt" "../private/compiler.rkt" "fixtures.rkt")
(define (compile clauses [helpers (hash)]) (make-construction-program 'test clauses helpers "test source"))
(define (bad? clauses) (check-exn exn:fail:geometry? (lambda () (compile clauses))))
(module+ test
  (test-case "elaborated program has a dependency graph and inferred types"
    (check-true (geometry-program? triangle))
    (check-equal? (hash-ref (construction-dependencies triangle) 'cA) '(A B))
    (check-equal? (geometry-node-type (findf (lambda (n) (eq? (geometry-node-id n) 'cA))
                                            (geometry-program-nodes triangle))) 'Circle))
  (test-case "unknown, duplicate and forward geometry bindings fail"
    (bad? '((given [A (point 0 0)]) (step [s (segment A B)])))
    (bad? '((given [A (point 0 0)] [A (point 1 0)])))
    (bad? '((given [A (point 0 0)]) (step [s (segment A B)] [B (point 1 0)])))
    (bad? '((given [$internal (point 0 0)]))))
  (test-case "types and primitive arities are checked before realization"
    (bad? '((given [A (point 0 0)]) (step [c (circle A)])))
    (bad? '((given [A (point 0 0)] [B (point 1 0)])
            (step [c (circle A B)] [s (segment c B)])))
    (bad? '((given [A (point 0 0)]) (require A)))
    (bad? '((given [n 3]) (step (show-label n))))
    (bad? '((given [n 3]) (layout (focus n)))))
  (test-case "layout and initial state can refer forward"
    (define p (compile '((given [A (point 0 0)] [B (point 2 0)])
                         (layout (focus M)) (initially (hide-label M))
                         (step [M (midpoint A B)]))))
    (check-true (geometry-program? p)))
  (test-case "timing clauses and per-step overrides are parsed"
    (define p (compile '((given [A (point 0 0)] [B (point 2 0)])
                         (timing [opening-pause 0.2] [read-delay 0.4] [action-duration 1.1] [step-pause 0.3])
                         (step #:read-delay 0.9 #:duration 0.7 #:pause 0.25 "AB" [AB (segment A B)]))))
    (check-equal? (geometry-timing-opening-pause (geometry-program-timing p)) 0.2)
    (check-equal? (geometry-timing-read-delay (geometry-program-timing p)) 0.4)
    (check-equal? (geometry-timing-action-duration (geometry-program-timing p)) 1.1)
    (check-equal? (geometry-timing-step-pause (geometry-program-timing p)) 0.3)
    (define s (first (geometry-program-steps p)))
    (check-equal? (hash-ref (geometry-step-timing s) 'read-delay) 0.9)
    (check-equal? (hash-ref (geometry-step-timing s) 'duration) 0.7)
    (check-equal? (hash-ref (geometry-step-timing s) 'pause) 0.25))
  (test-case "invalid timing clauses fail early"
    (bad? '((given [A (point 0 0)]) (timing [unknown 1]) (step (show A))))
    (bad? '((given [A (point 0 0)]) (timing [action-duration 0]) (step (show A))))
    (bad? '((given [A (point 0 0)]) (step #:duration 0 (show A))))
    (bad? '((given [A (point 0 0)]) (step #:unknown 1 (show A)))))
  (test-case "free choices and givens have distinct placement rules"
    (bad? '((given [A (point 0 0)]) (step [B (point)])))
    (bad? '((given [A (point 0 0)] [l (line (point) A)])))
    (bad? '((given [l (line (point 0 0) (point 1 0))]
                   [A (choose (point-on l))]))))
  (test-case "typed helper inputs and declared output counts are mandatory"
    (check-exn exn:fail:geometry?
               (lambda () (make-construction-helper 'bad '((given [A Point]) (results Point) (result A)) (hash) "test")))
    (check-exn exn:fail:geometry?
               (lambda () (make-construction-helper 'bad '((given [A : Point]) (results Line) (result A)) (hash) "test")))
    (check-exn exn:fail:geometry?
               (lambda () (make-construction-helper 'bad '((given [A : Point]) (results Point Point) (result A)) (hash) "test"))))
  (test-case "multi-result helpers bind caller-visible aliases"
    (define r (realize-construction pair-demo))
    (check-equal? (construction-ref r 'M) (point 0 0))
    (check-true (segment? (construction-ref r 'AB))))
  (test-case "helper arguments are checked at each call"
    (check-exn exn:fail:geometry?
               (lambda () (compile '((given [A (point 0 0)] [B (point 1 0)])
                                      (step [(X s) (pair A (circle A B))]))
                                   (hash 'pair pair-helper)))))
  (test-case "two helper calls have distinct internal identities"
    (define names (map geometry-node-id (geometry-program-nodes collapsed)))
    (check-equal? (length names) (length (remove-duplicates names)))
    (check-true (> (length names) 10))
    (check-equal? (sort (construction-visible-ids collapsed) symbol<?) '(A B C O m1 m2)))
  (test-case "expanded helpers retain their intermediate exposition"
    (check-true (> (length (construction-visible-ids expanded)) 3))
    (check-true (ormap (lambda (s) (ormap (lambda (a) (eq? (geometry-action-kind a) 'expanded))
                                         (geometry-step-actions s))) (geometry-program-steps expanded))))
  (test-case "invalid together, selector, and layout clauses fail early"
    (bad? '((given [A (point 0 0)]) (step (together (show A) (hide A)))))
    (bad? '((given [A (point 0 0)] [B (point 1 0)])
            (step [l (line A B)] [P (intersection l l #:index 0)])))
    (bad? '((given [A (point 0 0)]) (layout (unknown A)))))
  (test-case "intersection destructuring checks cardinality in each realization"
    (define p (compile '((given [A (point 0 0)] [B (point 1 0)]
                                [l (line (point -2 1) (point 2 1))])
                         (step [c (circle A B)] [(P Q) (intersections c l)]))))
    (check-exn exn:fail:geometry? (lambda () (realize-construction p))))
  (test-case "helper preconditions are checked on actual input values"
    (check-exn exn:fail:geometry?
               (lambda () (realize-construction expanded #:givens (hash 'B (point -2 0)))))))
