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
  (initially (show R P Q))
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
  ;; The finite secant is clipped to the graph window in purple.  At the
  ;; transition endpoint it is replaced—not overpainted—by the red tangent.
  ;; This small interior region avoids the curve, axes, and line intersection.
  (check-true (bitmap-region-has-rgb? secant-bitmap 201 209 208 216 #"\x6A\x1B\x9A"))
  (check-false (bitmap-region-has-rgb? secant-bitmap 201 209 208 216 #"\xB3\x26\x1E"))
  (check-true (bitmap-region-has-rgb? tangent-bitmap 201 209 197 205 #"\xB3\x26\x1E"))
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
  ;; component's chord step its exact finite segment is still present in green;
  ;; default auxiliary cleanup after the final secant step removes it.
  (check-true (bitmap-region-has-rgb? private-component-midpoint 304 312 122 130 #"\x0B\x6E\x4F"))
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
