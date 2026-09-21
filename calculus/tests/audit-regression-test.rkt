#lang racket/base

;;;
;;; Calculus Audit Regressions
;;;

;; These focused public-API checks retain the mathematical counterexamples
;; from the 2026-09-20 audit. Native sampling and clipping checks live in the
;; renderer smoke suite because their oracle is a rendered frame.

(require rackunit
         racket/string
         "../main.rkt"
         (only-in "../private/core.rkt"
                  calculus-snapshot-function-value
                  calculus-snapshot-formula-text
                  calculus-snapshot-formula-tex
                  calculus-snapshot-formula-fragments
                  calculus-snapshot-formula-skeleton-tex
                  calculus-snapshot-region-samples
                  calculus-snapshot-motion-state
                  calculus-snapshot-presentation-state
                  calculus-snapshot-label-visible?
                  calculus-snapshot-reading-owned-parts
                  calculus-model-nodes
                  c-part
                  calculus-plan-caption
                  calculus-snapshot-reading-points))

(provide run-calculus-audit-regression-tests)

(define (model-result model name [computation default-calculus-computation])
  (calculus-snapshot-ref (calculus-model-at model #:computation computation) name))

(define (check-value result expected)
  (check-equal? (calculus-result-status result) 'defined)
  (check-equal? (calculus-result-value result) expected))

(define (model-function-value model name input)
  (define snapshot (calculus-model-at model))
  (define function-result (calculus-snapshot-ref snapshot name))
  (if (eq? (calculus-result-status function-result) 'defined)
      (calculus-snapshot-function-value snapshot
                                        (calculus-result-value function-result)
                                        input)
      function-result))

(define audit-timing
  (calculus-timing #:opening-pause 0 #:read-delay 0
                   #:action-duration 1 #:step-pause 0))

(define audit-profile (calculus-profile #:timing audit-timing))

(define-calculus-model derivative-regressions
  (model
    [cube (function (x) (expt x 3))]
    [constant (function (x) 5)]
    [power-zero (function (x) (expt x 0))]
    [quotient (function (x) (/ 1 (+ x 1))
                        #:domain (domain-except real-line -1))]
    [second (derivative-function cube #:order 2)]
    [constant-prime (derivative-function constant)]
    [power-zero-prime (derivative-function power-zero)]
    [quotient-prime (derivative-function quotient)]))

(define-calculus-model integral-regressions
  (model
    [f (function (x) x)]
    [g (function (x) (* x x))]
    [F (antiderivative-function f #:using (function (x) (/ (* x x) 2)))]
    [G (antiderivative-function g #:using (function (x) (/ (* x x x) 3)))]
    [correct (definite-integral f #:from 0 #:to 1 #:antiderivative F)]
    [wrong-source (definite-integral f #:from 0 #:to 1 #:antiderivative G)]
    [quartic (function (x) (expt x 4))]
    [adaptive (definite-integral quartic #:from 0 #:to 1)]))

(define-calculus-lesson label-and-group-regressions
  (model [P (point 0 0)])
  (views [plot (graph-view #:x (closed -1 1) #:y (closed -1 1) #:objects (P))])
  (initially (show P) (deemphasize P))
  (step labels (hide-label P))
  (step grouped (together (normalize P) (pause 1))))

(define-calculus-lesson vary-regressions
  (model [a (parameter 0 #:domain (closed 0 2))])
  (views [axis (number-line-view #:range (closed 0 2) #:objects (a))])
  (initially (show a))
  (step route (vary a #:via (list 2) #:to 1 #:easing 'linear #:duration 3)))

;; Policies are sampled transient presentation tracks, not endpoint-only
;; records. This compact fixture gives headless coverage to graph/line reveal
;; and the guided-reading phase before native smoke tests inspect pixels.
(define-calculus-lesson motion-regressions
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [A (point 0 0)]
    [B (point 1 1)]
    [L (segment A B)]
    [R (input-reading G 1)])
  (views [plot (graph-view #:x (closed -1 2) #:y (closed -1 2)
                           #:objects (G L R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show G L))
  (step explain-reading (read R)))

(define-calculus-lesson refinement-regressions
  (model
    [n (parameter 2 #:kind 'integer #:domain (closed 2 8))]
    [f (function (x) x)]
    [partition (uniform-partition 0 2 #:count n)]
    [tags (tag-partition partition #:sample 'midpoint)]
    [sum (riemann-sum f tags)]
    [boxes (riemann-rectangles sum)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2)
                           #:objects (boxes))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show boxes))
  (step refine-boxes (refine partition #:counts (list 4 8) #:duration 2)))

(define-calculus-model part-regressions
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G 2)]
    [answer (x-coordinate (part R 'point))]))

(define-calculus-component audit-plus-one
  (inputs [a : (Parameter Scalar)])
  (model [y (+ a 1)])
  (exports y))

(define-calculus-model component-regressions
  (model
    [a (parameter 2 #:domain (closed 0 3))]
    [study (use-component audit-plus-one a)]))

(define-calculus-model live-field-regressions
  (model
    [a (parameter 9 #:domain (closed -20 20))]
    [equation (formula (= (value a) (+ (ref a) 1)))]))

;; Seventh-audit fixtures keep phase narration, point wrappers, and reverse
;; readings at the public semantic boundary independently of native painting.
(define-calculus-lesson r7-caption-phases
  (model [a (parameter 0 #:domain (closed 0 1))])
  (views [axis (number-line-view #:range (closed 0 1) #:objects (a))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show a))
  (step first #:say "a = 0" (pause 1) (checkpoint first-done))
  (step second #:say "a = 1" (set-parameter a 1) (pause 1)))

(define-calculus-model r7-wrapped-points
  (model
    [a (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (+ (expt (- x 1) 2) 1))]
    [df (derivative-function f)]
    [G (graph f)]
    [F (feature-point G #:at 1 #:kind 'global-minimum
         #:justification "(x-1)^2 is nonnegative, with equality at x=1.")]
    [P (point a a)]
    [S (snapshot-of P #:values ([a 1]))]
    [feature-x (x-coordinate F)]
    [feature-projection (projection F #:onto 'x)]
    [feature-tangent (tangent G #:at F #:derivative df)]
    [frozen-x (x-coordinate S)]
    [frozen-projection (projection S #:onto 'x)]))

(define-calculus-model r7-reverse-reading
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (output-reading G 1 #:inputs (list -1 1)
         #:completeness 'all
         #:justification "x^2=1 exactly when x=-1 or x=1.")]
    [left-point (part (reading-branch R 0) 'point)]
    [right-point (part (reading-branch R 1) 'point)]
    [left-input (part (reading-branch R 0) 'input)]
    [output (part R 'output)]))

;; Eighth-audit fixtures retain the public composition boundary: checkpoint
;; names are independent from ownership, and Reading parts stay typed through
;; aliases and frozen snapshots.
(define-calculus-lesson r8-qualified-checkpoint-caption
  (model [a (parameter 0 #:domain (closed 0 1))])
  (views [axis (number-line-view #:range (closed 0 1) #:objects (a))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show a))
  (step first #:say "a = 0" (pause 1) (checkpoint '(review before)))
  (step second #:say "a = 1" (set-parameter a 1) (pause 1)))

(define-calculus-lesson r8-colliding-checkpoint-caption
  (model [a (parameter 0 #:domain (closed 0 1))])
  (views [axis (number-line-view #:range (closed 0 1) #:objects (a))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step first #:say "a = 0"
    (pause 1/2) (checkpoint '(second before)) (pause 1/2))
  (step second #:say "a = 1" (set-parameter a 1) (pause 1)))

(define-calculus-model r8-projection-snapshots
  (model
    [a (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))] [G (graph f)]
    [R (input-reading G a)] [P (part R 'point)]
    [S (snapshot-of P #:values ([a 1]))]
    [D (snapshot-of (part R 'point) #:values ([a 1]))]
    [xS (x-coordinate S)] [yD (y-coordinate D)]))

(define-calculus-model r8-reverse-branch-protocol
  (model
    [f (function (x) (* x x))] [G (graph f)]
    [R (output-reading G 1 #:inputs (list -1 1)
         #:completeness 'all
         #:justification "x^2=1 exactly when x=-1 or x=1.")]
    [P (part (reading-branch R 0) 'point)]
    [B (reading-branch R 0)] [Q (part B 'point)]
    [input-guide (part B 'input-guide)]
    [output-guide (part B 'output-guide)]
    [input-label (part B 'input-label)]
    [branches (part R 'branches)] [output-label (part R 'output-label)]))

;; Ninth-audit fixtures distinguish mathematical duplicate candidates from
;; merely similar source spellings, and retain a component-exported Reading's
;; lexical model through both root and selected-branch evaluation.
(define-calculus-model r9-mixed-input-collision
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 1 1.0))]))

(define-calculus-model r9-signed-zero-collision
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 0 #:inputs (list 0.0 -0.0))]))

(define-calculus-model r9-distinct-close-inputs
  (model [f (function (x) 1)] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0 1/1000000000000))]))

(define-calculus-component r9-selected-roots-component
  (inputs [source-graph : Graph])
  (model [R (output-reading source-graph 1 #:inputs (list -1 1))])
  (exports R))

(define-calculus-model r9-exported-reading
  (model [f (function (x) (* x x))] [G (graph f)]
         [study (use-component r9-selected-roots-component G)]
         [right-point (part (reading-branch (part study 'R) 1) 'point)]))

;; Tenth-audit fixture: an output Reading's child state and generated label
;; preferences are independent presentation facts, with the root remaining a
;; visible mathematical owner throughout.
(define-calculus-lesson r10-reading-owned-presentation
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R))
  (step dim (deemphasize (part (reading-branch R 1) 'input-guide)))
  (step suppress (hide-label R)))

;; Eleventh-audit fixtures preserve view-local label preference cycles and
;; explicit inherited child demands even if the parent Reading is invalid.
(define-calculus-lesson r11-scoped-label-cycle
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [left (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))]
         [right (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step masked (hide-label (in-view left R)) (pause 1))
  (step restored (show-label (in-view left R)) (pause 1)))

(define-calculus-lesson r11-inherited-invalid-child
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 0) 'point))))

(define-calculus-lesson r11-inherited-missing-branch
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 7) 'point))))

;; Twelfth-audit fixtures distinguish strict demanded identity from a later
;; paint deduplication decision, including the canonical state of a named Part.
(define-calculus-lesson r12-visible-root-missing-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects (R (part (reading-branch R 7) 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step retain (pause 1)))

(define-calculus-lesson r12-inherited-missing-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 7) 'input-guide))))

(define-calculus-lesson r12-named-owned-point-state
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [P (part (reading-branch R 1) 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R P))
  (step dim (deemphasize P) (pause 1)))

;; Thirteenth-audit fixtures extend canonical Part identity through a second
;; model alias, without changing the distinct named-quantity rule for scalar
;; references.
(define-calculus-lesson r13-chained-owned-point-state
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [P (part (reading-branch R 1) 'point)]
         [A P]
         [xA (x-coordinate A)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R P A))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R P A))
  (step dim (deemphasize A) (pause 1)))

(define-calculus-lesson r13-distinct-scalar-alias-state
  (model [a (parameter 1 #:domain (closed 0 2))] [b a])
  (views [axis (number-line-view #:range (closed 0 2) #:objects (a b))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show a b))
  (step dim (deemphasize b) (pause 1)))

;; Fourteenth-audit fixture: public Parts are carriers, so a component export
;; must be classified by its declared value type before a later binding chooses
;; between named-scalar and nonscalar-alias identity.
(define-calculus-component r14-scalar-export
  (inputs [x : Scalar])
  (model [s (+ x 0)])
  (exports s))

(define-calculus-lesson r14-scalar-export-alias-state
  (model [study (use-component r14-scalar-export 1)]
         [u (part study 's)] [v u])
  (views [axis (number-line-view #:range (closed 0 2) #:objects (u v))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show u v))
  (step dim (deemphasize v) (pause 1))
  (step conceal (hide v) (pause 1)))

;; R15: selected type lookup must cross each finite component-export boundary,
;; not stop at the first exported Component root.
(define-calculus-component r15-scalar-leaf
  (inputs [x : Scalar])
  (model [s (+ x 0)])
  (exports s))

(define-calculus-component r15-scalar-shell
  (inputs [x : Scalar])
  (model [inner (use-component r15-scalar-leaf x)])
  (exports inner))

(define-calculus-lesson r15-nested-scalar-export-state
  (model [a (parameter 1 #:domain (closed 0 2))]
         [study (use-component r15-scalar-shell a)]
         [u (part (part study 'inner) 's)] [v u])
  (views [axis (number-line-view #:range (closed 0 2) #:objects (u v))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show u v))
  (step dim (deemphasize v) (pause 1))
  (step conceal (hide v) (pause 1)))

;; R15: component contracts follow a selected object's semantic type instead
;; of the surface constructor that first carried it into the caller model.
(define-calculus-component r15-point-consumer
  (inputs [p : Point])
  (model [x (x-coordinate p)])
  (exports x))

(define-calculus-component r15-scalar-pass-through
  (inputs [x : Scalar])
  (model [out x])
  (exports out))

(define-calculus-component r15-integer-pass-through
  (inputs [n : Integer])
  (model [out n])
  (exports out))

(define-calculus-component r15-boolean-pass-through
  (inputs [b : Boolean])
  (model [out b])
  (exports out))

(define-calculus-model r15-typed-component-inputs
  (model [a (parameter 0 #:domain (closed 0 2))]
         [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G 1)] [P (part R 'point)]
         [moving (point a a)] [S (snapshot-of moving #:values ([a 1]))]
         [H (horizontal-line 1)] [PL (point-on-line H #:x 1)]
         [g (function (x) (+ (expt (- x 1) 2) 1))] [GG (graph g)]
         [F (feature-point GG #:at 1 #:kind 'global-minimum
                           #:justification "(x-1)^2 is nonnegative and vanishes at x=1.")]
         [projected (use-component r15-point-consumer P)]
         [inline (use-component r15-point-consumer (part R 'point))]
         [frozen (use-component r15-point-consumer S)]
         [on-line (use-component r15-point-consumer PL)]
         [feature (use-component r15-point-consumer F)]
         [scalar (use-component r15-scalar-pass-through 1)]
         [integer (use-component r15-integer-pass-through 2)]
         [boolean (use-component r15-boolean-pass-through #t)]))

(define-calculus-model r15-named-point-as-scalar
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G 1)] [P (part R 'point)]
         [bad (use-component r15-scalar-pass-through P)]))

(define-calculus-model r15-inline-point-as-scalar
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G 1)]
         [bad (use-component r15-scalar-pass-through (part R 'point))]))

;; check-reading-rejected : calculus-result? -> void?
;; Reads through the same result bridge used by strict native preparation.
(define (check-reading-rejected result)
  (check-true (calculus-result? result))
  (check-not-equal? (calculus-result-status result) 'defined))

;; run-calculus-audit-regression-tests : -> void?
;;   Exercises each repaired headless semantic contract at its public boundary.
(define (run-calculus-audit-regression-tests)
  (check-value (model-function-value derivative-regressions 'second 1) 6)
  (check-value (model-function-value derivative-regressions 'constant-prime 3) 0)
  (check-value (model-function-value derivative-regressions 'power-zero-prime 3) 0)
  (check-value (model-function-value derivative-regressions 'quotient-prime 1) -1/4)
  (check-value (model-result integral-regressions 'correct) 1/2)
  (check-equal? (calculus-result-status (model-result integral-regressions 'wrong-source))
                'undefined)
  (check-equal?
   (calculus-result-status
    (model-result
     integral-regressions 'adaptive
     (calculus-computation #:absolute-tolerance 1e-12 #:relative-tolerance 1e-12
                           #:integration-budget 3)))
   'unresolved)
  (check-= (calculus-result-value
            (model-result
             integral-regressions 'adaptive
             (calculus-computation #:absolute-tolerance 1e-10 #:relative-tolerance 1e-10
                                   #:integration-budget 4096)))
            1/5 1e-9)
  (define approximate-model
    (let ()
      (define-calculus-model model (model [a (sin 1)] [b (+ a 0)]))
      model))
  (check-true (calculus-result-approximate? (model-result approximate-model 'b)))
  (check-value (model-result part-regressions 'answer) 2)
  (check-value (calculus-snapshot-ref (calculus-model-at component-regressions) '(study y)) 3)
  (define labels-final
    (calculus-plan-sample
     (compile-calculus-lesson label-and-group-regressions #:profile audit-profile)
     #:at 'final))
  (check-true (calculus-snapshot-visible? labels-final 'P))
  (check-equal? (calculus-snapshot-presentation-state labels-final 'P) 'normal)
  (define route-plan (compile-calculus-lesson vary-regressions #:profile audit-profile))
  (check-value (calculus-snapshot-ref (calculus-plan-sample route-plan #:at 2) 'a) 2)
  (check-value (calculus-snapshot-ref (calculus-plan-sample route-plan #:at 3/4) 'a) 3/4)
  (define motion-plan (compile-calculus-lesson motion-regressions #:profile audit-profile))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 1/2) 'G)
                '(graph trace 1/2))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 1/2) 'L)
                '(line extend 1/2))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 3/2) 'R)
                '(reading guided 1/2))
  (define refinement-plan
    (compile-calculus-lesson refinement-regressions #:profile audit-profile))
  (define refinement-quarter
    (calculus-plan-sample refinement-plan #:at 1/2))
  (check-value (calculus-snapshot-ref refinement-quarter 'n) 2)
  (check-equal? (calculus-snapshot-motion-state refinement-quarter 'boxes)
                '(refinement subdivide 1/2 4))
  (check-equal? (calculus-snapshot-presentation-state refinement-quarter 'boxes)
                'refining)
  (define-calculus-model notation
    (model [equation (formula (* (+ 1 2) 3))]
           [power (formula (expt (+ 1 2) 10))]
           [root (formula (sqrt (+ 1 2)))]
           [nested-fraction (formula (/ (+ 1 2) (/ 3 4)))]))
  (define notation-snapshot (calculus-model-at notation))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-text notation-snapshot 'equation))
                "(1 + 2) · 3")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'power))
                "\\left(1 + 2\\right)^{10}")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'root))
                "\\sqrt{1 + 2}")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'nested-fraction))
                "\\frac{1 + 2}{\\frac{3}{4}}")
  ;; Follow-up mathematical counterexamples: unsupported symbolic work must
  ;; remain unresolved through higher orders; numerical agreement must include
  ;; the two one-sided slopes; and integral evidence is judged on its current
  ;; cancellation-sensitive total rather than the first coarse estimate.
  (define-calculus-model followup-derivatives
    (model
      [f (function (x) (+ (abs (expt x 3)) (* x x)))]
      [d2 (derivative-function f #:order 2)]
      [answer (value-at d2 1)]
      [corner (function (x) (abs x))]
      [numeric-corner (derivative-function corner #:method 'numeric #:step 1/10)]
      [G (graph corner)]
      [P (point-on G #:x 0)]
      [T (tangent G #:at P #:derivative numeric-corner #:side 'both)]))
  (check-equal? (calculus-result-status (model-result followup-derivatives 'answer))
                'unresolved)
  (check-true
   (not (not (memq (calculus-result-status (model-result followup-derivatives 'T))
                   '(undefined unresolved)))))
  (define-calculus-model cancellation-integral
    (model [f (function (x) (- (expt x 6) 1/7))]
           [I (definite-integral f #:from 0 #:to 1)]))
  (define cancellation-result
    (model-result cancellation-integral 'I
                  (calculus-computation #:absolute-tolerance 1/1000000000000
                                        #:relative-tolerance 1/100
                                        #:integration-budget 4096)))
  (check-true
   (or (eq? (calculus-result-status cancellation-result) 'unresolved)
       (and (eq? (calculus-result-status cancellation-result) 'defined)
            (<= (abs (calculus-result-value cancellation-result))
                (+ 1/1000000000000
                   (* 1/100 (abs (calculus-result-value cancellation-result))))))))
  (define-calculus-model neighborhood-gap
    (model
      [D (domain-union (neighborhood 2 1) (neighborhood 5 7/4))]
      [f (function (x) 1 #:domain D)]
      [F (antiderivative-function f #:using (function (x) x #:domain D)
                               #:on D #:justification "each component")]
      [I (definite-integral f #:from 2 #:to 5 #:antiderivative F)]))
  (check-equal? (calculus-result-status (model-result neighborhood-gap 'I))
                'outside-domain)
  (define-calculus-model normal-and-named-part
    (model
      [f (function (x) (+ (expt (- x 2) 2) 1))]
      [df (derivative-function f)]
      [G (graph f)]
      [P (point-on G #:x 2)]
      [T (tangent G #:at P #:derivative df)]
      [N (normal T)]
      [R (input-reading G 2)]
      [reading-point (part R 'point)]
      [named-input (x-coordinate reading-point)]))
  (check-value (model-result normal-and-named-part 'N)
               (list 'vertical 2 (cons 2 1)))
  (check-value (model-result normal-and-named-part 'named-input) 2)
  (define smooth-route-profile
    (calculus-profile #:timing audit-timing
                      #:motion (calculus-motion #:parameter-easing 'smoothstep)))
  (define-calculus-lesson smooth-route
    (model [a (parameter 0 #:domain (closed 0 2))])
    (views [axis (number-line-view #:range (closed 0 2) #:objects (a))])
    (initially (show a))
    (step move (vary a #:via (list 2) #:to 1 #:easing 'smoothstep #:duration 3)))
  (check-value
   (calculus-snapshot-ref
    (calculus-plan-sample (compile-calculus-lesson smooth-route #:profile audit-profile) #:at 2) 'a)
   2)
  (define-calculus-lesson profile-route
    (model [a (parameter 0 #:domain (closed 0 1))])
    (views [axis (number-line-view #:range (closed 0 1) #:objects (a))])
    (initially (show a))
    (step move (vary a #:to 1 #:easing 'profile #:duration 1)))
  (check-value
   (calculus-snapshot-ref
    (calculus-plan-sample (compile-calculus-lesson profile-route #:profile smooth-route-profile)
                          #:at 1/4)
    'a)
   5/32)
  (define-calculus-lesson invalid-route
    (model [a (parameter 0 #:domain (closed 0 1))])
    (views [axis (number-line-view #:range (closed 0 1) #:objects (a))])
    (initially (show a))
    (step move (vary a #:via (list 2) #:to 1 #:duration 1)))
  (check-true (pair? (calculus-plan-diagnostics
                      (compile-calculus-lesson invalid-route #:profile audit-profile))))
  ;; R3: numerical agreement is invalid when all requested floating-point
  ;; stencil inputs collapse to the same large input.
  (define-calculus-model collapsed-numeric-stencil
    (model [identity (function (x) x)]
           [numeric-identity (derivative-function identity #:method 'numeric #:step 1e-5)]
           [answer (value-at numeric-identity 1e20)]))
  (check-equal? (calculus-result-status (model-result collapsed-numeric-stencil 'answer))
                'unresolved)
  ;; Rational literals and unary division retain their held operation trees in
  ;; each public inspection spelling.
  (define-calculus-model rational-notation
    (model [power (formula (expt 3/2 2))]
           [reciprocal (formula (/ 2))]))
  (define rational-snapshot (calculus-model-at rational-notation))
  (check-equal?
   (calculus-result-value (calculus-snapshot-formula-tex rational-snapshot 'power))
   "\\left(\\frac{3}{2}\\right)^{2}")
  (check-equal?
   (calculus-result-value (calculus-snapshot-formula-text rational-snapshot 'reciprocal))
   "1/(2)")
  ;; Valid endpoints do not license a continuous route through an explicitly
  ;; excluded union gap or puncture.
  (define-calculus-lesson union-gap-route
    (model [a (parameter -2 #:domain (domain-union (closed -2 -1) (closed 1 2)))])
    (views [axis (number-line-view #:range (closed -2 2) #:objects (a))])
    (initially (show a))
    (step move (vary a #:to 2 #:easing 'linear #:duration 1)))
  (define-calculus-lesson punctured-route
    (model [a (parameter -1 #:domain (punctured-neighborhood 0 2))])
    (views [axis (number-line-view #:range (closed -2 2) #:objects (a))])
    (initially (show a))
    (step move (vary a #:to 1 #:easing 'linear #:duration 1)))
  (check-true (pair? (calculus-plan-diagnostics
                      (compile-calculus-lesson union-gap-route #:profile audit-profile))))
  (check-true (pair? (calculus-plan-diagnostics
                      (compile-calculus-lesson punctured-route #:profile audit-profile))))
  ;; Region fill inputs carry declared topology even when a pole is not on the
  ;; original fixed sampling grid; no adjacent drawable pair may straddle it.
  (define-calculus-model off-grid-region-pole
    (model [f (function (x) (/ 1 (- x 1/7))
                       #:domain (domain-except real-line 1/7))]
           [G (graph f)] [R (region-under G #:from 0 #:to 1)]))
  (define region-snapshot (calculus-model-at off-grid-region-pole))
  (define region-descriptor
    (calculus-result-value (calculus-snapshot-ref region-snapshot 'R)))
  (define region-samples
    (calculus-result-value
     (calculus-snapshot-region-samples region-snapshot region-descriptor)))
  (check-false
   (for/or ([left (in-list region-samples)] [right (in-list (cdr region-samples))])
     (and (list? left) (pair? left) (list? right) (pair? right)
          (< (car left) 1/7 (car right)))))
  ;; Held piecewise thresholds are the same kind of topology evidence: a
  ;; non-grid-aligned jump is a separator for a filled region, not an affine
  ;; zero crossing between two unrelated branches.
  (define-calculus-model off-grid-piecewise-jump
    (model [f (piecewise-function (x)
                [(< x 1/7) -1]
                [else 1])]
           [G (graph f)] [R (region-under G #:from 0 #:to 1)]))
  (define jump-snapshot (calculus-model-at off-grid-piecewise-jump))
  (define jump-descriptor
    (calculus-result-value (calculus-snapshot-ref jump-snapshot 'R)))
  (define jump-samples
    (calculus-result-value
     (calculus-snapshot-region-samples jump-snapshot jump-descriptor)))
  (check-false
   (for/or ([left (in-list jump-samples)] [right (in-list (cdr jump-samples))])
     (and (list? left) (pair? left) (list? right) (pair? right)
          (< (car left) 1/7 (car right)))))
  ;; Dynamic leaves reserve a field inside a prepared TeX skeleton; converting
  ;; one numeric occurrence never flattens the surrounding fraction, power,
  ;; or radical into ordinary slash/caret text.
  (define-calculus-model live-structured-notation
    (model [a (parameter 9 #:domain (closed 0 10))]
           [E (formula (/ (expt (value a) 2)
                         (sqrt (+ (ref a) 1))))]))
  (define structured-skeleton
    (calculus-result-value
     (calculus-snapshot-formula-skeleton-tex
      (calculus-model-at live-structured-notation) 'E 2)))
  (check-true (string-contains? structured-skeleton "\\frac"))
  (check-true (string-contains? structured-skeleton "\\sqrt"))
  (check-true (string-contains? structured-skeleton "^{2}"))
  (define live-initial (calculus-model-at live-field-regressions))
  (define live-final (calculus-model-at live-field-regressions #:values (hash 'a 10)))
  (define initial-fragments
    (calculus-result-value
     (calculus-snapshot-formula-fragments live-initial 'equation)))
  (define final-fragments
    (calculus-result-value
     (calculus-snapshot-formula-fragments live-final 'equation)))
  ;; The field payload can change width (9→10), while held prefix/suffix
  ;; fragments retain their source order for the prepared native field layout.
  (check-equal? (map car initial-fragments) (map car final-fragments))
  (check-equal? (map car initial-fragments) '(field text))
  (check-equal? (cadr (car initial-fragments)) "9")
  (check-equal? (cadr (car final-fragments)) "10")
  ;; R4: a distinct floating-point stencil must use its effective spacing,
  ;; not certify 4/3 for the identity function at a large input.
  (define-calculus-model effective-numeric-stencil
    (model [identity (function (x) x)]
           [numeric-identity (derivative-function identity #:method 'numeric #:step 3.0)]
           [answer (value-at numeric-identity 1e16)]))
  (define effective-stencil-answer (model-result effective-numeric-stencil 'answer))
  (if (eq? (calculus-result-status effective-stencil-answer) 'defined)
      (check-= (calculus-result-value effective-stencil-answer) 1 1e-9)
      (check-equal? (calculus-result-status effective-stencil-answer) 'unresolved))
  ;; A live field inherits the same visible precedence grouping as the fully
  ;; resolved Formula.  In particular its rational value is the power base.
  (define-calculus-model live-rational-power
    (model [a (parameter 3/2 #:domain (closed 1 2))]
           [E (formula (expt (value a) 2))]))
  (define live-rational-snapshot (calculus-model-at live-rational-power))
  (define live-rational-text
    (calculus-result-value
     (calculus-snapshot-formula-text live-rational-snapshot 'E)))
  (define live-rational-fragments
    (calculus-result-value
     (calculus-snapshot-formula-fragments live-rational-snapshot 'E)))
  (check-equal? live-rational-text "(3/2)^2")
  (check-equal? (apply string-append (map cadr live-rational-fragments))
                live-rational-text)
  ;; Filled regions are graph topology consumers: provider-declared breaks
  ;; and graph-only restrictions both become samples and hard separators.
  (define (r4-jump-provider x) (if (< x 1/7) -1 1))
  (define (no-region-strip-across? samples cut)
    (not
     (for/or ([left (in-list samples)] [right (in-list (cdr samples))])
       (and (list? left) (list? right) (< (car left) cut (car right))))))
  (define-calculus-model provider-break-region
    (model [f (procedure-function (external r4-jump-provider)
                #:domain (closed 0 1) #:key 'r4-jump #:breaks (list 1/7))]
           [G (graph f)] [R (region-under G #:from 0 #:to 1)]))
  (define provider-region-snapshot (calculus-model-at provider-break-region))
  (define provider-region-samples
    (calculus-result-value
     (calculus-snapshot-region-samples
      provider-region-snapshot
      (calculus-result-value (calculus-snapshot-ref provider-region-snapshot 'R)))))
  (check-true (no-region-strip-across? provider-region-samples 1/7))
  (define-calculus-model restricted-graph-region
    (model [f (function (x) 1 #:domain (closed 0 1))]
           [G (graph f)]
           [H (graph-restriction G
                                 (domain-union (closed 0 1/7) (closed 29/200 1)))]
           [R (region-under H #:from 0 #:to 1)]))
  (define restricted-region-snapshot (calculus-model-at restricted-graph-region))
  (define restricted-region-samples
    (calculus-result-value
     (calculus-snapshot-region-samples
      restricted-region-snapshot
      (calculus-result-value (calculus-snapshot-ref restricted-region-snapshot 'R)))))
  (check-true (no-region-strip-across? restricted-region-samples
                                       (/ (+ 1/7 29/200) 2)))
  ;; R5: agreeing finite-difference estimates are only evidence when the
  ;; refinement really narrowed the floating-point stencil at the input.
  (define-calculus-model duplicate-effective-numeric-stencil
    (model [f (function (x) (expt (- x 1e16) 3))]
           [df (derivative-function f #:method 'numeric #:step 2.5)]
           [answer (value-at df 1e16)]))
  (define duplicate-stencil-answer
    (model-result duplicate-effective-numeric-stencil 'answer))
  (if (eq? (calculus-result-status duplicate-stencil-answer) 'defined)
      (check-= (calculus-result-value duplicate-stencil-answer) 0 1e-9)
      (check-equal? (calculus-result-status duplicate-stencil-answer)
                    'unresolved))
  ;; Graph-local `#:on` further restricts the source function's domain; it
  ;; does not restore a source pole that lies inside that displayed interval.
  (define-calculus-model explicit-graph-domain-pole
    (model [f (function (x) (/ 1 (- x 1/7))
                       #:domain (domain-except real-line 1/7))]
           [G (graph f #:on (closed 0 1))]
           [R (region-under G #:from 0 #:to 1)]))
  (define explicit-domain-snapshot
    (calculus-model-at explicit-graph-domain-pole))
  (define explicit-domain-samples
    (calculus-result-value
     (calculus-snapshot-region-samples
      explicit-domain-snapshot
      (calculus-result-value
       (calculus-snapshot-ref explicit-domain-snapshot 'R)))))
  (check-true (no-region-strip-across? explicit-domain-samples 1/7))
  ;; R6: the named initial phase precedes all timeline actions, whereas a
  ;; numeric zero remains right-continuous through simultaneous assignments.
  (define-calculus-lesson initial-phase-boundary
    (model [a (parameter 0 #:domain (closed 0 2))])
    (views [axis (number-line-view #:range (closed 0 2) #:objects (a))])
    (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
    (step setup (set-parameter a 1) (set-parameter a 2) (pause 1)))
  (define initial-phase-plan (compile-calculus-lesson initial-phase-boundary))
  (check-value
   (calculus-snapshot-ref (calculus-plan-sample initial-phase-plan #:at 'initial) 'a)
   0)
  (check-value
   (calculus-snapshot-ref
    (calculus-plan-sample initial-phase-plan #:at (calculus-step-start 'setup))
    'a)
   0)
  (check-value
   (calculus-snapshot-ref (calculus-plan-sample initial-phase-plan #:at 0) 'a)
   2)
  ;; Chords, secants, and tangents are graph-associated geometry.  They accept
  ;; independent coordinates only when those coordinates actually belong to
  ;; the named graph and its effective restriction.
  (define-calculus-model graph-incidence-regressions
    (model [f (function (x) (* x x))]
           [df (derivative-function f)]
           [G (graph f)]
           [H (graph f #:on (closed 0 1))]
           [Pbad (point 1 2)]
           [Pgood (point 1 1)]
           [Q (point-on G #:x 2)]
           [bad-chord (chord G Pbad Q)]
           [bad-secant (secant G Pbad Q)]
           [bad-tangent (tangent G #:at Pbad #:derivative df)]
           [bad-vertical-tangent
            (vertical-tangent G #:at Pbad
                              #:justification "A supplied vertical tangent claim.")]
           [out-of-range-secant (secant H Pgood Q)]
           [out-of-range-tangent (tangent H #:at Q #:derivative df)]
           [good-secant (secant G Pgood Q)]
           [good-tangent (tangent G #:at Pgood #:derivative df)]))
  (for ([name (in-list '(bad-chord bad-secant bad-tangent bad-vertical-tangent
                                   out-of-range-secant out-of-range-tangent))])
    (check-not-equal? (calculus-result-status
                       (model-result graph-incidence-regressions name))
                      'defined))
  (check-value (model-result graph-incidence-regressions 'good-secant)
               (list 'line 3 -2 (cons 1 1)))
  (check-value (model-result graph-incidence-regressions 'good-tangent)
               (list 'line 2 -1 (cons 1 1)))
  ;; R7: a symbolic phase preserves its authored caption at a shared numeric
  ;; boundary, whereas direct numeric sampling remains right-continuous.
  (define r7-caption-plan (compile-calculus-lesson r7-caption-phases))
  (check-equal? (calculus-plan-caption r7-caption-plan (calculus-step-end 'first))
                "a = 0")
  (check-equal? (calculus-plan-caption r7-caption-plan (calculus-checkpoint 'first-done))
                "a = 0")
  (check-equal? (calculus-plan-caption r7-caption-plan (calculus-step-start 'second))
                "a = 1")
  (check-equal? (calculus-plan-caption r7-caption-plan 1) "a = 1")
  ;; Feature points and frozen snapshots retain Point sort, so all ordinary
  ;; point consumers use their exact coordinates rather than a raw wrapper.
  (check-value (model-result r7-wrapped-points 'feature-x) 1)
  (check-value (model-result r7-wrapped-points 'feature-projection) (cons 1 0))
  (check-value (model-result r7-wrapped-points 'feature-tangent)
               (list 'line 0 1 (cons 1 1)))
  (check-value (model-result r7-wrapped-points 'frozen-x) 1)
  (check-value (model-result r7-wrapped-points 'frozen-projection) (cons 1 0))
  ;; Reverse readings enumerate author-supplied candidates in source order.
  ;; Their `#:completeness` claim remains authored metadata; each individual
  ;; candidate is nevertheless checked against graph domain and requested y.
  (define r7-reverse-snapshot (calculus-model-at r7-reverse-reading))
  (check-value (calculus-snapshot-ref r7-reverse-snapshot 'left-point) (cons -1 1))
  (check-value (calculus-snapshot-ref r7-reverse-snapshot 'right-point) (cons 1 1))
  (check-value (calculus-snapshot-ref r7-reverse-snapshot 'left-input) -1)
  (check-value (calculus-snapshot-ref r7-reverse-snapshot 'output) 1)
  (check-value (calculus-snapshot-reading-points r7-reverse-snapshot 'R)
               (list (cons -1 1) (cons 1 1)))
  ;; R8: a checkpoint's public name is an address, not an implicit owner path.
  ;; Both a qualified name and one colliding with a future step retain first's
  ;; lexical caption, while numeric sampling remains right-continuous.
  (define r8-qualified-plan (compile-calculus-lesson r8-qualified-checkpoint-caption))
  (check-value
   (calculus-snapshot-ref
    (calculus-plan-sample r8-qualified-plan
                          #:at (calculus-checkpoint '(review before)))
    'a)
   0)
  (check-equal?
   (calculus-plan-caption r8-qualified-plan (calculus-checkpoint '(review before)))
   "a = 0")
  (check-equal? (calculus-plan-caption r8-qualified-plan 1) "a = 1")
  (define r8-colliding-plan (compile-calculus-lesson r8-colliding-checkpoint-caption))
  (check-value
   (calculus-snapshot-ref
    (calculus-plan-sample r8-colliding-plan
                          #:at (calculus-checkpoint '(second before)))
    'a)
   0)
  (check-equal?
   (calculus-plan-caption r8-colliding-plan (calculus-checkpoint '(second before)))
   "a = 0")
  ;; A frozen Point preserves Reading's Point sort whether its source used a
  ;; named public projection or the direct public part spelling.
  (define r8-projection-snapshot
    (calculus-model-at r8-projection-snapshots #:values (hash 'a 2)))
  (check-value (calculus-snapshot-ref r8-projection-snapshot 'S) (cons 1 1))
  (check-value (calculus-snapshot-ref r8-projection-snapshot 'D) (cons 1 1))
  (check-value (calculus-snapshot-ref r8-projection-snapshot 'xS) 1)
  (check-value (calculus-snapshot-ref r8-projection-snapshot 'yD) 1)
  ;; Named intermediate branches compose exactly as the inline branch.  The
  ;; semantic guide and label parts remain addressable instead of becoming
  ;; renderer-only approximations.
  (define r8-branch-snapshot (calculus-model-at r8-reverse-branch-protocol))
  (check-value (calculus-snapshot-ref r8-branch-snapshot 'P) (cons -1 1))
  (check-value (calculus-snapshot-ref r8-branch-snapshot 'Q) (cons -1 1))
  (for ([name (in-list '(input-guide output-guide input-label branches output-label))])
    (check-equal? (calculus-result-status
                   (calculus-snapshot-ref r8-branch-snapshot name))
                  'defined))
  ;; A reverse Reading is an explicit candidate construction. Empty lists,
  ;; unsupported evidence, invalid outputs, and coalesced branch identities
  ;; are all structured partiality at the shared demanded-value boundary.
  (define-calculus-model r8-empty-reading
    (model [f (function (x) (* x x))] [G (graph f)]
           [R (output-reading G 1 #:inputs (list))]))
  (define-calculus-model r8-undefined-empty-reading
    (model [f (function (x) (* x x))] [G (graph f)]
           [R (output-reading G (/ 1 0) #:inputs (list))]))
  (define-calculus-model r8-missing-evidence-reading
    (model [f (function (x) (* x x))] [G (graph f)]
           [R (output-reading G 1 #:inputs (list -1 1) #:completeness 'all)]))
  (define-calculus-model r8-invalid-completeness-reading
    (model [f (function (x) (* x x))] [G (graph f)]
           [R (output-reading G 1 #:inputs (list -1 1) #:completeness 'typo)]))
  (define-calculus-model r8-colliding-branches-reading
    (model [h (parameter 0 #:domain (closed 0 1))]
           [f (function (x) (* x x))] [G (graph f)]
           [R (output-reading G (* h h) #:inputs (list (- h) h)
              #:completeness 'all
              #:justification "For h>0 these are the two square roots of h^2.")]))
  (for ([model (in-list (list r8-empty-reading r8-undefined-empty-reading
                              r8-missing-evidence-reading
                              r8-invalid-completeness-reading
                              r8-colliding-branches-reading))])
    (check-reading-rejected
     (calculus-snapshot-reading-points (calculus-model-at model) 'R)))
  ;; R9: reverse candidates collide by mathematical numeric equality, not by
  ;; their printed exactness or the sign bit of zero. Distinct close values
  ;; stay independently selected with no tolerance-based deduplication.
  (for ([model (in-list (list r9-mixed-input-collision r9-signed-zero-collision))])
    (check-reading-rejected
     (calculus-snapshot-reading-points (calculus-model-at model) 'R)))
  (check-value
   (calculus-snapshot-reading-points (calculus-model-at r9-distinct-close-inputs) 'R)
   (list (cons 0 1) (cons 1/1000000000000 1)))
  ;; A public component export remains caller-addressed while its Reading
  ;; geometry and branch projections evaluate in the component's lexical
  ;; model. The integer branch selector is typed internally, not public text.
  (define r9-exported-snapshot (calculus-model-at r9-exported-reading))
  (check-value (calculus-snapshot-reading-points r9-exported-snapshot '(study R))
               (list (cons -1 1) (cons 1 1)))
  (check-value (calculus-snapshot-ref r9-exported-snapshot 'right-point)
               (cons 1 1)))
  ;; R10: a generated Reading child inherits its root's label preference while
  ;; keeping its own visibility and presentation state. These are headless
  ;; preconditions for the native owned-part compositor tests.
  (define r10-plan (compile-calculus-lesson r10-reading-owned-presentation))
  (define r10-snapshot (calculus-plan-sample r10-plan #:at 'final))
  (define r10-root
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model r10-reading-owned-presentation))
              'R))
  (define r10-branch (c-part r10-root '(branches 1)))
  (define r10-point (c-part r10-branch 'point))
  (define r10-guide (c-part r10-branch 'input-guide))
  (define r10-input-label (c-part r10-branch 'input-label))
  (define r10-output-label (c-part r10-root 'output-label))
  (check-true (calculus-snapshot-visible? r10-snapshot r10-root #:view 'plot))
  (check-true (calculus-snapshot-visible? r10-snapshot r10-point #:view 'plot))
  (check-equal? (calculus-snapshot-presentation-state r10-snapshot r10-guide #:view 'plot)
                'deemphasized)
  (check-false (calculus-snapshot-label-visible? r10-snapshot r10-input-label #:view 'plot))
  (check-false (calculus-snapshot-label-visible? r10-snapshot r10-output-label #:view 'plot))
  ;; R11: local label actions consult and update the same scoped preference,
  ;; then fall back to the global owner state. Explicit inherited children are
  ;; retained as demand identities even when Reading geometry is nondefined.
  (define r11-label-plan (compile-calculus-lesson r11-scoped-label-cycle))
  (define r11-label-root
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model r11-scoped-label-cycle))
              'R))
  (define r11-label-masked
    (calculus-plan-sample r11-label-plan #:at (calculus-step-end 'masked)))
  (define r11-label-final (calculus-plan-sample r11-label-plan #:at 'final))
  (check-false (calculus-snapshot-label-visible? r11-label-masked r11-label-root #:view 'left))
  (check-true (calculus-snapshot-label-visible? r11-label-masked r11-label-root #:view 'right))
  (check-true (calculus-snapshot-label-visible? r11-label-final r11-label-root #:view 'left))
  (define (r11-child lesson index)
    (define root (hash-ref (calculus-model-nodes (calculus-lesson-model lesson)) 'R))
    (c-part (c-part root (list 'branches index)) 'point))
  (for ([lesson (in-list (list r11-inherited-invalid-child
                               r11-inherited-missing-branch))]
        [index (in-list '(0 7))])
    (define state (calculus-plan-sample (compile-calculus-lesson lesson) #:at 'final))
    (define target (r11-child lesson index))
    (check-true (calculus-snapshot-visible? state target #:view 'plot))
    (check-not-false (member target
                             (calculus-snapshot-reading-owned-parts state
                                                                     (hash-ref (calculus-model-nodes
                                                                                (calculus-lesson-model lesson))
                                                                               'R)
                                                                     #:view 'plot)))
    (check-not-equal? (calculus-result-status (calculus-snapshot-ref state target)) 'defined)
  ;; R12: rendering may deduplicate a Reading child only after the explicitly
  ;; requested identity is validated, and a named Part's state shares that
  ;; canonical child's identity when the root performs the one remaining draw.
  (define r12-missing-state
    (calculus-plan-sample (compile-calculus-lesson r12-visible-root-missing-point) #:at 'final))
  (define r12-missing-root
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model r12-visible-root-missing-point))
              'R))
  (define r12-missing-point (c-part (c-part r12-missing-root '(branches 7)) 'point))
  (check-true (calculus-snapshot-visible? r12-missing-state r12-missing-root #:view 'plot))
  (check-true (calculus-snapshot-visible? r12-missing-state r12-missing-point #:view 'plot))
  (check-not-equal? (calculus-result-status
                     (calculus-snapshot-ref r12-missing-state r12-missing-point))
                    'defined)
  (define r12-guide-state
    (calculus-plan-sample (compile-calculus-lesson r12-inherited-missing-guide) #:at 'final))
  (define r12-guide-root
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model r12-inherited-missing-guide))
              'R))
  (define r12-missing-guide (c-part (c-part r12-guide-root '(branches 7)) 'input-guide))
  (check-not-false
   (member r12-missing-guide
           (calculus-snapshot-reading-owned-parts r12-guide-state r12-guide-root #:view 'plot)))
  (define r12-named-state
    (calculus-plan-sample (compile-calculus-lesson r12-named-owned-point-state) #:at 'final))
  (define r12-named-point
    (hash-ref (calculus-model-nodes
               (calculus-lesson-model r12-named-owned-point-state))
              'P))
  (define r12-canonical-point
    (c-part (c-part (hash-ref (calculus-model-nodes
                                (calculus-lesson-model r12-named-owned-point-state))
                               'R)
                    '(branches 1))
            'point))
  (check-equal? (calculus-snapshot-presentation-state r12-named-state r12-named-point #:view 'plot)
                'deemphasized)
  (check-equal? (calculus-snapshot-presentation-state r12-named-state r12-canonical-point #:view 'plot)
                'deemphasized)
  ;; R13: a Part alias is a nonscalar alias through every model-binding hop.
  ;; Its public name remains inspectable while its value, coordinate consumer,
  ;; and persistent presentation state all resolve to the canonical Point.
  (define r13-chain-state
    (calculus-plan-sample (compile-calculus-lesson r13-chained-owned-point-state) #:at 'final))
  (define r13-chain-model (calculus-lesson-model r13-chained-owned-point-state))
  (define r13-point-alias (hash-ref (calculus-model-nodes r13-chain-model) 'P))
  (define r13-second-alias (hash-ref (calculus-model-nodes r13-chain-model) 'A))
  (define r13-canonical-point
    (c-part (c-part (hash-ref (calculus-model-nodes r13-chain-model) 'R) '(branches 1))
            'point))
  (check-value (calculus-snapshot-ref r13-chain-state 'A) (cons 1 1))
  (check-value (calculus-snapshot-ref r13-chain-state 'xA) 1)
  (for ([target (in-list (list r13-point-alias r13-second-alias r13-canonical-point))])
    (check-equal? (calculus-snapshot-presentation-state r13-chain-state target #:view 'plot)
                  'deemphasized))
  ;; Scalar aliases retain their own named read-only presentation identity.
  (define r13-scalar-state
    (calculus-plan-sample (compile-calculus-lesson r13-distinct-scalar-alias-state) #:at 'final))
  (define r13-scalar-model (calculus-lesson-model r13-distinct-scalar-alias-state))
  (check-equal?
   (calculus-snapshot-presentation-state r13-scalar-state
                                         (hash-ref (calculus-model-nodes r13-scalar-model) 'a)
                                         #:view 'axis)
   'normal)
  (check-equal?
   (calculus-snapshot-presentation-state r13-scalar-state
                                         (hash-ref (calculus-model-nodes r13-scalar-model) 'b)
                                         #:view 'axis)
   'deemphasized)
  ;; R14: scalar-valued component exports remain named, read-only scalar
  ;; quantities through subsequent bindings, unlike an exported Point alias.
  (define r14-scalar-plan (compile-calculus-lesson r14-scalar-export-alias-state))
  (define r14-scalar-dim
    (calculus-plan-sample r14-scalar-plan #:at (calculus-step-end 'dim)))
  (define r14-scalar-final (calculus-plan-sample r14-scalar-plan #:at 'final))
  (define r14-scalar-model (calculus-lesson-model r14-scalar-export-alias-state))
  (define r14-u (hash-ref (calculus-model-nodes r14-scalar-model) 'u))
  (define r14-v (hash-ref (calculus-model-nodes r14-scalar-model) 'v))
  (for ([name (in-list '(u v))])
    (check-value (calculus-snapshot-ref r14-scalar-final name) 1))
  (check-equal? (calculus-snapshot-presentation-state r14-scalar-dim r14-u #:view 'axis)
                'normal)
  (check-equal? (calculus-snapshot-presentation-state r14-scalar-dim r14-v #:view 'axis)
                'deemphasized)
  (check-true (calculus-snapshot-visible? r14-scalar-final 'u #:view 'axis))
  (check-false (calculus-snapshot-visible? r14-scalar-final 'v #:view 'axis))
  ;; R15: the selected leaf below the outer Component is a Scalar. `u` and
  ;; `v` therefore remain distinct named quantities even though their values
  ;; flow through the same finite component chain.
  (define r15-nested-plan (compile-calculus-lesson r15-nested-scalar-export-state))
  (define r15-nested-dim
    (calculus-plan-sample r15-nested-plan #:at (calculus-step-end 'dim)))
  (define r15-nested-final (calculus-plan-sample r15-nested-plan #:at 'final))
  (define r15-nested-model (calculus-lesson-model r15-nested-scalar-export-state))
  (define r15-u (hash-ref (calculus-model-nodes r15-nested-model) 'u))
  (define r15-v (hash-ref (calculus-model-nodes r15-nested-model) 'v))
  (for ([address (in-list '((study inner s) u v))])
    (check-value (calculus-snapshot-ref r15-nested-final address) 1))
  (define r15-overridden
    (calculus-plan-sample (compile-calculus-lesson r15-nested-scalar-export-state
                                                    #:values (hash 'a 2))
                          #:at 'final))
  (for ([address (in-list '((study inner s) u v))])
    (check-value (calculus-snapshot-ref r15-overridden address) 2))
  (check-equal? (calculus-snapshot-presentation-state r15-nested-dim r15-u #:view 'axis)
                'normal)
  (check-equal? (calculus-snapshot-presentation-state r15-nested-dim r15-v #:view 'axis)
                'deemphasized)
  (check-true (calculus-snapshot-visible? r15-nested-final 'u #:view 'axis))
  (check-false (calculus-snapshot-visible? r15-nested-final 'v #:view 'axis))
  ;; Selected Reading parts, frozen points, line points, and feature points
  ;; retain Point type at a component boundary.  The separate Scalar contract
  ;; accepts Scalar/Integer values but never a Point carried by a public Part.
  (define r15-input-snapshot (calculus-model-at r15-typed-component-inputs))
  (for ([address (in-list '((projected x) (inline x) (frozen x) (on-line x) (feature x)))])
    (check-value (calculus-snapshot-ref r15-input-snapshot address) 1))
  (check-value (calculus-snapshot-ref r15-input-snapshot '(scalar out)) 1)
  (check-value (calculus-snapshot-ref r15-input-snapshot '(integer out)) 2)
  (check-value (calculus-snapshot-ref r15-input-snapshot '(boolean out)) #t)
  (for ([model (in-list (list r15-named-point-as-scalar r15-inline-point-as-scalar))])
    (check-equal? (calculus-result-status
                   (calculus-snapshot-ref (calculus-model-at model) '(bad out)))
                  'undefined)))

(module+ test
  (run-calculus-audit-regression-tests))
