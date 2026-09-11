#lang racket/base

;; Executable regression checks that require only Racket's base distribution.
;; Also used by library-test.rkt, which integrates them into the RackUnit suite.
;; Mathematical oracles below are independent coordinate/vector calculations;
;; passing the construction's own assertions is not the only check.
(require racket/list racket/runtime-path racket/string
         (only-in racket/math pi)
         "../core.rkt" "../private/compiler.rkt" "../private/evaluate.rkt"
         (prefix-in c: "../constructions.rkt")
         "../examples/private/library-example-names.rkt" "library-alias-fixture.rkt")
(provide library-check-groups run-library-checks)
(define-runtime-path examples "../examples")

(define check-counter (make-parameter #f))
(define current-group (make-parameter "library"))
(define (ensure condition message . details)
  (when (check-counter)
    (set-box! (check-counter) (add1 (unbox (check-counter)))))
  (unless condition
    (error 'library-check "~a: ~a; ~e" (current-group) message details)))
(define (expect-error thunk [pattern #rx"."])
  (define result
    (with-handlers ([exn:fail:geometry? values]) (thunk) #f))
  (ensure (and result (regexp-match? pattern (exn-message result)))
          "expected a geometry diagnostic" (and result (exn-message result))))
(define (near a b [scale 1])
  (ensure (<= (abs (- a b)) (* 1e-7 (max 1e-8 (abs scale))))
          "numeric mismatch" a b scale))
(define (same-point a b [scale 1]) (near (distance a b) 0 scale))
(define (unit u) (point* u (/ 1 (norm u))))
(define (direction l) (point- (curve-end l) (curve-start l)))
(define (line-has l p [scale 1])
  (near (cross (unit (direction l)) (point- p (curve-start l))) 0 scale))
(define (orthogonal l m) (near (dot (unit (direction l)) (unit (direction m))) 0))
(define (parallel l m) (near (cross (unit (direction l)) (unit (direction m))) 0))
(define (same-line l m [scale 1])
  (parallel l m) (line-has l (curve-start m) scale))
(define (projection p l)
  (define a (curve-start l)) (define u (direction l))
  (point+ a (point* u (/ (dot (point- p a) u) (dot u u)))))
(define (length-of s) (distance (segment-a s) (segment-b s)))
(define (radii r ids)
  (define o (construction-ref r 'O))
  (define values (map (lambda (id) (distance o (construction-ref r id))) ids))
  (for ([v (in-list (cdr values))]) (near v (car values) (car values))))
(define (equal-sides r ids)
  (define lengths (map (lambda (id) (length-of (construction-ref r id))) ids))
  (for ([v (in-list (cdr lengths))]) (near v (car lengths) (car lengths))))
(define (program clauses [helpers (hash)])
  (make-construction-program 'library-test clauses helpers "library-checks"))
(define helpers
  (list c:perpendicular-bisector c:bisect-segment c:erect-perpendicular
        c:drop-perpendicular c:angle-bisector c:parallel-through-point
        c:copy-segment c:copy-angle))
(define expected-types
  '((Point Point Line) (Point Point Point) (Line Point Line)
    (Line Point Line) (Point Point Point Ray) (Line Point Line)
    (Segment Ray Point) (Angle Ray Side Ray)))
(define (run-helper h givens)
  (realize-construction (construction-helper-program h) #:givens givens #:samples 24))
(define (result-value h r)
  (construction-ref r (car (geometry-program-results (construction-helper-program h)))))
(define (contains-op? x op)
  (and (pair? x) (or (eq? (car x) op) (ormap (lambda (a) (contains-op? a op)) (cdr x)))))

(define (transformation scale theta reflected?)
  (lambda (x y)
    (define yy (if reflected? (- y) y))
    (point (+ 1.7 (* scale (- (* x (cos theta)) (* yy (sin theta)))))
           (+ -2.3 (* scale (+ (* x (sin theta)) (* yy (cos theta))))))))

(define (transformed-library-check scale theta reflected?)
  (define p (transformation scale theta reflected?))
  (define A (p 0 0)) (define B (p 4 0)) (define C (p -2 3))
  (define P (p 1 0)) (define Q (p 1.3 2.2))
  (define l (line A B)) (define source (segment A B))
  (define target (ray (p 6 -1) (p 8 1)))
  (define bisector (result-value c:perpendicular-bisector
                     (run-helper c:perpendicular-bisector (hash 'A A 'B B))))
  (line-has bisector (point* (point+ A B) 1/2) scale)
  (orthogonal bisector l)
  (define middle (result-value c:bisect-segment
                   (run-helper c:bisect-segment (hash 'A A 'B B))))
  (same-point middle (point* (point+ A B) 1/2) scale)
  (define erected (result-value c:erect-perpendicular
                    (run-helper c:erect-perpendicular (hash 'l l 'P P))))
  (line-has erected P scale) (orthogonal erected l)
  (ensure (positive? (cross (direction l) (point- (end-point erected) P)))
          "erected defining endpoint must lie on the directed line's left")
  (define dropped (result-value c:drop-perpendicular
                    (run-helper c:drop-perpendicular (hash 'l l 'P Q))))
  (define H (projection Q l))
  (line-has dropped H scale) (line-has dropped Q scale) (orthogonal dropped l)
  (same-point (end-point dropped) (point- (point* H 2) Q) scale)
  (define angle-result (result-value c:angle-bisector
                         (run-helper c:angle-bisector (hash 'A B 'B A 'C C))))
  (same-point (ray-a angle-result) A scale)
  (define expected (unit (point+ (unit (point- B A)) (unit (point- C A)))))
  (same-point (unit (direction angle-result)) expected)
  (define through (result-value c:parallel-through-point
                    (run-helper c:parallel-through-point (hash 'l l 'P Q))))
  (line-has through Q scale) (parallel through l)
  (define copied (result-value c:copy-segment
                   (run-helper c:copy-segment (hash 'source source 'target target))))
  (same-point copied (point+ (ray-a target) (point* (unit (direction target)) (* 4 scale))) scale)
  ;; Both orientations are relative to the target, not the source or screen.
  (define source-angle (angle-spec B A C))
  (for ([side (in-list '(left right))])
    (define copied-ray (result-value c:copy-angle
                         (run-helper c:copy-angle
                           (hash 'source source-angle 'target target 'side side))))
    (same-point (ray-a copied-ray) (ray-a target) scale)
    (define u (unit (direction target)))
    (define v (unit (direction copied-ray)))
    (define a (unit (point- B A))) (define b (unit (point- C A)))
    (near (dot u v) (dot a b))
    (near (cross u v) (* (if (eq? side 'left) 1 -1) (abs (cross a b))))))

;; One source of truth for all test wrappers; each group is an independently
;; runnable named thunk. No testing-library emulation or network dependency.
(define library-check-groups
  (append
   (for/list ([h (in-list helpers)] [types (in-list expected-types)])
     (cons (format "signature and straightedge/compass graph: ~a" (construction-helper-name h))
           (lambda ()
             (ensure (equal? (append (map cdr (construction-helper-parameters h))
                                    (construction-helper-result-types h)) types)
                     "incorrect helper signature")
             (define body (construction-helper-program h))
             (ensure (pair? (geometry-program-assertions body)) "missing postconditions")
             (ensure (pair? (geometry-program-steps body)) "missing exposition")
             ;; The midpoint kernel is allowed in tests/assertions, never as a
             ;; shortcut for an output in these eight algorithms.
             (for ([n (in-list (geometry-program-nodes body))])
               (ensure (not (contains-op? (geometry-node-expression n) 'midpoint))
                       "library used a midpoint shortcut" (geometry-node-id n))))))
   (for*/list ([scale (in-list '(0.01 1 40))] [theta (in-list '(0 0.37 1.71))]
               [reflect? (in-list '(#f #t))])
     (cons (format "all eight constructions: scale ~a, rotation ~a, reflection ~a" scale theta reflect?)
           (lambda () (transformed-library-check scale theta reflect?))))
   (list
    (cons "acute, right and obtuse angle copies and bisectors"
      (lambda ()
        (for* ([theta (in-list (list 0.12 0.6 (/ pi 2) 2.3 3.0))] [flip (in-list '(1 -1))])
          (define A (point 2 0)) (define B (point 0 0))
          (define C (point (* 3 (cos theta)) (* flip 3 (sin theta))))
          (define r (result-value c:angle-bisector
                      (run-helper c:angle-bisector (hash 'A A 'B B 'C C))))
          (same-point (unit (direction r)) (point (cos (/ theta 2)) (* flip (sin (/ theta 2)))))
          (for ([side '(left right)])
            (define target (ray (point 4 2) (point 4 3)))
            (define r2 (result-value c:copy-angle
                         (run-helper c:copy-angle (hash 'source (angle-spec A B C)
                                                       'target target 'side side))))
            (near (dot (unit (direction r2)) (point 0 1)) (cos theta))
            (near (cross (point 0 1) (unit (direction r2)))
                  (* (if (eq? side 'left) 1 -1) (sin theta)))))))
    (cons "preconditions reject degenerate or wrong-domain inputs"
      (lambda ()
        (define A (point 0 0)) (define B (point 2 0)) (define C (point 0 1))
        (define l (line A B))
        (for ([h (list c:perpendicular-bisector c:bisect-segment)])
          (expect-error (lambda () (run-helper h (hash 'A A 'B A)))))
        (expect-error (lambda () (run-helper c:erect-perpendicular (hash 'l l 'P C))))
        (for ([h (list c:drop-perpendicular c:parallel-through-point)])
          (expect-error (lambda () (run-helper h (hash 'l l 'P A)))))
        (for ([p (list A B (point -2 0))])
          (expect-error (lambda () (run-helper c:angle-bisector (hash 'A B 'B A 'C p)))))
        (expect-error (lambda () (run-helper c:copy-angle
                                  (hash 'source (angle-spec B A B) 'target (ray A C) 'side 'left))))
        (expect-error (lambda () (run-helper c:copy-angle
                                  (hash 'source (angle-spec B A C) 'target (ray A C) 'side 'above))))
        (expect-error (lambda () (run-helper c:copy-segment
                                  (hash 'source (circle A B) 'target (ray A C)))))))
    (cons "typed Angle, Side and Relation values are not drawable"
      (lambda ()
        (define p (program '((given [A (point 0 0)] [B (point 2 0)] [C (point 0 2)]
                                    [ang (angle B A C)] [side 'left]
                                    [fact (equal-length (segment A B) (segment A C))])
                             (step [mark (marker fact)]) (assert fact))))
        (define r (realize-construction p))
        (ensure (eq? (geometry-kind (construction-ref r 'ang)) 'Angle) "Angle type")
        (ensure (eq? (geometry-kind (construction-ref r 'side)) 'Side) "Side type")
        (ensure (eq? (geometry-kind (construction-ref r 'fact)) 'Relation) "Relation type")
        (ensure (equal? (sort (construction-visible-ids p) symbol<?) '(A B C mark)) "non-drawable leaked into view")
        (expect-error (lambda () (program '((given [x 'left]) (step (show x))))))
        (expect-error (lambda () (program '((given [A (point 0 0)]) (step [a (angle A A)])))))))
    (cons "typed helper Side argument is hygienically substituted"
      (lambda ()
        (define p (program '((given [A (point 2 0)] [B (point 0 0)] [C (point 0 2)]
                                    [s 'right] [a (angle A B C)] [r (ray (point 4 0) (point 5 0))])
                             (step [answer (copy a r s)])) (hash 'copy c:copy-angle)))
        (define r (realize-construction p))
        (define answer (construction-ref r 'answer))
        (ensure (< (point-y (end-point answer)) 0) "chosen side lost through helper")
        (expect-error (lambda () (program '((given [A (point 1 0)] [O (point 0 0)] [B (point 0 1)])
                                            (step [r (copy (angle A O B) (ray O A) 'above)]))
                                          (hash 'copy c:copy-angle))))))
    (cons "numeric compass radius validation and accessors"
      (lambda ()
        (define p (program '((given [A (point 1 2)] [B (point 4 2)])
                             (step [c (circle A #:radius (distance A B))]
                                   [P (intersection c (ray A B))]
                                   [a (angle B A (point 1 3))]
                                   [V (angle-vertex a)]))))
        (define r (realize-construction p))
        (same-point (construction-ref r 'P) (point 4 2))
        (same-point (construction-ref r 'V) (point 1 2))
        (near (circle-radius (construction-ref r 'c)) 3)
        (for ([radius (list 0 -1 +inf.0 +nan.0)])
          (expect-error (lambda () (circle-with-radius (point 0 0) radius))))
        (expect-error (lambda () (program '((given [A (point 0 0)]) (step [c (circle A #:radius A)])))))))
    (cons "false relations are values until require, assert or marker validates them"
      (lambda ()
        (define env (hash 'AB (segment (point 0 0) (point 2 0))
                          'AC (segment (point 0 0) (point 0 3))))
        (define rel (evaluate-expression '(equal-length AB AC) env))
        (ensure (relation? rel) "false relation must remain representable")
        (ensure (not (relation-holds? rel)) "false equality is true")
        (ensure (evaluate-expression '(not (equal-length AB AC)) env) "not relation")
        (ensure (evaluate-expression '(or (equal-length AB AC) #t) env) "or relation")
        (ensure (not (evaluate-expression '(and #t (equal-length AB AC)) env)) "and relation")
        (expect-error (lambda () (relation->marker rel)))
        (ensure (evaluate-expression '(not (perpendicular AB (line (point 0 1) (point 2 1)))) env)
                "non-intersecting perpendicular relation must be false")
        (expect-error (lambda () (realize-construction
                                  (program '((given [AB (segment (point 0 0) (point 2 0))]
                                                    [AC (segment (point 0 0) (point 0 3))])
                                             (assert (equal-length AB AC)))))) #rx"assertion failed")))
    (cons "assertions never select a lucky layout candidate"
      (lambda ()
        (define clauses '((given [A (point 0 0)] [B (point)]) (require (distinct? A B))))
        (define selected (realize-construction (program clauses) #:samples 8))
        (define B (construction-ref selected 'B))
        ;; Reject exactly the layout selected without the assertion. An
        ;; incorrect implementation would search for a different candidate.
        (define p (program (append clauses `((assert (distinct? B (point ,(point-x B) ,(point-y B))))))))
        (expect-error (lambda () (realize-construction p #:samples 8)) #rx"assertion failed")))
    (cons "step assertions are silent and reject forward references"
      (lambda ()
        (define clauses '((given [A (point 0 0)] [B (point 2 0)])
                          (step "Join." [AB (segment A B)])))
        (define plain (construction->timeline (program clauses)))
        (define checked (construction->timeline
                         (program '((given [A (point 0 0)] [B (point 2 0)])
                                    (step "Join." [AB (segment A B)] (assert (on A AB)))))))
        (near (geometry-timeline-duration checked) (geometry-timeline-duration plain))
        (ensure (= (length (geometry-timeline-events plain)) (length (geometry-timeline-events checked)))
                "assertion created an animation slot")
        (expect-error (lambda () (program '((given [A (point 0 0)] [B (point 2 0)])
                                            (step (assert (on A AB)) [AB (segment A B)])))))))
    (cons "library input arities and result types are checked early"
      (lambda ()
        (expect-error (lambda () (program '((given [A (point 0 0)]) (step [M (mid A)]))
                                          (hash 'mid c:bisect-segment))))
        (expect-error (lambda () (program '((given [A (point 0 0)] [B (point 1 0)])
                                            (step [r (copy (segment A B) (line A B))]))
                                          (hash 'copy c:copy-segment))))
        (expect-error (lambda () (program '((given [A (point 0 0)] [B (point 1 0)])
                                            (step [(X Y) (mid A B)])) (hash 'mid c:bisect-segment))))))
    (cons "collapsed and expanded helper results agree, cleanup protects caller"
      (lambda ()
        (define clauses '((given [A (point -2 0)] [B (point 2 0)])))
        (define hs (hash 'mid c:bisect-segment))
        (define plain (program (append clauses '((step [M (mid A B)]))) hs))
        (define expanded (program (append clauses '((step (expand [M (mid A B)] #:auxiliaries 'hide)))) hs))
        (define tp (construction->timeline plain)) (define te (construction->timeline expanded))
        (same-point (construction-ref (geometry-timeline-realization tp) 'M)
                    (construction-ref (geometry-timeline-realization te) 'M))
        (ensure (> (geometry-timeline-duration te) (geometry-timeline-duration tp)) "expanded exposition missing")
        (for ([id '(A B M)])
          (ensure (presentation-shown? (hash-ref (geometry-timeline-final te) id)) "cleanup hid caller/result" id))
        (for ([(id state) (in-hash (geometry-timeline-final te))] #:unless (memq id '(A B M)))
          (ensure (not (presentation-shown? state)) "cleanup leaked auxiliary" id))
        (ensure (equal? (sort (construction-visible-ids plain) symbol<?) '(A B M)) "collapsed leaks helper")
        (ensure (pair? (geometry-program-assertions plain)) "collapsed loses helper postconditions")
        (expect-error (lambda () (program (append clauses '((step (expand [M (mid A B)] #:auxiliaries 'erase)))) hs)))))
    (cons "two expanded calls retain separate identities and deemphasis policies"
      (lambda ()
        (define p (program '((given [A (point -2 0)] [B (point 2 0)] [C (point 1 3)])
                             (step (expand [m (pb A B)] #:auxiliaries 'deemphasize))
                             (step (expand [n (pb B C)] #:auxiliaries 'hide)))
                           (hash 'pb c:perpendicular-bisector)))
        (define t (construction->timeline p))
        (define ids (map geometry-node-id (geometry-program-nodes p)))
        (ensure (= (length ids) (length (remove-duplicates ids))) "duplicate helper IDs")
        (for ([id '(A B C m n)])
          (define st (hash-ref (geometry-timeline-final t) id))
          (ensure (and (presentation-shown? st) (not (presentation-secondary? st))) "caller restyled" id))
        (ensure (for/or ([(id st) (in-hash (geometry-timeline-final t))]
                         #:unless (memq id '(A B C m n)))
                  (and (presentation-shown? st) (presentation-secondary? st)))
                "deemphasize cleanup missing")))
    (cons "helper assertions survive collapsed composition"
      (lambda ()
        (define h (make-construction-helper 'wrong
                    '((given [A : Point] [B : Point]) (results Point)
                      (step [M (midpoint A B)]) (assert (= (distance A M) 12345)) (result M))
                    (hash) "test"))
        (expect-error (lambda () (construction->timeline
                                  (program '((given [A (point 0 0)] [B (point 4 0)])
                                             (step [M (wrong A B)])) (hash 'wrong h))))
                      #rx"assertion failed")))
    (cons "two prefixes for one exported helper both resolve"
      (lambda ()
        (define r (realize-construction two-prefixes))
        (ensure (line? (construction-ref r 'm)) "first alias")
        (ensure (line? (construction-ref r 'n)) "second alias")
        (radii r '(A B C))))
    (cons "all primitive accessor misuse is diagnosed"
      (lambda ()
        (for ([e '((start-point (circle (point 0 0) (point 1 0)))
                   (end-point (point 0 0))
                   (angle-first (line (point 0 0) (point 1 0)))
                   (side-of? (point 0 1) (line (point 0 0) (point 1 0)) 'up)
                   (marker (collinear (point 0 0) (point 1 0) (point 2 0))))])
          (expect-error (lambda () (program `((given [P (point 0 0)]) (step [result ,e])))))))))
   ;; Application tests and gallery tests are appended below.
   (for*/list ([name (in-list library-example-names)] [mode '(light dark)])
     (cons (format "application, independent oracle, reveal and annotations: ~a / ~a" name mode)
           (lambda () (check-application name mode))))
   (for/list ([mode '(light dark)])
     (cons (format "gallery library plates / ~a" mode)
           (lambda ()
             (define make (dynamic-require (build-path examples "gallery.rkt") 'make-demo-timeline))
             (define t (make #:theme-mode mode))
             (define a (prepare-geometry-annotations t))
             (ensure (annotation-plan? a) "gallery annotations failed")
             (ensure (null? (annotation-plan-warnings a)) "gallery estimated-layout collisions" (annotation-plan-warnings a))
             (ensure (> (geometry-timeline-duration t) 100) "library gallery plates missing")
             (check-sampling t))))))

(define (check-sampling t)
  (define duration (geometry-timeline-duration t))
  (define times (for/list ([i (in-range 25)]) (* duration (/ i 24))))
  (define expected (map (lambda (time) (sample-geometry-timeline t time)) times))
  (for ([time (in-list (reverse times))]) (sample-geometry-timeline t time))
  (ensure (equal? expected (map (lambda (time) (sample-geometry-timeline t time)) times))
          "random access changed sampled frames")
  ;; Simulate round-robin process partitioning without relying on OS scheduling.
  (for* ([worker (in-range 10)] [i (in-range worker 25 10)])
    (ensure (equal? (list-ref expected i) (sample-geometry-timeline t (list-ref times i)))
            "sharded sampling differs from sequential sampling" i))
  ;; Every fresh reveal with a target progresses from 0 to 1 without jumping.
  (for ([event (in-list (geometry-timeline-events t))])
    (define mid (/ (+ (geometry-event-start event) (geometry-event-end event)) 2))
    (define frame (sample-geometry-timeline t mid))
    (for* ([action (in-list (geometry-event-actions event))]
           #:when (eq? (geometry-action-kind action) 'reveal)
           [id (in-list (geometry-action-targets action))]
           #:unless (presentation-shown? (hash-ref (geometry-event-before event) id)))
      (define app (hash-ref (geometry-frame-appearances frame) id))
      (near (geometry-appearance-reveal app) 0.5))))

(define (check-application name mode)
  (define path (build-path examples (string-append name ".rkt")))
  (define make (dynamic-require path 'make-demo-timeline))
  (define t (make #:theme-mode mode))
  (define r (geometry-timeline-realization t))
  (define (v id) (construction-ref r id))
  (define program (geometry-realization-program r))
  (ensure (pair? (geometry-program-assertions program)) "example missing postconditions")
  (case (string->symbol name)
    [(square-on-segment)
     (define u (point- (v 'B) (v 'A)))
     (define vv (point (- (point-y u)) (point-x u)))
     (same-point (v 'D) (point+ (v 'A) vv))
     (same-point (v 'C) (point+ (v 'B) vv))
     (equal-sides r '(AB BC CD AD))]
    [(circumcenter)
     (radii r '(A B C))
     (for ([id '(A B C)]) (near (distance (v 'O) (v id)) (circle-radius (v 'k))))]
    [(incircle)
     (define A (v 'A)) (define B (v 'B)) (define C (v 'C))
     (define aa (distance B C)) (define bb (distance A C)) (define cc (distance A B))
     (define weighted (point* (point+ (point+ (point* A aa) (point* B bb)) (point* C cc))
                              (/ 1 (+ aa bb cc))))
     (same-point (v 'I) weighted)
     (for ([pair '((T A B) (U C A) (V B C))])
       (same-point (v (car pair)) (projection weighted (line (v (cadr pair)) (v (caddr pair)))))
       (near (distance weighted (v (car pair))) (circle-radius (v 'k))))]
    [(triangle-midline)
     (same-point (v 'M) (point* (point+ (v 'A) (v 'C)) 1/2))
     (same-point (v 'N) (point* (point+ (v 'B) (v 'C)) 1/2))
     (near (length-of (v 'MN)) (/ (distance (v 'A) (v 'B)) 2))]
    [(reflect-point)
     (define H (projection (v 'P) (v 'l)))
     (same-point (v 'H) H) (same-point (v 'Q) (point- (point* H 2) (v 'P)))]
    [(copy-triangle-sas)
     (near (distance (v 'O) (v 'B2)) (distance (v 'A) (v 'B)))
     (near (distance (v 'O) (v 'C2)) (distance (v 'A) (v 'C)))
     (near (distance (v 'B2) (v 'C2)) (distance (v 'B) (v 'C)))
     (ensure (positive? (cross (point- (v 'B2) (v 'O)) (point- (v 'C2) (v 'O)))) "SAS orientation")]
    [(divide-segment-five)
     (for ([id '(X1 X2 X3 X4)] [n (in-naturals 1)])
       (same-point (v id) (point+ (v 'A) (point* (point- (v 'B) (v 'A)) (/ n 5)))))
     (equal-sides r '(s1 s2 s3 s4 s5))]
    [(tangent-at-point)
     (same-point (projection (v 'O) (v 't)) (v 'P))
     (near (distance (v 'O) (projection (v 'O) (v 't))) (circle-radius (v 'k)))]
    [(orthocenter)
     (for ([pair '((A B C) (B A C) (C A B))])
       (define vertex (v (car pair))) (define side (line (v (cadr pair)) (v (caddr pair))))
       (near (dot (unit (direction side)) (point- (v 'H) vertex)) 0))]
    [(regular-hexagon)
     (define o (v 'O)) (define d (point- (v 'A) o))
     (for ([id '(A B C D E F)] [i (in-naturals)])
       (define theta (* i (/ pi 3)))
       (same-point (v id) (point+ o (point (- (* (point-x d) (cos theta)) (* (point-y d) (sin theta)))
                                           (+ (* (point-x d) (sin theta)) (* (point-y d) (cos theta)))))))
     (equal-sides r '(AB BC CD DE EF FA))]
    [(equilateral-triangle-chain)
     (equal-sides r '(AB AC BC BD BE DE DF DG FG))
     (same-point (v 'D) (point+ (v 'B) (point- (v 'B) (v 'A))))
     (same-point (v 'F) (point+ (v 'D) (point- (v 'B) (v 'A))))]
    [(parallel-at-distance)
     (parallel (v 'l) (v 'm))
     (near (distance (v 'P) (projection (v 'P) (v 'l))) (length-of (v 'unit)))]
    [(copy-angle)
     (define u (unit (direction (v 'target)))) (define w (unit (direction (v 'r))))
     (define a (unit (point- (v 'A) (v 'B)))) (define b (unit (point- (v 'C) (v 'B))))
     (near (dot u w) (dot a b))
     (ensure (negative? (cross u w)) "right-side copied angle")]
    [else (error 'check-application "missing independent oracle for ~a" name)])
  (check-sampling t)
  (define a (prepare-geometry-annotations t))
  (define b (prepare-geometry-annotations t))
  (ensure (equal? a b) "annotation placement is not deterministic")
  (ensure (and (positive? (hash-count (annotation-plan-labels a)))
               (positive? (hash-count (annotation-plan-marker-placements a))))
          "missing labels/markers")
  (ensure (not (ormap (lambda (warning) (eq? (car warning) 'outside-safe-area)) (annotation-plan-warnings a)))
          "annotation outside safe area" (annotation-plan-warnings a))
  ;; The three gallery prototypes are intentionally static. Every application
  ;; has at least one narrated reading phase before its first fresh action.
  (define cue (car (geometry-timeline-cues t)))
  (ensure (string? (geometry-cue-text cue)) "narration missing")
  (ensure (not (regexp-match? #rx"[Ee]mphasiz|[Dd]eemphasiz|[Hh]ighlight" (geometry-cue-text cue)))
          "narration describes styling rather than mathematics"))

(define (run-library-checks #:verbose? [verbose? #t])
  (define counter (box 0))
  (define start (current-inexact-milliseconds))
  (parameterize ([check-counter counter])
    (for ([g (in-list library-check-groups)])
      (when verbose? (printf "~a ... " (car g)) (flush-output))
      (parameterize ([current-group (car g)]) ((cdr g)))
      (when verbose? (displayln "ok"))))
  (define summary (hash 'groups (length library-check-groups) 'checks (unbox counter)
                         'elapsed-ms (- (current-inexact-milliseconds) start)))
  (when verbose?
    (printf "~a groups, ~a checks passed.\n" (hash-ref summary 'groups) (hash-ref summary 'checks)))
  summary)
(module+ main (void (run-library-checks)))
