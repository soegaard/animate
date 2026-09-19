#lang racket/base

;;;
;;; Calculus Core Smoke Tests
;;;

;; Exercises the first end-to-end headless reading lesson without importing a
;; renderer, font backend, or scene adapter.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt"
         (only-in "../private/core.rkt"
                  calculus-lesson-views
                  calculus-model-nodes
                  calculus-plan-lesson
                  calculus-snapshot-trace-points
                  calculus-snapshot-view-window))

;; Exports
(provide run-calculus-core-smoke-tests)


;;;
;;; Fixtures
;;;

(define-calculus-lesson reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R))])
  (initially (show G))
  (step read-output (read R))
  (step vary-input (vary a #:to -2 #:duration 4)))

;; invalid-parameter-path : calculus-lesson?
;;   Deliberately targets a value outside its declared parameter domain.
(define-calculus-lesson invalid-parameter-path
  (model
    [a (parameter 0 #:domain (closed -1 1))]
    [f (function (x) x)]
    [G (graph f)])
  (views [plot (graph-view #:x (closed -1 1) #:y (closed -1 1) #:objects (G))])
  (initially (show G))
  (step leave-domain (vary a #:to 2 #:duration 1)))

;; coincident-geometry-model : calculus-model?
;;   Distinguishes the valid degenerate segment from undefined directed lines.
(define-calculus-model coincident-geometry-model
  (model
    [P (point 1 1)]
    [S (segment P P)]
    [L (line-through P P)]
    [R (ray-through P P)]))

;; integer-variation : calculus-lesson?
;;   Deliberately attempts to interpolate a discrete parameter.
(define-calculus-lesson integer-variation
  (model
    [n (parameter 2 #:domain (integers 1 8) #:kind 'integer)])
  (views [numbers (number-line-view #:objects (n))])
  (step interpolate-count (vary n #:to 4 #:duration 1)))

;; invalid-integer-assignment : calculus-lesson?
;;   Assignments must preserve the declared discrete parameter capability.
(define-calculus-lesson invalid-integer-assignment
  (model
    [n (parameter 2 #:domain real-line #:kind 'integer)])
  (views [numbers (number-line-view #:objects (n))])
  (step fractional-count (set-parameter n 3/2)))

;; excluded-path : calculus-lesson?
;;   Deliberately crosses a declared hole while both endpoints are valid.
(define-calculus-lesson excluded-path
  (model
    [u (parameter 0 #:domain (domain-except (closed 0 2) 1))])
  (views [number-line (number-line-view #:objects (u))])
  (step cross-hole (vary u #:to 2 #:duration 1)))

;; incomplete-approach : calculus-lesson?
;;   Omits the finite authored stopping value required by approach.
(define-calculus-lesson incomplete-approach
  (model
    [u (parameter 0 #:domain (closed 0 2))])
  (views [number-line (number-line-view #:objects (u))])
  (step missing-stop (approach u #:to 1 #:side 'right #:duration 1)))

;; wrong-side-after-assignment : calculus-lesson?
;;   Verifies side validation uses the preceding assignment, not initial state.
(define-calculus-lesson wrong-side-after-assignment
  (model
    [u (parameter 0 #:domain (closed 0 2))])
  (views [number-line (number-line-view #:objects (u))])
  (step move-right (set-parameter u 2))
  (step approach-from-wrong-side
    (approach u #:to 1 #:side 'left #:until 9/10 #:duration 1)))

;; invalid-trace : calculus-lesson?
;;   A trace sweep must begin at the trace parameter's current value.
(define-calculus-lesson invalid-trace
  (model
    [u (parameter 1 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x u)]
    [locus (trace-of P #:parameter u #:over (closed 0 2))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 4)
                           #:objects (G P locus))])
  (step trace-locus (trace locus #:duration 1)))

;; trace-prefix : calculus-lesson?
;;   Provides an exact random-access locus whose animated prefix is determined
;;   by the authored sweep coordinate, never by earlier rendered frames.
(define-calculus-lesson trace-prefix
  (model
    [u (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x u)]
    [locus (trace-of P #:parameter u #:over (closed 0 2))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 4)
                           #:objects (G P locus))])
  (initially (show G))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step trace-locus (trace locus #:duration 2)))

;; focus-window : calculus-lesson?
;;   Freezes dynamic focus endpoints at action start and restores the declared
;;   prepared window without changing the parameter or graph coordinates.
(define-calculus-lesson focus-window
  (model
    [u (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -2 2)
                           #:objects (G))])
  (initially (show G))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step focus-plot
    (focus plot #:x (closed u (+ u 1)) #:y (closed -1 1) #:duration 2))
  (step move-parameter (set-parameter u 1))
  (step restore-plot (restore-view plot #:duration 2)))

;; invalid-focus-window : calculus-lesson?
;;   Focus is restricted to a declared graph view, not a number-line view.
(define-calculus-lesson invalid-focus-window
  (model [u (parameter 0 #:domain (closed 0 1))])
  (views [numbers (number-line-view #:objects (u))])
  (step invalid-camera
    (focus numbers #:x (closed 0 1) #:y (closed -1 1))))

;; conflicting-trace : calculus-lesson?
;;   A sweep and a simultaneous parameter write would have no single history.
(define-calculus-lesson conflicting-trace
  (model
    [u (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x u)]
    [locus (trace-of P #:parameter u #:over (closed 0 2))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 4)
                           #:objects (G P locus))])
  (step ambiguous-history
    (together
     (trace locus #:duration 1)
     (vary u #:to 1 #:duration 1))))

;; together-start-values : calculus-lesson?
;;   Disjoint simultaneous actions still evaluate targets from one start state.
(define-calculus-lesson together-start-values
  (model
    [a (parameter 0 #:domain (closed 0 2))]
    [b (parameter 0 #:domain (closed 0 2))])
  (views [numbers (number-line-view #:objects (a b))])
  (step move-together
    (together
     (vary a #:to 2 #:duration 1)
     (vary b #:to a #:duration 1))))

;; invalid-limit-transition : calculus-lesson?
;;   A line handoff needs an actual finite slope-limit claim.
(define-calculus-lesson invalid-limit-transition
  (model
    [source (horizontal-line 0)]
    [target (horizontal-line 1)])
  (views [plot (graph-view #:x (closed -1 1) #:y (closed -1 1)
                           #:objects (source target))])
  (initially (show source))
  (step invalid-handoff (limit-transition source target #:claim #f)))

;; visible-target-transition : calculus-lesson?
;;   A valid finite slope claim still cannot hand off to an already visible
;;   target; source and target must have a meaningful presentation transition.
(define-calculus-lesson visible-target-transition
  (model
    [f (function (x) (* x x))]
    [df (derivative-function f #:method 'supplied #:using (function (x) (* 2 x))
                            #:justification "The derivative of x² is 2x.")]
    [a 1]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [G (graph f)]
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [S (secant G P Q)]
    [m (difference-quotient f a h)]
    [L (limit-statement m #:parameter h #:to 0 #:value 2 #:side 'right
                        #:justification "The finite quotient approaches the tangent slope.")]
    [T (tangent G #:at P #:derivative df)])
  (views [plot (graph-view #:x (closed -1/2 5/2) #:y (closed -1/2 5)
                           #:objects (G P Q S T))])
  (initially (show S T))
  (step invalid-handoff (limit-transition S T #:claim L)))

;; partition-model : calculus-model?
;;   Covers explicit endpoint/tag checks and an exact trapezoidal quantity.
(define-calculus-model partition-model
  (model
    [f (function (x) (* x x))]
    [P (partition (list 0 1 2))]
    [bad-P (partition (list 0 1 1))]
    [tags (tag-partition P #:tags (list 0 3/2))]
    [bad-tags (tag-partition P #:tags (list 1/2 3))]
    [S (riemann-sum f tags)]
    [bad-S (riemann-sum f bad-tags)]
    [q (sum-value S)]
    [bad-q (sum-value bad-S)]
    [T (trapezoidal-sum f P)]
    [bad-T (trapezoidal-sum f bad-P)]))

;; numeric-integral-model : calculus-model?
;;   Exercises bounded numerical integration independently of a supplied rule.
(define-calculus-model numeric-integral-model
  (model
    [f (function (x) (* x x))]
    [I (definite-integral f #:from 0 #:to 2)]))

;; nested-refinement : calculus-lesson?
;;   Changes one direct integer partition count at two atomic boundaries.
(define-calculus-lesson nested-refinement
  (model
    [n (parameter 4 #:domain (integers 1 32) #:kind 'integer)]
    [P (uniform-partition 0 2 #:count n)])
  (views [number-line (number-line-view #:objects (P))])
  (step refine-cells (refine P #:counts (list 8 16) #:duration 1)))

;; nonnested-refinement : calculus-lesson?
;;   Deliberately asks for a count which cannot preserve uniform cell ancestry.
(define-calculus-lesson nonnested-refinement
  (model
    [n (parameter 4 #:domain (integers 1 32) #:kind 'integer)]
    [P (uniform-partition 0 2 #:count n)])
  (views [number-line (number-line-view #:objects (P))])
  (step refine-cells (refine P #:counts (list 6) #:duration 1)))

;; candidate-model : calculus-model?
;;   Validates supplied level-set, root, and intersection candidates only.
(define-calculus-model candidate-model
  (model
    [f (function (x) (- (* x x) 1))]
    [h (function (x) (+ x 1))]
    [G (graph f)]
    [H (graph h)]
    [solutions (level-set f 0
                          #:within (closed -2 2)
                          #:inputs (list -1 1))]
    [solution-values (solution-inputs solutions)]
    [bad-solutions (level-set f 0
                              #:within (closed -2 2)
                              #:inputs (list 0))]
    [unjustified-empty (level-set f 0
                                  #:within (closed -2 2)
                                  #:inputs (list)
                                  #:completeness 'all)]
    [root (root-point G #:x 1)]
    [not-root (root-point G #:x 0)]
    [crossing (intersection-point G H #:x -1)]))

;; sequence-iteration-model : calculus-model?
;;   Keeps finite indexed processes declarative and evaluates requested prefixes
;;   from their declared seeds.
(define-calculus-model sequence-iteration-model
  (model
    [s (sequence (n) (* n n) #:from 1)]
    [s3 (sequence-value s 3)]
    [before-s (sequence-value s 0)]
    [sum (partial-sum s #:from 1 #:to 3)]
    [empty-sum (partial-sum s #:from 3 #:to 2)]
    [points (sequence-points s #:through 3)]
    [iter (iteration-map (x) (+ x 1) #:start 0 #:steps 3)]
    [iter3 (iterate-value iter 3)]
    [iter4 (iterate-value iter 4)]
    [f (function (x) (- (* x x) 2))]
    [df (derivative-function f #:method 'symbolic)]
    [newton (newton-iteration f #:derivative df #:start 1 #:steps 3)]
    [newton3 (iterate-value newton 3)]
    [newton-prefix (newton-diagram newton #:through 3)]
    [g (function (x) (* x x))]
    [dg (derivative-function g #:method 'symbolic)]
    [stopped-newton (newton-iteration g #:derivative dg #:start 0 #:steps 1)]
    [stopped0 (iterate-value stopped-newton 0)]
    [stopped1 (iterate-value stopped-newton 1)]
    [wrong-newton (newton-iteration f #:derivative dg #:start 1 #:steps 1)]
    [wrong-newton1 (iterate-value wrong-newton 1)]))

;; analysis-claim-model : calculus-model?
;;   Checks declared claim vocabulary and evidence without inferring the claim.
(define-calculus-model analysis-claim-model
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [positive (sign-claim f #:on (open 0 2) #:sign 'positive
                          #:justification "x squared is positive away from zero.")]
    [bad-sign (sign-claim f #:on (open 0 2) #:sign 'upward
                          #:justification "Deliberately invalid category.")]
    [increasing (monotonicity-claim f #:on (closed 0 2) #:direction 'nondecreasing
                                      #:justification "The supplied derivative argument is nonnegative.")]
    [concave (concavity-claim f #:on (closed 0 2) #:direction 'up
                                #:justification "The supplied second-derivative argument is positive.")]
    [chart (sign-chart positive)]
    [minimum (feature-point G #:at 0 #:kind 'local-minimum
                            #:justification "The supplied feature label is a local minimum.")]
    [bad-feature (feature-point G #:at 0 #:kind 'ordinary-point
                                #:justification "Deliberately invalid category.")]))

;; limit-contract-model : calculus-model?
;;   Keeps limiting claims separate from source evaluation at excluded targets.
(define-calculus-model limit-contract-model
  (model
    [h (parameter 0 #:domain (closed 0 1))]
    [f (function (x) (* x x))]
    [punctured (punctured-neighborhood 0 1)]
    [inside-punctured (in-domain? 1/2 punctured)]
    [center-punctured (in-domain? 0 punctured)]
    [bad-neighborhood (neighborhood 0 0)]
    [bad-neighborhood-member (in-domain? 0 bad-neighborhood)]
    [input (input-band punctured)]
    [L (limit-statement (difference-quotient f 1 h)
                        #:parameter h #:to 0 #:value 2 #:side 'both
                        #:justification "The quotient simplifies to 2+h away from zero.")]
    [at-one-limit (limit-statement (value-at f h)
                                   #:parameter h #:to 1 #:value 2 #:side 'both
                                   #:justification "Deliberately mismatched function value.")]
    [true-at-one-limit (limit-statement (value-at f h)
                                        #:parameter h #:to 1 #:value 1 #:side 'both
                                        #:justification "The supplied limit agrees with f(1).")]
    [bad-side (limit-statement (value-at f h)
                               #:parameter h #:to 0 #:value 0 #:side 'up
                               #:justification "Deliberately invalid side.")]
    [epsilon-delta (epsilon-delta-condition
                    f #:at 1 #:limit 1 #:epsilon 1/2 #:delta 1/2
                    #:justification "A supplied local bound.")]
    [bad-epsilon (epsilon-delta-condition
                  f #:at 1 #:limit 1 #:epsilon 0 #:delta 1/2
                  #:justification "Deliberately nonpositive epsilon.")]
    [contradictory-continuity (continuity-condition
                               f #:at 1 #:limit-claim at-one-limit
                               #:justification "Deliberately mismatched limit value.")]
    [continuous-at-one (continuity-condition
                        f #:at 1 #:limit-claim true-at-one-limit
                        #:justification "The supplied limit and function value agree.")]))

;; tangent-contract-model : calculus-model?
;;   Requires a tangent derivative to retain its graph function's source.
(define-calculus-model tangent-contract-model
  (model
    [f (function (x) (* x x))]
    [g (function (x) (+ x 1))]
    [G (graph f)]
    [P (point-on G #:x 1)]
    [Q (point-on G #:x 2)]
    [change (increment P Q)]
    [df (derivative-function f #:method 'symbolic)]
    [dg (derivative-function g #:method 'symbolic)]
    [T (tangent G #:at P #:derivative df)]
    [bad-T (tangent G #:at P #:derivative dg)]
    [change-triangle (slope-triangle change)]
    [line-triangle (slope-triangle T #:at P #:run -1)]
    [bad-triangle (slope-triangle T #:at P #:run 0)]
    [linear (linearization f #:at 1 #:derivative df)]
    [linear-at-two (value-at linear 2)]
    [L (graph linear)]
    [error (approximation-error f linear)]
    [error-at-two (value-at error 2)]
    [error-segment-at-two (error-segment G L #:at 2)]
    [bad-linear (linearization f #:at 1 #:derivative dg)]
    [bad-linear-at-two (value-at bad-linear 2)]
    [taylor (taylor-polynomial f #:at 1 #:derivatives (list df))]
    [taylor-at-two (value-at taylor 2)]
    [constant-taylor (taylor-polynomial f #:at 1 #:derivatives (list))]
    [constant-taylor-at-two (value-at constant-taylor 2)]
    [bad-taylor (taylor-polynomial f #:at 1 #:derivatives (list dg))]
    [bad-taylor-at-two (value-at bad-taylor 2)]
    [V (vertical-tangent G #:at P #:justification "A supplied vertical tangent claim.")]
    [bad-V (vertical-tangent G #:at P #:justification "")]))

;; snapshot-model : calculus-model?
;;   Fixed objects retain their declaration-time parameter assignment.
(define-calculus-model snapshot-model
  (model
    [h (parameter 1 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x h)]
    [fixed-P (snapshot-of P #:values ([h 1/2]))]
    [O (point 0 0)]
    [change (increment O P)]
    [fixed-change (snapshot-of change #:values ([h 1/2]))]))

;; snapshot-override-lesson : calculus-lesson?
;;   Unlisted snapshot parameters use the lesson's compiled initial override.
(define-calculus-lesson snapshot-override-lesson
  (model
    [h (parameter 1 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x h)]
    [fixed-P (snapshot-of P #:values ())])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 4)
                           #:objects (G P fixed-P))])
  (step move-live-point (vary h #:to 2 #:duration 1)))

;; asymptote-contract-model : calculus-model?
;;   Cross-checks a supplied asymptote's geometric shape against its limit claim.
(define-calculus-model asymptote-contract-model
  (model
    [x (parameter 1 #:domain (open 0 2))]
    [f (function (t) (/ 1 t))]
    [G (graph f)]
    [vertical-claim (limit-statement (value-at f x)
                                     #:parameter x #:to 0 #:value +inf.0
                                     #:justification "The reciprocal grows without bound near zero.")]
    [horizontal-claim (limit-statement (value-at f x)
                                       #:parameter x #:to +inf.0 #:value 0
                                       #:justification "The reciprocal approaches zero at infinity.")]
    [V (vertical-line 0)]
    [H (horizontal-line 0)]
    [bad-H (horizontal-line 1)]
    [vertical-asymptote (asymptote-line G #:line V #:limit-claim vertical-claim)]
    [horizontal-asymptote (asymptote-line G #:line H #:limit-claim horizontal-claim)]
    [mismatched-asymptote (asymptote-line G #:line bad-H #:limit-claim horizontal-claim)]))


;;;
;;; Tests
;;;

;; run-calculus-core-smoke-tests : -> void?
;;   Verifies exact function attachment, deterministic sampling, and parameter motion.
(define (run-calculus-core-smoke-tests)
  (define plan (compile-calculus-lesson reading-square))
  (define initial (calculus-plan-sample plan #:at 'initial))
  (check-equal? (calculus-result-value (calculus-snapshot-ref initial '(R output))) 4)
  (check-true (calculus-snapshot-visible? initial 'G))
  (check-false (calculus-snapshot-visible? initial 'R))
  (define final (calculus-plan-sample plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref final 'a)) -2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref final '(R output))) 4)
  (check-true (calculus-snapshot-visible? final 'R))
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson invalid-parameter-path)))
                1)
  (define coincident (calculus-model-at coincident-geometry-model))
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'S)) 'defined)
  (check-equal? (calculus-result-value (calculus-snapshot-ref coincident 'S))
                (list 'segment (cons 1 1) (cons 1 1)))
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'L)) 'undefined)
  (check-equal? (calculus-result-status (calculus-snapshot-ref coincident 'R)) 'undefined)
  (define integer-plan (compile-calculus-lesson integer-variation))
  (check-equal? (length (calculus-plan-diagnostics integer-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample integer-plan #:at 'final) 'n))
                2)
  (define invalid-integer-assignment-plan
    (compile-calculus-lesson invalid-integer-assignment))
  (check-equal? (length (calculus-plan-diagnostics invalid-integer-assignment-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref
                  (calculus-plan-sample invalid-integer-assignment-plan #:at 'final) 'n))
                2)
  (define excluded-plan (compile-calculus-lesson excluded-path))
  (check-equal? (length (calculus-plan-diagnostics excluded-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample excluded-plan #:at 'final) 'u))
                0)
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson incomplete-approach)))
                1)
  (define wrong-side-plan (compile-calculus-lesson wrong-side-after-assignment))
  (check-equal? (length (calculus-plan-diagnostics wrong-side-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample wrong-side-plan #:at 'final) 'u))
                2)
  (define invalid-trace-plan (compile-calculus-lesson invalid-trace))
  (check-equal? (length (calculus-plan-diagnostics invalid-trace-plan)) 1)
  (define invalid-trace-final (calculus-plan-sample invalid-trace-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref invalid-trace-final 'u))
                1)
  (check-false (calculus-snapshot-visible? invalid-trace-final 'locus))
  (define trace-prefix-plan (compile-calculus-lesson trace-prefix))
  (check-equal? (length (calculus-plan-diagnostics trace-prefix-plan)) 0)
  (define trace-prefix-locus
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model (calculus-plan-lesson trace-prefix-plan)))
              'locus))
  (define trace-prefix-final (calculus-plan-sample trace-prefix-plan #:at 'final))
  (define trace-prefix-midpoint (calculus-plan-sample trace-prefix-plan #:at 1))
  (check-equal? (calculus-result-value (calculus-snapshot-ref trace-prefix-midpoint 'u)) 1)
  (check-equal? (calculus-snapshot-trace-points trace-prefix-midpoint trace-prefix-locus #:samples 4)
                (list (cons 0 0) (cons 1/2 1/4) (cons 1 1) #f #f))
  (check-equal? (calculus-snapshot-trace-points trace-prefix-final trace-prefix-locus #:samples 4)
                (list (cons 0 0) (cons 1/2 1/4) (cons 1 1) (cons 3/2 9/4) (cons 2 4)))
  (check-equal? (calculus-snapshot-trace-points
                 (calculus-model-at
                  (calculus-lesson-model (calculus-plan-lesson trace-prefix-plan)))
                 trace-prefix-locus #:samples 4)
                (calculus-snapshot-trace-points trace-prefix-final trace-prefix-locus #:samples 4))
  (define focus-plan (compile-calculus-lesson focus-window))
  (check-equal? (length (calculus-plan-diagnostics focus-plan)) 0)
  (define focus-view
    (hash-ref (calculus-lesson-views (calculus-plan-lesson focus-plan)) 'plot))
  (define focus-midpoint (calculus-plan-sample focus-plan #:at 1))
  (check-equal? (calculus-snapshot-view-window focus-midpoint focus-view)
                (list -1 3/2 -3/2 3/2))
  (check-equal? (calculus-result-value (calculus-snapshot-ref focus-midpoint 'u)) 0)
  (define restore-midpoint (calculus-plan-sample focus-plan #:at 3))
  ;; The focus target was frozen at u=0; restoring after u becomes 1 still
  ;; returns to the original declared camera window rather than a moving one.
  (check-equal? (calculus-result-value (calculus-snapshot-ref restore-midpoint 'u)) 1)
  (check-equal? (calculus-snapshot-view-window restore-midpoint focus-view)
                (list -1 3/2 -3/2 3/2))
  (check-false (calculus-snapshot-view-window
                (calculus-plan-sample focus-plan #:at 'final) focus-view))
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson invalid-focus-window)))
                1)
  (define conflicting-trace-plan (compile-calculus-lesson conflicting-trace))
  (check-equal? (length (calculus-plan-diagnostics conflicting-trace-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample conflicting-trace-plan #:at 'final) 'u))
                0)
  (define together-start-plan (compile-calculus-lesson together-start-values))
  (check-equal? (length (calculus-plan-diagnostics together-start-plan)) 0)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample together-start-plan #:at 'final) 'a))
                2)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample together-start-plan #:at 'final) 'b))
                0)
  (define invalid-transition-plan (compile-calculus-lesson invalid-limit-transition))
  (check-equal? (length (calculus-plan-diagnostics invalid-transition-plan)) 1)
  (define invalid-transition-final
    (calculus-plan-sample invalid-transition-plan #:at 'final))
  (check-true (calculus-snapshot-visible? invalid-transition-final 'source))
  (check-false (calculus-snapshot-visible? invalid-transition-final 'target))
  (define visible-target-plan (compile-calculus-lesson visible-target-transition))
  (check-equal? (length (calculus-plan-diagnostics visible-target-plan)) 1)
  (define visible-target-final
    (calculus-plan-sample visible-target-plan #:at 'final))
  (check-true (calculus-snapshot-visible? visible-target-final 'S))
  (check-true (calculus-snapshot-visible? visible-target-final 'T))
  (define changed-snapshot (calculus-model-at snapshot-model #:values (hash 'h 2)))
  (check-equal? (calculus-result-value (calculus-snapshot-ref changed-snapshot 'P))
                (cons 2 4))
  (check-equal? (calculus-result-value (calculus-snapshot-ref changed-snapshot 'fixed-P))
                (cons 1/2 1/4))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref changed-snapshot '(fixed-change dx)))
                1/2)
  (define snapshot-override-plan
    (compile-calculus-lesson snapshot-override-lesson #:values (hash 'h 3/2)))
  (define snapshot-override-final
    (calculus-plan-sample snapshot-override-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref snapshot-override-final 'P))
                (cons 2 4))
  (check-equal? (calculus-result-value (calculus-snapshot-ref snapshot-override-final 'fixed-P))
                (cons 3/2 9/4))
  (define partition-snapshot (calculus-model-at partition-model))
  (check-equal? (calculus-result-value (calculus-snapshot-ref partition-snapshot 'q)) 9/4)
  (check-equal? (calculus-result-status (calculus-snapshot-ref partition-snapshot 'bad-q)) 'undefined)
  (check-equal? (calculus-result-value (calculus-snapshot-ref partition-snapshot 'T)) 3)
  (check-equal? (calculus-result-status (calculus-snapshot-ref partition-snapshot 'bad-T)) 'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref
                  (calculus-model-at numeric-integral-model
                                     #:computation (calculus-computation #:integration-budget 2))
                  'I))
                'unresolved)
  (define refinement-plan (compile-calculus-lesson nested-refinement))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample refinement-plan #:at 5/2) 'n))
                4)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample refinement-plan #:at 13/5) 'n))
                8)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample refinement-plan #:at 'final) 'n))
                16)
  (define nonnested-plan (compile-calculus-lesson nonnested-refinement))
  (check-equal? (length (calculus-plan-diagnostics nonnested-plan)) 1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref (calculus-plan-sample nonnested-plan #:at 'final) 'n))
                4)
  (define candidate-snapshot (calculus-model-at candidate-model))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref candidate-snapshot 'solution-values))
                '(-1 1))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref candidate-snapshot 'bad-solutions))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref candidate-snapshot 'unjustified-empty))
                'unresolved)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref candidate-snapshot 'root))
                (cons 1 0))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref candidate-snapshot 'not-root))
                'unresolved)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref candidate-snapshot 'crossing))
                (cons -1 0))
  (define sequence-iteration-snapshot (calculus-model-at sequence-iteration-model))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 's3))
                9)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref sequence-iteration-snapshot 'before-s))
                'undefined)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'sum))
                14)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'empty-sum))
                0)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'points))
                (list (cons 1 1) (cons 2 4) (cons 3 9)))
  (check-equal? (hash-ref
                 (calculus-result->datum
                  (calculus-snapshot-ref sequence-iteration-snapshot 'points))
                 'value)
                (list (hash 'kind 'point 'x 1 'y 1)
                      (hash 'kind 'point 'x 2 'y 4)
                      (hash 'kind 'point 'x 3 'y 9)))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'iter3))
                3)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref sequence-iteration-snapshot 'iter4))
                'undefined)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'newton3))
                577/408)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'newton-prefix))
                (list (cons 0 1) (cons 1 3/2) (cons 2 17/12) (cons 3 577/408)))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref sequence-iteration-snapshot 'stopped0))
                0)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref sequence-iteration-snapshot 'stopped1))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref sequence-iteration-snapshot 'wrong-newton1))
                'unresolved)
  (define analysis-snapshot (calculus-model-at analysis-claim-model))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'positive))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'bad-sign))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'increasing))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'concave))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'chart))
                'defined)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref analysis-snapshot 'minimum))
                (cons 0 0))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref analysis-snapshot 'bad-feature))
                'undefined)
  (define limit-snapshot (calculus-model-at limit-contract-model))
  (check-true (calculus-result-value
               (calculus-snapshot-ref limit-snapshot 'inside-punctured)))
  (check-false (calculus-result-value
                (calculus-snapshot-ref limit-snapshot 'center-punctured)))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'bad-neighborhood-member))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'input))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'L))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'bad-side))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'epsilon-delta))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'bad-epsilon))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'contradictory-continuity))
                'unresolved)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'true-at-one-limit))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref limit-snapshot 'continuous-at-one))
                'defined)
  (define tangent-snapshot (calculus-model-at tangent-contract-model))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'T))
                (list 'line 2 -1 (cons 1 1)))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'change-triangle))
                'defined)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot '(change-triangle dx)))
                1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot '(change-triangle dy)))
                3)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot '(line-triangle dx)))
                -1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot '(line-triangle dy)))
                -2)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'bad-triangle))
                'undefined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'bad-T))
                'undefined)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'linear-at-two))
                3)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'error-at-two))
                1)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'error-segment-at-two))
                (list 'segment (cons 2 4) (cons 2 3)))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'bad-linear-at-two))
                'unresolved)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'taylor-at-two))
                3)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'constant-taylor-at-two))
                1)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'bad-taylor-at-two))
                'unresolved)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref tangent-snapshot 'V))
                (list 'vertical 1 (cons 1 1)))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref tangent-snapshot 'bad-V))
                'undefined)
  (define asymptote-snapshot (calculus-model-at asymptote-contract-model))
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref asymptote-snapshot 'vertical-asymptote))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref asymptote-snapshot 'horizontal-asymptote))
                'defined)
  (check-equal? (calculus-result-status
                 (calculus-snapshot-ref asymptote-snapshot 'mismatched-asymptote))
                'unresolved))

(module+ test
  (run-calculus-core-smoke-tests))
