#lang racket/base

;;;
;;; Calculus Rendering Smoke Tests
;;;

;; Verifies the public rendering adapter consumes the same lesson declaration
;; as headless inspection and produces ordinary Animate and Pict artifacts.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         (prefix-in pict: pict)
         (prefix-in native: "../../main.rkt")
         racket/class
         racket/draw
         racket/list
         (only-in "../../private/pict-renderer.rkt" gen:pict-renderer)
         (only-in "../private/core.rkt"
                  calculus-plan-caption
                  calculus-snapshot-label-anchor
                  calculus-snapshot-label-text
                  calculus-snapshot-marker-geometry
                  calculus-snapshot-formula-text)
         (only-in "guide-lessons-test.rkt"
                  guide-reading-square
                  guide-secant-to-tangent
                  guide-build-derivative
                  guide-limit-not-value
                  guide-sums-and-accumulation
                  guide-component-example)
         "../render.rkt")

;; Exports
(provide run-calculus-render-smoke-tests)

;; dynamic-formula-backend-calls : exact-nonnegative-integer?
;; Counts any whole-formula backend use. Live Formula field rows must keep it
;; at zero after preparation; static Formula tests continue to exercise the
;; real configured backend elsewhere in this suite.
(define dynamic-formula-backend-calls 0)

(struct counting-formula-renderer ()
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer _visual) #t)
   (define (pict-renderer-render _renderer _visual _camera)
     (set! dynamic-formula-backend-calls (add1 dynamic-formula-backend-calls))
     (pict:blank 1 1))])


;;;
;;; Fixture
;;;

;; render-reading-square : calculus-lesson?
;;   A compact graph-reading lesson with a visible graph and moving reading.
(define-calculus-lesson render-reading-square
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
  (step show-reading (show R))
  (step scan (vary a #:to -2 #:duration 1)))

;; render-scene-continuity : calculus-lesson?
;; A zero-pause one-second coordinate motion gives an independent off-grid
;; oracle for the scene adapter: at t=1/60 P must be at x=1/60, not held at 0.
(define-calculus-lesson render-scene-continuity
  (model
    [a (parameter 0 #:domain (closed 0 1))]
    [P (point a 0)])
  (views
    [plot (graph-view #:x (closed 0 1) #:y (closed -1 1) #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show P))
  (step move (vary a #:to 1 #:easing 'linear #:duration 1)))

;; render-demanded-invalid-point : calculus-lesson?
;; The graph's ordinary hole is legal, but an explicitly visible named point
;; at that hole is a strict native-output error rather than a skipped painter.
(define-calculus-lesson render-demanded-invalid-point
  (model
    [f (function (x) (/ 1 x) #:domain (domain-except real-line 0))]
    [G (graph f)]
    [P (point-on G #:x 0)])
  (views
    [plot (graph-view #:x (closed -1 1) #:y (closed -2 2) #:objects (G P))])
  (initially (show G P))
  (step retain (pause 1)))

;; render-hidden-invalid-point : calculus-lesson?
;; The same declared partial construction stays legal when it is not demanded.
(define-calculus-lesson render-hidden-invalid-point
  (model
    [f (function (x) (/ 1 x) #:domain (domain-except real-line 0))]
    [G (graph f)]
    [P (point-on G #:x 0)])
  (views
    [plot (graph-view #:x (closed -1 1) #:y (closed -2 2) #:objects (G P))])
  (initially (show G))
  (step retain (pause 1)))

;; static-graph-provider-calls : exact-nonnegative-integer?
;;   Counts an opaque but version-keyed provider so the native test can prove
;; that prepared static graph geometry is not resampled for an unrelated point.
(define static-graph-provider-calls 0)

;; render-static-graph-cache : calculus-lesson?
;;   Moves an ordinary point while its graph provider has no parameter dependency.
(define-calculus-lesson render-static-graph-cache
  (model
    [a (parameter -1 #:domain (closed -1 1))]
    [f (procedure-function
        (external (lambda (x)
                    (set! static-graph-provider-calls
                          (add1 static-graph-provider-calls))
                    (* x x)))
        #:domain (closed -2 2)
        #:key 'counted-static-square)]
    [G (graph f)]
    [P (point a 0)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -1 5)
                      #:objects (G P))])
  (initially (show G P))
  (step move-unrelated-point (vary a #:to 1 #:duration 1)))

;; render-dynamic-graph-cache : calculus-lesson?
;; A function-family parameter changes the graph itself.  This companion to
;; render-static-graph-cache ensures the prepared static path is never used as
;; a stale substitute for a parameter-dependent graph.
(define-calculus-lesson render-dynamic-graph-cache
  (model
    [scale (parameter 1 #:domain (closed 1 2))]
    [f (function (x) (* scale (* x x)))]
    [G (graph f)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -1 9)
                      #:objects (G))])
  (initially (show G))
  (step scale-graph (vary scale #:to 2 #:duration 1)))

;; render-special-value : calculus-lesson?
;;   Supplies an isolated graph value and the excluded nearby branch endpoint.
(define-calculus-lesson render-special-value
  (model
    [g (piecewise-function (x)
         [(= x 0) 4]
         [else (+ x 1)])]
    [G (graph g)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed 0 5)
                      #:objects (G))])
  (initially (show G))
  (step retain-special-value (show G)))

;; render-provider-break : calculus-lesson?
;; The opaque provider is finite at x=1/2, but its declared break remains a
;; mandatory gap in native graph topology.
(define-calculus-lesson render-provider-break
  (model
    [f (procedure-function (external (lambda (x) x))
                           #:domain (closed -1 1)
                           #:key 'identity-provider
                           #:breaks (list 1/2))]
    [G (graph f)])
  (views
    [plot (graph-view #:x (closed -1 1)
                      #:y (closed -1 1)
                      #:objects (G))])
  (initially (show G))
  (step retain-provider (pause 1)))

;; render-trace-square : calculus-lesson?
;;   Draws an authored locus prefix directly from its sweep coordinate.
(define-calculus-lesson render-trace-square
  (model
    [u (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x u)]
    [locus (trace-of P #:parameter u #:over (closed 0 2))])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 4)
                      #:objects (locus))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step trace-locus (trace locus #:duration 2)))

;; render-focus-square : calculus-lesson?
;;   Keeps mathematical coordinates fixed while a graph view changes window.
(define-calculus-lesson render-focus-square
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 3/2)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -2 2)
                      #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step focus-plot (focus plot #:x (closed 0 2) #:y (closed 0 4) #:duration 2)))

;; render-secant-tangent : calculus-lesson?
;;   Exercises native clipping and the semantic line replacement used by a
;;   standard secant-to-tangent transition.
(define-calculus-lesson render-secant-tangent
  (model
    [f (function (x) (* x x))]
    [df (derivative-function
         f #:method 'supplied #:using (function (x) (* 2 x))
         #:justification "The derivative of x² is 2x.")]
    [a 1]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [G (graph f)]
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [S (secant G P Q)]
    [m (difference-quotient f a h)]
    [L (limit-statement m #:parameter h #:to 0 #:value 2 #:side 'right
                        #:justification "The finite secant slope approaches 2.")]
    [T (tangent G #:at P #:derivative df)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G S T))])
  (initially (show G S))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step replace-secant (limit-transition S T #:claim L #:duration 1)))

;; render-slope-triangle : calculus-lesson?
;;   Keeps the directed rise/run construction in mathematical coordinates.
(define-calculus-lesson render-slope-triangle
  (model
    [P (point 1 1)]
    [Q (point 2 3)]
    [change (increment P Q)]
    [triangle (slope-triangle change #:labels #f)])
  (views
    [plot (graph-view #:x (closed 0 3)
                      #:y (closed 0 4)
                      #:objects (change triangle))])
  (initially (show change triangle))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-triangle (pause 1)))

;; render-epsilon-delta-bands : calculus-lesson?
;;   Uses the epsilon–delta claim's generated drawable regions directly.
(define-calculus-lesson render-epsilon-delta-bands
  (model
    [f (function (x) (+ x 1))]
    [epsilon 1/2]
    [delta 1/2]
    [bands (epsilon-delta-condition
            f #:at 1 #:limit 2 #:epsilon epsilon #:delta delta
            #:justification "Taking δ=ε works.")])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 4)
                      #:objects ((part bands 'input-band)
                                 (part bands 'output-band)))])
  (initially (show (part bands 'input-band) (part bands 'output-band)))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-bands (pause 1)))

;; render-riemann-rectangles : calculus-lesson?
;;   Makes the signed finite approximation directly drawable in a graph view.
(define-calculus-lesson render-riemann-rectangles
  (model
    [f (function (x) (* x x))]
    [partition (uniform-partition 0 2 #:count 4)]
    [tags (tag-partition partition #:sample 'midpoint)]
    [sum (riemann-sum f tags)]
    [rectangles (riemann-rectangles sum)])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 4)
                      #:objects (rectangles))])
  (initially (show rectangles))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-rectangles (pause 1)))

;; render-refinement-carrier : calculus-lesson?
;; Keeps two committed rectangles while a four-cell subdivision carrier is
;; sampled halfway through the action.
(define-calculus-lesson render-refinement-carrier
  (model
    [n (parameter 2 #:domain (integers 1 8) #:kind 'integer)]
    [f (function (x) x)]
    [partition (uniform-partition 0 2 #:count n)]
    [tags (tag-partition partition #:sample 'midpoint)]
    [sum (riemann-sum f tags)]
    [boxes (riemann-rectangles sum)])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 2)
                      #:objects (boxes))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show boxes))
  (step refine-boxes (refine partition #:counts (list 4) #:duration 1)))

;; render-reveal-policies : calculus-lesson?
;; Starts with both semantic objects hidden so trace/extend and fade can be
;; compared at an interior sample without changing their final mathematics.
(define-calculus-lesson render-reveal-policies
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [A (point 0 0)]
    [B (point 2 2)]
    [L (segment A B)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 4) #:objects (G L))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show G L)))

;; render-trapezoidal-regions : calculus-lesson?
;;   A single affine cell crossing zero must retain two signed visual pieces.
(define-calculus-lesson render-trapezoidal-regions
  (model
    [f (function (x) x)]
    [partition (uniform-partition -1 1 #:count 1)]
    [regions (trapezoidal-regions f partition)])
  (views
    [plot (graph-view #:x (closed -1 1)
                      #:y (closed -1 1)
                      #:objects (regions))])
  (initially (show regions))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-regions (pause 1)))

;; render-cropped-trapezoid : calculus-lesson?
;; Its source cell occupies 0≤x≤2 under y=x, while the camera shows 0≤x≤1.
;; Exact polygon clipping must retain the diagonal boundary to (1,1), not move
;; it to the independently clamped point (1,2).
(define-calculus-lesson render-cropped-trapezoid
  (model
    [f (function (x) x)]
    [partition (uniform-partition 0 2 #:count 1)]
    [regions (trapezoidal-regions f partition)])
  (views
    [plot (graph-view #:x (closed 0 1)
                      #:y (closed 0 2)
                      #:objects (regions))])
  (initially (show regions))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-regions (pause 1)))

;; render-partition-marks : calculus-lesson?
;;   Axis ticks are derived from the partition endpoints, not pixel spacing.
(define-calculus-lesson render-partition-marks
  (model
    [partition (uniform-partition 0 2 #:count 4)]
    [marks (partition-marks partition)])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 4)
                      #:objects (marks))])
  (initially (show marks))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-marks (pause 1)))

;; render-region-under : calculus-lesson?
;;   Geometry below and above the axis remains signed when visually split.
(define-calculus-lesson render-region-under
  (model
    [f (function (x) x)]
    [F (graph f)]
    [region (region-under F #:from -1 #:to 1)])
  (views
    [plot (graph-view #:x (closed -1 1)
                      #:y (closed -1 1)
                      #:objects (region))])
  (initially (show region))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-region (pause 1)))

;; render-region-between : calculus-lesson?
;;   Crossing graphs need no globally selected upper curve.
(define-calculus-lesson render-region-between
  (model
    [f (function (x) x)]
    [g (function (x) (- x))]
    [F (graph f)]
    [G (graph g)]
    [region (region-between F G #:from -1 #:to 1)])
  (views
    [plot (graph-view #:x (closed -1 1)
                      #:y (closed -1 1)
                      #:objects (region))])
  (initially (show region))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-region (pause 1)))

;; render-zero-width-integral-region : calculus-lesson?
;;   A visible accumulation region starts with coincident integration bounds.
;;   Native preparation must treat that exact zero-area state as empty paint,
;;   not as a sign crossing with an undefined affine interpolation.
(define-calculus-lesson render-zero-width-integral-region
  (model
    [x (parameter 0 #:domain (closed 0 1))]
    [f (function (u) (* u u))]
    [G (graph f)]
    [region (integral-region G #:from 0 #:to x)])
  (views
    [plot (graph-view #:x (closed 0 1)
                      #:y (closed 0 1)
                      #:objects (region))])
  (initially (show region))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-region (pause 1)))

;; render-sequence-points : calculus-lesson?
;;   Discrete samples must not be turned into a continuous plotted function.
(define-calculus-lesson render-sequence-points
  (model
    [s (sequence (n) (* n n) #:from 0)]
    [points (sequence-points s #:through 3)])
  (views
    [plot (graph-view #:x (closed -1/2 7/2)
                      #:y (closed -1/2 19/2)
                      #:objects (points))])
  (initially (show points))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-points (pause 1)))

;; render-number-line : calculus-lesson?
;;   A scalar gets a true coordinate marker in the declared finite range.
(define-calculus-lesson render-number-line
  (model [a (parameter 1 #:domain (closed 0 2))])
  (views [line (number-line-view #:range (closed 0 2) #:objects (a))])
  (initially (show a))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-value (pause 1)))

;; render-sign-chart : calculus-lesson?
;;   Renders supplied signed intervals without numerically inferring a sign.
(define-calculus-lesson render-sign-chart
  (model
    [f (function (x) x)]
    [negative (sign-claim f #:on (open -2 0) #:sign 'negative
                          #:justification "x is negative on the declared interval.")]
    [positive (sign-claim f #:on (open 0 2) #:sign 'positive
                          #:justification "x is positive on the declared interval.")]
    [chart (sign-chart negative positive)])
  (views [line (number-line-view #:range (closed -2 2) #:objects (chart))])
  (initially (show chart))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-chart (pause 1)))

;; render-point-component : calculus-component?
;;   Exercises the native bridge for a caller-visible lexical component export.
(define-calculus-component render-point-component
  (inputs [G : Graph] [a : Scalar])
  (model [P (point-on G #:x a)])
  (exports P))

;; render-component-export : calculus-lesson?
;;   The component owns the point construction, while the caller owns its view.
(define-calculus-lesson render-component-export
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [study (use-component render-point-component G 1)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -1 4)
                      #:objects (G (part study 'P)))])
  (initially (show G study))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-export (pause 1)))

;; render-r7-inverse-readout : calculus-component?
;; An exported readout begins hidden and undefined, so native preparation must
;; still reserve a component-local live field before its exact result appears.
(define-calculus-component render-r7-inverse-readout
  (inputs [x : Scalar])
  (model [r (value-readout (/ 1 x) #:label "r" #:format 'exact)])
  (exports r))

(define-calculus-lesson render-r7-component-readout
  (model [a (parameter 0 #:domain (closed 0 1))]
         [study (use-component render-r7-inverse-readout a)])
  (views [facts (formula-view #:objects ((part study 'r)))])
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step establish
    (set-parameter a (/ 1 (expt 10 200)))
    (show (part study 'r))))

;; R7 point-sort and reverse-reading rendering fixtures.  The graph is absent
;; from the reverse view so every observed marker must come from the Reading.
(define-calculus-lesson render-r7-feature-point
  (model [f (function (x) (+ (expt (- x 1) 2) 1))]
         [G (graph f)]
         [F (feature-point G #:at 1 #:kind 'global-minimum
              #:justification "(x-1)^2 is nonnegative, with equality at x=1.")])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2) #:objects (F))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show F)))

(define-calculus-lesson render-r7-frozen-point
  (model [a (parameter 0 #:domain (closed 0 2))]
         [P (point a a)]
         [S (snapshot-of P #:values ([a 1]))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2) #:objects (S))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show S)))

(define-calculus-lesson render-r7-reverse-reading
  (model [f (function (x) (* x x))]
         [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
              #:completeness 'all
              #:justification "x^2=1 exactly when x=-1 or x=1.")])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step read-backwards (read R)))

(define-calculus-lesson render-r7-invalid-reverse-reading
  (model [f (function (x) (* x x))]
         [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step read-backwards (read R)))

;; R8 preserves Point presentation through both public Reading-point snapshot
;; spellings, and through a named reverse-Reading branch intermediate.
(define-calculus-lesson render-r8-named-projection-snapshot
  (model [a (parameter 0 #:domain (closed 0 2))]
         [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G a)] [P (part R 'point)]
         [S (snapshot-of P #:values ([a 1]))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2) #:objects (S))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show S)))

(define-calculus-lesson render-r8-direct-projection-snapshot
  (model [a (parameter 0 #:domain (closed 0 2))]
         [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G a)]
         [S (snapshot-of (part R 'point) #:values ([a 1]))])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2) #:objects (S))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show S)))

(define-calculus-lesson render-r8-named-reverse-branch-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
              #:completeness 'all
              #:justification "x^2=1 exactly when x=-1 or x=1.")]
         [B (reading-branch R 0)] [Q (part B 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (Q))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show Q)))

;; These intentionally invalid constructions are demanded only by their
;; native views. They prove strict preparation cannot silently turn an invalid
;; Reading declaration into a blank successful picture.
(define-calculus-lesson render-r8-empty-reverse-reading
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R)))

(define-calculus-lesson render-r8-reverse-reading-without-evidence
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1) #:completeness 'all)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R)))

(define-calculus-lesson render-r8-colliding-reverse-branches
  (model [h (parameter 1 #:domain (closed 0 1))]
         [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G (* h h) #:inputs (list (- h) h)
              #:completeness 'all
              #:justification "The two distinct roots are -h and h for h>0.")])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step meet (vary h #:to 0 #:duration 1)))

;; R9 keeps inline selected branches typed through native preparation, paints
;; owned Reading parts independently, and resolves component exports without
;; flattening their lexical target into a public address.
(define-calculus-lesson render-r9-inline-reverse-branch
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects ((part (reading-branch R 1) 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 1) 'point))))

(define-calculus-lesson render-r9-input-guide-only
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))]
         [B (reading-branch R 1)] [U (part B 'input-guide)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (U))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show U)))

(define-calculus-lesson render-r9-hide-owned-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R #:duration 1))
  (step conceal (hide (part (reading-branch R 1) 'input-guide))))

(define-calculus-component render-r9-selected-roots-component
  (inputs [source-graph : Graph])
  (model [R (output-reading source-graph 1 #:inputs (list -1 1))])
  (exports R))

(define-calculus-lesson render-r9-exported-reverse-reading
  (model [f (function (x) (* x x))] [G (graph f)]
         [study (use-component render-r9-selected-roots-component G)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects ((part study 'R)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read (part study 'R))))

(define-calculus-lesson render-r9-reading-labels-on
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R)))

(define-calculus-lesson render-r9-reading-labels-off
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R)))

;; R10 exercises strict region geometry and the remaining Reading-part
;; composition paths: selected labels, inherited membership, per-part state,
;; owner label preferences, and projected Point auto-fit evidence.
(define-calculus-lesson render-r10-invalid-region-order
  (model [f (function (x) (+ x 1))] [G (graph f)]
         [A (region-under G #:from 1 #:to 0)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (A))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show A)))

(define-calculus-lesson render-r10-hidden-invalid-region
  (model [f (function (x) (+ x 1))] [G (graph f)]
         [A (region-under G #:from 1 #:to 0)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (A))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain (pause 1)))

(define-calculus-component render-r10-region-component
  (inputs [source : Graph])
  (model [A (region-under source #:from 0 #:to 1)])
  (exports A))

(define-calculus-lesson render-r10-exported-region
  (model [f (function (x) (+ x 1))] [G (graph f)]
         [study (use-component render-r10-region-component G)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects ((part study 'A)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part study 'A))))

(define-calculus-lesson render-r10-selected-input-label
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)]
         [L (part (reading-branch R 1) 'input-label)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R L))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step select (show L)))

(define-calculus-lesson render-r10-inline-input-label
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects (R (part (reading-branch R 1) 'input-label)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step retain (pause 1)))

(define-calculus-component render-r10-roots-component
  (inputs [source : Graph])
  (model [R (output-reading source 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (exports R))

(define-calculus-lesson render-r10-exported-output-label
  (model [f (function (x) (* x x))] [G (graph f)]
         [study (use-component render-r10-roots-component G)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects ((part study 'R)
                                      (part (part study 'R) 'output-label)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show (part study 'R)))
  (step retain (pause 1)))

(define-calculus-lesson render-r10-inherited-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 1) 'point))))

(define-calculus-lesson render-r10-inherited-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 1) 'input-guide))))

(define-calculus-lesson render-r10-owned-guide-state
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R))
  (step dim (deemphasize (part (reading-branch R 1) 'input-guide))))

(define-calculus-lesson render-r10-owner-label-preference
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (read R))
  (step suppress (hide-label R)))

(define-calculus-lesson render-r10-literal-auto-point
  (model [P (point 1 1)])
  (views [plot (graph-view #:x (closed -2 2) #:y 'auto #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show P)))

(define-calculus-lesson render-r10-forward-auto-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (input-reading G 1)] [P (part R 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y 'auto #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show P)))

(define-calculus-lesson render-r10-reverse-auto-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))]
         [P (part (reading-branch R 1) 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y 'auto #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show P)))

(define-calculus-lesson render-r10-inline-reverse-auto-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1))])
  (views [plot (graph-view #:x (closed -2 2) #:y 'auto
                           #:objects ((part (reading-branch R 1) 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 1) 'point))))

;; r11-half-opacity-points-profile : calculus-profile?
;;   Makes repeated marker painting observable without depending on a
;; platform-specific anti-aliased outline colour.
(define r11-half-opacity-points-profile
  (calculus-profile
   #:theme
   (calculus-theme #:base light-calculus-theme
                   #:rules (list (calculus-style #:kind 'point #:opacity 1/2)))))

;; R11 renders view-local label restoration, explicitly demanded reverse
;; Reading children whose geometry cannot be obtained, and root/child
;; membership combinations that must paint an owned marker only once.
(define-calculus-lesson render-r11-scoped-hide-show
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [left (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))]
         [right (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step masked (hide-label (in-view left R)) (pause 1))
  (step restored (show-label (in-view left R)) (pause 1)))

(define-calculus-lesson render-r11-scoped-show-hide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label 'numeric #:output-label 'numeric)])
  (views [left (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))]
         [right (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R) (hide-label R))
  (step unmasked (show-label (in-view left R)) (pause 1))
  (step remasked (hide-label (in-view left R)) (pause 1)))

(define-calculus-lesson render-r11-inherited-invalid-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 0) 'point))))

(define-calculus-lesson render-r11-inherited-invalid-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 0) 'input-guide))))

(define-calculus-lesson render-r11-inherited-invalid-index
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 7) 'point))))

(define-calculus-lesson render-r11-hidden-invalid-reading
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list 0)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain (pause 1)))

(define-calculus-lesson render-r11-reading-root
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show R)))

(define-calculus-lesson render-r11-reading-root-plus-point
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects (R (part (reading-branch R 1) 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show R)))

(define-calculus-lesson render-r11-reading-root-plus-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects (R (part (reading-branch R 1) 'input-guide)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show R)))

(define-calculus-lesson render-r11-reading-root-twice
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show R)))

;; R12 keeps strict selection validation separate from duplicate painting and
;; canonicalizes a named reverse-Reading Point before the root draws it.
(define-calculus-lesson render-r12-visible-root-missing-inline
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3)
                           #:objects (R (part (reading-branch R 7) 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R))
  (step retain (pause 1)))

(define-calculus-lesson render-r12-visible-root-missing-named
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [P (part (reading-branch R 7) 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R P))
  (step retain (pause 1)))

(define-calculus-lesson render-r12-missing-input-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [U (part (reading-branch R 7) 'input-guide)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (U))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show U) (pause 1)))

(define-calculus-lesson render-r12-missing-output-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [U (part (reading-branch R 7) 'output-guide)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (U))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show U) (pause 1)))

(define-calculus-lesson render-r12-inherited-missing-input-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part (reading-branch R 7) 'input-guide)) (pause 1)))

(define-calculus-lesson render-r12-valid-input-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [U (part (reading-branch R 1) 'input-guide)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (U))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show U) (pause 1)))

(define-calculus-lesson render-r12-valid-output-guide
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [U (part (reading-branch R 1) 'output-guide)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (U))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show U) (pause 1)))

(define-calculus-lesson render-r12-named-point-state
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [P (part (reading-branch R 1) 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R P))
  (step before (pause 1))
  (step dim (deemphasize P) (pause 1)))

(define-calculus-lesson render-r12-inline-point-state
  (model [f (function (x) (* x x))] [G (graph f)]
         [R (output-reading G 1 #:inputs (list -1 1)
                            #:input-label #f #:output-label #f)]
         [P (part (reading-branch R 1) 'point)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -1 3) #:objects (R P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show R P))
  (step before (pause 1))
  (step dim (deemphasize (part (reading-branch R 1) 'point)) (pause 1)))

;; render-private-chord-component : calculus-component?
;;   Keeps the chord private to callers while its own expanded explanation can
;;   present it in the compatible graph view of the exported secant geometry.
(define-calculus-component render-private-chord-component
  (inputs [G : Graph] [a : Scalar] [h : Scalar])
  (model
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)]
    [S (secant G P Q)])
  (exports P Q S)
  (constraints (not (= h 0)))
  (exposition
    (step points #:duration 1 (show P Q))
    (step chord #:duration 1 (show C))
    (step secant #:duration 1 (show S))))

;; render-private-component-exposition : calculus-lesson?
;;   The caller lists only public parts.  The intermediate chord is supplied
;;   by the component's namespaced expanded-presentation bridge.
(define-calculus-lesson render-private-component-exposition
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [study (use-component render-private-chord-component G 1 1)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'Q) (part study 'S)))])
  (initially (show G))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step explain-study (explain study #:mode 'expanded)))

;; render-deemphasized-chord-component : calculus-component?
;;   Leaves its one private graph construction visible only as a subdued
;; auxiliary after the expanded explanation settles.
(define-calculus-component render-deemphasized-chord-component
  (inputs [G : Graph] [a : Scalar] [h : Scalar])
  (model
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)])
  (exports P Q)
  (constraints (not (= h 0)))
  (exposition
    (step chord #:duration 1 (show C))))

;; render-deemphasized-private-component : calculus-lesson?
;;   The caller owns the only compatible graph view. `deemphasize` preserves
;; private construction visibility while changing its native presentation.
(define-calculus-lesson render-deemphasized-private-component
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [study (use-component render-deemphasized-chord-component G 1 1)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'Q)))])
  (initially (show G))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step explain-study
    (explain study #:mode 'expanded #:auxiliaries 'deemphasize)))

;; render-emphasis-state : calculus-lesson?
;;   Separates persistent deemphasis from a transient highlight and confirms
;; that normalize restores the persistent native presentation state.
(define-calculus-lesson render-emphasis-state
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 1)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -1 4)
                      #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step deemphasize-point (deemphasize P))
  (step callout-point (highlight P))
  (step normalize-point (normalize P)))

;; render-captioned-state : calculus-lesson?
;;   Leaves the graph unchanged so the bottom native caption band can be
;; checked independently of the lesson's mathematical drawing.
(define-calculus-lesson render-captioned-state
  (model
    [P (point 1 1)])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 2)
                      #:objects (P))])
  (initially (show P))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step describe-point #:say "Point P stays fixed." (pause 1)))

;; render-styled-point : calculus-lesson?
;;   A one-marker fixture for property-by-property native style cascading.
(define-calculus-lesson render-styled-point
  (model [P (point 1 1)])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (P))])
  (initially (show P))
  (step retain-point (pause 1)))

;; render-styled-line : calculus-lesson?
;;   One long semantic segment makes the output-pixel dash realization
;; independently inspectable without sampling a graph polyline.
(define-calculus-lesson render-styled-line
  (model
    [A (point 1/4 1)]
    [B (point 7/4 1)]
    [S (segment A B)])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (S))])
  (initially (show S))
  (step retain-line (pause 1)))

;; render-styled-label : calculus-lesson?
;;   Keeps a label and its point separately addressable while their native
;; placement remains anchored to the same semantic coordinate.
(define-calculus-lesson render-styled-label
  (model
    [P (point 1 1)]
    [L (point-label P "P")])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (P L))])
  (initially (show P L))
  (step retain-label (pause 1)))

;; render-colliding-labels : calculus-lesson?
;;   Two labels share one exact point anchor.  Native planning must retain
;; separate stable text placements and a leader for the displaced candidate.
(define-calculus-lesson render-colliding-labels
  (model
    [P (point 1 1)]
    [L1 (point-label P "P")]
    [L2 (point-label P "Q")])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (P L1 L2))])
  (initially (show P L1 L2))
  (step retain-labels (pause 1)))

;; render-parameter-graph-label : calculus-lesson?
;;   Keeps a graph-label anchor in the semantic parameter environment instead
;; of allowing a native renderer to interpret a held #:at expression.
(define-calculus-lesson render-parameter-graph-label
  (model
    [a (parameter 1 #:domain (closed 0 4))]
    [f (function (x) 0)]
    [G (graph f)]
    [L (graph-label G "f" #:at a)])
  (views [plot (graph-view #:x (closed 0 4)
                           #:y (closed -1 1)
                           #:objects (G L))])
  (initially (show G L))
  (step move-label (set-parameter a 3)))

;; render-hidden-anchor-label : calculus-lesson?
;;   A label's own preference may be visible while its hidden point anchor
;; keeps the native annotation effectively absent.
(define-calculus-lesson render-hidden-anchor-label
  (model
    [P (point 1 1)]
    [L (point-label P "P")])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (P L))])
  (initially (show L))
  (step retain-label (pause 1)))

;; render-equal-scale-point : calculus-lesson?
;;   A non-square world window exposes the graph-view letterbox map directly.
(define-calculus-lesson render-equal-scale-point
  (model [P (point 2 0)])
  (views [plot (graph-view #:x (closed 0 4)
                           #:y (closed 0 1)
                           #:scale 'equal
                           #:objects (P))])
  (initially (show P))
  (step retain-point (pause 1)))

;; render-auto-fit-square : calculus-lesson?
;;   A finite graph and attached point make a frozen vertical auto-fit window
;; directly inspectable without treating any infinite line as fit evidence.
(define-calculus-lesson render-auto-fit-square
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 1)])
  (views [plot (graph-view #:x (closed -2 2)
                           #:y 'auto
                           #:objects (G P))])
  (initially (show G P))
  (step retain-plot (pause 1)))

;; render-frozen-auto-fit : calculus-lesson?
;;   A changing graph family supplies extrema at distinct timeline positions;
;; preparation must reserve one shared vertical window for both snapshots.
(define-calculus-lesson render-frozen-auto-fit
  (model
    [a (parameter 1 #:domain (closed 1 3))]
    [f (function (x) (* a x))]
    [G (graph f)]
    [P (point-on G #:x 3/4)])
  (views [plot (graph-view #:x (closed 0 1)
                           #:y 'auto
                           #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step increase-slope (vary a #:to 3 #:duration 1)))

;; render-auto-fit-focus : calculus-lesson?
;; An auto-fit graph view still has a deterministic camera baseline when a
;; later focus and restore action interpolate its authored finite target.
(define-calculus-lesson render-auto-fit-focus
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 3/2)])
  (views [plot (graph-view #:x (closed -2 2)
                           #:y 'auto
                           #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step focus-plot
    (focus plot #:x (closed 1 2) #:y (closed 1 4) #:duration 1))
  (step restore-plot
    (restore-view plot #:duration 1)))

;; render-unfit-auto : calculus-lesson?
;;   An infinite vertical line offers no finite vertical fit evidence, so an
;; authored auto request must diagnose rather than inherit a made-up range.
(define-calculus-lesson render-unfit-auto
  (model [L (vertical-line 0)])
  (views [plot (graph-view #:x (closed -1 1)
                           #:y 'auto
                           #:objects (L))])
  (initially (show L))
  (step retain-line (pause 1)))

;; render-axis-markers : calculus-lesson?
;;   Combines a declared domain span, an included graph endpoint, and a
;; directional approach marker without providing any renderer-only flags.
(define-calculus-lesson render-axis-markers
  (model
    [D (closed -1 1)]
    [f (function (x) (* x x) #:domain (closed 0 2))]
    [G (graph f)]
    [I (interval-marker D #:axis 'x)]
    [E (endpoint-marker G #:at 0)]
    [A (approach-marker 1/2 #:axis 'x #:side 'left)])
  (views [plot (graph-view #:x (closed -2 2)
                           #:y (closed -1 3)
                           #:objects (G I E A))])
  (initially (show G I E A))
  (step retain-markers (pause 1)))

;; render-open-endpoint-marker : calculus-lesson?
;;   A transparent held body supplies the exact excluded-boundary value needed
;; for an open endpoint marker without sampling a native graph path.
(define-calculus-lesson render-open-endpoint-marker
  (model
    [f (function (x) (* x x) #:domain (open 0 2))]
    [G (graph f)]
    [E (endpoint-marker G #:at 0)])
  (views [plot (graph-view #:x (closed -1 3)
                           #:y (closed -1 4)
                           #:objects (G E))])
  (initially (show G E))
  (step retain-marker (pause 1)))

;; render-unresolved-endpoint-marker : calculus-lesson?
;;   A piecewise branch has no generic branch-limit proof in this core bridge,
;; so it stays unresolved rather than using whichever branch happens to match.
(define-calculus-lesson render-unresolved-endpoint-marker
  (model
    [f (piecewise-function (x)
         [(< x 1) x]
         [else (* x x)]
         #:domain (open 0 2))]
    [G (graph f)]
    [E (endpoint-marker G #:at 0)])
  (views [plot (graph-view #:x (closed -1 3)
                           #:y (closed -1 4)
                           #:objects (G E))])
  (initially (show G E))
  (step retain-marker (pause 1)))

;; render-hole-marker : calculus-lesson?
;;   A domain exclusion becomes two semantic spans with a hollow membership
;; marker at the excluded coordinate, not a gap guessed from raster samples.
(define-calculus-lesson render-hole-marker
  (model
    [D (domain-except (closed -2 2) 0)]
    [H (interval-marker D #:axis 'x)])
  (views [plot (graph-view #:x (closed -2 2)
                           #:y (closed -1 1)
                           #:objects (H))])
  (initially (show H))
  (step retain-marker (pause 1)))

;; render-graph-restriction : calculus-lesson?
;;   Keeps the restricted graph's source identity while narrowing its actual
;; mathematical domain for point attachment and native graph sampling.
(define-calculus-lesson render-graph-restriction
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (graph-restriction G (closed 0 1))]
    [P (point-on R #:x 1/2)]
    [Q (point-on R #:x -1/2)])
  (views [plot (graph-view #:x (closed -2 2)
                           #:y (closed -1 4)
                           #:objects (R P Q))])
  ;; Q is intentionally outside R's declared restriction. It remains a
  ;; headless partial object for inspection, but native strict output may only
  ;; draw the legal graph topology and the valid named point P.
  (initially (show R P))
  (step retain-restriction (pause 1)))

;; composite-marker-domains : calculus-model?
;;   Headless coverage for an intersection that retains one open and one closed
;; endpoint after declarative set algebra.
(define-calculus-model composite-marker-domains
  (model
    [D (domain-intersection (closed -2 2) (open 0 3))]
    [I (interval-marker D #:axis 'x)]))

;; render-formula-linkage : calculus-lesson?
;;   Exercises held ref/value Formula text and a live formatted readout.
(define-calculus-lesson render-formula-linkage
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 1)]
    [Q (point-on G #:x 2)]
    [change (increment P Q)]
    [m (slope (secant G P Q))]
    [equation (formula
               (= (ref m)
                  (/ (ref (part change 'dy))
                     (ref (part change 'dx)))))]
    [meter (value-readout m #:label "m" #:format 'decimal #:digits 2)])
  (views [facts (formula-view #:objects (equation meter))])
  (initially (show equation meter))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-formulas (pause 1)))

;; render-static-formula-row : calculus-lesson?
;; A symbolic formula shares a view with a changing graph point. Its notation
;; is eligible for preparation-time reuse because it has no `(value ...)` leaf.
(define-calculus-lesson render-static-formula-row
  (model
    [a (parameter -1 #:domain (closed -1 1))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x a)]
    [notation (formula (ref f))])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -1 5)
                      #:objects (G P))]
    [facts (formula-view #:objects (notation))])
  (initially (show G P notation))
  (step move-point (vary a #:to 1 #:duration 1)))

;; render-live-formula-value : calculus-lesson?
;; An explicit Formula value leaf must remain a current snapshot field rather
;; than being captured with the symbolic rows prepared above.
(define-calculus-lesson render-live-formula-value
  (model
    [a (parameter 1 #:domain (closed 1 2))]
    [equation (formula (= (ref a) (value a)))])
  (views [facts (formula-view #:objects (equation))])
  (initially (show equation))
  (step change-value (vary a #:to 2 #:duration 1)))

;; render-exact-interior-readout : calculus-lesson?
;; Exact 0→1 motion has the ordinary interior display `a 1/2`; its endpoint
;; strings are both shorter, so this guards against endpoint-only reservation.
(define-calculus-lesson render-exact-interior-readout
  (model [a (parameter 0 #:domain (closed 0 1))]
         [reading (value-readout a #:label "a" #:format 'exact)])
  (views [facts (formula-view #:objects (reading))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show reading))
  (step move (vary a #:to 1 #:easing 'linear #:duration 1)))

;; render-reading-point-projection : calculus-lesson?
;; A selected public point is already the Reading's demanded geometry; strict
;; validation must not append a second `point` projection to its address.
(define-calculus-lesson render-reading-point-projection
  (model [f (function (x) (* x x))]
         [G (graph f)]
         [R (input-reading G 1)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2)
                           #:objects ((part R 'point)))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show (part R 'point))))

;; render-named-reading-point-projection : calculus-lesson?
;; A named public alias to a Reading's point receives the same point marker
;; dispatch as the literal projection in the preceding lesson.
(define-calculus-lesson render-named-reading-point-projection
  (model [f (function (x) (* x x))]
         [G (graph f)]
         [R (input-reading G 1)]
         [P (part R 'point)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2)
                           #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show P)))

;; render-point-on-line : calculus-lesson?
;; Every documented Point constructor receives the same native marker dispatch
;; as literal, graph-derived, and Reading-projection points.
(define-calculus-lesson render-point-on-line
  (model [L (horizontal-line 1)]
         [P (point-on-line L #:x 1)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2)
                           #:objects (P))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show P)))

;; render-positioned-live-fields : calculus-lesson?
;; Exercises the real backend's prepared field probes in numerator,
;; denominator, exponent, radical, and nested positions at an interior state.
(define-calculus-lesson render-positioned-live-fields
  (model [a (parameter 2 #:domain (closed 2 3))]
         [numerator (formula (/ (value a) 7))]
         [denominator (formula (/ 1 (value a)))]
         [exponent (formula (expt 2 (value a)))]
         [radical (formula (sqrt (value a)))]
         [nested (formula (/ (expt 2 (value a)) (+ 1 (value a))))])
  (views [facts (formula-view #:objects (numerator denominator exponent radical nested))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show numerator denominator exponent radical nested))
  (step move (vary a #:to 3 #:easing 'linear #:duration 1)))

;; render-too-many-live-fields : calculus-lesson?
;; A field color/probe namespace is an explicit preparation capability, never
;; permission to paint an unmeasured thirteenth value at the formula origin.
(define-calculus-lesson render-too-many-live-fields
  (model [a (parameter 1 #:domain (closed 1 2))]
         [E (formula (+ (value a) (value (+ a 1)) (value (+ a 2))
                        (value (+ a 3)) (value (+ a 4)) (value (+ a 5))
                        (value (+ a 6)) (value (+ a 7)) (value (+ a 8))
                        (value (+ a 9)) (value (+ a 10)) (value (+ a 11))
                        (value (+ a 12))))])
  (views [facts (formula-view #:objects (E))])
  (initially (show E))
  (step retain (pause 1)))

;; render-wide-exact-readout : calculus-lesson?
;; An arbitrarily wide exact result must receive a layout diagnostic, not draw
;; through the formula panel's outer margin.
(define-calculus-lesson render-wide-exact-readout
  (model [a (parameter 1 #:domain (closed 1 (expt 10 100)))]
         [r (value-readout a #:label "a" #:format 'exact)])
  (views [facts (formula-view #:objects (r))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show r))
  (step move (vary a #:to (expt 10 100) #:easing 'linear #:duration 1)))

;; render-hidden-wide-exact-readout : calculus-lesson?
;; The initially undefined value is hidden, but its later defined exact form
;; still participates in preparation-time field bounds and overflow checks.
(define-calculus-lesson render-hidden-wide-exact-readout
  (model [a (parameter 0 #:domain (closed 0 1))]
         [r (value-readout (/ 1 a) #:label "r" #:format 'exact)])
  (views [facts (formula-view #:objects (r))])
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step establish
    (set-parameter a (/ 1 (expt 10 200)))
    (show r)))

;; render-hidden-small-exact-readout : calculus-lesson?
;; The companion small final value establishes that becoming defined before
;; showing a readout remains a supported native rendering path.
(define-calculus-lesson render-hidden-small-exact-readout
  (model [a (parameter 0 #:domain (closed 0 1))]
         [r (value-readout (/ 1 a) #:label "r" #:format 'exact)])
  (views [facts (formula-view #:objects (r))])
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step establish (set-parameter a 1/2) (show r)))

;; render-invalid-composite-reading : calculus-lesson?
;; A reading root is a descriptor, but its demanded point is undefined at the
;; graph's declared hole. Strict native preparation must traverse that part.
(define-calculus-lesson render-invalid-composite-reading
  (model
    [f (function (x) (/ 1 x) #:domain (domain-except real-line 0))]
    [G (graph f)]
    [R (input-reading G 0)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -3 3) #:objects (G R))])
  (initially (show G R))
  (step retain (pause 1)))

;; render-hidden-composite-reading : calculus-lesson?
;; The same partial reading is legal when hidden; the graph's visible topology
;; still contains its ordinary mathematical gap.
(define-calculus-lesson render-hidden-composite-reading
  (model
    [f (function (x) (/ 1 x) #:domain (domain-except real-line 0))]
    [G (graph f)]
    [R (input-reading G 0)])
  (views [plot (graph-view #:x (closed -2 2) #:y (closed -3 3) #:objects (G R))])
  (initially (show G))
  (step retain (pause 1)))

;; render-readout-error-policy : calculus-lesson?
;; Default and explicit error policies are output-blocking; label is the one
;; author-controlled way to display a nondefined result.
(define-calculus-lesson render-readout-error-policy
  (model
    [default-error (value-readout (/ 1 0) #:label "d")]
    [explicit-error (value-readout (/ 1 0) #:label "e" #:undefined 'error)]
    [explicit-label (value-readout (/ 1 0) #:label "l" #:undefined 'label)])
  (views [facts (formula-view #:objects (default-error explicit-error explicit-label))])
  (initially (show default-error explicit-error explicit-label))
  (step retain (pause 1)))

;; render-readout-label-policy : calculus-lesson?
(define-calculus-lesson render-readout-label-policy
  (model [labelled (value-readout (/ 1 0) #:label "l" #:undefined 'label)])
  (views [facts (formula-view #:objects (labelled))])
  (initially (show labelled))
  (step retain (pause 1)))

;; render-newton-diagram : calculus-lesson?
;;   Draws finite graph-to-tangent-to-axis construction steps from exact iterates.
(define-calculus-lesson render-newton-diagram
  (model
    [f (function (x) (- (* x x) 2))]
    [df (derivative-function f #:method 'symbolic)]
    [G (graph f)]
    [iteration (newton-iteration f #:derivative df #:start 1 #:steps 3)]
    [k (parameter 2 #:domain (integers 0 3) #:kind 'integer)]
    [diagram (newton-diagram iteration #:through k)])
  (views [plot (graph-view #:x (closed 1/2 2)
                           #:y (closed -3/2 2)
                           #:objects (G diagram))])
  (initially (show G diagram))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-diagram (pause 1)))

;; render-stacked-number-lines : calculus-lesson?
;;   Verifies the profile layout controls panel planning without changing values.
(define-calculus-lesson render-stacked-number-lines
  (model [a (parameter 1 #:domain (closed 0 2))])
  (views [upper (number-line-view #:range (closed 0 2) #:objects (a))]
         [lower (number-line-view #:range (closed 0 2) #:objects (a))])
  (initially (show a))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-value (pause 1)))

;; render-vertical-asymptote : calculus-lesson?
;;   A supplied claim certifies the vertical guide before native drawing.
(define-calculus-lesson render-vertical-asymptote
  (model
    [u (parameter 1 #:domain (open 0 2))]
    [f (function (x) (/ 1 x))]
    [G (graph f)]
    [claim (limit-statement (value-at f u)
                            #:parameter u #:to 0 #:value +inf.0
                            #:justification "The reciprocal grows without bound near zero.")]
    [line (vertical-line 0)]
    [asymptote (asymptote-line G #:line line #:limit-claim claim)])
  (views [plot (graph-view #:x (closed -1 1)
                           #:y (closed -2 2)
                           #:objects (G asymptote))])
  (initially (show G asymptote))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-asymptote (pause 1)))

;; render-coordinate-reading : calculus-lesson?
;;   Shares native guide construction with input readings through point parts.
(define-calculus-lesson render-coordinate-reading
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 1)]
    [reading (coordinate-reading P #:labels 'both)])
  (views [plot (graph-view #:x (closed 0 2)
                           #:y (closed 0 2)
                           #:objects (G reading))])
  (initially (show G reading))
  (timing [opening-pause 1] [read-delay 0] [action-duration 1] [step-pause 0])
  (step retain-reading (pause 1)))

;; bitmap-rgb : bitmap% exact-nonnegative-integer? exact-nonnegative-integer? -> bytes?
;;   Reads one rendered pixel without depending on an image-file encoder.
(define (bitmap-rgb bitmap x y)
  (define bytes (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 bytes)
  (subbytes bytes 1 4))

;; bitmap-region-has-rgb? : bitmap% natural? natural? natural? natural? bytes? -> boolean?
;;   Locates a native stroke without making a test depend on one rasterization
;;   pixel at an anti-aliased endpoint.
(define (bitmap-region-has-rgb? bitmap x-min x-max y-min y-max expected)
  (for*/or ([x (in-range x-min (add1 x-max))]
            [y (in-range y-min (add1 y-max))])
    (equal? (bitmap-rgb bitmap x y) expected)))

;; bitmap-region-has-non-rgb? : bitmap% natural? natural? natural? natural? bytes? -> boolean?
;;   Detects a rendered stroke while permitting anti-aliasing around its edge.
(define (bitmap-region-has-non-rgb? bitmap x-min x-max y-min y-max unexpected)
  (for*/or ([x (in-range x-min (add1 x-max))]
            [y (in-range y-min (add1 y-max))])
    (not (equal? (bitmap-rgb bitmap x y) unexpected))))

;; bitmap-regions-differ? : bitmap% bitmap% natural? natural? natural? natural? -> boolean?
;;   Detects a semantic drawing change in one stable rectangular native region.
(define (bitmap-regions-differ? first second x-min x-max y-min y-max)
  (for*/or ([x (in-range x-min (add1 x-max))]
            [y (in-range y-min (add1 y-max))])
    (not (equal? (bitmap-rgb first x y) (bitmap-rgb second x y)))))

;; pict->opaque-bitmap : pict? exact-positive-integer? exact-positive-integer? -> bitmap%
;;   Composites a native pict onto an opaque test surface before reading pixels.
(define (pict->opaque-bitmap picture width height)
  (define bitmap (make-bitmap width height))
  (define context (new bitmap-dc% [bitmap bitmap]))
  (send context set-pen (new pen% [color "white"] [style 'transparent]))
  (send context set-brush (new brush% [color "white"] [style 'solid]))
  (send context draw-rectangle 0 0 width height)
  (pict:draw-pict picture context 0 0)
  (send context set-bitmap #f)
  bitmap)

;; bitmap-argb-bytes : bitmap% exact-positive-integer? exact-positive-integer? -> bytes?
;;   Captures one compact in-memory raster for parity checks without writing
;; frame files or review bundles.
(define (bitmap-argb-bytes bitmap width height)
  (define bytes (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height bytes)
  bytes)


;;;
;;; Tests
;;;

;; run-calculus-render-smoke-tests : -> void?
;;   Checks native preparation dimensions and terminal scene/Pict agreement.
(define (run-calculus-render-smoke-tests)
  (define prepared
    (prepare-calculus-lesson render-reading-square #:width 480 #:height 270))
  (check-true (prepared-calculus-lesson? prepared))
  (define picture (prepared-lesson->pict prepared #:at 'final))
  (check-true (pict:pict? picture))
  (check-equal? (pict:pict-width picture) 480)
  (check-equal? (pict:pict-height picture) 270)
  ;; Strict native validation evaluates a reading's required point rather than
  ;; accepting its descriptor root. The same unused partial construction stays
  ;; legal when it is hidden beside a graph with an ordinary discontinuity.
  (check-exn exn:fail?
             (lambda ()
               (prepared-lesson->pict
                (prepare-calculus-lesson render-invalid-composite-reading
                                          #:width 480 #:height 270)
                #:at 'initial)))
  (check-true
   (pict:pict?
    (prepared-lesson->pict
     (prepare-calculus-lesson render-hidden-composite-reading #:width 480 #:height 270)
     #:at 'initial)))
  ;; Omitted and explicit error policies must block native output; only the
  ;; author-selected label policy produces an explicit undefined readout.
  (check-exn exn:fail?
             (lambda ()
               (prepared-lesson->pict
                (prepare-calculus-lesson render-readout-error-policy
                                          #:width 480 #:height 270)
                #:at 'initial)))
  (define labelled-readout-prepared
    (prepare-calculus-lesson render-readout-label-policy #:width 480 #:height 270))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-formula-text
     (calculus-plan-sample (prepared-lesson-plan labelled-readout-prepared) #:at 'initial)
     'labelled))
   "l undefined")
  (check-true (pict:pict? (prepared-lesson->pict labelled-readout-prepared #:at 'initial)))
  ;; R3 native boundaries: an ordinary exact interior value must render, and
  ;; a selected Reading point must validate as that point rather than R.point.
  (define exact-readout-prepared
    (prepare-calculus-lesson render-exact-interior-readout #:width 480 #:height 270))
  (for ([time (in-list (list 'initial 1/2 'final))])
    (check-true
     (pict:pict?
      (prepared-lesson->pict exact-readout-prepared #:at time))))
  (define selected-reading-prepared
    (prepare-calculus-lesson render-reading-point-projection #:width 480 #:height 270))
  (define selected-reading-snapshot
    (calculus-plan-sample (prepared-lesson-plan selected-reading-prepared) #:at 'initial))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref selected-reading-snapshot '(R point)))
                (cons 1 1))
  (define selected-reading-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict selected-reading-prepared #:at 'initial) 480 270))
  (define selected-reading-final
    (pict->opaque-bitmap
     (prepared-lesson->pict selected-reading-prepared #:at 'final) 480 270))
  ;; R4: the public `(part R 'point)` is dispatched as a point before the
  ;; Reading root, so its marker changes ink at its mathematical coordinate.
  (check-true (bitmap-regions-differ? selected-reading-initial selected-reading-final
                                      230 250 125 145))
  ;; R5: model naming must not erase the type-directed point projection.
  (define named-reading-prepared
    (prepare-calculus-lesson render-named-reading-point-projection
                             #:width 480 #:height 270))
  (define named-reading-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict named-reading-prepared #:at 'initial) 480 270))
  (define named-reading-final
    (pict->opaque-bitmap
     (prepared-lesson->pict named-reading-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? named-reading-initial named-reading-final
                                      230 250 125 145))
  ;; R6: point-on-line is evaluated as a Point and must paint the same marker
  ;; ink instead of falling through the graph panel's no-op branch.
  (define point-on-line-prepared
    (prepare-calculus-lesson render-point-on-line #:width 480 #:height 270))
  (define point-on-line-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict point-on-line-prepared #:at 'initial) 480 270))
  (define point-on-line-final
    (pict->opaque-bitmap
     (prepared-lesson->pict point-on-line-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? point-on-line-initial point-on-line-final
                                      230 250 125 145))
  ;; R7: an exported Readout whose initial value is partial still owns a
  ;; prepared live field.  The later 201-digit exact result therefore reaches
  ;; the same explicit overflow policy as a direct Readout instead of being
  ;; silently drawn through the unconstrained Formula fallback.
  (define r7-component-readout-prepared
    (prepare-calculus-lesson render-r7-component-readout #:width 480 #:height 270))
  (define r7-component-readout-initial
    (calculus-plan-sample (prepared-lesson-plan r7-component-readout-prepared) #:at 'initial))
  (check-false (calculus-snapshot-visible? r7-component-readout-initial '(study r)))
  (check-not-equal?
   (calculus-result-status
    (calculus-snapshot-formula-text r7-component-readout-initial '(study r)))
   'defined)
  (check-exn #rx"field|layout|fit|minimum"
             (lambda ()
               (prepared-lesson->pict r7-component-readout-prepared #:at 'final)))
  ;; Feature points and point snapshots are ordinary native Point consumers.
  ;; The initial symbolic phase has no marker; final marker ink is observed at
  ;; their exact world coordinate (1,1), not on a sampled graph segment.
  (define r7-feature-prepared
    (prepare-calculus-lesson render-r7-feature-point #:width 480 #:height 270))
  (define r7-feature-initial
    (pict->opaque-bitmap (prepared-lesson->pict r7-feature-prepared #:at 'initial) 480 270))
  (define r7-feature-final
    (pict->opaque-bitmap (prepared-lesson->pict r7-feature-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r7-feature-initial r7-feature-final 230 250 125 145))
  (define r7-frozen-prepared
    (prepare-calculus-lesson render-r7-frozen-point #:width 480 #:height 270))
  (define r7-frozen-initial
    (pict->opaque-bitmap (prepared-lesson->pict r7-frozen-prepared #:at 'initial) 480 270))
  (define r7-frozen-final
    (pict->opaque-bitmap (prepared-lesson->pict r7-frozen-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r7-frozen-initial r7-frozen-final 230 250 125 145))
  ;; Reverse readings paint every explicitly declared candidate in source
  ;; order. Invalid candidates are demanded native values, so a blank picture
  ;; is never accepted as a successful reverse construction.
  (define r7-reverse-prepared
    (prepare-calculus-lesson render-r7-reverse-reading #:width 480 #:height 270))
  (define r7-reverse-initial
    (pict->opaque-bitmap (prepared-lesson->pict r7-reverse-prepared #:at 'initial) 480 270))
  (define r7-reverse-final
    (pict->opaque-bitmap (prepared-lesson->pict r7-reverse-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r7-reverse-initial r7-reverse-final 126 146 125 145))
  (check-true (bitmap-regions-differ? r7-reverse-initial r7-reverse-final 334 354 125 145))
  ;; R8: reverse Reading's settled construction has explicit horizontal
  ;; output and vertical input guides, not just the two point markers. At an
  ;; early guided frame only the output stage has begun, preserving the
  ;; documented output -> graph -> input choreography.
  (check-true (bitmap-regions-differ? r7-reverse-initial r7-reverse-final
                                      282 302 125 145))
  (check-true (bitmap-regions-differ? r7-reverse-initial r7-reverse-final
                                      334 354 151 171))
  (define r7-reverse-early
    (pict->opaque-bitmap (prepared-lesson->pict r7-reverse-prepared #:at 1/6) 480 270))
  (check-true (bitmap-regions-differ? r7-reverse-initial r7-reverse-early
                                      282 302 125 145))
  (check-false (bitmap-regions-differ? r7-reverse-initial r7-reverse-early
                                       334 354 151 171))
  (check-exn exn:fail?
             (lambda ()
               (prepared-lesson->pict
                (prepare-calculus-lesson render-r7-invalid-reverse-reading
                                          #:width 480 #:height 270)
                #:at 'final)))
  ;; R8: a public Reading Point retains its native marker sort through both
  ;; frozen wrappers, and a named reverse-branch Point remains a Point rather
  ;; than falling through the generic `part` renderer case.
  (for ([lesson (in-list (list render-r8-named-projection-snapshot
                               render-r8-direct-projection-snapshot))])
    (define prepared (prepare-calculus-lesson lesson #:width 480 #:height 270))
    (define initial
      (pict->opaque-bitmap (prepared-lesson->pict prepared #:at 'initial) 480 270))
    (define final
      (pict->opaque-bitmap (prepared-lesson->pict prepared #:at 'final) 480 270))
    (check-true (bitmap-regions-differ? initial final 230 250 125 145)))
  (define r8-branch-prepared
    (prepare-calculus-lesson render-r8-named-reverse-branch-point #:width 480 #:height 270))
  (define r8-branch-initial
    (pict->opaque-bitmap (prepared-lesson->pict r8-branch-prepared #:at 'initial) 480 270))
  (define r8-branch-final
    (pict->opaque-bitmap (prepared-lesson->pict r8-branch-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r8-branch-initial r8-branch-final 126 146 125 145))
  ;; Every declaration failure becomes a native-output error when its Reading
  ;; is visible, rather than an empty-but-successful graph panel.
  (for ([lesson (in-list (list render-r8-empty-reverse-reading
                               render-r8-reverse-reading-without-evidence
                               render-r8-colliding-reverse-branches))])
    (check-exn #rx"reading|candidate|empty|completeness|justification|collid"
               (lambda ()
                 (prepared-lesson->pict
                  (prepare-calculus-lesson lesson #:width 480 #:height 270)
                  #:at 'final))))
  ;; R9: native presentation preserves typed inline branch selectors, paints
  ;; a named owned guide without its siblings, and lets an explicit child hide
  ;; remove only that guide—not the selected point marker.
  (define r9-inline-prepared
    (prepare-calculus-lesson render-r9-inline-reverse-branch #:width 480 #:height 270))
  (define r9-inline-initial
    (pict->opaque-bitmap (prepared-lesson->pict r9-inline-prepared #:at 'initial) 480 270))
  (define r9-inline-final
    (pict->opaque-bitmap (prepared-lesson->pict r9-inline-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r9-inline-initial r9-inline-final 334 354 125 145))
  (define r9-guide-prepared
    (prepare-calculus-lesson render-r9-input-guide-only #:width 480 #:height 270))
  (define r9-guide-initial
    (pict->opaque-bitmap (prepared-lesson->pict r9-guide-prepared #:at 'initial) 480 270))
  (define r9-guide-final
    (pict->opaque-bitmap (prepared-lesson->pict r9-guide-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r9-guide-initial r9-guide-final 334 354 151 171))
  (define r9-hide-prepared
    (prepare-calculus-lesson render-r9-hide-owned-guide #:width 480 #:height 270))
  (define r9-hide-before
    (pict->opaque-bitmap
     (prepared-lesson->pict r9-hide-prepared #:at (calculus-step-end 'reveal)) 480 270))
  (define r9-hide-after
    (pict->opaque-bitmap (prepared-lesson->pict r9-hide-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r9-hide-before r9-hide-after 334 354 151 171))
  (check-false (bitmap-regions-differ? r9-hide-before r9-hide-after 334 354 125 145))
  ;; Component exports bridge their Reading geometry through the component
  ;; model, while the caller remains responsible for the visible export.
  (define r9-exported-prepared
    (prepare-calculus-lesson render-r9-exported-reverse-reading #:width 480 #:height 270))
  (define r9-exported-initial
    (pict->opaque-bitmap (prepared-lesson->pict r9-exported-prepared #:at 'initial) 480 270))
  (define r9-exported-final
    (pict->opaque-bitmap (prepared-lesson->pict r9-exported-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r9-exported-initial r9-exported-final 126 146 125 145))
  (check-true (bitmap-regions-differ? r9-exported-initial r9-exported-final 334 354 125 145))
  ;; Numeric Reading labels are real native glyphs; #f disables those owned
  ;; labels without changing the underlying points and guides.
  (define r9-labels-on
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-r9-reading-labels-on #:width 480 #:height 270)
      #:at 'final)
     480 270))
  (define r9-labels-off
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-r9-reading-labels-off #:width 480 #:height 270)
      #:at 'final)
     480 270))
  (check-false (bytes=? (bitmap-argb-bytes r9-labels-on 480 270)
                        (bitmap-argb-bytes r9-labels-off 480 270)))
  ;; R10: a visible geometric region must demand sampled geometry rather than
  ;; accepting only its descriptor. Hidden partial geometry remains legal, and
  ;; a component export retains its lexical model while it is sampled.
  (check-exn #rx"region|bound|increasing|mathematical"
             (lambda ()
               (prepared-lesson->pict
                (prepare-calculus-lesson render-r10-invalid-region-order #:width 480 #:height 270)
                #:at 'final)))
  (check-not-exn
   (lambda ()
     (prepared-lesson->pict
      (prepare-calculus-lesson render-r10-hidden-invalid-region #:width 480 #:height 270)
      #:at 'final)))
  (define r10-exported-region-prepared
    (prepare-calculus-lesson render-r10-exported-region #:width 480 #:height 270))
  (define r10-exported-region-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict r10-exported-region-prepared #:at 'initial) 480 270))
  (define r10-exported-region-final
    (pict->opaque-bitmap
     (prepared-lesson->pict r10-exported-region-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r10-exported-region-initial r10-exported-region-final
                                      282 302 151 171))
  ;; Selected input labels and an exported output label retain their distinct
  ;; owners during strict validation and native painting.
  (for ([lesson (in-list (list render-r10-selected-input-label
                               render-r10-inline-input-label
                               render-r10-exported-output-label))])
    (check-not-exn
     (lambda ()
       (pict->opaque-bitmap
        (prepared-lesson->pict
         (prepare-calculus-lesson lesson #:width 480 #:height 270)
         #:at 'final)
        480 270))))
  ;; A Reading child may inherit its declared view membership without its root
  ;; being shown. It paints exactly that child, not the whole root composite.
  (for ([lesson (in-list (list render-r10-inherited-point render-r10-inherited-guide))]
        [region (in-list (list (list 334 354 125 145) (list 334 354 151 171)))])
    (define prepared (prepare-calculus-lesson lesson #:width 480 #:height 270))
    (define initial (pict->opaque-bitmap (prepared-lesson->pict prepared #:at 'initial) 480 270))
    (define final (pict->opaque-bitmap (prepared-lesson->pict prepared #:at 'final) 480 270))
    (check-true (bitmap-regions-differ? initial final (first region) (second region)
                                       (third region) (fourth region))))
  ;; Root composition re-enters the selected guide's state/style context:
  ;; deemphasizing that guide changes it while leaving the marker untouched.
  (define r10-guide-state-prepared
    (prepare-calculus-lesson render-r10-owned-guide-state #:width 480 #:height 270))
  (define r10-guide-state-before
    (pict->opaque-bitmap
     (prepared-lesson->pict r10-guide-state-prepared #:at (calculus-step-end 'reveal)) 480 270))
  (define r10-guide-state-after
    (pict->opaque-bitmap (prepared-lesson->pict r10-guide-state-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r10-guide-state-before r10-guide-state-after 334 354 151 171))
  (check-false (bitmap-regions-differ? r10-guide-state-before r10-guide-state-after 338 350 129 141))
  ;; An owner-level label preference masks generated Reading labels but not
  ;; their graph point or guide geometry.
  (define r10-label-prepared
    (prepare-calculus-lesson render-r10-owner-label-preference #:width 480 #:height 270))
  (define r10-label-before
    (pict->opaque-bitmap
     (prepared-lesson->pict r10-label-prepared #:at (calculus-step-end 'reveal)) 480 270))
  (define r10-label-after
    (pict->opaque-bitmap (prepared-lesson->pict r10-label-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? r10-label-before r10-label-after 347 383 188 218))
  (check-false (bitmap-regions-differ? r10-label-before r10-label-after 338 350 129 141))
  ;; Equivalent direct and selected Point semantics use the same finite auto
  ;; evidence, so their isolated final rasters are identical.
  (define r10-literal-auto-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-r10-literal-auto-point #:width 480 #:height 270)
      #:at 'final)
     480 270))
  (for ([lesson (in-list (list render-r10-forward-auto-point
                               render-r10-reverse-auto-point
                               render-r10-inline-reverse-auto-point))])
    (define actual
      (pict->opaque-bitmap
       (prepared-lesson->pict
        (prepare-calculus-lesson lesson #:width 480 #:height 270)
        #:at 'final)
       480 270))
    (check-true (bytes=? (bitmap-argb-bytes r10-literal-auto-bitmap 480 270)
                         (bitmap-argb-bytes actual 480 270))))
  ;; R11: a view-local label setting has priority within its own view but must
  ;; fall back to—and restore—the common owner preference after a later
  ;; opposite operation.
  (define (r11-raster lesson [profile default-calculus-profile] [at 'final])
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson lesson #:profile profile #:width 480 #:height 270)
      #:at at)
     480 270))
  (define (r11-pixels bitmap x y width height)
    (define data (make-bytes (* 4 width height)))
    (send bitmap get-argb-pixels x y width height data)
    data)
  (define (check-r11-label-cycle lesson middle)
    (define initial (r11-raster lesson default-calculus-profile 'initial))
    (define changed (r11-raster lesson default-calculus-profile middle))
    (define final (r11-raster lesson))
    (check-false (bytes=? (bitmap-argb-bytes initial 480 270)
                          (bitmap-argb-bytes changed 480 270)))
    (check-true (bytes=? (bitmap-argb-bytes initial 480 270)
                         (bitmap-argb-bytes final 480 270))))
  (check-r11-label-cycle render-r11-scoped-hide-show (calculus-step-end 'masked))
  (check-r11-label-cycle render-r11-scoped-show-hide (calculus-step-end 'unmasked))
  ;; A visible inherited Reading child is output demand even when resolving
  ;; its parent geometry fails. Conversely, a hidden invalid root is not a
  ;; demand and remains legal.
  (for ([lesson (in-list (list render-r11-inherited-invalid-point
                               render-r11-inherited-invalid-guide
                               render-r11-inherited-invalid-index))])
    (check-exn #rx"mathematical|candidate|branch|outside|reading|Reading"
               (lambda () (r11-raster lesson))))
  (check-not-exn (lambda () (r11-raster render-r11-hidden-invalid-reading)))
  ;; A Reading root already owns its generated Point and guide. Declaring the
  ;; same object again in its view must not darken a translucent marker or
  ;; redraw either of the pre-existing owned children.
  (define r11-root-bitmap
    (r11-raster render-r11-reading-root r11-half-opacity-points-profile))
  (define r11-root-plus-point-bitmap
    (r11-raster render-r11-reading-root-plus-point r11-half-opacity-points-profile))
  (for ([x (in-list '(134 342))])
    (check-true (bytes=? (r11-pixels r11-root-bitmap x 133 4 4)
                         (r11-pixels r11-root-plus-point-bitmap x 133 4 4))))
  (for ([lesson (in-list (list render-r11-reading-root-twice
                               render-r11-reading-root-plus-guide))])
    (define actual (r11-raster lesson r11-half-opacity-points-profile))
    (check-true (bytes=? (bitmap-argb-bytes r11-root-bitmap 480 270)
                         (bitmap-argb-bytes actual 480 270))))
  ;; R12: validation visits every visible requested selector before paint
  ;; suppression. A valid Reading cannot stand in for an out-of-range Point or
  ;; guide, while valid selected guides retain their independent draw paths.
  (for ([lesson (in-list (list render-r12-visible-root-missing-inline
                               render-r12-visible-root-missing-named
                               render-r12-missing-input-guide
                               render-r12-missing-output-guide
                               render-r12-inherited-missing-input-guide))])
    (check-exn #rx"mathematical|candidate|branch|outside|reading|Reading"
               (lambda () (r11-raster lesson))))
  (for ([lesson (in-list (list render-r12-valid-input-guide
                               render-r12-valid-output-guide))]
        [region (in-list (list (list 334 354 151 171)
                               (list 272 292 125 145)))])
    (define initial (r11-raster lesson default-calculus-profile 'initial))
    (define final (r11-raster lesson))
    (check-true (bitmap-regions-differ? initial final
                                        (first region) (second region)
                                        (third region) (fourth region))))
  ;; A named Point and its inline spelling resolve to the same canonical
  ;; state before the visible Reading paints its single owned marker.
  (define r12-named-before
    (r11-raster render-r12-named-point-state default-calculus-profile
                (calculus-step-end 'before)))
  (define r12-named-after (r11-raster render-r12-named-point-state))
  (define r12-inline-before
    (r11-raster render-r12-inline-point-state default-calculus-profile
                (calculus-step-end 'before)))
  (define r12-inline-after (r11-raster render-r12-inline-point-state))
  (for ([pair (in-list (list (cons r12-named-before r12-named-after)
                             (cons r12-inline-before r12-inline-after)))])
    (check-true (bitmap-regions-differ? (car pair) (cdr pair) 338 350 129 141))
    (check-false (bitmap-regions-differ? (car pair) (cdr pair) 130 142 129 141)))
  (check-true (bytes=? (r11-pixels r12-named-after 338 129 12 12)
                       (r11-pixels r12-inline-after 338 129 12 12)))
  ;; A real mathematical backend, rather than the opaque call-count double,
  ;; supplies the prepared field geometry used by these nested live formulas.
  (define positioned-fields-prepared
    (prepare-calculus-lesson render-positioned-live-fields #:width 960 #:height 540))
  ;; The transparent prepared value exposes no public renderer API, but its
  ;; immutable layout record lets this native regression assert that the real
  ;; backend supplied occurrence rectangles rather than falling back to a
  ;; flattened slash/caret cursor.  Field four is the geometry map in the
  ;; internal prepared row record.
  (define positioned-layouts (vector-ref (struct->vector positioned-fields-prepared) 9))
  (for ([target (in-list '(numerator denominator exponent radical nested))])
    (define positioned-layout (hash-ref positioned-layouts (list 'facts target)))
    (define normal-geometries
      (hash-ref (vector-ref (struct->vector positioned-layout) 4) 'normal))
    (check-true (and (list? normal-geometries) (pair? normal-geometries))))
  ;; A field in an exponent has a genuinely script-sized prepared reservation,
  ;; rather than reusing the display-style rectangle of a top-level numerator.
  (define numerator-geometry
    (car (hash-ref (vector-ref (struct->vector
                                (hash-ref positioned-layouts '(facts numerator))) 4)
                   'normal)))
  (define exponent-geometry
    (car (hash-ref (vector-ref (struct->vector
                                (hash-ref positioned-layouts '(facts exponent))) 4)
                   'normal)))
  (check-true (< (vector-ref (struct->vector exponent-geometry) 3)
                 (vector-ref (struct->vector numerator-geometry) 3)))
  (for ([time (in-list (list 'initial 1/2 'final))])
    (check-true
     (pict:pict?
      (prepared-lesson->pict positioned-fields-prepared #:at time))))
  ;; Exercise the shared native preparation path at the two standard review
  ;; sizes. These are real in-memory rasters, not dimension-only Pict checks
  ;; and not image/video artifacts retained in the workspace.
  (for ([dimensions (in-list (list (cons 1280 720) (cons 1920 1080)))])
    (define width (car dimensions))
    (define height (cdr dimensions))
    (define raster
      (pict->opaque-bitmap
       (prepared-lesson->pict
        (prepare-calculus-lesson render-reading-square #:width width #:height height)
        #:at 'final)
       width height))
  (check-equal? (bitmap-rgb raster 0 0) #"\xFF\xFF\xFF"))
  ;; Fade paints the complete semantic graph/line at changing opacity, while
  ;; trace/extend paints changing extents. Interior samples must therefore
  ;; differ both from completion and from each other.
  (define fade-reveal-prepared
    (prepare-calculus-lesson
     render-reveal-policies
     #:profile (calculus-profile
                #:motion (calculus-motion #:graph-reveal 'fade #:line-reveal 'fade)
                #:timing (calculus-timing #:opening-pause 0 #:read-delay 0
                                          #:action-duration 1 #:step-pause 0))
     #:width 480 #:height 270))
  (define trace-reveal-prepared
    (prepare-calculus-lesson render-reveal-policies #:width 480 #:height 270))
  (define fade-quarter
    (pict->opaque-bitmap (prepared-lesson->pict fade-reveal-prepared #:at 1/4) 480 270))
  (define fade-final
    (pict->opaque-bitmap (prepared-lesson->pict fade-reveal-prepared #:at 'final) 480 270))
  (define trace-quarter
    (pict->opaque-bitmap (prepared-lesson->pict trace-reveal-prepared #:at 1/4) 480 270))
  (check-true (bitmap-regions-differ? fade-quarter fade-final 32 448 32 238))
  (check-true (bitmap-regions-differ? fade-quarter trace-quarter 32 448 32 238))
  ;; Static graph sampling is owned by preparation. Moving the unrelated
  ;; point must not call the opaque graph provider once the prepared cache has
  ;; been constructed; this also keeps the result independent of frame order.
  (set! static-graph-provider-calls 0)
  (define cached-graph-prepared
    (prepare-calculus-lesson render-static-graph-cache #:width 480 #:height 270))
  (define calls-after-preparation static-graph-provider-calls)
  (check-true (positive? calls-after-preparation))
  (void
   (pict->opaque-bitmap
    (prepared-lesson->pict cached-graph-prepared #:at 'final) 480 270))
  (check-equal? static-graph-provider-calls calls-after-preparation)
  (void
   (pict->opaque-bitmap
    (prepared-lesson->pict cached-graph-prepared #:at 'initial) 480 270))
  (check-equal? static-graph-provider-calls calls-after-preparation)
  ;; Render quality controls adaptive graph geometry rather than merely being
  ;; accepted as an inert configuration record. A tighter chord tolerance
  ;; requires more static provider samples, while both are fixed at preparation
  ;; and therefore remain frame-order independent.
  (set! static-graph-provider-calls 0)
  (void
   (prepare-calculus-lesson
    render-static-graph-cache #:width 480 #:height 270
    #:quality (calculus-render-quality #:curve-tolerance 128 #:max-depth 1)))
  (define coarse-quality-calls static-graph-provider-calls)
  (set! static-graph-provider-calls 0)
  (void
   (prepare-calculus-lesson
    render-static-graph-cache #:width 480 #:height 270
    #:quality (calculus-render-quality #:curve-tolerance 1/32 #:max-depth 4)))
  (check-true (> static-graph-provider-calls coarse-quality-calls))
  ;; A writable function-family parameter invalidates its graph geometry.
  ;; The byte comparison is intentionally confined to one prepared object and
  ;; one backend, where it distinguishes the two mathematical graph states.
  (define dynamic-graph-prepared
    (prepare-calculus-lesson render-dynamic-graph-cache #:width 480 #:height 270))
  (define dynamic-graph-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict dynamic-graph-prepared #:at 'initial) 480 270))
  (define dynamic-graph-final
    (pict->opaque-bitmap
     (prepared-lesson->pict dynamic-graph-prepared #:at 'final) 480 270))
  (check-false
   (bytes=? (bitmap-argb-bytes dynamic-graph-initial 480 270)
            (bitmap-argb-bytes dynamic-graph-final 480 270)))
  ;; Formula preparation is similarly dependency-sensitive. The symbolic row
  ;; remains pixel-identical while only its neighboring graph point moves;
  ;; an explicit Formula `(value ...)` leaf still updates at the new state.
  (define static-formula-prepared
    (prepare-calculus-lesson render-static-formula-row #:width 480 #:height 270))
  (define static-formula-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict static-formula-prepared #:at 'initial) 480 270))
  (define static-formula-final
    (pict->opaque-bitmap
     (prepared-lesson->pict static-formula-prepared #:at 'final) 480 270))
  (check-false (bitmap-regions-differ? static-formula-initial static-formula-final
                                       32 235 32 238))
  (define live-formula-prepared
    (prepare-calculus-lesson render-live-formula-value #:width 480 #:height 270))
  (define live-formula-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict live-formula-prepared #:at 'initial) 480 270))
  (define live-formula-final
    (pict->opaque-bitmap
     (prepared-lesson->pict live-formula-prepared #:at 'final) 480 270))
  (check-true (bitmap-regions-differ? live-formula-initial live-formula-final
                                      32 448 32 100))
  ;; A backend that cannot expose probe geometry is now rejected during
  ;; preparation.  It must not silently fall back to a shared row origin.
  (set! dynamic-formula-backend-calls 0)
  (define opaque-formula-outcome
    (with-handlers ([exn:fail? values])
      (prepare-calculus-lesson render-live-formula-value
                               #:formula-backend (counting-formula-renderer)
                               #:width 480 #:height 270)))
  (check-true (exn:fail? opaque-formula-outcome))
  (check-true (regexp-match? #rx"field|geometry|layout"
                             (exn-message opaque-formula-outcome)))
  (check-true (> dynamic-formula-backend-calls 0))
  ;; R4: probe identifiers are generated per occurrence; the thirteenth
  ;; field gets its own prepared rectangle instead of an arbitrary rejection
  ;; or a shared-origin fallback.
  (define many-fields-prepared
    (prepare-calculus-lesson render-too-many-live-fields #:width 480 #:height 270))
  (define many-fields-layout
    (hash-ref (vector-ref (struct->vector many-fields-prepared) 9) '(facts E)))
  (define many-fields-geometries
    (hash-ref (vector-ref (struct->vector many-fields-layout) 4) 'normal))
  (check-equal? (length many-fields-geometries) 13)
  (check-equal? (length (remove-duplicates many-fields-geometries)) 13)
  ;; Exact readouts do not smear long values through their owning panel's
  ;; margin.  A readable-layout diagnostic is the deliberate policy here.
  (define wide-readout-prepared
    (prepare-calculus-lesson render-wide-exact-readout #:width 480 #:height 270))
  (check-exn #rx"field|layout|overflow|reservation"
             (lambda () (prepared-lesson->pict wide-readout-prepared #:at 'final)))
  ;; R5: an initially hidden, undefined readout still has to reserve its
  ;; later exact value.  The oversized variant fails visibly and the small
  ;; companion variant renders normally.
  (define hidden-wide-readout-prepared
    (prepare-calculus-lesson render-hidden-wide-exact-readout
                             #:width 480 #:height 270))
  (define hidden-wide-readout-initial
    (calculus-plan-sample (prepared-lesson-plan hidden-wide-readout-prepared)
                          #:at 'initial))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref hidden-wide-readout-initial 'a))
                0)
  (check-false (calculus-snapshot-visible? hidden-wide-readout-initial 'r))
  (check-not-equal?
   (calculus-result-status
    (calculus-snapshot-formula-text hidden-wide-readout-initial 'r))
   'defined)
  (define hidden-wide-readout-snapshot
    (calculus-plan-sample (prepared-lesson-plan hidden-wide-readout-prepared)
                          #:at 'final))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-formula-text hidden-wide-readout-snapshot 'r))
   (string-append "r " (number->string (expt 10 200))))
  (check-exn #rx"field|layout|fit|minimum"
             (lambda ()
               (pict->opaque-bitmap
                (prepared-lesson->pict hidden-wide-readout-prepared #:at 'final)
                480 270)))
  (define hidden-small-readout-prepared
    (prepare-calculus-lesson render-hidden-small-exact-readout
                             #:width 480 #:height 270))
  (define hidden-small-readout-snapshot
    (calculus-plan-sample (prepared-lesson-plan hidden-small-readout-prepared)
                          #:at 'final))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-formula-text hidden-small-readout-snapshot 'r))
   "r 2")
  (check-not-exn
   (lambda ()
     (pict->opaque-bitmap
      (prepared-lesson->pict hidden-small-readout-prepared #:at 'final)
      480 270)))
  ;; The six complete Guide modules are not merely headless declarations.
  ;; Exercise their final native preparations as standard 1280×720 in-memory
  ;; rasters, keeping this test free of persisted image or video artifacts.
  (for ([guide-lesson
         (in-list (list guide-reading-square
                        guide-secant-to-tangent
                        guide-build-derivative
                        guide-limit-not-value
                        guide-sums-and-accumulation
                        guide-component-example))])
    (define guide-picture
      (prepared-lesson->pict
       (prepare-calculus-lesson guide-lesson #:width 1280 #:height 720)
       #:at 'final))
    (check-equal? (pict:pict-width guide-picture) 1280)
    (check-equal? (pict:pict-height guide-picture) 720)
    (define guide-raster (pict->opaque-bitmap guide-picture 1280 720))
    (check-equal? (bitmap-rgb guide-raster 0 0) #"\xFF\xFF\xFF"))
  ;; Preparation is immutable: asking for the terminal state before an earlier
  ;; state cannot make the repeated terminal raster depend on frame history.
  (define final-first-bitmap (pict->opaque-bitmap picture 480 270))
  (void (prepared-lesson->pict prepared #:at 'initial))
  (define final-repeated-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict prepared #:at 'final) 480 270))
  (check-equal? (bitmap-argb-bytes final-first-bitmap 480 270)
                (bitmap-argb-bytes final-repeated-bitmap 480 270))
  (define dark-profile-picture
    (prepared-lesson->pict
     (prepare-calculus-lesson render-reading-square
                              #:profile classroom-dark-profile #:width 480 #:height 270)
     #:at 'final))
  (define dark-profile-bitmap (pict->opaque-bitmap dark-profile-picture 480 270))
  ;; Standard dark profiles use their documented canvas and neutral-panel
  ;; colors without changing the lesson's semantic geometry or timing.
  (check-equal? (bitmap-rgb dark-profile-bitmap 0 0) #"\x17\x1A\x21")
  (check-equal? (bitmap-rgb dark-profile-bitmap 40 40) #"\x24\x2A\x35")
  ;; A theme that supplies only new rules inherits the base palette rather
  ;; than falling back to the unrelated light defaults.
  (define inherited-dark-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-reading-square
       #:profile
       (calculus-profile
        #:theme (calculus-theme #:base dark-calculus-theme
                                #:rules (list (calculus-style #:kind 'point
                                                              #:marker-radius (calculus-px 5)))))
       #:width 480 #:height 270)
      #:at 'final)
     480 270))
  (check-equal? (bitmap-rgb inherited-dark-bitmap 0 0) #"\x17\x1A\x21")
  (define styled-profile
    (calculus-profile
     #:theme
     (calculus-theme
      #:base light-calculus-theme
      #:rules
      (list (calculus-style #:kind 'point #:fill "#2166C2" #:marker-radius (calculus-px 5))
            (calculus-style #:target 'P #:fill "#0B6E4F" #:marker-radius (calculus-px 7))))))
  (define styled-point-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-styled-point
                               #:profile styled-profile #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; A target selector outranks a kind selector for each independently resolved
  ;; property, yielding the green seven-pixel marker rather than the blue
  ;; five-pixel fallback.
  (check-equal? (bitmap-rgb styled-point-bitmap 240 135) #"\x0B\x6E\x4F")
  (check-equal? (bitmap-rgb styled-point-bitmap 246 135) #"\x0B\x6E\x4F")
  (define relative-marker-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-styled-point
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules (list (calculus-style #:target 'P #:fill "#0B6E4F"
                                        #:marker-radius (calculus-rel 1/20)))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Relative cosmetic lengths use min(480,270)=270, not this plot panel's
  ;; shorter height. The 13.5-pixel marker reaches x=252 from its center.
  (check-equal? (bitmap-rgb relative-marker-bitmap 252 135) #"\x0B\x6E\x4F")
  (define translucent-point-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-styled-point
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules (list (calculus-style #:target 'P #:fill "#0B6E4F"
                                        #:opacity 1/2))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Opacity is a separate property from fill: the marker is visible, but it
  ;; is composited over the panel instead of retaining the opaque green bytes.
  (check-not-equal? (bitmap-rgb translucent-point-bitmap 240 135) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb translucent-point-bitmap 240 135) #"\x0B\x6E\x4F")
  (define styled-axis-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-styled-point
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules
         (list (calculus-style #:kind 'axis #:view 'plot #:stroke "#0B6E4F"
                               #:stroke-width (calculus-px 2)))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Axes are view-owned presentation objects: a view/kind selector changes
  ;; their paint without creating a mathematical zero-axis model object.
  (check-equal? (bitmap-rgb styled-axis-bitmap 32 90) #"\x0B\x6E\x4F")
  (define equal-scale-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-equal-scale-point #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The 4:1 mathematical window is letterboxed into a 4:1 plot inside the
  ;; wider panel. P=(2,0) therefore lands at y=187, not the panel's y=238.
  (check-equal? (bitmap-rgb equal-scale-bitmap 240 187) #"\xB3\x26\x1E")
  (check-not-equal? (bitmap-rgb equal-scale-bitmap 240 238) #"\xB3\x26\x1E")
  (define auto-fit-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-auto-fit-square #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Auto fitting is prepared once from finite graph/point evidence. P=(1,1)
  ;; therefore sits in the lower portion of the fitted [about -0.2,4.2] window,
  ;; not in the unrelated legacy -5..5 fallback range.
  (check-true (bitmap-region-has-rgb? auto-fit-bitmap 338 350 174 190 #"\xB3\x26\x1E"))
  (define frozen-auto-prepared
    (prepare-calculus-lesson render-frozen-auto-fit #:width 480 #:height 270))
  (define frozen-auto-initial-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict frozen-auto-prepared #:at 'initial)
     480 270))
  (define frozen-auto-final-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict frozen-auto-prepared #:at 'final)
     480 270))
  ;; P rises from (3/4,3/4) to (3/4,9/4), but both positions use the one
  ;; preparation-time y window fitted over the complete parameter motion.
  (check-true (bitmap-region-has-rgb? frozen-auto-initial-bitmap 338 350 175 189 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? frozen-auto-final-bitmap 338 350 81 95 #"\xB3\x26\x1E"))
  (define auto-focus-prepared
    (prepare-calculus-lesson render-auto-fit-focus #:width 480 #:height 270))
  (define auto-focus-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict auto-focus-prepared #:at 1)
     480 270))
  (define auto-restore-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict auto-focus-prepared #:at 'final)
     480 270))
  ;; P=(3/2,9/4) reaches the center of the authored focus x-window at the
  ;; first terminal boundary, then returns to its frozen auto-fit placement.
  ;; This is a real camera transition, not an inert action on an auto view.
  (check-true (bitmap-region-has-rgb? auto-focus-bitmap 232 248 144 160 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? auto-restore-bitmap 390 402 115 130 #"\xB3\x26\x1E"))
  (check-exn #px"cannot determine a finite #:y 'auto fit"
             (lambda ()
               (prepare-calculus-lesson render-unfit-auto #:width 480 #:height 270)))
  (define marker-plan
    (prepared-lesson-plan
     (prepare-calculus-lesson render-axis-markers #:width 480 #:height 270)))
  (define marker-snapshot (calculus-plan-sample marker-plan #:at 'initial))
  ;; Domain inclusion and graph-boundary validity arrive from the core bridge;
  ;; the renderer never gets an arbitrary open/closed styling decision.
  (check-equal?
   (calculus-result-value (calculus-snapshot-marker-geometry marker-snapshot 'I))
   (list 'interval-marker 'x (list (list 'span -1 1 #t #t))))
  (check-equal?
   (calculus-result-value (calculus-snapshot-marker-geometry marker-snapshot 'E))
   (list 'endpoint-marker 0 0 #t))
  (check-equal?
   (calculus-result-value (calculus-snapshot-marker-geometry marker-snapshot 'A))
   (list 'approach-marker 'x 'left 1/2))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-marker-geometry
     (calculus-plan-sample
      (prepared-lesson-plan
       (prepare-calculus-lesson render-open-endpoint-marker #:width 480 #:height 270))
      #:at 'initial)
     'E))
   (list 'endpoint-marker 0 0 #f))
  (check-equal?
   (calculus-result-status
    (calculus-snapshot-marker-geometry
     (calculus-plan-sample
      (prepared-lesson-plan
       (prepare-calculus-lesson render-unresolved-endpoint-marker #:width 480 #:height 270))
      #:at 'initial)
     'E))
   'unresolved)
  (define hole-plan
    (prepared-lesson-plan
     (prepare-calculus-lesson render-hole-marker #:width 480 #:height 270)))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-marker-geometry
     (calculus-plan-sample hole-plan #:at 'initial) 'H))
   (list 'interval-marker 'x
         (list (list 'span -2 0 #t #f)
               (list 'span 0 2 #f #t))))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-marker-geometry
     (calculus-model-at composite-marker-domains) 'I))
   (list 'interval-marker 'x (list (list 'span 0 2 #f #t))))
  (define restricted-plan
    (prepared-lesson-plan
     (prepare-calculus-lesson render-graph-restriction #:width 480 #:height 270)))
  (define restricted-snapshot (calculus-plan-sample restricted-plan #:at 'initial))
  (check-equal? (calculus-result-value (calculus-snapshot-ref restricted-snapshot 'P))
                (cons 1/2 1/4))
  (check-equal? (calculus-result-status (calculus-snapshot-ref restricted-snapshot 'Q))
                'outside-domain)
  (define open-endpoint-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
     (prepare-calculus-lesson render-open-endpoint-marker #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-true (bitmap-region-has-rgb? open-endpoint-bitmap 130 142 190 203 #"\x6A\x1B\x9A"))
  (define hole-marker-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-hole-marker #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-true (bitmap-region-has-rgb? hole-marker-bitmap 236 244 126 143 #"\x6A\x1B\x9A"))
  (define restricted-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-graph-restriction #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The source parabola is shown only on x∈[0,1]; an ordinary panel location
  ;; on its omitted negative branch remains untouched.
  (check-equal? (bitmap-rgb restricted-bitmap 136 156) #"\xFA\xFA\xFA")
  (check-true (bitmap-region-has-rgb? restricted-bitmap 312 324 169 179 #"\x21\x66\xC2"))
  (define marker-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-axis-markers #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-true (bitmap-region-has-rgb? marker-bitmap 145 170 184 190 #"\x6A\x1B\x9A"))
  (check-true (bitmap-region-has-rgb? marker-bitmap 286 300 180 190 #"\x6A\x1B\x9A"))
  (define styled-line-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-styled-line
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules
         (list (calculus-style #:kind 'segment #:stroke "#2166C2")
               (calculus-style #:target 'S #:stroke "#0B6E4F"
                               #:stroke-width (calculus-px 2)
                               #:dash '(16 16)))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The target rule independently resolves both stroke and dash above the
  ;; less-specific kind stroke; the gap exposes panel background rather than
  ;; turning the semantic segment into several smaller mathematical objects.
  (check-equal? (bitmap-rgb styled-line-bitmap 92 135) #"\x0B\x6E\x4F")
  (check-equal? (bitmap-rgb styled-line-bitmap 108 135) #"\xFA\xFA\xFA")
  (define styled-guide-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-reading-square
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules
         (list (calculus-style #:target 'R #:stroke "#0B6E4F"
                               #:stroke-width (calculus-px 2) #:dash 'solid))))
       #:width 480 #:height 270)
      #:at 'final)
     480 270))
  ;; A reading remains the same snapshot-owned point and pair of guides; a
  ;; guide rule changes only their native paint realization.
  (check-true (bitmap-region-has-rgb? styled-guide-bitmap 70 78 110 130 #"\x0B\x6E\x4F"))
  (define styled-label-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-styled-label
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules
         (list (calculus-style #:target 'L #:fill "#0B6E4F"
                               #:font-size (calculus-px 16)
                               #:label-gap (calculus-px 12)))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Label paint and offset are target-addressable, while the anchor remains
  ;; the exact point P=(1,1) rather than a pixel-derived placement surrogate.
  (define default-label-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-styled-label #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-label-text
     (calculus-plan-sample
      (prepared-lesson-plan
       (prepare-calculus-lesson render-styled-label #:width 480 #:height 270))
      #:at 'initial)
     'L))
   "P")
  (define colliding-labels-prepared
    (prepare-calculus-lesson
     render-colliding-labels
     #:profile
     (calculus-profile
      #:theme
      (calculus-theme
       #:base light-calculus-theme
       #:rules
       (list (calculus-style #:target 'L1 #:fill "#0B6E4F")
             (calculus-style #:target 'L2 #:fill "#B3261E"))))
     #:width 480 #:height 270))
  (define colliding-labels-first
    (pict->opaque-bitmap
     (prepared-lesson->pict colliding-labels-prepared #:at 'initial) 480 270))
  ;; The sorted L1/L2 placement plan reserves the conventional northeast slot
  ;; for L1 and moves L2 to a separate northwest slot with a leader.  Sampling
  ;; the same semantic moment after another request cannot change either slot.
  ;; Thin glyph strokes can be antialiased, so the first check observes the
  ;; occupied northeast text region rather than requiring one exact RGB pixel.
  (check-true (bitmap-region-has-non-rgb? colliding-labels-first
                                            242 266 104 128 #"\xFA\xFA\xFA"))
  (check-true (bitmap-region-has-rgb? colliding-labels-first 210 240 104 128 #"\xB3\x26\x1E"))
  (void (prepared-lesson->pict colliding-labels-prepared #:at 'final))
  (define colliding-labels-repeated
    (pict->opaque-bitmap
     (prepared-lesson->pict colliding-labels-prepared #:at 'initial) 480 270))
  (check-equal? (bitmap-argb-bytes colliding-labels-first 480 270)
                (bitmap-argb-bytes colliding-labels-repeated 480 270))
  (define parameter-label-plan
    (prepared-lesson-plan
     (prepare-calculus-lesson render-parameter-graph-label #:width 480 #:height 270)))
  ;; The declared #:at parameter is evaluated by the pure snapshot bridge and
  ;; follows the timeline; native label placement receives only these points.
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-label-anchor
     (calculus-plan-sample parameter-label-plan #:at 'initial) 'L))
   (cons 1 0))
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-label-anchor
     (calculus-plan-sample parameter-label-plan #:at 'final) 'L))
   (cons 3 0))
  (check-true (bitmap-regions-differ? default-label-bitmap styled-label-bitmap
                                      248 282 100 128))
  (define hidden-anchor-label-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-hidden-anchor-label #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Showing the label cannot resurrect or annotate an anchor that presentation
  ;; keeps hidden; this region has neither the point nor its label glyph.
  (check-false (bitmap-region-has-non-rgb? hidden-anchor-label-bitmap
                                           248 282 100 128 #"\xFA\xFA\xFA"))
  (define scene (prepared-lesson->scene prepared))
  (check-true (native:scene? scene))
  (check-equal? (native:scene-duration scene)
                (calculus-plan-duration (prepared-lesson-plan prepared)))
  (define scene-picture (native:scene->pict scene (native:scene-duration scene)))
  (check-equal? (pict:pict-width scene-picture) 480)
  (check-equal? (pict:pict-height scene-picture) 270)
  ;; A terminal scene uses the same prepared snapshot/panel composition as a
  ;; terminal pict; this compares the actual native raster rather than only
  ;; their outer dimensions.
  (check-equal?
   (bitmap-argb-bytes (pict->opaque-bitmap picture 480 270) 480 270)
   (bitmap-argb-bytes (pict->opaque-bitmap scene-picture 480 270) 480 270))
  ;; Arbitrary-time scene sampling must use the same semantic moment as a
  ;; prepared still. In particular, this off-grid 60-fps sample is neither a
  ;; cached t=0 picture nor a 30-fps held interpolation.
  (define continuity-prepared
    (prepare-calculus-lesson render-scene-continuity #:width 480 #:height 270))
  (define continuity-scene (prepared-lesson->scene continuity-prepared))
  (define off-grid-time 1/60)
  (define continuity-still
    (pict->opaque-bitmap
     (prepared-lesson->pict continuity-prepared #:at off-grid-time) 480 270))
  (define continuity-scene-bitmap
    (pict->opaque-bitmap
     (native:scene->pict continuity-scene off-grid-time) 480 270))
  (define continuity-initial
    (pict->opaque-bitmap
     (prepared-lesson->pict continuity-prepared #:at 'initial) 480 270))
  (check-equal?
   (bitmap-argb-bytes continuity-still 480 270)
   (bitmap-argb-bytes continuity-scene-bitmap 480 270))
  (check-not-equal?
   (bitmap-argb-bytes continuity-initial 480 270)
   (bitmap-argb-bytes continuity-scene-bitmap 480 270))
  ;; A named visible construction at a graph hole is demanded output. It must
  ;; fail conversion with its address instead of disappearing, while the same
  ;; hidden declaration leaves the legal graph topology renderable.
  (define demanded-invalid-prepared
    (prepare-calculus-lesson render-demanded-invalid-point #:width 480 #:height 270))
  (check-exn exn:fail:contract?
             (lambda () (prepared-lesson->pict demanded-invalid-prepared #:at 'initial)))
  (check-true
   (pict:pict?
    (prepared-lesson->pict
     (prepare-calculus-lesson render-hidden-invalid-point #:width 480 #:height 270)
     #:at 'initial)))
  ;; One-call outputs are shallow conveniences over the exact same prepared
  ;; path; they accept preparation keywords but no separate movie policy.
  (define one-call-picture (lesson->pict render-reading-square #:width 480 #:height 270))
  (check-true (pict:pict? one-call-picture))
  (check-equal? (pict:pict-width one-call-picture) 480)
  (check-true (native:visual? (lesson->visual render-reading-square #:width 480 #:height 270)))
  (check-true (native:scene? (lesson->scene render-reading-square #:width 480 #:height 270)))
  (define topology-picture
    (prepared-lesson->pict
     (prepare-calculus-lesson render-special-value #:width 480 #:height 270)
     #:at 'final))
  (define topology-bitmap (pict->opaque-bitmap topology-picture 480 270))
  ;; The special branch owns (0,4); the else branch contributes the open
  ;; endpoint (0,1).  The centers verify the semantic markers, not a sampled
  ;; approximation just to one side of x=0.
  (check-not-equal? (bitmap-rgb topology-bitmap 240 73) #"\xFA\xFA\xFA")
  (check-equal? (bitmap-rgb topology-bitmap 240 197) #"\xFA\xFA\xFA")
  (define provider-break-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-provider-break #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; x=y would otherwise pass directly through (1/2,1/2). The declared opaque
  ;; provider break splits both incident strokes instead of painting continuity.
  (check-equal? (bitmap-rgb provider-break-bitmap 345 83) #"\xFA\xFA\xFA")
  (define trace-prepared
    (prepare-calculus-lesson render-trace-square #:width 480 #:height 270))
  (define trace-midpoint-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict trace-prepared #:at 1) 480 270))
  (define trace-final-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict trace-prepared #:at 'final) 480 270))
  ;; The point (3/2,9/4) lies beyond the mid-trace prefix but on the completed
  ;; locus. Its pixel proves native output respects semantic prefix state.
  (check-equal? (bitmap-rgb trace-midpoint-bitmap 344 122) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb trace-final-bitmap 344 122) #"\xFA\xFA\xFA")
  (define focus-prepared
    (prepare-calculus-lesson render-focus-square #:width 480 #:height 270))
  (define focus-initial-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict focus-prepared #:at 'initial) 480 270))
  (define focus-final-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict focus-prepared #:at 'final) 480 270))
  ;; P remains the mathematical point (3/2,9/4), while the focused window
  ;; changes its rendered position without mutating the model.
  (check-equal? (bitmap-rgb focus-initial-bitmap 344 122) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb focus-final-bitmap 344 122) #"\xFA\xFA\xFA")
  (define line-prepared
    (prepare-calculus-lesson render-secant-tangent #:width 480 #:height 270))
  (define line-initial
    (calculus-plan-sample (prepared-lesson-plan line-prepared) #:at 'initial))
  (check-true (calculus-snapshot-visible? line-initial 'S))
  (check-false (calculus-snapshot-visible? line-initial 'T))
  (define secant-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict line-prepared #:at 'initial) 480 270))
  (define tangent-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict line-prepared #:at 'final) 480 270))
  (define crossfade-midpoint-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict line-prepared #:at 3/2) 480 270))
  (define rotating-midpoint-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-secant-tangent
       #:profile
       (calculus-profile
        #:motion (calculus-motion #:limit-transition 'rotate-carrier))
       #:width 480 #:height 270)
      #:at 3/2)
     480 270))
  ;; The finite secant is clipped to the graph window in purple.  At the
  ;; transition endpoint it is replaced—not overpainted—by the red tangent.
  ;; This small interior region avoids the curve, axes, and line intersection.
  (check-true (bitmap-region-has-rgb? secant-bitmap 201 209 208 216 #"\x6A\x1B\x9A"))
  (check-false (bitmap-region-has-rgb? secant-bitmap 201 209 208 216 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? tangent-bitmap 201 209 197 205 #"\xB3\x26\x1E"))
  ;; Crossfade retains both endpoint lines at intermediate opacity, whereas
  ;; rotate-carrier draws one exact anchored intermediate slope. Their sampled
  ;; rasters must therefore differ before the common settled tangent endpoint.
  (check-true (bitmap-regions-differ? crossfade-midpoint-bitmap rotating-midpoint-bitmap
                                      150 330 100 220))
  (define triangle-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-slope-triangle #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The horizontal and vertical parts share the semantic corner (2,1), so
  ;; their native strokes retain the directed increment rather than a pixel
  ;; angle approximation.
  (check-true (bitmap-region-has-rgb? triangle-bitmap 236 244 182 190 #"\xA6\x5E\x00"))
  (check-true (bitmap-region-has-rgb? triangle-bitmap 305 313 127 135 #"\xA6\x5E\x00"))
  (check-true (bitmap-region-has-rgb? triangle-bitmap 236 244 131 139 #"\x5F\x63\x68"))
  (define band-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-epsilon-delta-bands #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; At x=1 with δ=1/2, the input boundaries are x=1/2 and x=3/2;
  ;; at L=2 with ε=1/2, the output boundaries are y=3/2 and y=5/2.
  (check-true (bitmap-region-has-rgb? band-bitmap 132 140 96 104 #"\xA6\x5E\x00"))
  (check-true (bitmap-region-has-rgb? band-bitmap 32 40 156 164 #"\x6A\x1B\x9A"))
  (define rectangles-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-riemann-rectangles #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The first midpoint cell is [0,1/2] with height 1/16. Its pale fill is a
  ;; semantic finite contribution, not a polygon inferred from the curve.
  (check-true (bitmap-region-has-rgb? rectangles-bitmap 80 88 231 236 #"\xD9\xE8\xFF"))
  (define styled-rectangles-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-riemann-rectangles
       #:profile
       (calculus-profile
        #:theme (calculus-theme #:base light-calculus-theme
                                #:rules (list (calculus-style #:target 'rectangles
                                                              #:fill "#0B6E4F"))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The fill changes after exact signed cells are prepared; it does not alter
  ;; their partition, tag, height, or sign classification.
  (check-true (bitmap-region-has-rgb? styled-rectangles-bitmap 80 88 231 236 #"\x0B\x6E\x4F"))
  (define refinement-carrier-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-refinement-carrier #:width 480 #:height 270)
      #:at 1/2)
     480 270))
  ;; At the midpoint the semantic count remains 2, while the orange line at
  ;; x=1/2 is the prepared four-cell subdivision carrier. It is not a third
  ;; noninteger mathematical partition or a screen-derived redraw.
  (check-true (bitmap-region-has-rgb? refinement-carrier-bitmap 130 142 198 222 #"\xA6\x5E\x00"))
  (define trapezoids-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-trapezoidal-regions #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; y=x crosses the x-axis inside its one trapezoid. The renderer splits the
  ;; exact affine cell at zero, leaving its negative and positive pieces distinct.
  (check-true (bitmap-region-has-rgb? trapezoids-bitmap 132 140 156 164 #"\xFF\xE3\xE3"))
  (check-true (bitmap-region-has-rgb? trapezoids-bitmap 340 348 105 113 #"\xD9\xE8\xFF"))
  (define cropped-trapezoid-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-cropped-trapezoid #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; At x=1/2, y=1/4 remains inside the clipped affine cell while y=3/4 is
  ;; outside. This detects true edge/window intersections rather than merely
  ;; checking that an offscreen source vertex was clamped into the panel.
  (check-true (bitmap-region-has-rgb? cropped-trapezoid-bitmap 234 246 204 216 #"\xD9\xE8\xFF"))
  (check-false (bitmap-region-has-rgb? cropped-trapezoid-bitmap 234 246 152 164 #"\xD9\xE8\xFF"))
  (define marks-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-partition-marks #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The endpoint 1/2 maps to the second exact uniform-partition tick.
  (check-true (bitmap-region-has-rgb? marks-bitmap 132 140 232 240 #"\x5F\x63\x68"))
  (define under-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-region-under #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-true (bitmap-region-has-rgb? under-bitmap 132 140 156 164 #"\xFF\xE3\xE3"))
  (check-true (bitmap-region-has-rgb? under-bitmap 340 348 105 113 #"\xD9\xE8\xFF"))
  ;; Coincident integration bounds produce an all-zero region strip. It is a
  ;; valid settled mathematical state and must render without attempting an
  ;; affine sign-crossing division.
  (define zero-width-region-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-zero-width-integral-region #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (check-equal? (bitmap-rgb zero-width-region-bitmap 240 135) #"\xFA\xFA\xFA")
  (define between-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-region-between #:width 480 #:height 270)
     #:at 'initial)
     480 270))
  (check-true (bitmap-region-has-rgb? between-bitmap 340 348 131 139 #"\xE7\xD8\xFF"))
  (define sequence-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-sequence-points #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; (2,4) is one authored marker; the gap between samples remains empty.
  (check-true (bitmap-region-has-rgb? sequence-bitmap 288 296 140 148 #"\x6A\x1B\x9A"))
  (check-equal? (bitmap-rgb sequence-bitmap 239 167) #"\xFA\xFA\xFA")
  (define number-line-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-number-line #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The declared midpoint value a=1 maps to the number line's center.
  (check-true (bitmap-region-has-rgb? number-line-bitmap 236 244 131 139 #"\x6A\x1B\x9A"))
  (define translucent-number-line-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-number-line
       #:profile
       (calculus-profile
        #:theme (calculus-theme #:base light-calculus-theme
                                #:rules (list (calculus-style #:target 'a #:opacity 1/2))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Number-line markers now honor opacity independently of their semantic
  ;; coordinate.  The midpoint is still painted, but composited over its panel.
  (check-not-equal? (bitmap-rgb translucent-number-line-bitmap 240 135) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb translucent-number-line-bitmap 240 135) #"\x6A\x1B\x9A")
  (define sign-chart-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-sign-chart #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The colored intervals are the two supplied claims, rather than signs
  ;; estimated from samples of f between their endpoints.
  (check-true (bitmap-region-has-rgb? sign-chart-bitmap 132 140 131 139 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? sign-chart-bitmap 340 348 131 139 #"\x21\x66\xC2"))
  (define component-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-component-export #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The component export P=(1,1) is a native point in the caller's plot,
  ;; not a formula fallback or a separately sampled screen coordinate.
  (check-true (bitmap-region-has-rgb? component-bitmap 340 348 152 160 #"\xB3\x26\x1E"))
  (define private-component-prepared
    (prepare-calculus-lesson render-private-component-exposition #:width 480 #:height 270))
  (define private-component-midpoint
    (pict->opaque-bitmap
     (prepared-lesson->pict private-component-prepared #:at 3/2)
     480 270))
  (define private-component-final
    (pict->opaque-bitmap
     (prepared-lesson->pict private-component-prepared #:at 'final)
     480 270))
  ;; C is deliberately absent from the caller's view declaration. During the
  ;; component's chord step its exact finite segment extends from its clipped
  ;; source endpoint, so a first-half region is green while its far endpoint
  ;; is not yet painted. Default auxiliary cleanup removes it after the final
  ;; secant step.
  (check-true (bitmap-region-has-rgb? private-component-midpoint 270 290 140 160 #"\x0B\x6E\x4F"))
  (check-false (bitmap-region-has-rgb? private-component-midpoint 340 356 82 104 #"\x0B\x6E\x4F"))
  (check-false (bitmap-region-has-rgb? private-component-final 304 312 122 130 #"\x0B\x6E\x4F"))
  (define deemphasized-private-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-deemphasized-private-component #:width 480 #:height 270)
      #:at 'final)
     480 270))
  ;; `deemphasize` retains C as a private auxiliary but lowers its alpha rather
  ;; than silently treating cleanup as hide or leaving the full green stroke.
  (check-true (bitmap-region-has-non-rgb? deemphasized-private-bitmap
                                           304 312 122 130 #"\xFA\xFA\xFA"))
  (check-false (bitmap-region-has-rgb? deemphasized-private-bitmap
                                        304 312 122 130 #"\x0B\x6E\x4F"))
  (define emphasis-prepared
    (prepare-calculus-lesson render-emphasis-state #:width 480 #:height 270))
  (define deemphasized-point-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict emphasis-prepared #:at 1/2)
     480 270))
  (define highlighted-point-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict emphasis-prepared #:at 3/2)
     480 270))
  (define normalized-point-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict emphasis-prepared #:at 'final)
     480 270))
  ;; The point's persistent faded state survives the first action, the
  ;; highlighted midpoint has a direct orange ring, and normalize restores
  ;; the original native point color after that transient callout ends.
  (check-false (bitmap-region-has-rgb? deemphasized-point-bitmap
                                        340 348 152 160 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? highlighted-point-bitmap
                                       334 354 146 166 #"\xD9\x77\x06"))
  (check-true (bitmap-region-has-rgb? normalized-point-bitmap
                                       340 348 152 160 #"\xB3\x26\x1E"))
  (define caption-prepared
    (prepare-calculus-lesson render-captioned-state #:width 480 #:height 270))
  (define caption-initial-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict caption-prepared #:at 'initial) 480 270))
  (define caption-final-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict caption-prepared #:at 'final) 480 270))
  (check-equal?
   (calculus-plan-caption (prepared-lesson-plan caption-prepared) 'final)
   "Point P stays fixed.")
  ;; A profile reserves the same caption band throughout an annotated lesson;
  ;; only the authored narration paints dark text after its step starts.
  (check-true (bitmap-regions-differ? caption-initial-bitmap caption-final-bitmap
                                      24 220 200 220))
  (define captions-disabled-profile
    (calculus-profile #:layout (calculus-layout #:captions? #f)))
  (define captions-disabled-initial-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-captioned-state
                               #:profile captions-disabled-profile #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (define captions-disabled-final-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-captioned-state
                               #:profile captions-disabled-profile #:width 480 #:height 270)
      #:at 'final)
     480 270))
  (check-false (bitmap-regions-differ? captions-disabled-initial-bitmap
                                       captions-disabled-final-bitmap
                                       24 220 200 220))
  (define formula-snapshot
    (calculus-plan-sample
     (prepared-lesson-plan
      (prepare-calculus-lesson render-formula-linkage #:width 480 #:height 270))
     #:at 'initial))
  ;; The text is based on linked quantity identities. Δy and Δx come from
  ;; increment parts, and the value readout observes the same semantic slope.
  (check-equal?
   (calculus-result-value
   (calculus-snapshot-formula-text formula-snapshot
                                    'equation))
   "m = (Δy)/(Δx)")
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-formula-text formula-snapshot
                                    'meter))
   "m 3.00")
  (define styled-formula-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson
       render-formula-linkage
       #:profile
       (calculus-profile
        #:theme
        (calculus-theme
         #:base light-calculus-theme
         #:rules (list (calculus-style #:target 'equation #:fill "#0B6E4F"
                                        #:font-size (calculus-px 24)))))
       #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  (define formula-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-formula-linkage #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Prepared formula rows paint semantic notation rather than the old generic
  ;; descriptor fallback, which had no visible Formula text at this location.
  ;; TeX's vector outlines can be antialiased across every covered pixel, so
  ;; prove visible mathematical paint against the formula panel rather than
  ;; requiring one fully opaque native-text pixel.
  (check-true (bitmap-region-has-non-rgb? formula-bitmap 44 220 45 75 #"\xFA\xFA\xFA"))
  (check-true (bitmap-regions-differ? formula-bitmap styled-formula-bitmap
                                      40 260 38 95))
  (define newton-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-newton-diagram #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The first construction joins (1,-1) to the exact next intercept 3/2.
  ;; Its purple tangent segment is distinct from the blue function graph.
  (check-true (bitmap-region-has-rgb? newton-bitmap 236 244 174 184 #"\x6A\x1B\x9A"))
  (check-true (bitmap-region-has-rgb? newton-bitmap 166 174 204 212 #"\xB3\x26\x1E"))
  (define stacked-profile
    (calculus-profile
     #:layout (calculus-layout #:arrangement 'stacked
                                #:margin (calculus-px 32)
                                #:gap (calculus-px 10))))
  (define stacked-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-stacked-number-lines
                               #:profile stacked-profile #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; Both presentation instances share a=1, while the profile places their
  ;; native axes in separate stable stacked panels.
  (check-true (bitmap-region-has-rgb? stacked-bitmap 236 244 77 85 #"\x6A\x1B\x9A"))
  (check-true (bitmap-region-has-rgb? stacked-bitmap 236 244 185 193 #"\x6A\x1B\x9A"))
  (define asymptote-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-vertical-asymptote #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; The certified vertical line remains visually distinct from the x=0 axis.
  (check-true (bitmap-region-has-rgb? asymptote-bitmap 236 244 72 80 #"\x5F\x63\x68"))
  (define coordinate-reading-bitmap
    (pict->opaque-bitmap
     (prepared-lesson->pict
      (prepare-calculus-lesson render-coordinate-reading #:width 480 #:height 270)
      #:at 'initial)
     480 270))
  ;; P=(1,1) supplies both guides and the marker through coordinate-reading's
  ;; public point part, rather than requiring a separate input-reading object.
  (check-true (bitmap-region-has-rgb? coordinate-reading-bitmap 236 244 177 185 #"\x6A\x6A\x6A"))
  (check-true (bitmap-region-has-rgb? coordinate-reading-bitmap 236 244 131 139 #"\xB3\x26\x1E")))

(module+ test
  (run-calculus-render-smoke-tests))
