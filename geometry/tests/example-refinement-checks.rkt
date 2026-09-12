#lang racket/base

;; User review notes, 2026-09-12: executable headless regression checks. These
;; exercise the real DSL, helper expansion, annotation planner, and drawing order.
(require racket/list racket/runtime-path racket/string
         (only-in racket/math pi)
         "../core.rkt" "../private/compiler.rkt" "../private/drawing.rkt")
(provide example-refinement-check-groups run-example-refinement-checks)
(define-runtime-path examples "../examples")
(define counter (make-parameter #f))
(define group-name (make-parameter "example-refinements"))
(define (check condition message . values)
  (when (counter) (set-box! (counter) (add1 (unbox (counter)))))
  (unless condition (error 'example-refinements "~a: ~a ~s" (group-name) message values)))
(define (near a b [epsilon 1e-8])
  (check (<= (abs (- a b)) epsilon) "numeric mismatch" a b))
(define (same p q) (near (distance p q) 0))
(define (build name mode)
  ((dynamic-require (build-path examples (string-append name ".rkt")) 'make-demo-timeline)
   #:theme-mode mode))
(define (program-of t) (geometry-realization-program (geometry-timeline-realization t)))
(define (env-of t) (geometry-realization-values (geometry-timeline-realization t)))
(define (style-of t id)
  (define n (findf (lambda (n) (eq? id (geometry-node-id n)))
                   (geometry-program-nodes (program-of t))))
  (resolve-geometry-style (geometry-timeline-theme t) (geometry-node-type n) 'normal
                          (object-style-overrides (program-of t) id)))
(define (captions t)
  (filter values (map geometry-step-span-narration (geometry-timeline-steps t))))
(define (make-program clauses [helpers (hash)])
  (make-construction-program 'refinement clauses helpers "example-refinement-checks.rkt"))
(define (fails thunk)
  (check (with-handlers ([exn:fail:geometry? (lambda (e) #t)]) (thunk) #f)
         "expected a geometry diagnostic"))

(define scalene-examples
  '("circumcenter" "copy-triangle-sas" "incircle" "orthocenter" "triangle-midline"))
(define triangle-groups
  (for*/list ([name scalene-examples] [mode '(light dark)])
    (cons (format "distinctly scalene, acute input: ~a / ~a" name mode)
      (lambda ()
        (define t (build name mode)) (define env (env-of t))
        (define A (hash-ref env 'A)) (define B (hash-ref env 'B)) (define C (hash-ref env 'C))
        (define lengths (sort (list (distance A B) (distance A C) (distance B C)) <))
        (define angles (map (lambda (a) (* (/ 180 pi) (angle-measure a)))
                            (list (angle-spec B A C) (angle-spec A B C) (angle-spec A C B))))
        ;; Prevent a return to nearly equilateral or nearly isosceles inputs.
        (check (> (/ (last lengths) (car lengths)) 1.45) "insufficient side contrast" lengths)
        (for ([x lengths] [y (cdr lengths)])
          (check (> (- y x) (* 0.10 (last lengths))) "two sides are too similar" lengths))
        (check (andmap (lambda (a) (< 30 a 86)) angles) "skinny, right, or obtuse input" angles)
        (check (> (- (apply max angles) (apply min angles)) 35) "angles are too alike" angles)
        (near (apply + angles) 180)
        ;; Realization also evaluates each example's existing postconditions.
        (check (pair? (geometry-program-assertions (program-of t))) "missing mathematical postconditions")
        (define plan (prepare-geometry-annotations t))
        (check (not (ormap (lambda (w) (eq? (car w) 'outside-safe-area))
                           (annotation-plan-warnings plan))) "label outside the view")
        (when (member name '("circumcenter" "incircle" "orthocenter"))
          (define center (hash-ref env (cond [(equal? name "circumcenter") 'O]
                                            [(equal? name "incircle") 'I] [else 'H])))
          ;; For these acute examples the center is inside the triangle, but
          ;; visibly displaced from the equilateral/centroid special case.
          (define centroid (point* (point+ (point+ A B) C) 1/3))
          (check (> (distance center centroid) (* 0.04 (last lengths)))
                 "center is still too close to the symmetric special case" center centroid))))))

(define direction-groups
  (for/list ([mode '(light dark)])
    (cons (format "angle copy preserves the source's left side / ~a" mode)
      (lambda ()
        (define t (build "copy-angle" mode)) (define env (env-of t))
        (define source-a (point- (hash-ref env 'A) (hash-ref env 'B)))
        (define source-b (point- (hash-ref env 'C) (hash-ref env 'B)))
        (define target (hash-ref env 'target)) (define result (hash-ref env 'r))
        (define u (point- (ray-b target) (ray-a target)))
        (define v (point- (ray-b result) (ray-a result)))
        (check (> (cross source-a source-b) 0) "source is not left of BA")
        (check (> (cross u v) 0) "copy is not left of the target")
        (near (/ (dot source-a source-b) (* (norm source-a) (norm source-b)))
              (/ (dot u v) (* (norm u) (norm v))))
        (check (member "Copy the angle onto the left side of the target ray." (captions t))
               "incorrect side in narration")
        (check (not (ormap (lambda (s) (regexp-match? #rx"right side" s)) (captions t))) "old right-side caption")
        (define plan (prepare-geometry-annotations t))
        (for ([id '(source-mark target-mark)])
          (check (equal? (hash-ref (annotation-plan-texts plan) id) "α") "alpha missing" id))
        (check (= (hash-ref (annotation-plan-marker-counts plan) 'source-mark)
                  (hash-ref (annotation-plan-marker-counts plan) 'target-mark)) "matching arcs differ")))))

(define label-groups
  (for/list ([mode '(light dark)])
    (cons (format "division labels are close, stable and unambiguous / ~a" mode)
      (lambda ()
        (define t (build "divide-segment-five" mode))
        (define env (env-of t))
        (define ids '(P1 P2 P3 P4 P5))
        (define plan (prepare-geometry-annotations t))
        (check (equal? plan (prepare-geometry-annotations t)) "unstable annotation placement")
        (for ([id ids] [text '("P₁" "P₂" "P₃" "P₄" "P₅")])
          (define p (hash-ref env id)) (define q (hash-ref (annotation-plan-labels plan) id))
          (same (point- q p) (point -0.54 -0.08))
          (check (< (distance p q) 0.55) "label too far from its point" id)
          (check (equal? (hash-ref (annotation-plan-texts plan) id) text) "subscript lost" id)
          (near (hash-ref (style-of t id) 'font-size) 0.28) ; do not shrink the text
          (for ([other ids] #:unless (eq? other id))
            (check (< (distance q p) (distance q (hash-ref env other))) "ambiguous nearest point" id other)))
        (for ([w (annotation-plan-warnings plan)])
          (when (and (eq? (car w) 'label-geometry-overlap) (memq (cadr w) ids))
            ;; One transient compass arc may cross a conservative estimated
            ;; text box. No parallel, auxiliary ray, or point may do so.
            (check (circle? (hash-ref env (caddr w))) "division label intersects ray/parallel/point" w)))))))

(define naming-groups
  (for*/list ([name '("parallel-at-distance" "tangent-at-point")] [mode '(light dark)])
    (cons (format "helper points use Q, R, S, not X/Y: ~a / ~a" name mode)
      (lambda ()
        (define t (build name mode)) (define p (program-of t))
        (define-values (visible label-masks) (geometry-visibility-masks t))
        (define labels
          (for/list ([n (geometry-program-nodes p)]
                      #:when (and (eq? (geometry-node-type n) 'Point)
                                  (hash-has-key? label-masks (geometry-node-id n))))
            (annotation-text p (geometry-node-id n))))
        (for ([letter '("Q" "R" "S")]) (check (member letter labels) "preferred helper label missing" letter))
        (check (= (length labels) (length (remove-duplicates labels))) "ambiguous displayed point name" labels)
        (for ([text labels]) (check (not (regexp-match? #rx"^[XY]" text)) "unwanted X/Y helper label" text))
        (check (member "Call one of the circle intersections S." (captions t)) "helper caption not updated")
        (check (member "Let R be the other intersection with the line." (captions t)) "other intersection caption not updated")
        (check (not (ormap (lambda (s) (regexp-match? #px"\\b[XY]\\b" s)) (captions t))) "old helper name in caption")))))

(define layering-groups
  (for/list ([mode '(light dark)])
    (cons (format "the square's original gold segment stays in front of its supporting line / ~a" mode)
      (lambda ()
        (define t (build "square-on-segment" mode)) (define env (env-of t))
        (define nodes (geometry-program-nodes (program-of t)))
        (define ordered (ordered-drawable-nodes nodes))
        (define ids (map geometry-node-id ordered))
        (define A (hash-ref env 'A)) (define B (hash-ref env 'B))
        (define base-position (index-of ids 'AB))
        (define supports
          (filter (lambda (n)
                    (define value (hash-ref env (geometry-node-id n)))
                    (and (or (line? value) (ray? value)) (on A value) (on B value))) nodes))
        (check (pair? supports) "test did not find the helper's overlaid supporting line")
        (for ([n supports])
          (check (< (index-of ids (geometry-node-id n)) base-position) "support paints above gold AB"))
        (define normal (style-of t 'AB))
        (check (eq? (hash-ref normal 'stroke-family) 'gold) "AB is no longer gold")
        (define active-support? #f)
        (for ([event (geometry-timeline-events t)])
          (for ([state (list (geometry-event-before event) (geometry-event-after event))])
            (when (ormap (lambda (n) (presentation-shown? (hash-ref state (geometry-node-id n)))) supports)
              (set! active-support? #t)
              (check (presentation-shown? (hash-ref state 'AB)) "base was hidden to work around overpainting")
              (check (not (presentation-secondary? (hash-ref state 'AB))) "gold base was faded out"))))
        (check active-support? "supporting line was removed instead of layered")
        (check (equal? (map geometry-node-id (filter (lambda (n) (memq (geometry-node-type n) '(Segment Circle))) ordered))
                       (map geometry-node-id (filter (lambda (n) (memq (geometry-node-type n) '(Segment Circle))) nodes)))
               "relative source order of finite curves changed")))))

(define color-groups
  (for/list ([mode '(light dark)])
    (cons (format "hexagon circumcircle has a distinct color family / ~a" mode)
      (lambda ()
        (define t (build "regular-hexagon" mode))
        (define main-family (hash-ref (style-of t 'k) 'stroke-family))
        (check (eq? main-family 'purple) "main circle family changed")
        (for ([n (geometry-program-nodes (program-of t))]
               #:when (and (eq? (geometry-node-type n) 'Circle) (not (eq? (geometry-node-id n) 'k))))
          (check (not (eq? main-family (hash-ref (style-of t (geometry-node-id n)) 'stroke-family)))
                 "helper circle shares main color family" (geometry-node-id n)))
        (check (presentation-shown? (hash-ref (geometry-timeline-final t) 'k)) "main circle hidden at conclusion")))))

(define relative-pin-groups
  (list
    (cons "label-offset follows the realized point, including overridden givens"
      (lambda ()
        (define p (make-program '((given [A (point 2 3)]) (layout (label-offset A (point -0.5 -0.1))))))
        (for ([A (list (point 2 3) (point -4 2))])
          (define t (construction->timeline p #:givens (hash 'A A)))
          (same (hash-ref (annotation-plan-labels (prepare-geometry-annotations t)) 'A)
                (point+ A (point -0.5 -0.1))))))
    (cons "absolute pins and adapter overrides take precedence over relative offsets"
      (lambda ()
        (define p (make-program '((given [A (point 2 3)])
                                 (layout (label-offset A (point -0.5 -0.1)) (label-at A (point 3 4))))))
        (define t (construction->timeline p))
        (same (hash-ref (annotation-plan-labels (prepare-geometry-annotations t)) 'A) (point 3 4))
        (same (hash-ref (annotation-plan-labels (prepare-geometry-annotations t #:labels (hash 'A (point 1 4)))) 'A)
              (point 1 4))))
    (cons "relative offsets must be finite literals attached to points"
      (lambda ()
        (for ([hint '((label-offset A (point +nan.0 0)) (label-offset A (point 0 +inf.0))
                      (label-offset missing (point 0 0)) (label-offset s (point 0 0))
                      (label-offset A 2) (label-offset A (point 0)))])
          (fails (lambda () (make-program `((given [A (point 0 0)] [B (point 2 0)] [s (segment A B)])
                                           (layout ,hint))))))))
    (cons "helper-relative offsets are hygienically renamed onto result aliases"
      (lambda ()
        (define h
          (make-construction-helper 'located
            '((given [A : Point] [B : Point]) (results Point)
              (layout (label-offset M (point -0.4 0.15)))
              (step [M (midpoint A B)]) (result M)) (hash) "relative pin helper"))
        (define p (make-program '((given [P (point 0 0)] [Q (point 4 0)])
                                 (step (expand [answer (located P Q)]))) (hash 'located h)))
        (define t (construction->timeline p))
        (same (hash-ref (annotation-plan-labels (prepare-geometry-annotations t)) 'answer) (point 1.6 0.15))))))

(define example-refinement-check-groups
  (append triangle-groups direction-groups label-groups naming-groups
          layering-groups color-groups relative-pin-groups))
(define (run-example-refinement-checks)
  (define counts (box 0))
  (for ([group example-refinement-check-groups])
    (printf "~a ... " (car group)) (flush-output)
    (parameterize ([counter counts] [group-name (car group)]) ((cdr group)))
    (displayln "ok"))
  (printf "~a refinement groups, ~a checks passed.\n"
          (length example-refinement-check-groups) (unbox counts)))
(module+ main (run-example-refinement-checks))
