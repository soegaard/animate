#lang racket/base

;; The calculus core deliberately has no dependency on animate's renderer,
;; pict, draw, or GUI libraries.  It is the semantic boundary used by both
;; inspection and the rendering adapter.

(require racket/list
         racket/match
         racket/math
         racket/string)

(provide
 ;; Public values and inspection API.
 calculus-lesson? calculus-model? calculus-component? calculus-plan?
 calculus-snapshot? calculus-result? calculus-moment?
 calculus-lesson-model calculus-model-at compile-calculus-lesson
 calculus-plan-duration calculus-plan-diagnostics calculus-plan-sample
 calculus-step-start calculus-step-end calculus-checkpoint
 calculus-snapshot-ref calculus-snapshot-visible? calculus-snapshot-diagnostics
 calculus-result-status calculus-result-method calculus-result-approximate?
 calculus-result-value calculus-result-message calculus-result->datum
 calculus-diagnostic-severity calculus-diagnostic-code calculus-diagnostic-address
 calculus-diagnostic-message
 ;; Profiles and numerical policy.
 calculus-profile calculus-profile? calculus-theme calculus-theme? calculus-style calculus-style?
 calculus-layout calculus-layout? calculus-motion calculus-motion? calculus-timing calculus-timing?
 calculus-computation calculus-computation? calculus-px calculus-rel calculus-em calculus-length?
 classroom-light-profile classroom-dark-profile textbook-profile default-calculus-profile
 light-calculus-theme dark-calculus-theme default-calculus-computation
 ;; The declaration macros use these private implementation bindings.
 make-model bind-model-value make-lesson make-component make-held-function
 model-node-ref model-with-constraints current-model-node-ref call-with-imported-model
 make-piecewise-function make-generic make-view-reference calculus-real-line
 c-expression c-expression? c-expression-op c-expression-arguments
 calculus-pi calculus-e with-view-name
 c-node? c-node-id c-node-kind c-node-data c-node-parts
 c-function? c-function-variable c-function-body c-function-domain c-function-label c-function-provenance
 c-piecewise? c-piecewise-variable c-piecewise-branches c-piecewise-else c-piecewise-domain c-piecewise-label
 calculus-model-nodes calculus-lesson-views calculus-lesson-roles calculus-lesson-steps
 c-domain? c-domain-kind c-domain-arguments
 c-object? c-object-kind c-object-arguments c-object-options
 c-part? c-part-parent c-part-name
 c-action? c-action-kind c-action-targets c-action-options
 c-step? make-step c-view? c-view-name c-view-kind c-view-arguments c-view-options
 c-param-spec? make-param-spec
 calculus-component-part-node calculus-component-private-part-node
 calculus-component-private-presentation-parts
 calculus-component-private-presentation-view-names
 calculus-snapshot-component-private-ref calculus-snapshot-component-private-visible?
 calculus-snapshot-presentation-state calculus-snapshot-motion-state calculus-snapshot-label-visible?
 calculus-graph-source-function calculus-graph-parameter-dependencies
 calculus-snapshot-function-value calculus-snapshot-graph-value
 calculus-snapshot-function-branch calculus-snapshot-function-branch-value
 calculus-snapshot-function-breaks
 calculus-snapshot-trace-points calculus-snapshot-view-window calculus-snapshot-view-window-state calculus-snapshot-riemann-cells
 calculus-snapshot-riemann-carrier-cells
 calculus-snapshot-trapezoid-cells calculus-snapshot-partition-points
 calculus-snapshot-region-samples calculus-snapshot-sign-chart-intervals
 calculus-snapshot-newton-segments
 calculus-snapshot-asymptote-geometry
 calculus-snapshot-formula-text calculus-snapshot-formula-tex calculus-snapshot-formula-fragments
 calculus-snapshot-formula-skeleton-tex
 calculus-snapshot-label-text calculus-snapshot-label-anchor
 calculus-snapshot-marker-geometry
 calculus-plan-caption calculus-plan-has-captions?
 calculus-plan-lesson calculus-plan-profile calculus-plan-events c-event-start c-event-end
 calculus-profile-data-theme calculus-theme-data-background calculus-theme-data-foreground
 calculus-theme-data-font-family calculus-theme-data-font-size
 calculus-theme-data-base calculus-theme-data-rules
 calculus-style-data-kind calculus-style-data-role calculus-style-data-state
 calculus-style-data-target calculus-style-data-view calculus-style-data-stroke
 calculus-style-data-fill calculus-style-data-stroke-width calculus-style-data-dash
 calculus-style-data-opacity calculus-style-data-marker-radius calculus-style-data-font-size
 calculus-style-data-label-gap
 calculus-profile-data-layout calculus-layout-data-arrangement calculus-layout-data-panel-order
 calculus-layout-data-margin calculus-layout-data-gap calculus-layout-data-captions?
 calculus-layout-data-caption-height calculus-layout-data-fit-samples
 calculus-length-unit calculus-length-value
 action-kinds view-kinds)

;; -------------------------------------------------------------------------
;; Immutable source-neutral semantic data

;; calculus-result records an ordinary mathematical outcome without using NaN.
(struct calculus-result (status method approximate? value message) #:transparent)
;;  - status        one of 'defined, 'outside-domain, 'undefined, or 'unresolved
;;  - method        provenance symbol such as 'definition, 'symbolic, or 'numeric
;;  - approximate?  whether the reported value is numerically approximate
;;  - value         mathematical value when status is 'defined, otherwise #f
;;  - message       optional immutable explanation for a nondefined result
;; calculus-diagnostic records one stable user-facing diagnostic location.
(struct calculus-diagnostic (severity code address step time message) #:transparent)
;;  - severity      one of 'info, 'warning, or 'error
;;  - code          stable diagnostic category symbol
;;  - address       optional public semantic address
;;  - step          optional authored step address
;;  - time          optional sample time
;;  - message       human-readable explanation
;; c-domain holds an unevaluated domain construction and source order.
(struct c-domain (kind arguments) #:transparent)
;;  - kind          documented domain constructor symbol
;;  - arguments     immutable ordered endpoint or child-domain expressions
;; c-expression holds an immutable scalar or Boolean expression tree.
(struct c-expression (op arguments) #:transparent)
;;  - op            documented scalar operator symbol
;;  - arguments     immutable ordered operand expressions
;; c-param-spec records the declaration-time invariants of one writable scalar.
(struct c-param-spec (initial domain kind label) #:transparent)
;;  - initial       declared finite initial scalar
;;  - domain        held domain which constrains all assigned values
;;  - kind          'real or 'integer parameter capability
;;  - label         optional author-facing notation
;; c-node owns one named semantic identity in a model.
(struct c-node (id kind data parts) #:transparent)
;;  - id            stable public root symbol
;;  - kind          semantic category symbol
;;  - data          held descriptor or scalar expression
;;  - parts         immutable public-part metadata map
;; c-function is a held single-variable function declaration.
(struct c-function (variable body domain label provenance) #:transparent)
;;  - variable      lexical mathematical variable symbol
;;  - body          held expression or supported function descriptor
;;  - domain        declared input-domain upper bound
;;  - label         optional author-facing notation
;;  - provenance    immutable definition-source descriptor
;; c-piecewise is an ordered held function with an optional final else branch.
(struct c-piecewise (variable branches else domain label) #:transparent)
;;  - variable      lexical mathematical variable symbol
;;  - branches      immutable ordered condition/value pairs
;;  - else          optional fallback held expression
;;  - domain        declared input-domain upper bound
;;  - label         optional author-facing notation
;; c-object is the generic immutable descriptor for non-scalar constructions.
(struct c-object (kind arguments options) #:transparent)
;;  - kind          documented constructor symbol
;;  - arguments     immutable ordered operands
;;  - options       immutable symbol-keyed option hash
;; c-part names one public semantic subobject without allocating a duplicate.
(struct c-part (parent name) #:transparent)
;;  - parent        root descriptor or another part
;;  - name          documented part symbol or stable nested part path
;; c-view holds a named abstract representation with no pixel geometry.
(struct c-view (name kind arguments options) #:transparent)
;;  - name          lesson-local stable view symbol
;;  - kind          graph, formula, or number-line view constructor symbol
;;  - arguments     immutable ordered view operands
;;  - options       immutable view geometry and object-list options
;; c-action is an immutable exposition command before timeline lowering.
(struct c-action (kind targets options) #:transparent)
;;  - kind          documented action symbol
;;  - targets       immutable ordered semantic targets
;;  - options       immutable action timing and behavior options
;; c-step is one named caption and ordered group of exposition commands.
(struct c-step (id say read-delay duration pause commands) #:transparent)
;;  - id            stable step symbol
;;  - say           optional caption string
;;  - read-delay    optional pre-command delay
;;  - duration      optional default command duration
;;  - pause         optional post-step pause
;;  - commands      immutable ordered c-action values
;; calculus-model retains mathematical nodes separately from presentation.
(struct calculus-model (nodes constraints) #:transparent)
;;  - nodes         immutable public-name to c-node map
;;  - constraints   immutable ordered held Boolean requirements
;; calculus-component is a pure reusable declaration descriptor.
(struct calculus-component (name inputs bindings exports constraints exposition) #:transparent)
;;  - name          component declaration symbol
;;  - inputs        immutable (input-name . type-name) declarations
;;  - bindings      procedure that maps supplied semantic inputs to a private model
;;  - exports       immutable public export-name list
;;  - constraints   immutable component constraint data
;;  - exposition    optional procedure mapping supplied semantic inputs to
;;                  immutable private c-step data
;; calculus-lesson joins one model to views, presentation, and exposition.
(struct calculus-lesson (model views roles initial timing steps) #:transparent)
;;  - model         immutable calculus-model
;;  - views         immutable stable-name to c-view map
;;  - roles         immutable ordered presentation role assignments
;;  - initial       immutable persistent initial c-action list
;;  - timing        optional calculus-timing override
;;  - steps         immutable ordered c-step list
;; c-event is a lowered leaf action with exact temporal placement.
(struct c-event (ordinal start end action group) #:transparent)
;;  - ordinal       stable same-time ordering index
;;  - start         exact or finite action start time
;;  - end           exact or finite action end time
;;  - action        source c-action descriptor
;;  - group         #f for a sequential action, otherwise one flattened
;;                  together-group identity used for conflict checks
;; calculus-moment identifies a semantic phase independent of numeric ties.
(struct calculus-moment (kind address) #:transparent)
;;  - kind          'step-start, 'step-end, or 'checkpoint
;;  - address       stable public step/checkpoint path
;; calculus-plan is a compiled headless lesson with no native objects.
(struct calculus-plan (lesson profile values computation events duration diagnostics moments captions) #:transparent)
;;  - lesson        source immutable calculus-lesson
;;  - profile       selected immutable presentation profile
;;  - values        immutable initial parameter-value map
;;  - computation   selected immutable numerical policy
;;  - events        immutable ordered c-event list
;;  - duration      total nonnegative lesson duration
;;  - diagnostics   immutable compilation diagnostics
;;  - moments       immutable phase/address to time-and-order map
;;  - captions      immutable nested occurrence caption records
;; c-caption records one authored caption's active timing interval.
(struct c-caption (path text start end) #:transparent)
;;  - path          stable outer-step/component/local-step occurrence path
;;  - text          authored immutable caption string
;;  - start         caption start before its step read delay
;;  - end           caption end after that step's authored pause
;; calculus-snapshot is one immutable inspectable semantic state.
(struct calculus-snapshot (model values visible diagnostics computation) #:transparent)
;;  - model         snapshot's immutable calculus-model
;;  - values        immutable current parameter-value map
;;  - visible       immutable presentation-state map: visibility plus private
;;                  namespaced emphasis, highlight, trace, and camera slots
;;  - diagnostics   immutable sampling diagnostics
;;  - computation   numerical policy used for every inspected result
;; calculus-length is a unit-tagged pure presentation dimension.
(struct calculus-length (unit value) #:transparent)
;;  - unit          'px, 'rel, or 'em
;;  - value         nonnegative finite magnitude
;; calculus-style-data is one ordered pure style rule.
(struct calculus-style-data (kind role state target view stroke fill stroke-width dash opacity marker-radius font-size label-gap) #:transparent)
;;  - kind, role, state, target, view  optional semantic selectors
;;  - stroke, fill, stroke-width, dash, opacity, marker-radius, font-size, label-gap
;;                     inherited or explicitly authored presentation values
;; calculus-theme-data is a theme inheritance node and its style rules.
(struct calculus-theme-data (base background foreground font-family font-size rules) #:transparent)
;;  - base          optional inherited calculus theme
;;  - background    optional native background color descriptor
;;  - foreground    optional native foreground color descriptor
;;  - font-family   optional font family descriptor
;;  - font-size     optional calculus-length
;;  - rules         immutable ordered calculus-style-data list
;; calculus-layout-data describes panel arrangement and stable label policy.
(struct calculus-layout-data (arrangement panel-order margin gap captions? caption-height label-policy fit-samples) #:transparent)
;;  - arrangement, panel-order  layout selection data
;;  - margin, gap, caption-height  calculus-length layout dimensions
;;  - captions?     whether captions reserve layout space
;;  - label-policy  stable or fixed placement policy
;;  - fit-samples   deterministic representative-sample count
;; calculus-motion-data selects pure semantic motion styles.
(struct calculus-motion-data (graph-reveal line-reveal reading parameter-easing refinement limit-transition focus highlight reduced-motion?) #:transparent)
;;  - graph-reveal through highlight  documented motion-policy symbols
;;  - reduced-motion?  whether native preparation must avoid dynamic emphasis
;; calculus-timing-data holds the four lesson timing defaults in seconds.
(struct calculus-timing-data (opening-pause read-delay action-duration step-pause) #:transparent)
;;  - opening-pause, read-delay, action-duration, step-pause  finite timing values
;; calculus-profile-data composes independent theme, layout, motion, and timing.
(struct calculus-profile-data (theme layout motion timing) #:transparent)
;;  - theme, layout, motion, timing  validated immutable policy records
;; calculus-computation-data bounds numerical approximation independently of pixels.
(struct calculus-computation-data (absolute-tolerance relative-tolerance derivative-step integration-method integration-budget) #:transparent)
;;  - absolute-tolerance, relative-tolerance, derivative-step  positive finite reals
;;  - integration-method  documented numerical integration symbol
;;  - integration-budget  positive exact integrand-evaluation limit

;; defined : any/c symbol? boolean? -> calculus-result?
;;   Constructs a successful result with provenance.
(define (defined value [method 'definition] [approximate? #f])
  (calculus-result 'defined method approximate? value #f))
;; outside : string? -> calculus-result?
;;   Constructs a distinct out-of-domain outcome.
(define (outside message) (calculus-result 'outside-domain 'definition #f #f message))
;; undefined : string? -> calculus-result?
;;   Constructs a distinct undefined-expression outcome.
(define (undefined message) (calculus-result 'undefined 'definition #f #f message))
;; unresolved : string? symbol? -> calculus-result?
;;   Constructs a distinct unavailable-information outcome.
(define (unresolved message [method 'definition]) (calculus-result 'unresolved method #f #f message))
;; result-error : calculus-result? -> string?
;;   Retrieves a usable result explanation.
(define (result-error result)
  (or (calculus-result-message result) "mathematical value is not defined"))
;; result-method-join : symbol? symbol? -> symbol?
;;   Retains a single provenance when it survives a calculation and records a
;;   genuine combination without pretending that the enclosing arithmetic is a
;;   new proof of either input.
(define (result-method-join earlier later)
  (cond [(eq? earlier later) earlier]
        [(eq? earlier 'definition) later]
        [(eq? later 'definition) earlier]
        [else 'mixed]))
;; result-compose-provenance : calculus-result? calculus-result? -> calculus-result?
;;   Carries the independent method and approximation facts of one defined
;;   dependency into a result constructed from it.  Nondefined results are
;;   never rewritten: their status and diagnostic remain the primary fact.
(define (result-compose-provenance dependency result)
  (if (and (eq? (calculus-result-status dependency) 'defined)
           (eq? (calculus-result-status result) 'defined))
      (calculus-result
       'defined
       (result-method-join (calculus-result-method dependency)
                           (calculus-result-method result))
       (or (calculus-result-approximate? dependency)
           (calculus-result-approximate? result))
       (calculus-result-value result)
       #f)
      result))
;; result-with-method : calculus-result? symbol? -> calculus-result?
;;   Reclassifies a successful result for one explicitly selected mathematical
;;   method while preserving its approximation evidence.
(define (result-with-method result method)
  (if (eq? (calculus-result-status result) 'defined)
      (calculus-result 'defined method (calculus-result-approximate? result)
                       (calculus-result-value result) #f)
      result))
;; result-bind : calculus-result? procedure? -> calculus-result?
;;   Sequences only defined mathematical outcomes and composes their
;;   provenance.  A continuation still receives the raw mathematical value so
;;   ordinary evaluator code stays direct and cannot accidentally inspect a
;;   renderer-oriented result record.
(define (result-bind result proc)
  (if (eq? (calculus-result-status result) 'defined)
      (result-compose-provenance result (proc (calculus-result-value result)))
      result))

;; action-kinds : list?
;;   Names the exposition forms understood by the compiler.
(define action-kinds
  '(show hide show-label hide-label deemphasize normalize highlight highlight-quantity
         read vary set-parameter approach trace refine limit-transition focus restore-view
         together compare pause checkpoint explain))
;; view-kinds : list?
;;   Names the supported abstract view forms.
(define view-kinds '(graph-view formula-view number-line-view))

;; calculus-real-line : c-domain?
;;   Holds the default unbounded input domain.
(define calculus-real-line (c-domain 'real-line '()))
;; calculus-pi : c-expression?
;;   Holds π until evaluation asks for its numeric value.
(define calculus-pi (c-expression 'constant (list 'pi)))
;; calculus-e : c-expression?
;;   Holds Euler's number until evaluation asks for its numeric value.
(define calculus-e (c-expression 'constant (list 'e)))
;; snapshot-basis-key : symbol?
;;   Privately retains a plan/model's compiled initial parameter map so a
;;   snapshot never accidentally freezes a later sampled frame state.
(define snapshot-basis-key (gensym 'calculus-snapshot-basis))

;; -------------------------------------------------------------------------
;; Policies.  They are data, not callbacks.

;; finite-real? : any/c -> boolean?
;;   Recognizes core numeric values.
(define (finite-real? value)
  (and (real? value) (rational? value)))
;; immutable-list-copy : list? -> list?
;;   Retains ordered source data without caller mutation.
(define (immutable-list-copy values)
  (for/list ([value (in-list values)]) value))
;; positive-finite? : any/c -> boolean?
;;   Recognizes positive core measurements.
(define (positive-finite? value) (and (finite-real? value) (positive? value)))
;; nonnegative-finite? : any/c -> boolean?
;;   Recognizes nonnegative core measurements.
(define (nonnegative-finite? value) (and (finite-real? value) (not (negative? value))))
;; check : symbol? procedure? string? any/c -> any/c
;;   Applies one constructor contract.
(define (check who predicate description value)
  (unless (predicate value) (raise-argument-error who description value))
  value)
;; calculus-px : nonnegative-real? -> calculus-length?
;;   Constructs an output-pixel length.
(define (calculus-px value) (calculus-length 'px (check 'calculus-px nonnegative-finite? "nonnegative finite real" value)))
;; calculus-rel : nonnegative-real? -> calculus-length?
;;   Constructs a panel-relative length.
(define (calculus-rel value) (calculus-length 'rel (check 'calculus-rel nonnegative-finite? "nonnegative finite real" value)))
;; calculus-em : nonnegative-real? -> calculus-length?
;;   Constructs a font-relative length.
(define (calculus-em value) (calculus-length 'em (check 'calculus-em nonnegative-finite? "nonnegative finite real" value)))

;; documented-style-kinds : list?
;;   Kept separate from semantic node kinds: one selector can cover several
;; concrete construction nodes without changing their mathematical identity.
(define documented-style-kinds
  '(graph point line segment guide label marker region rectangle readout formula axis))
(define documented-style-states '(normal deemphasized highlighted refining))
(define documented-roles
  '(primary comparison auxiliary input output increment approximation result
            positive negative annotation))

;; style-color? : any/c -> boolean?
;;   Accepts the documented opaque/alpha CSS literals only. Native color
;; conversion remains in the rendering adapter.
(define (style-color? value)
  (and (string? value) (regexp-match? #px"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$" value)))

;; style-address? : any/c -> boolean?
;;   A style target names a public semantic address, never a drawing-list
;; position or a private component leaf.
(define (style-address? value)
  (or (symbol? value)
      (and (list? value) (pair? value) (andmap symbol? value))))

;; calculus-style : keyword-options -> calculus-style?
;;   Constructs a pure selector-based presentation rule.
(define (calculus-style #:kind [kind #f] #:role [role #f] #:state [state #f]
                       #:target [target #f] #:view [view #f]
                       #:stroke [stroke 'inherit] #:fill [fill 'inherit]
                       #:stroke-width [stroke-width 'inherit] #:dash [dash 'inherit]
                       #:opacity [opacity 'inherit] #:marker-radius [marker-radius 'inherit]
                       #:font-size [font-size 'inherit] #:label-gap [label-gap 'inherit])
  (when kind
    (check 'calculus-style (lambda (value) (memq value documented-style-kinds))
           "documented style kind" kind))
  (when role
    (check 'calculus-style (lambda (value) (memq value documented-roles))
           "documented presentation role" role))
  (when state
    (check 'calculus-style (lambda (value) (memq value documented-style-states))
           "documented presentation state" state))
  (when target (check 'calculus-style style-address? "public mathematical address" target))
  (when view (check 'calculus-style symbol? "view symbol" view))
  (for ([color (in-list (list stroke fill))])
    (unless (or (eq? color 'inherit) (eq? color 'none) (style-color? color))
      (raise-arguments-error 'calculus-style
                             "stroke and fill must be 'inherit, 'none, or a #RRGGBB[AA] string"
                             "value" color)))
  (unless (or (eq? dash 'inherit) (eq? dash 'solid)
              (and (list? dash) (pair? dash) (andmap positive-finite? dash)))
    (raise-arguments-error 'calculus-style
                           "dash must be 'inherit, 'solid, or a nonempty list of positive lengths"
                           "dash" dash))
  (when (and opacity (not (eq? opacity 'inherit)))
    (check 'calculus-style (lambda (v) (and (finite-real? v) (<= 0 v 1))) "opacity in [0,1]" opacity))
  (for ([dimension (in-list (list stroke-width marker-radius font-size label-gap))])
    (when (and dimension (not (eq? dimension 'inherit)))
      (check 'calculus-style calculus-length? "calculus-length?" dimension)))
  (calculus-style-data kind role state target view stroke fill stroke-width dash opacity marker-radius font-size label-gap))

;; calculus-theme : keyword-options -> calculus-theme?
;;   Constructs an immutable inheritable theme.
(define (calculus-theme #:base [base #f] #:background [background #f] #:foreground [foreground #f]
                        #:font-family [font-family #f] #:font-size [font-size #f] #:rules [rules '()])
  (when base (check 'calculus-theme calculus-theme? "calculus-theme?" base))
  (for ([color (in-list (filter values (list background foreground)))])
    (check 'calculus-theme style-color? "#RRGGBB[AA] color string" color))
  (when font-family (check 'calculus-theme string? "font family string" font-family))
  (when font-size
    (check 'calculus-theme calculus-length? "calculus-length?" font-size)
    (when (eq? (calculus-length-unit font-size) 'em)
      (raise-arguments-error 'calculus-theme
                             "base font size cannot use an em length"
                             "font-size" font-size)))
  (check 'calculus-theme list? "list?" rules)
  (for ([rule (in-list rules)]) (check 'calculus-theme calculus-style? "calculus-style?" rule))
  (calculus-theme-data base background foreground font-family font-size (immutable-list-copy rules)))

;; calculus-layout : keyword-options -> calculus-layout?
;;   Constructs deterministic panel and annotation placement policy.
(define (calculus-layout #:arrangement [arrangement 'auto] #:panel-order [panel-order #f]
                         #:margin [margin (calculus-rel 1/20)] #:gap [gap (calculus-rel 1/30)]
                         #:captions? [captions? #t] #:caption-height [caption-height (calculus-rel 7/50)]
                         #:label-policy [label-policy 'stable] #:fit-samples [fit-samples 257])
  (check 'calculus-layout (lambda (v) (memq v '(auto stacked side-by-side))) "'auto, 'stacked, or 'side-by-side" arrangement)
  (check 'calculus-layout calculus-length? "calculus-length?" margin)
  (check 'calculus-layout calculus-length? "calculus-length?" gap)
  (check 'calculus-layout calculus-length? "calculus-length?" caption-height)
  (check 'calculus-layout (lambda (v) (memq v '(stable fixed))) "'stable or 'fixed" label-policy)
  (check 'calculus-layout (lambda (v) (and (exact-integer? v) (>= v 2))) "exact integer at least 2" fit-samples)
  (calculus-layout-data arrangement panel-order margin gap captions? caption-height label-policy fit-samples))

;; calculus-motion : keyword-options -> calculus-motion?
;;   Constructs native motion policy without changing mathematics.
(define (calculus-motion #:graph-reveal [graph-reveal 'trace] #:line-reveal [line-reveal 'extend]
                         #:reading [reading 'guided] #:parameter-easing [parameter-easing 'linear]
                         #:refinement [refinement 'subdivide] #:limit-transition [limit-transition 'crossfade]
                         #:focus [focus 'pan-zoom] #:highlight [highlight 'outline]
                         #:reduced-motion? [reduced-motion? #f])
  (for ([entry (in-list (list (cons graph-reveal '(trace fade)) (cons line-reveal '(extend fade))
                              (cons reading '(guided simultaneous)) (cons parameter-easing '(linear smoothstep))
                              (cons refinement '(subdivide crossfade)) (cons limit-transition '(crossfade rotate-carrier))
                              (cons focus '(pan-zoom cut)) (cons highlight '(outline pulse))))])
    (unless (memq (car entry) (cdr entry))
      (raise-arguments-error 'calculus-motion "unsupported motion policy" "value" (car entry))))
  (calculus-motion-data graph-reveal line-reveal reading parameter-easing refinement limit-transition focus highlight reduced-motion?))

;; calculus-timing : keyword-options -> calculus-timing?
;;   Constructs exact delay and duration defaults.
(define (calculus-timing #:opening-pause [opening-pause 3/5] #:read-delay [read-delay 1]
                         #:action-duration [action-duration 1] #:step-pause [step-pause 3/5])
  (for ([pair (in-list (list (cons 'opening-pause opening-pause) (cons 'read-delay read-delay)
                             (cons 'action-duration action-duration) (cons 'step-pause step-pause)))])
    (check 'calculus-timing nonnegative-finite? "nonnegative finite real" (cdr pair)))
  (unless (positive? action-duration)
    (raise-arguments-error 'calculus-timing "action duration must be positive" "action-duration" action-duration))
  (calculus-timing-data opening-pause read-delay action-duration step-pause))

;; light-calculus-theme : calculus-theme?
;;   Provides the light presentation baseline.
(define light-calculus-theme
  (calculus-theme #:background "#FFFFFF" #:foreground "#202124" #:font-size (calculus-rel 1/30)))
;; dark-calculus-theme : calculus-theme?
;;   Provides the dark presentation baseline.
(define dark-calculus-theme
  (calculus-theme #:background "#171A21" #:foreground "#F5F7FA" #:font-size (calculus-rel 1/30)))
;; calculus-profile : keyword-options -> calculus-profile?
;;   Combines independent appearance, layout, motion, and timing policies.
(define (calculus-profile #:theme [theme light-calculus-theme] #:layout [layout (calculus-layout)]
                          #:motion [motion (calculus-motion)] #:timing [timing (calculus-timing)])
  (check 'calculus-profile calculus-theme-data? "calculus-theme?" theme)
  (check 'calculus-profile calculus-layout-data? "calculus-layout?" layout)
  (check 'calculus-profile calculus-motion-data? "calculus-motion?" motion)
  (check 'calculus-profile calculus-timing-data? "calculus-timing?" timing)
  (calculus-profile-data theme layout motion timing))
;; classroom-light-profile : calculus-profile?
;;   Provides the default classroom appearance.
(define classroom-light-profile (calculus-profile))
;; classroom-dark-profile : calculus-profile?
;;   Provides a dark classroom appearance.
(define classroom-dark-profile (calculus-profile #:theme dark-calculus-theme))
;; textbook-profile : calculus-profile?
;;   Provides a reduced-motion presentation baseline.
(define textbook-profile (calculus-profile #:motion (calculus-motion #:highlight 'outline #:reduced-motion? #t)))
;; default-calculus-profile : calculus-profile?
;;   Names the profile selected when #:profile is omitted.
(define default-calculus-profile classroom-light-profile)

;; calculus-computation : keyword-options -> calculus-computation?
;;   Constructs numerical accuracy policy independently of renderer quality.
(define (calculus-computation #:absolute-tolerance [absolute-tolerance 1e-10]
                              #:relative-tolerance [relative-tolerance 1e-8]
                              #:derivative-step [derivative-step 1e-4]
                              #:integration-method [integration-method 'adaptive-simpson]
                              #:integration-budget [integration-budget 10000])
  (for ([value (in-list (list absolute-tolerance relative-tolerance derivative-step))])
    (check 'calculus-computation positive-finite? "positive finite real" value))
  (check 'calculus-computation (lambda (v) (eq? v 'adaptive-simpson)) "'adaptive-simpson" integration-method)
  (check 'calculus-computation (lambda (v) (and (exact-integer? v) (positive? v))) "positive exact integer" integration-budget)
  (calculus-computation-data absolute-tolerance relative-tolerance derivative-step integration-method integration-budget))
;; default-calculus-computation : calculus-computation?
;;   Names the default mathematical numerical policy.
(define default-calculus-computation (calculus-computation))

;; Alias struct predicates/accessors to their documented spellings.
(define calculus-style? calculus-style-data?)
(define calculus-theme? calculus-theme-data?)
(define calculus-layout? calculus-layout-data?)
(define calculus-motion? calculus-motion-data?)
(define calculus-timing? calculus-timing-data?)
(define calculus-profile? calculus-profile-data?)
(define calculus-computation? calculus-computation-data?)

;; -------------------------------------------------------------------------
;; Declarations and generic contextual constructors

;; make-param-spec : scalar? c-domain? symbol? any/c -> c-param-spec?
;;   Validates the immutable data that identifies a writable parameter.
(define (make-param-spec initial domain kind label)
  (unless (memq kind '(real integer))
    (raise-arguments-error 'parameter "#:kind must be 'real or 'integer" "kind" kind))
  (c-param-spec initial domain kind label))

;; hash-options : list? -> immutable-hash?
;;   Converts parsed keyword pairs into immutable semantic options.
(define (hash-options pairs)
  (make-immutable-hash pairs))

;; make-generic : symbol? list? immutable-hash? -> semantic-descriptor?
;;   Builds one contextual descriptor while keeping operands held.
(define (make-generic kind positional [options (hash)])
  (define args (immutable-list-copy positional))
  (define opts (if (immutable? options) options (hash-copy options)))
  (define (option name [default #f]) (hash-ref opts name default))
  (case kind
    [(parameter)
     (unless (= (length args) 1) (raise-arguments-error 'parameter "requires an initial value" "arguments" args))
     (unless (hash-has-key? opts 'domain) (raise-arguments-error 'parameter "requires #:domain" "arguments" args))
     (make-param-spec (first args) (option 'domain) (option 'kind 'real) (option 'label #f))]
    [(real-line) calculus-real-line]
    [(empty-domain) (c-domain 'empty '())]
    [(closed open closed-open open-closed singleton neighborhood punctured-neighborhood
             domain-union domain-intersection domain-except integers)
     (c-domain kind args)]
    [(in-domain?) (c-expression 'in-domain? args)]
    [(+ - * / expt sqrt abs exp log sin cos tan asin acos atan = < <= > >= and or not if list
         value-at x-coordinate y-coordinate slope difference-quotient sum-value area-of
               sequence-value iterate-value)
     (c-expression kind args)]
    [(partial-sum)
     (c-object kind args opts)]
    [(part) (apply make-part args)]
    [(reading-branch)
     (unless (= (length args) 2) (raise-arguments-error 'reading-branch "requires a reading and source index" "arguments" args))
     (c-part (first args) (list 'branches (second args)))]
    [(graph-view formula-view number-line-view)
     (c-view #f kind args opts)]
    [(show hide show-label hide-label deemphasize normalize highlight highlight-quantity
            read vary set-parameter approach trace refine limit-transition focus restore-view
            together compare pause checkpoint explain)
     (c-action kind args opts)]
    [(graph graph-restriction point point-on axis-point projection segment line-through ray-through horizontal-line vertical-line
             input-reading output-reading coordinate-reading point-label graph-label quantity-label value-readout interval-marker
             endpoint-marker approach-marker chord secant increment slope-triangle tangent vertical-tangent normal point-on-line
             linearization approximation-error error-segment taylor-polynomial neighborhood punctured-neighborhood input-band
             output-band limit-statement epsilon-delta-condition continuity-condition asymptote-line definite-integral
             accumulation-function integral-region region-under region-between partition uniform-partition tag-partition partition-marks
             riemann-sum riemann-rectangles trapezoidal-sum trapezoidal-regions refinement level-set solution-inputs root-point
             intersection-point sign-claim monotonicity-claim concavity-claim sign-chart feature-point sequence sequence-points
             iteration-map newton-iteration newton-diagram snapshot-of formula formula-of ref value formula-occurrence
             quantity-correspondence trace-of restrict-function compose-functions difference-function derivative-function
             antiderivative-function procedure-function use-component in-view explain)
     (c-object kind args opts)]
    [else (c-object kind args opts)]))

;; make-part : semantic-descriptor? part-name? -> c-part?
;;   References a public subpart without allocating another mathematical object.
(define (make-part parent name)
  (unless (or (symbol? name) (and (list? name) (pair? name)))
    (raise-argument-error 'part "symbol? or documented part path" name))
  (c-part parent name))

;; with-view-name : c-view? symbol? -> c-view?
;;   Attaches a stable lesson-local name to an abstract view descriptor.
(define (with-view-name view name)
  (unless (c-view? view) (raise-argument-error 'views "view descriptor" view))
  (unless (symbol? name) (raise-argument-error 'views "symbol?" name))
  (struct-copy c-view view [name name]))

;; make-view-reference : symbol? -> c-view?
;;   Retains an authored view name inside later timeline commands without
;;   rebuilding or aliasing the view declaration itself.
(define (make-view-reference name)
  (unless (symbol? name) (raise-argument-error 'view "symbol?" name))
  (c-view name 'view-reference '() (hash)))

;; make-held-function : symbol? any/c ... -> c-function?
;;   Builds a lexical single-variable function whose body remains held.
(define (make-held-function variable body #:domain [domain calculus-real-line] #:label [label #f])
  (c-function variable body domain label '(definition)))

;; make-piecewise-function : symbol? list? any/c ... -> c-piecewise?
;;   Builds a source-ordered piecewise held function.
(define (make-piecewise-function variable branches else #:domain [domain calculus-real-line] #:label [label #f])
  (c-piecewise variable (immutable-list-copy branches) else domain label))

;; semantic-kind : any/c -> symbol?
;;   Selects the identity category retained by a bound value.
(define (semantic-kind value)
  (cond [(c-node? value) (c-node-kind value)]
        [(c-domain? value) 'domain]
        [(c-function? value) 'function]
        [(c-piecewise? value) 'function]
        [(c-expression? value) 'scalar]
        [(c-part? value) 'part]
        [(c-object? value) (c-object-kind value)]
        [(or (number? value) (boolean? value)) 'scalar]
        [else 'opaque]))

;; provider-key-datum? : any/c -> boolean?
;;   Accepts reconstructible immutable datum shapes for opaque provider
;; identity. Procedures, mutable boxes, and arbitrary host objects cannot
;; serve as a stable version key.
(define (provider-key-datum? value)
  (cond [(or (number? value) (boolean? value) (symbol? value) (keyword? value)
             (char? value) (null? value)) #t]
        [(string? value) (immutable? value)]
        [(bytes? value) (immutable? value)]
        [(pair? value) (and (provider-key-datum? (car value))
                            (provider-key-datum? (cdr value)))]
        [(vector? value) (and (immutable? value)
                              (for/and ([item (in-vector value)])
                                (provider-key-datum? item)))]
        [(hash? value) (and (immutable? value)
                            (for/and ([(key datum) (in-hash value)])
                              (and (provider-key-datum? key)
                                   (provider-key-datum? datum))))]
        [else #f]))

;; validate-procedure-function : c-object? -> void?
;;   Keeps opaque providers at a narrow explicit boundary. Their values may be
;; mathematically partial, but their host identity and declared domain are not
;; silently optional implementation details.
(define (validate-procedure-function object)
  (define arguments (c-object-arguments object))
  (define options (c-object-options object))
  (unless (and (= (length arguments) 1) (procedure? (first arguments)))
    (raise-arguments-error 'procedure-function
                           "requires exactly one procedure supplied through external"
                           "arguments" arguments))
  (unless (hash-has-key? options 'domain)
    (raise-arguments-error 'procedure-function "requires #:domain" "options" options))
  (unless (c-domain? (hash-ref options 'domain))
    (raise-arguments-error 'procedure-function "requires a declared domain" "domain"
                           (hash-ref options 'domain)))
  (unless (hash-has-key? options 'key)
    (raise-arguments-error 'procedure-function "requires #:key" "options" options))
  (unless (provider-key-datum? (hash-ref options 'key))
    (raise-arguments-error 'procedure-function "#:key must be immutable datum"
                           "key" (hash-ref options 'key))))

;; bind-model-value : symbol? semantic-value? boolean? -> c-node?
;;   Gives one ordered model binding its stable public identity.
(define (bind-model-value name raw direct-reference?)
  (unless (symbol? name) (raise-argument-error 'model "symbol?" name))
  (cond
    [(c-param-spec? raw) (c-node name 'parameter raw (hash))]
    [(c-node? raw)
     (if (memq (c-node-kind raw) '(scalar parameter part))
         (c-node name 'scalar (c-expression 'ref (list raw)) (hash))
         raw)]
    [(or (c-expression? raw) (number? raw) (boolean? raw) (list? raw))
     (c-node name 'scalar raw (hash))]
    [(c-function? raw) (c-node name 'function raw (hash))]
    [(c-piecewise? raw) (c-node name 'function raw (hash))]
    [(c-domain? raw) (c-node name 'domain raw (hash))]
    [(c-object? raw)
     (when (eq? (c-object-kind raw) 'procedure-function)
       (validate-procedure-function raw))
     (c-node name (semantic-kind raw) raw (hash))]
    [(c-part? raw) (c-node name (semantic-kind raw) raw (hash))]
    [else (raise-arguments-error 'model "unsupported immutable mathematical value" "binding" name "value" raw)]))

;; make-model : list? list? -> calculus-model?
;;   Builds an immutable unique-name mathematical dependency model.
(define (make-model bindings [constraints '()])
  (define names (map car bindings))
  (unless (= (length names) (length (remove-duplicates names)))
    (raise-arguments-error 'model "duplicate model binding" "names" names))
  (define nodes (make-immutable-hash bindings))
  (calculus-model nodes (immutable-list-copy constraints)))

;; model-node-ref : calculus-model? symbol? -> c-node?
;;   Supplies declaration-time lexical imports for `use-model` without turning
;;   model addresses into strings, eval, or mutable global namespace state.
(define (model-node-ref model name)
  (check 'use-model calculus-model? "calculus-model?" model)
  (unless (symbol? name) (raise-argument-error 'use-model "symbol? node name" name))
  (hash-ref (calculus-model-nodes model) name
            (lambda ()
              (raise-arguments-error 'use-model "known public model binding"
                                     "name" name))))

;; current-imported-model is scoped only while a `use-model` declaration is
;; constructing immutable descriptors. It is not lesson state and cannot leak
;; into sampling, rendering, or another declaration.
(define current-imported-model (make-parameter #f))

;; current-model-node-ref : symbol? -> c-node?
;;   Resolves a lexical source identifier inside a hygienically lowered
;;   `use-model` declaration without relying on an unbound generated name.
(define (current-model-node-ref name)
  (model-node-ref (current-imported-model) name))

;; call-with-imported-model : calculus-model? (-> any/c) -> any/c
;;   Delimits imported-name resolution to one declaration construction.
(define (call-with-imported-model model thunk)
  (check 'use-model calculus-model? "calculus-model?" model)
  (unless (procedure? thunk) (raise-argument-error 'use-model "procedure?" thunk))
  (parameterize ([current-imported-model model]) (thunk)))

;; model-with-constraints : calculus-model? list? -> calculus-model?
;;   Retains a shared model's identities and constraints while allowing a
;;   consuming lesson to add its own held requirements.
(define (model-with-constraints model extra-constraints)
  (check 'use-model calculus-model? "calculus-model?" model)
  (unless (list? extra-constraints)
    (raise-argument-error 'use-model "list? constraints" extra-constraints))
  (make-model
   (for/list ([(name node) (in-hash (calculus-model-nodes model))])
     (cons name node))
   (append (calculus-model-constraints model) extra-constraints)))

;; make-lesson : calculus-model? list? list? list? any/c list? -> calculus-lesson?
;;   Joins a mathematical model to abstract views and exposition data.
(define (make-lesson model views roles initial timing steps)
  (check 'define-calculus-lesson calculus-model? "calculus-model?" model)
  (unless (pair? views) (raise-arguments-error 'define-calculus-lesson "requires at least one view" "views" views))
  (calculus-lesson model (make-immutable-hash views) roles initial timing (immutable-list-copy steps)))

;; make-component : symbol? list? procedure? list? list? (or/c procedure? #f) -> calculus-component?
;;   Records one lexical component builder. Its builder contains only held
;;   semantic descriptors; instantiation never creates native presentation data.
(define (make-component name inputs bindings exports constraints exposition)
  (calculus-component name inputs bindings exports constraints exposition))

;; make-step : symbol? keyword-options c-action? ... -> c-step?
;;   Constructs a validated immutable source step.
(define (make-step id #:say [say #f] #:read-delay [read-delay #f] #:duration [duration #f]
                   #:pause [pause #f] . commands)
  (unless (symbol? id) (raise-argument-error 'step "symbol?" id))
  (for ([value (in-list (filter values (list read-delay duration pause)))])
    (check 'step nonnegative-finite? "nonnegative finite seconds" value))
  (when (and duration (not (positive? duration)))
    (raise-arguments-error 'step "#:duration must be positive" "duration" duration))
  (c-step id say read-delay duration pause (immutable-list-copy commands)))

;; -------------------------------------------------------------------------
;; Headless evaluation

(define (node-raw value)
  (if (c-node? value) (c-node-data value) value))

(define (lookup-function value)
  (define raw (node-raw value))
  (cond [(or (c-function? raw) (c-piecewise? raw)) raw]
        [(and (c-object? raw) (memq (c-object-kind raw) '(restrict-function compose-functions difference-function derivative-function antiderivative-function accumulation-function linearization taylor-polynomial approximation-error procedure-function))) raw]
        [else #f]))

(define (finite-number-result value method approximate?)
  (cond [(and (real? value) (rational? value)) (defined value method approximate?)]
        [else (undefined "expression did not produce a finite real value")]))

(define (eval-domain domain environment model computation)
  (define raw (node-raw domain))
  (if (c-domain? raw)
      (defined raw)
      (undefined "expected a domain")))

(define (eval-domain-number value environment model computation)
  (result-bind (eval-raw value environment model computation)
               (lambda (number)
                 (if (finite-real? number)
                     (defined number)
                     (undefined "domain endpoint is not a finite real number")))))

(define (domain-contains? domain value environment model computation)
  (define raw (node-raw domain))
  (cond
    [(not (c-domain? raw)) (undefined "expected a domain")]
    [(not (finite-real? value)) (defined #f)]
    [else
     (define (endpoint index)
       (eval-domain-number (list-ref (c-domain-arguments raw) index) environment model computation))
     (case (c-domain-kind raw)
       [(real-line) (defined #t)]
       [(empty) (defined #f)]
       [(singleton)
        (result-bind (endpoint 0) (lambda (a) (defined (= value a))))]
       [(closed open closed-open open-closed)
        (result-bind (endpoint 0)
                     (lambda (a)
                       (result-bind (endpoint 1)
                                    (lambda (b)
                                      (cond [(> a b) (unresolved "domain endpoints are crossed")]
                                            [(eq? (c-domain-kind raw) 'closed) (defined (<= a value b))]
                                            [(eq? (c-domain-kind raw) 'open) (defined (< a value b))]
                                            [(eq? (c-domain-kind raw) 'closed-open) (defined (and (<= a value) (< value b)))]
                                            [else (defined (and (< a value) (<= value b)))])))))]
       [(integers)
        (result-bind (endpoint 0) (lambda (a)
                                     (result-bind (endpoint 1) (lambda (b)
                                                                  (defined (and (exact-integer? value) (<= a value b)))))))]
       [(neighborhood punctured-neighborhood)
        (result-bind
         (endpoint 0)
         (lambda (center)
           (result-bind
            (endpoint 1)
            (lambda (radius)
              (if (not (positive? radius))
                  (undefined "neighborhood radius must be positive")
                  (defined
                   (and (< (- center radius) value (+ center radius))
                        (or (eq? (c-domain-kind raw) 'neighborhood)
                            (not (= value center))))))))))]
       [(domain-union)
        (let loop ([items (c-domain-arguments raw)])
          (cond [(null? items) (defined #f)]
                [else (result-bind (domain-contains? (car items) value environment model computation)
                                   (lambda (inside?) (if inside? (defined #t) (loop (cdr items)))))]))]
       [(domain-intersection)
        (let loop ([items (c-domain-arguments raw)])
          (cond [(null? items) (defined #t)]
                [else (result-bind (domain-contains? (car items) value environment model computation)
                                   (lambda (inside?) (if inside? (loop (cdr items)) (defined #f))))]))]
       [(domain-except)
        (define base (first (c-domain-arguments raw)))
        (define holes (rest (c-domain-arguments raw)))
        (result-bind (domain-contains? base value environment model computation)
                     (lambda (inside?)
                       (if (not inside?) (defined #f)
                           (let loop ([items holes])
                             (cond [(null? items) (defined #t)]
                                   [else (result-bind (eval-domain-number (car items) environment model computation)
                                                      (lambda (hole) (if (= value hole) (defined #f) (loop (cdr items)))))])))))]
       [else (unresolved (format "unsupported domain kind ~a" (c-domain-kind raw)))] )]))

(define (numeric-values values)
  (andmap finite-real? values))

(define (apply-expression op values)
  (with-handlers ([exn:fail? (lambda (error) (undefined (exn-message error)))])
    (case op
      [(+) (finite-number-result (apply + values) 'definition #f)]
      [(*) (finite-number-result (apply * values) 'definition #f)]
      [(-) (finite-number-result (apply - values) 'definition #f)]
      [(/) (if (member 0 (rest values)) (undefined "division by zero") (finite-number-result (apply / values) 'definition #f))]
      [(expt) (finite-number-result (apply expt values) 'definition #f)]
      [(sqrt) (if (negative? (first values)) (undefined "square root is not real") (finite-number-result (sqrt (first values)) 'definition #f))]
      [(abs) (finite-number-result (abs (first values)) 'definition #f)]
      [(exp log sin cos tan asin acos atan)
       (finite-number-result (apply (case op [(exp) exp] [(log) log] [(sin) sin] [(cos) cos] [(tan) tan]
                                          [(asin) asin] [(acos) acos] [else atan]) values) 'definition #t)]
      [(= < <= > >=) (defined (apply (case op [(=) =] [(<) <] [(<=) <=] [(>) >] [else >=]) values))]
      [(not) (defined (not (first values)))]
      [(list) (defined (immutable-list-copy values))]
      [else (unresolved (format "unsupported scalar operation ~a" op))])))

(define (eval-expression expression environment model computation lexical)
  (match expression
    [(c-expression 'constant (list 'pi)) (defined pi 'definition #t)]
    [(c-expression 'constant (list 'e)) (defined (exp 1) 'definition #t)]
    [(c-expression 'var (list name))
     (hash-ref lexical name (lambda () (undefined (format "unbound mathematical variable ~a" name))))]
    [(c-expression 'ref (list value)) (eval-raw value environment model computation lexical)]
    [(c-expression 'if (list test consequent alternative))
     (result-bind (eval-raw test environment model computation lexical)
                  (lambda (choice) (if choice (eval-raw consequent environment model computation lexical)
                                       (eval-raw alternative environment model computation lexical))))]
    [(c-expression 'and arguments)
     (let loop ([rest arguments])
       (cond [(null? rest) (defined #t)]
             [else (result-bind (eval-raw (car rest) environment model computation lexical)
                                (lambda (value) (if value (loop (cdr rest)) (defined #f))))]))]
    [(c-expression 'or arguments)
     (let loop ([rest arguments])
       (cond [(null? rest) (defined #f)]
             [else (result-bind (eval-raw (car rest) environment model computation lexical)
                                (lambda (value) (if value (defined #t) (loop (cdr rest)))))]))]
    [(c-expression 'in-domain? (list value domain))
     (result-bind (eval-raw value environment model computation lexical)
                  (lambda (number) (domain-contains? domain number environment model computation)))]
    [(c-expression 'value-at (list function input))
     (result-bind (eval-raw input environment model computation lexical)
                  (lambda (number) (evaluate-function function number environment model computation lexical)))]
    [(c-expression 'x-coordinate (list point))
     (result-bind (eval-point point environment model computation lexical)
                  (lambda (value) (defined (car value))))]
    [(c-expression 'y-coordinate (list point))
     (result-bind (eval-point point environment model computation lexical)
                  (lambda (value) (defined (cdr value))))]
    [(c-expression 'difference-quotient (list function a h))
     (result-bind (eval-raw h environment model computation lexical)
                  (lambda (increment)
                    (if (= increment 0)
                        (undefined "difference quotient is undefined at h = 0")
                        (result-bind (eval-raw a environment model computation lexical)
                                     (lambda (base)
                                       (result-bind (evaluate-function function (+ base increment) environment model computation lexical)
                                                    (lambda (upper)
                                                      (result-bind (evaluate-function function base environment model computation lexical)
                                                                   (lambda (lower)
                                                                     (finite-number-result (/ (- upper lower) increment)
                                                                                           'definition
                                                                                           #f))))))))))]
    [(c-expression 'slope (list line)) (eval-slope line environment model computation lexical)]
    [(c-expression 'sum-value (list sum)) (eval-sum-value sum environment model computation lexical)]
    [(c-expression 'area-of (list region)) (eval-area region environment model computation lexical)]
    [(c-expression 'sequence-value (list sequence index)) (eval-sequence-value sequence index environment model computation lexical)]
    [(c-expression 'partial-sum (list sequence from to)) (eval-partial-sum sequence from to environment model computation lexical)]
    [(c-expression 'iterate-value (list iteration index)) (eval-iterate-value iteration index environment model computation lexical)]
    [(c-expression op arguments)
     (let loop ([remaining arguments] [values '()])
       (cond [(null? remaining) (apply-expression op (reverse values))]
             [else (result-bind (eval-raw (car remaining) environment model computation lexical)
                                (lambda (value) (loop (cdr remaining) (cons value values))))]))]
    [_ (undefined "invalid held expression")]))

(define (eval-node node environment model computation lexical)
  (case (c-node-kind node)
    [(parameter) (defined (hash-ref environment (c-node-id node)))]
    [(scalar part) (eval-raw (c-node-data node) environment model computation lexical)]
    [else (eval-raw (c-node-data node) environment model computation lexical)]))

(define (eval-raw value environment model computation [lexical (hash)])
  (cond [(c-node? value) (eval-node value environment model computation lexical)]
        [(c-expression? value) (eval-expression value environment model computation lexical)]
        [(c-part? value) (eval-part value environment model computation lexical)]
        [(c-object? value) (eval-object value environment model computation lexical)]
        [(or (c-function? value) (c-piecewise? value) (c-domain? value)) (defined value)]
        [(or (number? value) (boolean? value) (string? value) (symbol? value)) (defined value)]
        [(list? value)
         (let loop ([remaining value] [values '()])
           (if (null? remaining) (defined (immutable-list-copy (reverse values)))
               (result-bind (eval-raw (car remaining) environment model computation lexical)
                            (lambda (item) (loop (cdr remaining) (cons item values))))))]
        [else (unresolved "unsupported mathematical value")]))

(define (function-domain function)
  (define raw (node-raw function))
  (cond [(c-function? raw) (c-function-domain raw)]
        [(c-piecewise? raw) (c-piecewise-domain raw)]
        [(and (c-object? raw) (eq? (c-object-kind raw) 'restrict-function))
         (c-domain 'domain-intersection
                   (list (function-domain (first (c-object-arguments raw)))
                         (second (c-object-arguments raw))))]
        [(and (c-object? raw) (eq? (c-object-kind raw) 'derivative-function))
         ;; A derivative is never licensed outside the source function's
         ;; declared domain.  `#:on` may narrow that scope, but cannot restore
         ;; an excluded source input.
         (define source-domain
           (function-domain (first (c-object-arguments raw))))
         (define requested (hash-ref (c-object-options raw) 'on #f))
         (if requested
             (c-domain 'domain-intersection (list source-domain requested))
             source-domain)]
        [(and (c-object? raw) (eq? (c-object-kind raw) 'antiderivative-function))
         ;; Endpoint subtraction may only use the registered evaluator where
         ;; that evaluator itself is defined.  An optional declaration can
         ;; further restrict, never widen, this scope.
         (define using (hash-ref (c-object-options raw) 'using #f))
         (define using-domain (if using (function-domain using) calculus-real-line))
         (define requested (hash-ref (c-object-options raw) 'on #f))
         (if requested
             (c-domain 'domain-intersection (list using-domain requested))
             using-domain)]
        [(and (c-object? raw) (hash-has-key? (c-object-options raw) 'domain)) (hash-ref (c-object-options raw) 'domain)]
        [else calculus-real-line]))

(define (evaluate-function function input environment model computation [lexical (hash)])
  (define source (lookup-function function))
  (cond
    [(not source) (undefined "expected a calculus function")]
    [else
     (result-bind (domain-contains? (function-domain source) input environment model computation)
                  (lambda (inside?)
                    (if (not inside?)
                        (outside "input is outside the declared function domain")
                        (cond
                          [(c-function? source)
                           (define body (c-function-body source))
                           (cond [(c-expression? body) (eval-raw body environment model computation (hash-set lexical (c-function-variable source) (defined input)))]
                                 [(procedure? body) (with-handlers ([exn:fail? (lambda (error) (undefined (exn-message error)))])
                                                        (finite-number-result (body input) 'definition #t))]
                                 [(c-object? body) (eval-function-object body input environment model computation lexical)]
                                 [else (eval-raw body environment model computation (hash-set lexical (c-function-variable source) (defined input)))])]
                          [(c-piecewise? source)
                           (let loop ([branches (c-piecewise-branches source)])
                             (cond [(null? branches)
                                    (if (c-piecewise-else source)
                                        (eval-raw (c-piecewise-else source) environment model computation (hash-set lexical (c-piecewise-variable source) (defined input)))
                                        (undefined "no piecewise branch applies"))]
                                   [else (result-bind (eval-raw (caar branches) environment model computation (hash-set lexical (c-piecewise-variable source) (defined input)))
                                                      (lambda (matches?)
                                                        (if matches?
                                                            (eval-raw (cdar branches) environment model computation (hash-set lexical (c-piecewise-variable source) (defined input)))
                                                            (loop (cdr branches)))))]))]
                          [else (eval-function-object source input environment model computation lexical)]))))]))

(define (eval-function-object source input environment model computation lexical)
  (define args (c-object-arguments source))
  (case (c-object-kind source)
    [(restrict-function)
     (evaluate-function (first args) input environment model computation lexical)]
    [(procedure-function)
     (define provider (first args))
     (if (procedure? provider)
         (with-handlers ([exn:fail? (lambda (error) (undefined (exn-message error)))])
           (finite-number-result (provider input) 'definition #t))
         (unresolved "procedure-function provider is not a procedure"))]
    [(compose-functions)
     (result-bind (evaluate-function (second args) input environment model computation lexical)
                  (lambda (inner) (evaluate-function (first args) inner environment model computation lexical)))]
    [(difference-function)
     (result-bind (evaluate-function (first args) input environment model computation lexical)
                  (lambda (left) (result-bind (evaluate-function (second args) input environment model computation lexical)
                                               (lambda (right) (finite-number-result (- left right) 'definition #f)))))]
    [(derivative-function)
     (eval-derivative source input environment model computation lexical)]
    [(antiderivative-function)
     (evaluate-function (hash-ref (c-object-options source) 'using) input environment model computation lexical)]
    [(accumulation-function)
     (eval-integral (first args) (hash-ref (c-object-options source) 'from) input
                    (hash-ref (c-object-options source) 'antiderivative #f) environment model computation lexical)]
    [(linearization)
     (define function (first args))
     (define base (hash-ref (c-object-options source) 'at))
     (define derivative (hash-ref (c-object-options source) 'derivative))
     (if (not (derivative-compatible? function derivative))
         (unresolved "linearization derivative must be declared for its function")
         (result-bind (eval-raw base environment model computation lexical)
                      (lambda (a)
                        (result-bind (evaluate-function function a environment model computation lexical)
                                     (lambda (fa)
                                       (result-bind (evaluate-function derivative a environment model computation lexical)
                                                    (lambda (slope) (finite-number-result (+ fa (* slope (- input a))) 'definition #f))))))))]
    [(taylor-polynomial)
     (define function (first args))
     (define base (hash-ref (c-object-options source) 'at #f))
     (define derivative-expression (hash-ref (c-object-options source) 'derivatives '()))
     (result-bind
      (eval-raw base environment model computation lexical)
      (lambda (a)
        (result-bind
         (evaluate-function function a environment model computation lexical)
         (lambda (fa)
           (result-bind
            (eval-raw derivative-expression environment model computation lexical)
            (lambda (derivatives)
              (cond
                [(not (list? derivatives)) (undefined "taylor-polynomial #:derivatives must be a list")]
                [(not (andmap (lambda (derivative) (derivative-compatible? function derivative)) derivatives))
                 (unresolved "Taylor derivatives must be declared for the polynomial function")]
                [else
                 (let loop ([order 1] [remaining derivatives] [total fa])
                   (if (null? remaining)
                       (finite-number-result total 'definition #f)
                       (result-bind
                        (evaluate-function (car remaining) a environment model computation lexical)
                        (lambda (value)
                          (loop (add1 order)
                                (cdr remaining)
                                (+ total
                                   (/ (* value (expt (- input a) order))
                                      (natural-factorial order))))))))])))))))]
    [(approximation-error)
     (result-bind (evaluate-function (first args) input environment model computation lexical)
                  (lambda (left) (result-bind (evaluate-function (second args) input environment model computation lexical)
                                               (lambda (right) (finite-number-result (- left right) 'definition #f)))))]
    [else (unresolved (format "unsupported function operation ~a" (c-object-kind source)))]))

;; natural-factorial : exact-nonnegative-integer? -> exact-positive-integer?
;;   Supplies the exact Taylor-series denominator without native dependencies.
(define (natural-factorial value)
  (for/fold ([product 1]) ([factor (in-range 1 (add1 value))])
    (* product factor)))

;; differentiate : any/c symbol? -> (or/c c-expression? finite-real? #f)
;;   Builds the documented conservative symbolic derivative for a held expression.
(define (differentiate expression variable)
  ;; `#f` is the one internal marker for an unsupported rule.  It must be
  ;; propagated before a new arithmetic expression is built: leaving it as a
  ;; child would let a later pass mistake the failure for a constant.
  (define (supported? derivative) (not (eq? derivative #f)))
  (define (all-supported derivatives)
    (and (andmap supported? derivatives) derivatives))
  (cond
    [(number? expression) 0]
    [(and (c-expression? expression)
          (eq? (c-expression-op expression) 'var)
          (eq? (first (c-expression-arguments expression)) variable))
     1]
    [(c-expression? expression)
     (define op (c-expression-op expression))
     (define arguments (c-expression-arguments expression))
     (define (expression* name . items) (c-expression name items))
     (case op
       [(var) 0]
       [(+)
        (define derivatives (all-supported (map (lambda (item) (differentiate item variable)) arguments)))
        (and derivatives (apply expression* '+ derivatives))]
       [(-)
        (define derivatives (all-supported (map (lambda (item) (differentiate item variable)) arguments)))
        (and derivatives (apply expression* '- derivatives))]
       [(*)
        (if (null? arguments)
            0
            (let ([derivatives
                   (all-supported
                    (map (lambda (item) (differentiate item variable)) arguments))])
              (and derivatives
                   (apply expression* '+
                          (for/list ([index (in-range (length arguments))])
                            (apply expression* '*
                                   (for/list ([item (in-list arguments)]
                                              [position (in-naturals)])
                                     (if (= index position)
                                         (list-ref derivatives position)
                                         item))))))))]
       [(expt)
        (cond
          [(not (and (= (length arguments) 2) (exact-integer? (second arguments)))) #f]
          [(zero? (second arguments)) 0]
          [else
           (define base-derivative (differentiate (first arguments) variable))
           (and (supported? base-derivative)
                (expression* '* (second arguments)
                             (expression* 'expt (first arguments) (sub1 (second arguments)))
                             base-derivative))])]
       [(/)
        (cond
          [(= (length arguments) 1)
           (define numerator-derivative (differentiate (first arguments) variable))
           (and (supported? numerator-derivative)
                (expression* '/
                             (expression* '* -1 numerator-derivative)
                             (expression* 'expt (first arguments) 2)))]
          [(= (length arguments) 2)
           (define numerator (first arguments))
           (define denominator (second arguments))
           (define numerator-derivative (differentiate numerator variable))
           (define denominator-derivative (differentiate denominator variable))
           (and (supported? numerator-derivative)
                (supported? denominator-derivative)
                (expression* '/
                             (expression* '-
                                          (expression* '* numerator-derivative denominator)
                                          (expression* '* numerator denominator-derivative))
                             (expression* 'expt denominator 2)))]
          [else #f])]
       [(sin cos exp log sqrt)
        (define operand-derivative (differentiate (first arguments) variable))
        (and (supported? operand-derivative)
             (case op
               [(sin) (expression* '* (expression* 'cos (first arguments)) operand-derivative)]
               [(cos) (expression* '* -1 (expression* 'sin (first arguments)) operand-derivative)]
               [(exp) (expression* '* (expression* 'exp (first arguments)) operand-derivative)]
               [(log) (expression* '/ operand-derivative (first arguments))]
               [else (expression* '/ operand-derivative
                                  (expression* '* 2 (expression* 'sqrt (first arguments))))]))]
       [else #f])]
    [else 0]))

;; differentiate-order : any/c symbol? exact-positive-integer? -> (or/c c-expression? finite-real? #f)
;;   Applies the structural derivative rule the requested number of times,
;;   retaining `#f` when any intermediate expression is unsupported.
(define (differentiate-order expression variable order)
  (let loop ([remaining order] [current expression])
    (cond [(zero? remaining) current]
          [else
           (define next (differentiate current variable))
           (and next (loop (sub1 remaining) next))])))

(define (eval-derivative descriptor input environment model computation lexical)
  (define source (first (c-object-arguments descriptor)))
  (define options (c-object-options descriptor))
  (define method (hash-ref options 'method 'symbolic))
  (define order (hash-ref options 'order 1))
  (cond
    [(not (exact-positive-integer? order))
     (undefined "derivative #:order must be a positive exact integer")]
    [else
     (case method
       [(supplied)
        (result-with-method
         (evaluate-function (hash-ref options 'using) input environment model computation lexical)
         'supplied)]
       [(numeric)
        (cond
          [(not (= order 1))
           (unresolved "numeric differentiation supports only first derivatives" 'numeric)]
          [else
           (define initial-step
             (hash-ref options 'step
                       (calculus-computation-data-derivative-step computation)))
           (define absolute (calculus-computation-data-absolute-tolerance computation))
           (define relative (calculus-computation-data-relative-tolerance computation))
           ;; A single finite difference is evidence, not certification.
           ;; Compare a centered estimate with its half step and with both
           ;; one-sided slopes so a symmetric cancellation at a corner cannot
           ;; masquerade as a two-sided derivative.
           (let loop ([h initial-step] [remaining 24])
             (define (centered step)
               (result-bind
                (evaluate-function source (+ input step) environment model computation lexical)
                (lambda (right)
                  (result-bind
                   (evaluate-function source (- input step) environment model computation lexical)
                   (lambda (left)
                     (finite-number-result (/ (- right left) (* 2 step)) 'numeric #t))))))
             (define (one-sided step)
               (result-bind
                (evaluate-function source input environment model computation lexical)
                (lambda (center)
                  (result-bind
                   (evaluate-function source (+ input step) environment model computation lexical)
                   (lambda (right)
                     (result-bind
                      (evaluate-function source (- input step) environment model computation lexical)
                      (lambda (left)
                        (defined (list (/ (- right center) step)
                                       (/ (- center left) step))))))))))
             (result-bind
              (centered h)
              (lambda (coarse)
                (result-bind
                 (centered (/ h 2))
                 (lambda (fine)
                   (result-bind
                    (one-sided (/ h 2))
                    (lambda (sides)
                      (define right-slope (first sides))
                      (define left-slope (second sides))
                      (define tolerance
                        (+ absolute
                           (* relative
                              (max (abs coarse) (abs fine)
                                   (abs right-slope) (abs left-slope)))))
                      (cond
                        [(and (<= (abs (- fine coarse)) tolerance)
                              (<= (abs (- right-slope left-slope)) tolerance))
                         (finite-number-result fine 'numeric #t)]
                        [(zero? remaining)
                         (unresolved "numeric derivative did not establish a stable two-sided slope" 'numeric)]
                        [else (loop (/ h 2) (sub1 remaining))]))))))))])]
       [else
        (define source-function (lookup-function source))
        (if (c-function? source-function)
            (let ([derived (differentiate-order (c-function-body source-function)
                                                (c-function-variable source-function) order)])
              (if derived
                  (result-with-method
                   (eval-raw derived environment model computation
                             (hash-set lexical (c-function-variable source-function) (defined input)))
                   'symbolic)
                  (unresolved "symbolic differentiation is unsupported for this expression" 'symbolic)))
            (unresolved "symbolic differentiation requires a held function" 'symbolic))])]))

;; graph-function : semantic-value? -> (or/c semantic-value? #f)
;;   Resolves a graph restriction through its source graph rather than treating
;; the graph record itself as a function descriptor.
(define (graph-function graph)
  (define source (node-raw graph))
  (cond [(not (c-object? source)) #f]
        [(eq? (c-object-kind source) 'graph)
         (and (pair? (c-object-arguments source))
              (first (c-object-arguments source)))]
        [(eq? (c-object-kind source) 'graph-restriction)
         (and (pair? (c-object-arguments source))
              (graph-function (first (c-object-arguments source))))]
        [else #f]))

;; calculus-graph-source-function : semantic-value? -> (or/c semantic-value? #f)
;;   Private adapter bridge for topology metadata such as ordered piecewise
;; branches. Mathematical values remain available only through snapshot calls.
(define (calculus-graph-source-function graph)
  (graph-function graph))

;; calculus-graph-parameter-dependencies : calculus-lesson? semantic-value?
;;                                         -> (listof symbol?)
;;   Returns the direct and transitive writable parameter identities used by a
;; graph descriptor.  The native adapter uses this immutable dependency fact to
;; precompute only graph geometry that cannot change during the lesson; it does
;; not expose model internals through the public calculus API.
(define (calculus-graph-parameter-dependencies lesson graph)
  (check 'calculus-graph-parameter-dependencies calculus-lesson? "calculus-lesson?" lesson)
  (define nodes (calculus-model-nodes (calculus-lesson-model lesson)))
  (define seen (make-hash))
  (define dependencies '())
  (define (visit value)
    (for ([identifier (in-list (semantic-node-identifiers value))])
      (unless (hash-ref seen identifier #f)
        (hash-set! seen identifier #t)
        (define node (hash-ref nodes identifier #f))
        (when node
          (if (eq? (c-node-kind node) 'parameter)
              (set! dependencies (cons identifier dependencies))
              (visit (c-node-data node)))))))
  (visit graph)
  (sort (remove-duplicates dependencies) symbol<?))

;; graph-domain : semantic-value? -> c-domain?
;;   Combines the graph's own declared domain with every explicit graph
;; restriction. This preserves a restriction as mathematical membership, not a
;; merely native clipping preference.
(define (graph-domain graph)
  (define source (node-raw graph))
  (cond [(not (c-object? source)) calculus-real-line]
        [(eq? (c-object-kind source) 'graph)
         (define function (graph-function graph))
         (hash-ref (c-object-options source) 'on
                   (function-domain (or (lookup-function function) function)))]
        [(eq? (c-object-kind source) 'graph-restriction)
         (define arguments (c-object-arguments source))
         (if (>= (length arguments) 2)
             (c-domain 'domain-intersection
                       (list (graph-domain (first arguments)) (second arguments)))
             calculus-real-line)]
        [else calculus-real-line]))

;; evaluate-graph : semantic-value? finite-real? hash? calculus-model?
;;                  calculus-computation? [hash?] -> calculus-result?
;;   Evaluates a graph only inside its composed declared restriction before
;; asking its held source function for a value.
(define (evaluate-graph graph input environment model computation [lexical (hash)])
  (define function (graph-function graph))
  (cond [(not function) (undefined "expected a calculus graph")]
        [else
         (result-bind
          (domain-contains? (graph-domain graph) input environment model computation)
          (lambda (inside?)
            (if inside?
                (evaluate-function function input environment model computation lexical)
                (outside "input is outside the declared graph domain"))))]))

;; scalar-equivalent? : finite-real? finite-real? calculus-computation? -> boolean?
;;   Preserves exact equality while making an explicitly inexact candidate's
;;   residual subject to the mathematical—not graphical—tolerance policy.
(define (scalar-equivalent? left right computation)
  (or (= left right)
      (and (or (inexact? left) (inexact? right))
           (<= (abs (- left right))
               (+ (calculus-computation-data-absolute-tolerance computation)
                  (* (calculus-computation-data-relative-tolerance computation)
                     (max (abs left) (abs right))))))))

;; eval-level-set : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Validates explicitly supplied candidates and deliberately performs no root search.
(define (eval-level-set solutions environment model computation lexical)
  (define raw (node-raw solutions))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'level-set)))
      (undefined "expected a level set")
      (let ([function (first (c-object-arguments raw))]
            [target (second (c-object-arguments raw))]
            [within (hash-ref (c-object-options raw) 'within #f)]
            [inputs (hash-ref (c-object-options raw) 'inputs #f)]
            [completeness (hash-ref (c-object-options raw) 'completeness 'selected)]
            [justification (hash-ref (c-object-options raw) 'justification #f)])
        (cond
          [(not (and within inputs)) (undefined "level set requires #:within and #:inputs")]
          [else
           (result-bind
            (eval-raw target environment model computation lexical)
            (lambda (output)
              (result-bind
               (eval-raw inputs environment model computation lexical)
               (lambda (candidates)
                 (if (not (and (finite-real? output) (list? candidates)
                               (andmap finite-real? candidates)))
                     (undefined "level-set targets and inputs must be finite real values")
                     (let loop ([remaining candidates] [validated '()])
                       (cond
                         [(null? remaining)
                          (if (and (null? candidates) (eq? completeness 'all) (not justification))
                              (unresolved "an empty complete level set needs a justification")
                              (defined (immutable-list-copy (reverse validated))))]
                         [else
                          (define candidate (car remaining))
                          (result-bind
                           (domain-contains? within candidate environment model computation)
                           (lambda (inside?)
                             (if (not inside?)
                                 (undefined "level-set candidate is outside #:within")
                                 (result-bind
                                  (evaluate-function function candidate environment model computation lexical)
                                  (lambda (value)
                                    (if (scalar-equivalent? value output computation)
                                        (loop (cdr remaining) (cons candidate validated))
                                        (undefined "level-set candidate does not satisfy the supplied output")))))))])))))))]))))

;; eval-solution-inputs : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Projects the already validated, source-ordered candidate input list.
(define (eval-solution-inputs descriptor environment model computation lexical)
  (define raw (node-raw descriptor))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'solution-inputs)))
      (undefined "expected solution inputs")
      (eval-raw (first (c-object-arguments raw)) environment model computation lexical)))

(define (eval-point point environment model computation lexical)
  (cond
    ;; Public parts retain their source identity, but point consumers require
    ;; the point value owned by that source.  Resolve the part once rather
    ;; than rejecting its wrapper or manufacturing a detached replacement.
    [(c-part? point) (eval-part point environment model computation lexical)]
    ;; Binding a public part introduces a scalar `ref` alias.  Geometric
    ;; consumers follow that alias so `(x-coordinate P)` agrees with the
    ;; direct `(x-coordinate (part R 'point))` spelling.
    [(and (c-node? point)
          (or (c-expression? (c-node-data point))
              (c-part? (c-node-data point))))
     (result-bind
      (eval-raw point environment model computation lexical)
      (lambda (value)
        (if (and (pair? value) (finite-real? (car value)) (finite-real? (cdr value)))
            (defined value)
            (undefined "named value does not resolve to a point"))))]
    [else
     (define raw (node-raw point))
     (cond
    [(and (pair? raw) (finite-real? (car raw)) (finite-real? (cdr raw))) (defined raw)]
    [(not (c-object? raw)) (undefined "expected a point")]
    [else
     (define args (c-object-arguments raw))
     (define options (c-object-options raw))
     (case (c-object-kind raw)
       [(point)
        (result-bind (eval-raw (first args) environment model computation lexical)
                     (lambda (x) (result-bind (eval-raw (second args) environment model computation lexical)
                                              (lambda (y) (defined (cons x y))))))]
       [(point-on)
        (define graph (first args))
        (result-bind (eval-raw (hash-ref options 'x) environment model computation lexical)
                     (lambda (x) (result-bind (evaluate-graph graph x environment model computation lexical)
                                              (lambda (y) (defined (cons x y))))))]
       [(axis-point)
        (result-bind (eval-raw (second args) environment model computation lexical)
                     (lambda (value) (defined (if (eq? (first args) 'x) (cons value 0) (cons 0 value)))))]
       [(projection)
        (result-bind (eval-point (first args) environment model computation lexical)
                     (lambda (p) (defined (if (eq? (hash-ref options 'onto) 'x) (cons (car p) 0) (cons 0 (cdr p))))))]
       [(root-point)
        (define graph (first args))
        (define x (hash-ref options 'x))
        (result-bind (eval-raw x environment model computation lexical)
                     (lambda (v) (result-bind (evaluate-graph graph v environment model computation lexical)
                                               (lambda (y) (if (scalar-equivalent? y 0 computation)
                                                               (defined (cons v y))
                                                               (unresolved "candidate is not a root"))))))]
       [(intersection-point)
        (define x (hash-ref options 'x))
        (result-bind (eval-raw x environment model computation lexical)
                     (lambda (v)
                       (result-bind (evaluate-graph (first args) v environment model computation lexical)
                                    (lambda (left)
                                      (result-bind (evaluate-graph (second args) v environment model computation lexical)
                                                   (lambda (right)
                                                     (if (scalar-equivalent? left right computation)
                                                         (defined (cons v left))
                                                         (unresolved "candidate is not an intersection"))))))))]
       [(point-on-line)
        (result-bind (eval-line (first args) environment model computation lexical)
                     (lambda (line)
                       (cond
                         [(eq? (car line) 'vertical)
                          (undefined "x does not select a point on a vertical line")]
                         [(not (eq? (car line) 'line))
                          (undefined "point-on-line requires an infinite line")]
                         [else
                          (result-bind (eval-raw (hash-ref options 'x) environment model computation lexical)
                                       (lambda (x) (defined (cons x (+ (third line) (* (second line) x))))))])))]
       [else (undefined (format "unsupported point kind ~a" (c-object-kind raw)))] )])]))

(define (line-through-points p q kind)
  (if (equal? p q)
      (if (memq kind '(segment chord))
          (defined (list 'segment p q))
          (undefined "coincident points do not determine a line"))
      (let ([dx (- (car q) (car p))] [dy (- (cdr q) (cdr p))])
        (case kind
          [(segment chord) (defined (list 'segment p q))]
          [(ray-through) (defined (list 'ray p q))]
          [else
           (if (= dx 0) (defined (list 'vertical (car p) p))
               (defined (list 'line (/ dy dx) (- (cdr p) (* (/ dy dx) (car p))) p)))]))))

(define (eval-line line environment model computation lexical)
  (cond
    [(c-part? line) (eval-part line environment model computation lexical)]
    [(and (c-node? line)
          (or (c-expression? (c-node-data line))
              (c-part? (c-node-data line))))
     (result-bind
      (eval-raw line environment model computation lexical)
      (lambda (value)
        (if (and (list? value) (pair? value)
                 (memq (first value) '(line vertical segment ray)))
            (defined value)
            (undefined "named value does not resolve to a line"))))]
    [else
     (define raw (node-raw line))
     (if (not (c-object? raw)) (undefined "expected a line")
      (let ([args (c-object-arguments raw)] [options (c-object-options raw)])
        (case (c-object-kind raw)
          [(line-through ray-through secant chord segment)
           (result-bind (eval-point (if (memq (c-object-kind raw) '(secant chord)) (second args) (first args)) environment model computation lexical)
                        (lambda (p) (result-bind (eval-point (if (memq (c-object-kind raw) '(secant chord)) (third args) (second args)) environment model computation lexical)
                                                 (lambda (q) (line-through-points p q (c-object-kind raw))))))]
          [(horizontal-line) (result-bind (eval-raw (first args) environment model computation lexical) (lambda (y) (defined (list 'line 0 y (cons 0 y)))))]
          [(vertical-line) (result-bind (eval-raw (first args) environment model computation lexical) (lambda (x) (defined (list 'vertical x (cons x 0)))))]
          [(tangent)
           (define graph (first args))
           (define derivative (hash-ref options 'derivative #f))
           (if (not (derivative-compatible? (graph-function graph) derivative))
               (undefined "tangent derivative must be declared for the graph function")
               (result-bind
                (eval-point (hash-ref options 'at) environment model computation lexical)
                (lambda (p)
                  (result-bind
                   (evaluate-function derivative (car p) environment model computation lexical)
                   (lambda (m) (defined (list 'line m (- (cdr p) (* m (car p))) p)))))))]
          [(vertical-tangent)
           (if (not (nonempty-justification? (hash-ref options 'justification #f)))
               (undefined "vertical-tangent requires a nonempty #:justification")
               (result-bind (eval-point (hash-ref options 'at) environment model computation lexical)
                            (lambda (p) (defined (list 'vertical (car p) p)))))]
          [(normal)
           (result-bind (eval-line (first args) environment model computation lexical)
                        (lambda (source)
                          (if (eq? (car source) 'vertical)
                              (defined (list 'line 0 (cdr (third source)) (third source)))
                              (if (= (second source) 0)
                                  (defined (list 'vertical (car (fourth source)) (fourth source)))
                                  ;; Finite lines store `(line slope intercept
                                  ;; anchor)`: their third field is not a
                                  ;; point.  All normal cases retain the
                                  ;; original anchor so the perpendicular
                                  ;; construction passes through it.
                                  (let ([anchor (fourth source)])
                                    (defined (list 'line
                                                   (/ -1 (second source))
                                                   (- (cdr anchor)
                                                      (* (/ -1 (second source))
                                                         (car anchor)))
                                                   anchor)))))))]
          [else (undefined "expected a line")])))]))

(define (eval-slope line environment model computation lexical)
  (result-bind (eval-line line environment model computation lexical)
               (lambda (value)
                 (case (car value)
                   [(vertical) (undefined "vertical line has no finite slope")]
                   [(line) (defined (second value))]
                   [(segment)
                    (define p (second value))
                    (define q (third value))
                    (define dx (- (car q) (car p)))
                    (if (= dx 0)
                        (undefined "vertical segment has no finite slope")
                        (defined (/ (- (cdr q) (cdr p)) dx)))]
                   [else (undefined "slope requires a line or segment")]))))

;; eval-error-segment : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Joins two graph values at one exact mathematical input, preserving error sign.
(define (eval-error-segment segment environment model computation lexical)
  (define raw (node-raw segment))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'error-segment)))
      (undefined "expected an error segment")
      (let ([left (first (c-object-arguments raw))]
            [right (second (c-object-arguments raw))]
            [input (hash-ref (c-object-options raw) 'at #f)])
        (cond
          [(not (and (graph-function left) (graph-function right)))
           (undefined "error-segment requires two graphs")]
          [else
           (result-bind
            (eval-raw input environment model computation lexical)
            (lambda (x)
              (result-bind
               (evaluate-graph left x environment model computation lexical)
               (lambda (left-value)
                 (result-bind
                  (evaluate-graph right x environment model computation lexical)
                  (lambda (right-value)
                    (defined (list 'segment (cons x left-value) (cons x right-value)))))))))]))))

;; eval-slope-triangle-geometry : semantic-value? hash? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Builds directed mathematical legs for an increment or a selected finite line run.
(define (eval-slope-triangle-geometry source options environment model computation lexical)
  (define raw (node-raw source))
  (if (and (c-object? raw) (eq? (c-object-kind raw) 'increment))
      (result-bind
       (eval-raw (c-object-arguments raw) environment model computation lexical)
       (lambda (points)
         (match points
           [(list from to)
            (defined (list from to (cons (car to) (cdr from))
                           (- (car to) (car from)) (- (cdr to) (cdr from))))]
           [_ (undefined "increment slope-triangle requires two points")])))
      (result-bind
       (eval-line source environment model computation lexical)
       (lambda (line)
         (if (eq? (car line) 'vertical)
             (undefined "a slope triangle requires a nonvertical line")
             (result-bind
              (eval-raw (list (hash-ref options 'at #f) (hash-ref options 'run #f))
                        environment model computation lexical)
              (lambda (values)
                (match values
                  [(list from run)
                   (if (not (and (finite-real? run) (not (= run 0))
                                 (scalar-equivalent? (cdr from)
                                                     (+ (* (second line) (car from)) (third line))
                                                     computation)))
                       (undefined "slope-triangle needs a nonzero run at a point on its line")
                       (let ([to (cons (+ (car from) run)
                                       (+ (cdr from) (* (second line) run)))])
                         (defined (list from to (cons (car to) (cdr from))
                                        run (* (second line) run)))))]
                  [_ (undefined "line slope-triangle requires a point and run")]))))))))

;; eval-slope-triangle : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Validates labels and mathematical geometry before presentation reads its parts.
(define (eval-slope-triangle triangle environment model computation lexical)
  (define raw (node-raw triangle))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'slope-triangle)))
      (undefined "expected a slope triangle")
      (let ([labels (hash-ref (c-object-options raw) 'labels 'symbolic)])
        (if (not (memq labels '(symbolic numeric both #f)))
            (undefined "slope-triangle has an unsupported #:labels value")
            (result-bind
             (eval-slope-triangle-geometry (first (c-object-arguments raw))
                                           (c-object-options raw)
                                           environment model computation lexical)
             (lambda (_) (defined raw)))))))

(define (component-instance-model instance)
  (define raw (node-raw instance))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'use-component)))
     (undefined "expected a component instance")]
    [(null? (c-object-arguments raw))
     (undefined "use-component requires a component declaration")]
    [else
     (define component (first (c-object-arguments raw)))
     (define supplied (rest (c-object-arguments raw)))
     (cond
       [(not (calculus-component? component))
        (undefined "use-component requires a calculus component")]
       [(not (= (length supplied) (length (calculus-component-inputs component))))
        (undefined "use-component received the wrong number of inputs")]
       [(not (procedure? (calculus-component-bindings component)))
        (undefined "component has no lexical model builder")]
       [else
        (with-handlers ([exn:fail?
                         (lambda (error)
                           (undefined (format "component instantiation failed: ~a"
                                              (exn-message error))))])
          (define private-model
            (apply (calculus-component-bindings component) supplied))
          (if (calculus-model? private-model)
              (defined private-model)
              (undefined "component builder did not produce a calculus model")))] )]))

;; component-instance-exposition : c-node? -> calculus-result?
;;   Materializes an expanded component's private steps in the component's
;;   lexical scope.  This is deliberately separate from model construction:
;;   an explanation has no authority to mutate caller-owned capabilities.
(define (component-instance-exposition instance)
  (define raw (and (c-node? instance) (node-raw instance)))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'use-component)))
     (undefined "expected a component instance")]
    [(null? (c-object-arguments raw))
     (undefined "use-component requires a component declaration")]
    [else
     (define component (first (c-object-arguments raw)))
     (define supplied (rest (c-object-arguments raw)))
     (define exposition
       (and (calculus-component? component)
            (calculus-component-exposition component)))
     (cond
       [(not (calculus-component? component))
        (undefined "use-component requires a calculus component")]
       [(not (procedure? exposition))
        (undefined "component has no expanded exposition")]
       [else
        (with-handlers ([exn:fail?
                         (lambda (error)
                           (undefined (format "component exposition failed: ~a"
                                              (exn-message error))))])
          (define steps (apply exposition supplied))
          (if (and (list? steps) (andmap c-step? steps))
              (defined (immutable-list-copy steps))
              (undefined "component exposition did not produce steps")))])]))

;; component-input-kind-valid? : symbol? semantic-value? -> boolean?
;;   Performs the narrow structural input checks that are meaningful before a
;;   snapshot supplies scalar values. Evaluation and component constraints give
;;   the corresponding value-level diagnostics later.
(define (component-input-kind-valid? type value)
  (cond
    [(and (list? type) (= (length type) 2) (eq? (first type) 'Parameter))
     (and (c-node? value)
          (eq? (c-node-kind value) 'parameter)
          (let ([kind (c-param-spec-kind (c-node-data value))])
            (case (second type)
              [(Scalar) (eq? kind 'real)]
              [(Integer) (eq? kind 'integer)]
              [else #f])))]
    [else
     (case type
       [(Graph) (and (graph-function value) #t)]
       [(Function) (and (lookup-function value) #t)]
       [(Parameter) (and (c-node? value) (eq? (c-node-kind value) 'parameter))]
       [(Point) (or (and (c-node? value)
                         (memq (c-node-kind value)
                               '(point point-on axis-point projection root-point intersection-point)))
                    (and (c-object? value)
                         (memq (c-object-kind value)
                               '(point point-on axis-point projection root-point intersection-point))))]
       [(Scalar)
        (or (number? value)
            (c-expression? value)
            (and (c-node? value) (memq (c-node-kind value) '(scalar parameter part)))
            (and (c-part? value) #t))]
       [else #f])]))

;; component-instance-valid? : semantic-value? calculus-model? ... -> calculus-result?
;;   Checks declared input categories and held component constraints without
;;   permitting an instance to mutate any caller-owned input capability.
(define (component-instance-valid? instance environment model computation lexical)
  (result-bind
   (component-instance-model instance)
   (lambda (private-model)
     (define raw (node-raw instance))
     (define component (first (c-object-arguments raw)))
     (define supplied (rest (c-object-arguments raw)))
     (define input-valid?
       (for/and ([declaration (in-list (calculus-component-inputs component))]
                 [value (in-list supplied)])
         (and (pair? declaration)
              (component-input-kind-valid? (cdr declaration) value))))
     (cond
       [(not input-valid?)
        (undefined "use-component input does not satisfy its declared type")]
       [else
        (let loop ([constraints (calculus-model-constraints private-model)])
          (cond
            [(null? constraints) (defined private-model)]
            [else
             (result-bind
              (eval-raw (car constraints) environment private-model computation lexical)
              (lambda (satisfied?)
                (if satisfied?
                    (loop (cdr constraints))
                    (unresolved "component constraint failed"))))]))]))))

;; calculus-component-part-node : c-part? -> (or/c c-node? #f)
;;   Gives the native adapter the declared kind of one public component export
;;   without evaluating its values or crossing the semantic/native boundary.
(define (calculus-component-part-node part)
  (and (c-part? part)
       (symbol? (c-part-name part))
       (let ([parent (c-part-parent part)])
         (and (c-node? parent)
              (let ([raw (node-raw parent)])
                (and (c-object? raw)
                     (eq? (c-object-kind raw) 'use-component)
                     (pair? (c-object-arguments raw))
                     (let ([component (first (c-object-arguments raw))])
                       (and (calculus-component? component)
                            (member (c-part-name part) (calculus-component-exports component))
                            (let ([instance-result (component-instance-model parent)])
                              (and (eq? (calculus-result-status instance-result) 'defined)
                                   (hash-ref (calculus-model-nodes
                                              (calculus-result-value instance-result))
                                             (c-part-name part)
                                             #f)))))))))))

;; component-private-part-address : c-part? -> (or/c (listof symbol?) #f)
;;   Decodes the renderer-only `(private ...)` presentation path. This path is
;;   intentionally not accepted by `part` evaluation or public inspection.
(define (component-private-part-address part)
  (and (c-part? part)
       (c-node? (c-part-parent part))
       (let ([name (c-part-name part)])
         (and (list? name)
              (>= (length name) 2)
              (eq? (first name) 'private)
              (andmap symbol? (rest name))
              (rest name)))))

;; calculus-component-private-part-node : c-part? -> (or/c c-node? #f)
;;   Supplies native preparation with a private component object's kind only
;;   while an expanded explanation has made its namespaced presentation live.
;;   It does not turn that object into a public address.
(define (calculus-component-private-part-node part)
  (define private-address (component-private-part-address part))
  (and private-address
       (let ([instance-result (component-instance-model (c-part-parent part))])
         (and (eq? (calculus-result-status instance-result) 'defined)
              (hash-ref (calculus-model-nodes (calculus-result-value instance-result))
                        (first private-address)
                        #f)))))

;; calculus-component-private-presentation-parts : c-node? -> list?
;;   Enumerates namespaced private presentation leaves for native preparation.
;;   The public model never receives these paths, and visibility still decides
;;   whether a particular expanded explanation presents one of them.
(define (calculus-component-private-presentation-parts instance)
  (define raw (and (c-node? instance) (node-raw instance)))
  (cond
    [(not (and (c-object? raw)
               (eq? (c-object-kind raw) 'use-component)
               (pair? (c-object-arguments raw))))
     '()]
    [else
     (define component (first (c-object-arguments raw)))
     (define instance-result (component-instance-model instance))
     (if (and (calculus-component? component)
              (eq? (calculus-result-status instance-result) 'defined))
         (for/list ([name (in-list (sort (hash-keys
                                          (calculus-model-nodes
                                           (calculus-result-value instance-result)))
                                         symbol<?))]
                    #:unless (or (member name (calculus-component-exports component))
                                 (member name (map car (calculus-component-inputs component)))))
           (c-part instance (list 'private name)))
         '())]))

;; component-instance-export-name : c-node? semantic-target? -> (or/c symbol? #f)
;;   Finds the first public component export beneath `instance`, preserving
;;   nested public parts as presentations of that export rather than treating
;;   them as unrelated caller-owned objects.
(define (component-instance-export-name instance target)
  (cond
    [(not (c-part? target)) #f]
    [(eq? (c-part-parent target) instance)
     (and (symbol? (c-part-name target)) (c-part-name target))]
    [else (component-instance-export-name instance (c-part-parent target))]))

;; semantic-node-identifiers : semantic-value? -> (listof symbol?)
;;   Collects direct semantic dependencies from a held descriptor without
;;   evaluating them. It is used to select a component private object's
;;   compatible public placement and to determine conservative native cache
;;   invalidation; neither use infers mathematics or geometry from samples.
(define (semantic-node-identifiers value)
  (cond
    [(c-node? value) (list (c-node-id value))]
    [(c-part? value) (semantic-node-identifiers (c-part-parent value))]
    [(c-function? value)
     (append (semantic-node-identifiers (c-function-body value))
             (semantic-node-identifiers (c-function-domain value)))]
    [(c-piecewise? value)
     (append (append-map semantic-node-identifiers (c-piecewise-branches value))
             (semantic-node-identifiers (c-piecewise-else value))
             (semantic-node-identifiers (c-piecewise-domain value)))]
    [(c-expression? value)
     (append-map semantic-node-identifiers (c-expression-arguments value))]
    [(c-domain? value)
     (append-map semantic-node-identifiers (c-domain-arguments value))]
    [(c-object? value)
     (append (append-map semantic-node-identifiers (c-object-arguments value))
             (append-map semantic-node-identifiers
                         (hash-values (c-object-options value))))]
    [(pair? value)
     (append (semantic-node-identifiers (car value))
             (semantic-node-identifiers (cdr value)))]
    [else '()]))

;; component-private-related-exports : c-part? -> (listof symbol?)
;;   Relates a private construction to the component exports that occur in its
;;   held declaration. A private object with no such relation cannot be placed
;;   in a caller graph view without inventing a presentation policy.
(define (component-private-related-exports part)
  (define instance (and (c-part? part) (c-part-parent part)))
  (define raw (and (c-node? instance) (node-raw instance)))
  (define component
    (and (c-object? raw) (pair? (c-object-arguments raw))
         (first (c-object-arguments raw))))
  (define private-node (and instance (calculus-component-private-part-node part)))
  (if (and (calculus-component? component) private-node)
      (filter (lambda (name) (member name (calculus-component-exports component)))
              (remove-duplicates
               (semantic-node-identifiers (node-raw private-node))))
      '()))

;; calculus-component-private-presentation-view-names : calculus-lesson? c-node? c-part?
;;                                                      -> (listof symbol?)
;;   Lists the unique graph-view candidates that contain an export directly
;;   related to a private component leaf. Zero or multiple candidates are left
;;   visible to compilation as a diagnostic, never resolved by renderer order.
(define (calculus-component-private-presentation-view-names lesson instance part)
  (check 'calculus-component-private-presentation-view-names calculus-lesson? "calculus-lesson?" lesson)
  (define related (component-private-related-exports part))
  (define candidate-names
    (for/list ([view (in-hash-values (calculus-lesson-views lesson))]
               #:when
               (and (eq? (c-view-kind view) 'graph-view)
                    (for/or ([target (in-list
                                      (hash-ref (c-view-options view) 'objects '()))])
                      (member (component-instance-export-name instance target)
                              related))))
      (c-view-name view)))
  (if (or (null? related) (not (c-node? instance)))
      '()
      (sort candidate-names symbol<?)))

(define (eval-part part environment model computation lexical)
  (define parent (node-raw (c-part-parent part)))
  (define name (c-part-name part))
  (cond
    [(and (list? name) (pair? name) (eq? (car name) 'branches))
     (c-part (c-part-parent part) name)]
    [(and (c-object? parent) (eq? (c-object-kind parent) 'use-component))
     (result-bind
      (component-instance-valid? (c-part-parent part) environment model computation lexical)
      (lambda (private-model)
        (define component (first (c-object-arguments parent)))
        (cond
          [(not (and (symbol? name)
                     (member name (calculus-component-exports component))))
           (undefined "component part is not a public export")]
          [else
           (define exported (hash-ref (calculus-model-nodes private-model) name #f))
           (if exported
               (eval-raw exported environment private-model computation lexical)
               (undefined "component export is not declared in its model"))]))) ]
    [(not (c-object? parent)) (undefined "object has no public parts")]
    [else
     (define args (c-object-arguments parent))
     (case (c-object-kind parent)
       [(input-reading)
        (define graph (first args)) (define input (second args))
        (case name
          [(input) (eval-raw input environment model computation lexical)]
          [(point) (eval-point (c-object 'point-on (list graph) (hash 'x input)) environment model computation lexical)]
          [(output) (result-bind (eval-raw input environment model computation lexical)
                                  (lambda (x) (evaluate-graph graph x environment model computation lexical)))]
          [(input-guide output-guide) (defined (c-part parent name))]
          [else (defined (c-part parent name))])]
       [(coordinate-reading)
        (case name
          [(point) (eval-point (first args) environment model computation lexical)]
          [(input) (result-bind (eval-point (first args) environment model computation lexical) (lambda (p) (defined (car p))))]
          [(output) (result-bind (eval-point (first args) environment model computation lexical) (lambda (p) (defined (cdr p))))]
          [else (defined (c-part parent name))])]
       [(increment)
        (case name
          [(from) (eval-point (first args) environment model computation lexical)]
          [(to) (eval-point (second args) environment model computation lexical)]
          [(dx dy ratio)
           (result-bind (eval-point (first args) environment model computation lexical)
                        (lambda (p) (result-bind (eval-point (second args) environment model computation lexical)
                                                 (lambda (q)
                                                   (case name [(dx) (defined (- (car q) (car p)))]
                                                              [(dy) (defined (- (cdr q) (cdr p)))]
                                                              [else (if (= (car q) (car p)) (undefined "vertical increment has no ratio")
                                                                        (defined (/ (- (cdr q) (cdr p)) (- (car q) (car p)))))])))))]
          [(corner) (result-bind (eval-point (first args) environment model computation lexical)
                                 (lambda (p) (result-bind (eval-point (second args) environment model computation lexical)
                                                          (lambda (q) (defined (cons (car q) (cdr p)))))))]
          [else (defined (c-part parent name))])]
       [(snapshot-of)
        (result-bind
         (snapshot-frozen-environment (c-part-parent part)
                                      environment model computation lexical)
         (lambda (frozen)
           (eval-part (c-part (first args) name)
                      frozen model computation lexical)))]
       [(slope-triangle)
        (result-bind
         (eval-slope-triangle-geometry (first args) (c-object-options parent)
                                       environment model computation lexical)
         (lambda (geometry)
           (define from (first geometry))
           (define to (second geometry))
           (define corner (third geometry))
           (define dx (fourth geometry))
           (define dy (fifth geometry))
           (case name
             [(horizontal) (defined (list 'segment from corner))]
             [(vertical) (defined (list 'segment corner to))]
             [(corner) (defined corner)]
             [(dx run-label) (defined dx)]
             [(dy rise-label) (defined dy)]
             [else (defined (c-part parent name))])))]
       [(epsilon-delta-condition)
        (result-bind
         (eval-epsilon-delta-condition (c-part-parent part) environment model computation lexical)
         (lambda (_)
           (result-bind
            (eval-raw (list (hash-ref (c-object-options parent) 'at)
                            (hash-ref (c-object-options parent) 'limit)
                            (hash-ref (c-object-options parent) 'epsilon)
                            (hash-ref (c-object-options parent) 'delta))
                      environment model computation lexical)
            (lambda (values)
              (match values
                [(list at limit epsilon delta)
                 (case name
                   [(epsilon) (defined epsilon)]
                   [(delta) (defined delta)]
                   [(input-neighborhood) (defined (list 'open-domain (- at delta) (+ at delta)))]
                   [(output-neighborhood) (defined (list 'open-domain (- limit epsilon) (+ limit epsilon)))]
                   [(input-band) (defined (list 'input-band (- at delta) (+ at delta)))]
                   [(output-band) (defined (list 'output-band (- limit epsilon) (+ limit epsilon)))]
                   [else (defined (c-part parent name))])]
                [_ (undefined "epsilon-delta parts require scalar values")])))))]
       [(riemann-sum)
        (case name [(value) (eval-sum-value parent environment model computation lexical)] [else (defined (c-part parent name))])]
       [else (defined (c-part parent name))])]))

(define (eval-partition partition environment model computation lexical)
  (define raw (node-raw partition))
  (cond
    [(not (c-object? raw)) (undefined "expected a partition")]
    [(eq? (c-object-kind raw) 'partition)
     (result-bind
      (eval-raw (first (c-object-arguments raw)) environment model computation lexical)
      (lambda (points)
        (if (and (list? points)
                 (>= (length points) 2)
                 (andmap finite-real? points)
                 (for/and ([left (in-list points)] [right (in-list (rest points))])
                   (< left right)))
            (defined (immutable-list-copy points))
            (undefined "partition needs at least two finite strictly increasing endpoints"))))]
    [(eq? (c-object-kind raw) 'uniform-partition)
     (define a (first (c-object-arguments raw))) (define b (second (c-object-arguments raw)))
     (define n (hash-ref (c-object-options raw) 'count))
     (result-bind (eval-raw a environment model computation lexical)
                  (lambda (left) (result-bind (eval-raw b environment model computation lexical)
                                               (lambda (right) (result-bind (eval-raw n environment model computation lexical)
                                                                            (lambda (count)
                                                                              (if (and (exact-integer? count) (positive? count) (< left right))
                                                                                  (defined (for/list ([i (in-range (add1 count))]) (+ left (* i (/ (- right left) count)))))
                                                                                  (undefined "uniform partition needs increasing bounds and a positive integer count"))))))))]
    [else (undefined "expected a partition")]))

;; calculus-snapshot-partition-points : calculus-snapshot? semantic-value? -> calculus-result?
;;   Resolves a partition-marks object's exact endpoints for native axis marks.
(define (calculus-snapshot-partition-points snapshot marks)
  (cond
    [(not (calculus-snapshot? snapshot))
     (raise-argument-error 'calculus-snapshot-partition-points "calculus-snapshot?" snapshot)]
    [else
     (define raw (node-raw marks))
     (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'partition-marks)))
         (undefined "expected partition marks")
         (eval-partition (first (c-object-arguments raw))
                         (calculus-snapshot-values snapshot)
                         (calculus-snapshot-model snapshot)
                         (calculus-snapshot-computation snapshot)
                         (hash)))]))

(define (eval-tags tagged environment model computation lexical)
  (define raw (node-raw tagged))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'tag-partition)))
      (undefined "expected a tagged partition")
      (result-bind (eval-partition (first (c-object-arguments raw)) environment model computation lexical)
                   (lambda (points)
                     (define rule (hash-ref (c-object-options raw) 'sample #f))
                     (cond
                       [rule
                        (case rule
                          [(left right midpoint)
                           (defined
                            (for/list ([a (in-list points)] [b (in-list (rest points))])
                              (case rule [(left) a] [(right) b] [else (/ (+ a b) 2)])))]
                          [else (undefined "tag sample rule must be 'left, 'right, or 'midpoint")])]
                       [else
                        (define tags-expression (hash-ref (c-object-options raw) 'tags #f))
                        (if (not tags-expression)
                            (undefined "tag partition needs #:sample or #:tags")
                            (result-bind
                             (eval-raw tags-expression environment model computation lexical)
                             (lambda (tags)
                               (if (and (list? tags)
                                        (= (length tags) (sub1 (length points)))
                                        (andmap finite-real? tags)
                                        (for/and ([tag (in-list tags)]
                                                  [a (in-list points)]
                                                  [b (in-list (rest points))])
                                          (<= a tag b)))
                                   (defined (immutable-list-copy tags))
                                   (undefined "explicit tags require one finite tag in each closed subinterval")))))])))))

(define (eval-sum-value sum environment model computation lexical)
  (define raw (node-raw sum))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'riemann-sum)))
     (undefined "expected a Riemann sum")]
    [else
     (define tagged (second (c-object-arguments raw)))
     (define function (first (c-object-arguments raw)))
     (result-bind
      (eval-tags tagged environment model computation lexical)
      (lambda (tags)
        (define tag-source (node-raw tagged))
        (result-bind
         (eval-partition (first (c-object-arguments tag-source)) environment model computation lexical)
         (lambda (points)
           (let loop ([samples tags] [endpoints points] [total 0])
             (if (null? samples)
                 (defined total)
                 (result-bind
                  (evaluate-function function (car samples) environment model computation lexical)
                  (lambda (height)
                    (loop (cdr samples)
                          (cdr endpoints)
                          (+ total (* height (- (second endpoints) (first endpoints)))))))))))))]))

;; riemann-cells/in-environment : semantic-value? hash? calculus-model?
;;                                calculus-computation? -> calculus-result?
;;   Evaluates rectangle geometry against an explicit immutable parameter map.
;;   Refinement carriers use this same semantic calculation for their proposed
;;   next count; the renderer never invents child heights from pixels.
(define (riemann-cells/in-environment rectangles environment model computation)
  (define raw (node-raw rectangles))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'riemann-rectangles)))
      (undefined "expected Riemann rectangles")
      (let* ([sum (first (c-object-arguments raw))]
             [sum-raw (node-raw sum)])
        (if (not (and (c-object? sum-raw) (eq? (c-object-kind sum-raw) 'riemann-sum)))
            (undefined "Riemann rectangles require a Riemann sum")
            (let ([function (first (c-object-arguments sum-raw))]
                  [tagged (second (c-object-arguments sum-raw))])
              (result-bind
               (eval-tags tagged environment model computation (hash))
               (lambda (tags)
                 (define tagged-raw (node-raw tagged))
                 (result-bind
                  (eval-partition (first (c-object-arguments tagged-raw))
                                  environment model computation (hash))
                  (lambda (points)
                    (let loop ([lefts points] [rights (rest points)] [samples tags] [cells '()])
                      (cond
                        [(null? samples) (defined (immutable-list-copy (reverse cells)))]
                        [(or (null? lefts) (null? rights))
                         (undefined "Riemann tags do not match partition cells")]
                        [else
                         (result-bind
                          (evaluate-function function (car samples) environment model computation (hash))
                          (lambda (height)
                            (loop (rest lefts) (rest rights) (rest samples)
                                  (cons (list (car lefts) (car rights) height) cells))))])))))))))))

;; calculus-snapshot-riemann-cells : calculus-snapshot? semantic-value? -> calculus-result?
;;   Supplies exact, snapshot-derived rectangle cells to the native adapter.
(define (calculus-snapshot-riemann-cells snapshot rectangles)
  (unless (calculus-snapshot? snapshot)
    (raise-argument-error 'calculus-snapshot-riemann-cells "calculus-snapshot?" snapshot))
  (riemann-cells/in-environment rectangles
                                (calculus-snapshot-values snapshot)
                                (calculus-snapshot-model snapshot)
                                (calculus-snapshot-computation snapshot)))

;; riemann-rectangle-count-parameter : semantic-value? -> (or/c c-node? #f)
;;   Finds the direct uniform-partition capability used by a rectangle source.
(define (riemann-rectangle-count-parameter rectangles)
  (define raw (node-raw rectangles))
  (define sum (and (c-object? raw) (pair? (c-object-arguments raw))
                   (first (c-object-arguments raw))))
  (define sum-raw (node-raw sum))
  (define tagged (and (c-object? sum-raw) (>= (length (c-object-arguments sum-raw)) 2)
                      (second (c-object-arguments sum-raw))))
  (define tagged-raw (node-raw tagged))
  (define partition (and (c-object? tagged-raw) (pair? (c-object-arguments tagged-raw))
                         (first (c-object-arguments tagged-raw))))
  (define partition-raw (node-raw partition))
  (define count (and (c-object? partition-raw)
                     (eq? (c-object-kind partition-raw) 'uniform-partition)
                     (hash-ref (c-object-options partition-raw) 'count #f)))
  (and (c-node? count) (eq? (c-node-kind count) 'parameter) count))

;; calculus-snapshot-riemann-carrier-cells : calculus-snapshot? semantic-value?
;;                                             exact-positive-integer? -> calculus-result?
;;   Supplies the exact prospective nested rectangles used only while a
;;   refinement transition is active.  The ordinary snapshot remains at its
;;   committed integer count.
(define (calculus-snapshot-riemann-carrier-cells snapshot rectangles count)
  (unless (calculus-snapshot? snapshot)
    (raise-argument-error 'calculus-snapshot-riemann-carrier-cells "calculus-snapshot?" snapshot))
  (if (not (exact-positive-integer? count))
      (undefined "refinement carrier count must be a positive exact integer")
      (let ([parameter (riemann-rectangle-count-parameter rectangles)])
        (if (not parameter)
            (undefined "Riemann rectangles do not use a direct uniform count parameter")
            (riemann-cells/in-environment
             rectangles
             (hash-set (calculus-snapshot-values snapshot) (c-node-id parameter) count)
             (calculus-snapshot-model snapshot)
             (calculus-snapshot-computation snapshot))))))

;; eval-trapezoidal-sum : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Computes the exact signed finite trapezoidal sum from increasing cells.
(define (eval-trapezoidal-sum sum environment model computation lexical)
  (define raw (node-raw sum))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'trapezoidal-sum)))
     (undefined "expected a trapezoidal sum")]
    [else
     (define function (first (c-object-arguments raw)))
     (define partition (second (c-object-arguments raw)))
     (result-bind
      (eval-partition partition environment model computation lexical)
      (lambda (points)
        (let loop ([lefts points] [rights (rest points)] [total 0])
          (cond
            [(null? rights) (defined total)]
            [else
             (result-bind
              (evaluate-function function (car lefts) environment model computation lexical)
              (lambda (left-height)
                (result-bind
                 (evaluate-function function (car rights) environment model computation lexical)
                 (lambda (right-height)
                   (loop (cdr lefts) (cdr rights)
                         (+ total
                            (* (- (car rights) (car lefts))
                               (/ (+ left-height right-height) 2))))))))]))))]))

;; calculus-snapshot-trapezoid-cells : calculus-snapshot? semantic-value? -> calculus-result?
;;   Returns (list left right left-height right-height) cells for a drawable
;;   trapezoidal region, evaluated directly from the immutable snapshot.
(define (calculus-snapshot-trapezoid-cells snapshot regions)
  (cond
    ((not (calculus-snapshot? snapshot))
     (raise-argument-error 'calculus-snapshot-trapezoid-cells "calculus-snapshot?" snapshot))
    (else
     (define raw (node-raw regions))
     (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'trapezoidal-regions)))
         (undefined "expected trapezoidal regions")
         (let ([function (first (c-object-arguments raw))]
               [partition (second (c-object-arguments raw))]
               [environment (calculus-snapshot-values snapshot)]
               [model (calculus-snapshot-model snapshot)]
               [computation (calculus-snapshot-computation snapshot)])
           (result-bind
            (eval-partition partition environment model computation (hash))
            (lambda (points)
              (let loop ([lefts points] [rights (rest points)] [cells '()])
                (cond
                  ((null? rights) (defined (immutable-list-copy (reverse cells))))
                  (else
                   (result-bind
                    (evaluate-function function (car lefts) environment model computation (hash))
                    (lambda (left-height)
                      (result-bind
                       (evaluate-function function (car rights) environment model computation (hash))
                       (lambda (right-height)
                         (loop (rest lefts) (rest rights)
                               (cons (list (car lefts) (car rights) left-height right-height)
                                     cells))))))))))))))))

;; domain-boundary-expressions : c-domain? -> list?
;;   Collects all declared finite boundary candidates without treating a
;;   renderer sample as a mathematical domain test.  The resulting values let
;;   interval integration test every declared hole and every interval between
;;   domain boundaries.
(define (domain-boundary-expressions domain)
  (define raw (node-raw domain))
  (cond
    [(not (c-domain? raw)) '()]
    [(memq (c-domain-kind raw)
            '(closed open closed-open open-closed singleton integers))
     (c-domain-arguments raw)]
    [(memq (c-domain-kind raw) '(neighborhood punctured-neighborhood))
     ;; A neighborhood stores center/radius, not two boundary coordinates.
     ;; Include both derived endpoints and (for a puncture) the excluded
     ;; center, so every membership interval can be proved rather than sampled
     ;; only at accidental center/radius values.
     (define center (first (c-domain-arguments raw)))
     (define radius (second (c-domain-arguments raw)))
     (append (list (c-expression '- (list center radius))
                   (c-expression '+ (list center radius)))
             (if (eq? (c-domain-kind raw) 'punctured-neighborhood)
                 (list center)
                 '()))]
    [(eq? (c-domain-kind raw) 'domain-except)
     (append (append-map domain-boundary-expressions
                         (take (c-domain-arguments raw) 1))
             (rest (c-domain-arguments raw)))]
    [(memq (c-domain-kind raw) '(domain-union domain-intersection))
     (append-map domain-boundary-expressions (c-domain-arguments raw))]
    [else '()]))

;; domain-path-covered? : c-domain? finite-real? finite-real? hash? calculus-model?
;;                         calculus-computation? hash? -> calculus-result?
;;   Confirms that one closed integration path stays within an explicitly
;;   declared domain.  Every endpoint, hole, and interval between consecutive
;;   declared boundaries is checked, which preserves ordinary finite unions
;;   and catches a declared singularity even when quadrature would not sample
;;   it by chance.
(define (domain-path-covered? domain a b environment model computation lexical)
  (let/ec abort
    (define boundaries
      (for/list ([expression (in-list (domain-boundary-expressions domain))])
        (define result (eval-domain-number expression environment model computation))
        (unless (eq? (calculus-result-status result) 'defined) (abort result))
        (calculus-result-value result)))
    (define ordered
      (sort (remove-duplicates (append (list a b)
                                       (filter (lambda (value)
                                                 (and (finite-real? value)
                                                      (<= (min a b) value (max a b))))
                                               boundaries)))
            <))
    (define probes
      (append ordered
              (for/list ([left (in-list ordered)] [right (in-list (rest ordered))]
                         #:when (< left right))
                (/ (+ left right) 2))))
    (for ([probe (in-list probes)])
      (define membership
        (domain-contains? domain probe environment model computation))
      (unless (eq? (calculus-result-status membership) 'defined) (abort membership))
      (unless (calculus-result-value membership)
        (abort (outside "integration path leaves the declared function domain"))))
    (defined #t)))

;; simpson/evaluate : procedure? finite-real? finite-real? calculus-computation? -> calculus-result?
;;   Applies a bounded adaptive Simpson rule.  Function values are memoized by
;;   exact mathematical input, local errors are compared against a subdivided
;;   tolerance, and any exhausted evaluation budget remains unresolved.
(define (simpson/evaluate evaluate a b computation)
  (define budget (calculus-computation-data-integration-budget computation))
  (define absolute (calculus-computation-data-absolute-tolerance computation))
  (define relative (calculus-computation-data-relative-tolerance computation))
  (let/ec abort
    (define cache (make-hash))
    (define evaluations 0)
    (define (sample input)
      (cond
        [(hash-has-key? cache input) (hash-ref cache input)]
        [(>= evaluations budget)
         (abort (unresolved "numeric integration budget exhausted before the requested tolerance was established"
                            'numeric))]
        [else
         (set! evaluations (add1 evaluations))
         (define result (evaluate input))
         (unless (eq? (calculus-result-status result) 'defined) (abort result))
         (define value (calculus-result-value result))
         (unless (finite-real? value)
           (abort (undefined "integrand did not produce a finite real value")))
         (hash-set! cache input value)
         value]))
    (define (estimate left middle right f-left f-middle f-right)
      (* (/ (- right left) 6) (+ f-left (* 4 f-middle) f-right)))
    ;; A panel records its raw Simpson estimate and sampled endpoints.  Every
    ;; refinement step expands the complete active partition, then tests the
    ;; *sum* of its retained error evidence against the current integral
    ;; estimate.  Relative tolerance is therefore never frozen at a cancelled
    ;; first estimate.
    (define (refine-panel panel)
      (match-define (list left middle right f-left f-middle f-right coarse) panel)
      (define left-middle (/ (+ left middle) 2))
      (define right-middle (/ (+ middle right) 2))
      (define f-left-middle (sample left-middle))
      (define f-right-middle (sample right-middle))
      (define left-estimate
        (estimate left left-middle middle f-left f-left-middle f-middle))
      (define right-estimate
        (estimate middle right-middle right f-middle f-right-middle f-right))
      (define refined (+ left-estimate right-estimate))
      (define correction (/ (- refined coarse) 15))
      (values (list (list left left-middle middle f-left f-left-middle f-middle left-estimate)
                    (list middle right-middle right f-middle f-right-middle f-right right-estimate))
              (+ refined correction)
              (abs correction)))
    (cond
      [(= a b) (defined 0 'numeric #t)]
      [(< budget 5)
       (unresolved "numeric integration budget is too small to estimate Simpson error" 'numeric)]
      [else
       (define middle (/ (+ a b) 2))
       (define coarse (estimate a middle b (sample a) (sample middle) (sample b)))
       (let loop ([panels (list (list a middle b (sample a) (sample middle) (sample b) coarse))])
         (define next-panels '())
         (define corrected-total 0)
         (define total-error 0)
         (for ([panel (in-list panels)])
           (define-values (children corrected error) (refine-panel panel))
           (set! next-panels (append next-panels children))
           (set! corrected-total (+ corrected-total corrected))
           (set! total-error (+ total-error error)))
         (define tolerance (+ absolute (* relative (abs corrected-total))))
         (if (<= total-error tolerance)
             (finite-number-result corrected-total 'numeric #t)
             (loop next-panels)))])))

;; simpson : semantic-value? finite-real? finite-real? hash? calculus-model?
;;           calculus-computation? hash? -> calculus-result?
;;   Ordinary function integration is a thin specialization of the evaluator
;; form.  Graph-derived quantities use simpson/evaluate so their graph domain
;; remains part of the calculation rather than only a rendering concern.
(define (simpson function a b environment model computation lexical)
  (simpson/evaluate
   (lambda (input)
     (evaluate-function function input environment model computation lexical))
   a b computation))

;; antiderivative-for? : semantic-value? semantic-value? -> boolean?
;;   Confirms that endpoint subtraction uses the descriptor registered for the
;;   requested integrand, rather than merely any function with plausible
;;   endpoint values.
(define (antiderivative-for? function antiderivative)
  (define raw (node-raw antiderivative))
  (and (c-object? raw)
       (eq? (c-object-kind raw) 'antiderivative-function)
       (= (length (c-object-arguments raw)) 1)
       (same-semantic-source? function (first (c-object-arguments raw)))))

(define (eval-integral function from to antiderivative environment model computation lexical)
  (result-bind
   (eval-raw from environment model computation lexical)
   (lambda (a)
     (result-bind
      (eval-raw to environment model computation lexical)
      (lambda (b)
        (result-bind
         (domain-path-covered? (function-domain function) a b environment model computation lexical)
         (lambda (_)
           (cond
             [(= a b) (defined 0)]
             [antiderivative
              (cond
                [(not (antiderivative-for? function antiderivative))
                 (undefined "integral #:antiderivative is not registered for its integrand")]
                [else
                 (result-bind
                  (domain-path-covered? (function-domain antiderivative) a b environment model computation lexical)
                  (lambda (_)
                    (result-bind
                     (evaluate-function antiderivative b environment model computation lexical)
                     (lambda (fb)
                       (result-bind
                        (evaluate-function antiderivative a environment model computation lexical)
                        (lambda (fa)
                          (result-with-method
                           (finite-number-result (- fb fa) 'supplied #f)
                           'supplied)))))))])]
             [else (simpson function a b environment model computation lexical)]))))))))

(define (eval-area region environment model computation lexical)
  (define raw (node-raw region))
  (if (not (and (c-object? raw) (memq (c-object-kind raw) '(region-under integral-region region-between))))
      (undefined "expected a region")
      (let* ([arguments (c-object-arguments raw)]
             [left-graph (first arguments)]
             [left-function (graph-function left-graph)]
             [right-graph (and (eq? (c-object-kind raw) 'region-between)
                               (second arguments))]
             [right-function (and right-graph (graph-function right-graph))]
             [from (hash-ref (c-object-options raw) 'from)]
             [to (hash-ref (c-object-options raw) 'to)])
        (cond
          [(not left-function) (undefined "region requires a graph")]
          [(and (eq? (c-object-kind raw) 'region-between) (not right-function))
           (undefined "region-between requires two graphs")]
          [else
           (result-bind
            (eval-raw (list from to) environment model computation lexical)
            (lambda (bounds)
              (match bounds
                [(list a b)
                 (cond
                   [(not (and (finite-real? a) (finite-real? b)))
                    (undefined "region bounds must be finite")]
                   [(and (memq (c-object-kind raw) '(region-under region-between)) (> a b))
                    (undefined "geometric region bounds must be increasing")]
                   [else
                    (simpson/evaluate
                     (lambda (input)
                       (result-bind
                        (evaluate-graph left-graph input environment model computation lexical)
                        (lambda (left-value)
                          (if right-graph
                              (result-bind
                               (evaluate-graph right-graph input environment model computation lexical)
                               (lambda (right-value)
                                 (defined (abs (- left-value right-value)))))
                              (defined (abs left-value))))))
                     (min a b) (max a b) computation)])]
                [_ (undefined "region bounds must be scalar values")])))]))))

;; calculus-snapshot-region-samples : calculus-snapshot? semantic-value? -> calculus-result?
;;   Provides a fixed, snapshot-derived sequence of (x y-left y-right) samples
;;   for one region. #f samples explicitly preserve mathematical gaps for the
;;   native adapter; no drawing path may bridge them.
(define (calculus-snapshot-region-samples snapshot region)
  (cond
    ((not (calculus-snapshot? snapshot))
     (raise-argument-error 'calculus-snapshot-region-samples "calculus-snapshot?" snapshot))
    (else
     (define raw (node-raw region))
     (if (not (and (c-object? raw) (memq (c-object-kind raw) '(integral-region region-under region-between))))
         (undefined "expected a region")
         (let* ([arguments (c-object-arguments raw)]
                [left-graph (first arguments)]
                [left-function (graph-function left-graph)]
                [right-graph (and (eq? (c-object-kind raw) 'region-between)
                                  (second arguments))]
                [right-function (and right-graph (graph-function right-graph))]
                [from (hash-ref (c-object-options raw) 'from)]
                [to (hash-ref (c-object-options raw) 'to)]
                [environment (calculus-snapshot-values snapshot)]
                [model (calculus-snapshot-model snapshot)]
                [computation (calculus-snapshot-computation snapshot)])
           (cond
             ((not left-function) (undefined "region requires a graph"))
             ((and (eq? (c-object-kind raw) 'region-between) (not right-function))
              (undefined "region-between requires two graphs"))
             (else
              (result-bind
               (eval-raw (list from to) environment model computation (hash))
               (lambda (bounds)
                 (if (not (and (list? bounds) (= (length bounds) 2)))
                     (undefined "region bounds must be scalar values")
                     (let ((a (first bounds)) (b (second bounds)))
                       (cond
                         ((not (and (finite-real? a) (finite-real? b)))
                          (undefined "region bounds must be finite"))
                         ((and (memq (c-object-kind raw) '(region-under region-between)) (> a b))
                          (undefined "geometric region bounds must be increasing"))
                         (else
                          (define start (min a b))
                          (define end (max a b))
                          (define sample-count 120)
                          (define samples
                            (for/list ((index (in-range (add1 sample-count))))
                              (define x (+ start (* (- end start) (/ index sample-count))))
                              (define left (evaluate-graph left-graph x environment model computation (hash)))
                              (define right
                                (if right-graph
                                    (evaluate-graph right-graph x environment model computation (hash))
                                    (defined 0)))
                              (and (eq? (calculus-result-status left) 'defined)
                                   (eq? (calculus-result-status right) 'defined)
                                   (finite-real? (calculus-result-value left))
                                   (finite-real? (calculus-result-value right))
                                   (list x (calculus-result-value left) (calculus-result-value right)))))
                          (defined (immutable-list-copy samples)))))))))))))))

(define (eval-sequence-value sequence index environment model computation lexical)
  (define raw (node-raw sequence))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'sequence)))
     (undefined "expected a sequence")]
    [else
     (define variable (first (c-object-arguments raw)))
     (define body (second (c-object-arguments raw)))
     (define first-index (hash-ref (c-object-options raw) 'from 0))
     (result-bind
      (eval-raw index environment model computation lexical)
      (lambda (n)
        (result-bind
         (eval-raw first-index environment model computation lexical)
         (lambda (start)
           (if (and (exact-integer? n) (exact-integer? start) (>= n start))
               (eval-raw body environment model computation
                         (hash-set lexical variable (defined n)))
               (undefined "sequence index must be an integer at or above #:from"))))))]))

;; eval-partial-sum : semantic-value? semantic-value? semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Computes an inclusive finite sum over valid integer sequence indices.
(define (eval-partial-sum sequence from to environment model computation lexical)
  (result-bind (eval-raw from environment model computation lexical)
               (lambda (a)
                 (result-bind
                  (eval-raw to environment model computation lexical)
                  (lambda (b)
                    (cond
                      [(not (and (exact-integer? a) (exact-integer? b)))
                       (undefined "partial-sum bounds must be exact integers")]
                      [(< b a) (defined 0)]
                      [else
                       (let loop ([n a] [total 0])
                         (if (> n b)
                             (defined total)
                             (result-bind
                              (eval-sequence-value sequence n environment model computation lexical)
                              (lambda (value) (loop (add1 n) (+ total value))))))]))))))

;; eval-iterate-value : semantic-value? semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Evaluates a finite iteration directly from its seed, never from prior frames.
(define (same-semantic-source? left right)
  (or (eq? left right)
      (and (c-node? left) (c-node? right)
           (eq? (c-node-id left) (c-node-id right)))))

;; derivative-compatible? : semantic-value? semantic-value? -> boolean?
;;   Requires a declared first derivative to retain the same function source.
;;   Tangent and Newton constructions have first-order meaning; accepting a
;;   second derivative merely because it names the same source is invalid.
(define (derivative-compatible? function derivative)
  (define raw (node-raw derivative))
  (and (c-object? raw)
       (eq? (c-object-kind raw) 'derivative-function)
       (= (length (c-object-arguments raw)) 1)
       (= (hash-ref (c-object-options raw) 'order 1) 1)
       (same-semantic-source? function (first (c-object-arguments raw)))))

(define (eval-iterate-value iteration index environment model computation lexical)
  (define raw (node-raw iteration))
  (cond
    ((not (and (c-object? raw) (memq (c-object-kind raw) '(iteration-map newton-iteration))))
     (undefined "expected an iteration"))
    (else
     (result-bind
      (eval-raw index environment model computation lexical)
      (lambda (limit)
        (define steps (hash-ref (c-object-options raw) 'steps #f))
        (define seed (hash-ref (c-object-options raw) 'start #f))
        (result-bind
         (eval-raw steps environment model computation lexical)
         (lambda (count)
           (result-bind
            (eval-raw seed environment model computation lexical)
            (lambda (initial)
             (cond
                ((not (and (exact-nonnegative-integer? limit)
                           (exact-nonnegative-integer? count)
                           (<= limit count)
                           (finite-real? initial)))
                 (undefined "iteration index must be within its declared finite step count"))
                ((and (eq? (c-object-kind raw) 'newton-iteration)
                      (not (derivative-compatible?
                            (first (c-object-arguments raw))
                            (hash-ref (c-object-options raw) 'derivative #f))))
                 (unresolved "Newton derivative must be declared for the iteration function"))
                ((eq? (c-object-kind raw) 'iteration-map)
                 (define variable (first (c-object-arguments raw)))
                 (define body (second (c-object-arguments raw)))
                 (let loop ([position 0] [current initial])
                   (if (= position limit)
                       (defined current)
                       (result-bind
                        (eval-raw body environment model computation
                                  (hash-set lexical variable (defined current)))
                        (lambda (next) (loop (add1 position) next))))))
                (else
                 (define function (first (c-object-arguments raw)))
                 (define derivative (hash-ref (c-object-options raw) 'derivative #f))
                 (let loop ([position 0] [current initial])
                   (if (= position limit)
                       (defined current)
                       (result-bind
                        (evaluate-function function current environment model computation lexical)
                        (lambda (fx)
                          (result-bind
                           (evaluate-function derivative current environment model computation lexical)
                           (lambda (dx)
                             (if (= dx 0)
                                 (undefined "Newton derivative is zero")
                                 (loop (add1 position) (- current (/ fx dx)))))))))))))))))))))

;; eval-sequence-points : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Returns only authored integer-indexed samples, never an interpolated curve.
(define (eval-sequence-points marker environment model computation lexical)
  (define raw (node-raw marker))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'sequence-points)))
      (undefined "expected sequence-points")
      (let* ([sequence (first (c-object-arguments raw))]
             [through (hash-ref (c-object-options raw) 'through #f)]
             [sequence-raw (node-raw sequence)])
        (cond
          [(not (and (c-object? sequence-raw) (eq? (c-object-kind sequence-raw) 'sequence)))
           (undefined "sequence-points requires a sequence")]
          [(not through) (undefined "sequence-points requires #:through")]
          [else
           (result-bind
            (eval-raw through environment model computation lexical)
            (lambda (last-index)
              (result-bind
               (eval-raw (hash-ref (c-object-options sequence-raw) 'from 0)
                         environment model computation lexical)
               (lambda (first-index)
                 (if (not (and (exact-integer? first-index) (exact-integer? last-index)))
                     (undefined "sequence-points indices must be exact integers")
                     (let loop ([index first-index] [points '()])
                       (if (> index last-index)
                           (defined (reverse points))
                           (result-bind
                            (eval-sequence-value sequence index environment model computation lexical)
                            (lambda (value)
                              (loop (add1 index) (cons (cons index value) points)))))))))))]))))

;; eval-newton-diagram : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Retains the available Newton iterate prefix as indexed mathematical data.
(define (eval-newton-diagram marker environment model computation lexical)
  (define raw (node-raw marker))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'newton-diagram)))
      (undefined "expected newton-diagram")
      (let* ([iteration (first (c-object-arguments raw))]
             [through (hash-ref (c-object-options raw) 'through #f)]
             [iteration-raw (node-raw iteration)])
        (cond
          [(not (and (c-object? iteration-raw)
                     (eq? (c-object-kind iteration-raw) 'newton-iteration)))
           (undefined "newton-diagram requires a Newton iteration")]
          [(not through) (undefined "newton-diagram requires #:through")]
          [else
           (result-bind
            (eval-raw through environment model computation lexical)
            (lambda (last-index)
              (if (not (exact-nonnegative-integer? last-index))
                  (undefined "newton-diagram index must be a nonnegative exact integer")
                  (let loop ([index 0] [points '()])
                    (if (> index last-index)
                        (defined (reverse points))
                        (result-bind
                         (eval-iterate-value iteration index environment model computation lexical)
                         (lambda (value)
                           (loop (add1 index) (cons (cons index value) points)))))))))]))))

;; nonempty-justification? : any/c -> boolean?
;;   Claims retain author-supplied evidence rather than attempting a new solver.
(define (nonempty-justification? value)
  (and (string? value) (not (string=? value ""))))

;; eval-analysis-claim : semantic-value? symbol? (listof symbol?) hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Validates the declared scope, category, and supplied evidence of one claim.
(define (eval-analysis-claim claim kind allowed-values environment model computation lexical)
  (define raw (node-raw claim))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) kind)))
      (undefined (format "expected ~a" kind))
      (let* ([function (first (c-object-arguments raw))]
             [scope (hash-ref (c-object-options raw) 'on #f)]
             [value-key (if (eq? kind 'sign-claim) 'sign 'direction)]
             [value (hash-ref (c-object-options raw) value-key #f)]
             [justification (hash-ref (c-object-options raw) 'justification #f)])
        (cond
          [(not (lookup-function function)) (undefined "analysis claim requires a function")]
          [(not (memq value allowed-values)) (undefined "analysis claim has an unsupported category")]
          [(not (nonempty-justification? justification))
           (undefined "analysis claim requires a nonempty #:justification")]
          [else
           (result-bind (eval-domain scope environment model computation)
                        (lambda (_) (defined raw)))]))))

;; eval-sign-chart : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Depends on validated supplied claims without inferring their interval truth.
(define (eval-sign-chart chart environment model computation lexical)
  (define raw (node-raw chart))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'sign-chart)))
      (undefined "expected a sign chart")
      (let loop ([claims (c-object-arguments raw)])
        (cond
          [(null? claims) (undefined "sign-chart requires at least one claim")]
          [else
           (result-bind
            (eval-raw (car claims) environment model computation lexical)
            (lambda (_) (if (null? (cdr claims)) (defined raw) (loop (cdr claims)))))]))))

;; calculus-snapshot-sign-chart-intervals : calculus-snapshot? semantic-value? -> calculus-result?
;;   Converts validated supplied sign claims into finite number-line intervals.
;;   The result retains the declared sign label; no sign is inferred by samples.
(define (calculus-snapshot-sign-chart-intervals snapshot chart)
  (if (not (calculus-snapshot? snapshot))
      (raise-argument-error 'calculus-snapshot-sign-chart-intervals "calculus-snapshot?" snapshot)
      (let ((raw (node-raw chart)))
        (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'sign-chart)))
            (undefined "expected a sign chart")
            (let ((environment (calculus-snapshot-values snapshot))
                  (model (calculus-snapshot-model snapshot))
                  (computation (calculus-snapshot-computation snapshot)))
              (result-bind
               (eval-sign-chart chart environment model computation (hash))
               (lambda (_)
                 (let loop ((claims (c-object-arguments raw)) (intervals '()))
                   (cond
                     ((null? claims)
                      (defined (immutable-list-copy (reverse intervals))))
                     (else
                      (let* ((claim-raw (node-raw (car claims)))
                             (bounds
                              (and (c-object? claim-raw)
                                   (eq? (c-object-kind claim-raw) 'sign-claim)
                                   (finite-interval-bounds
                                    (hash-ref (c-object-options claim-raw) 'on #f)
                                    environment
                                    model
                                    computation))))
                        (cond
                          ((not (and (c-object? claim-raw)
                                     (eq? (c-object-kind claim-raw) 'sign-claim)))
                           (undefined "sign-chart requires sign claims"))
                          ((not bounds)
                           (undefined "sign-chart needs finite interval claims"))
                          (else
                           (loop
                            (cdr claims)
                            (cons (list (first bounds)
                                        (second bounds)
                                        (hash-ref (c-object-options claim-raw) 'sign #f))
                                  intervals)))))))))))))))

;; eval-feature-point : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Places one supplied graph point while preserving its distinct named property.
(define (eval-feature-point feature environment model computation lexical)
  (define raw (node-raw feature))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'feature-point)))
     (undefined "expected a feature point")]
    [else
     (define graph (first (c-object-arguments raw)))
     (define at (hash-ref (c-object-options raw) 'at #f))
     (define kind (hash-ref (c-object-options raw) 'kind #f))
     (define justification (hash-ref (c-object-options raw) 'justification #f))
     (cond
       [(not (graph-function graph)) (undefined "feature-point requires a graph")]
       [(not (memq kind '(stationary critical local-minimum local-maximum global-minimum global-maximum inflection)))
        (undefined "feature-point has an unsupported #:kind")]
       [(not (nonempty-justification? justification))
        (undefined "feature-point requires a nonempty #:justification")]
       [else
        (result-bind (eval-raw at environment model computation lexical)
                     (lambda (x)
                        (result-bind
                        (evaluate-graph graph x environment model computation lexical)
                        (lambda (y) (defined (cons x y))))))])]))

;; extended-real-value? : any/c -> boolean?
;;   Accepts authored finite limits and the two explicit infinite limit values.
(define (extended-real-value? value)
  (or (finite-real? value) (eqv? value +inf.0) (eqv? value -inf.0)))

;; direct-real-parameter? : semantic-value? -> boolean?
;;   Limits bind one directly declared, continuously varying parameter.
(define (direct-real-parameter? value)
  (and (c-node? value)
       (eq? (c-node-kind value) 'parameter)
       (eq? (c-param-spec-kind (c-node-data value)) 'real)))

;; eval-limit-statement : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Validates a supplied limit claim without evaluating its source at the target.
(define (eval-limit-statement claim environment model computation lexical)
  (define raw (node-raw claim))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'limit-statement)))
      (undefined "expected a limit statement")
      (let* ([parameter (hash-ref (c-object-options raw) 'parameter #f)]
             [target (hash-ref (c-object-options raw) 'to #f)]
             [limit-value (hash-ref (c-object-options raw) 'value #f)]
             [side-provided? (hash-has-key? (c-object-options raw) 'side)]
             [side (hash-ref (c-object-options raw) 'side 'both)]
             [justification (hash-ref (c-object-options raw) 'justification #f)])
        (cond
          [(not (direct-real-parameter? parameter))
           (undefined "limit-statement requires a direct real #:parameter")]
          [(not (nonempty-justification? justification))
           (undefined "limit-statement requires a nonempty #:justification")]
          [else
           (result-bind
            (eval-raw target environment model computation lexical)
            (lambda (target-value)
              (result-bind
               (eval-raw limit-value environment model computation lexical)
               (lambda (claimed-value)
                 (cond
                   [(not (and (extended-real-value? target-value)
                              (extended-real-value? claimed-value)))
                    (undefined "limit targets and values must be finite or explicit infinities")]
                   [(or (eqv? target-value +inf.0) (eqv? target-value -inf.0))
                    (if side-provided?
                        (undefined "an infinite limit target does not accept #:side")
                        (defined raw))]
                   [(not (memq side '(both left right)))
                    (undefined "limit-statement has an unsupported #:side")]
                   [else (defined raw)])))))]))))

;; eval-band : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Confirms that a drawable band retains one valid mathematical domain.
(define (eval-band band environment model computation lexical)
  (define raw (node-raw band))
  (if (not (and (c-object? raw) (memq (c-object-kind raw) '(input-band output-band))))
      (undefined "expected an input or output band")
      (let ([domain (first (c-object-arguments raw))])
        (result-bind (eval-domain domain environment model computation)
                     (lambda (_) (defined raw))))))

;; eval-epsilon-delta-condition : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Validates finite authored epsilon/delta data without searching for a delta.
(define (eval-epsilon-delta-condition condition environment model computation lexical)
  (define raw (node-raw condition))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'epsilon-delta-condition)))
      (undefined "expected an epsilon-delta condition")
      (let* ([function (first (c-object-arguments raw))]
             [at (hash-ref (c-object-options raw) 'at #f)]
             [limit-value (hash-ref (c-object-options raw) 'limit #f)]
             [epsilon (hash-ref (c-object-options raw) 'epsilon #f)]
             [delta (hash-ref (c-object-options raw) 'delta #f)]
             [justification (hash-ref (c-object-options raw) 'justification #f)])
        (cond
          [(not (lookup-function function)) (undefined "epsilon-delta condition requires a function")]
          [(not (nonempty-justification? justification))
           (undefined "epsilon-delta condition requires a nonempty #:justification")]
          [else
           (result-bind
            (eval-raw (list at limit-value epsilon delta) environment model computation lexical)
            (lambda (values)
              (match values
                [(list a limit epsilon-value delta-value)
                 (if (and (finite-real? a) (finite-real? limit)
                          (finite-real? epsilon-value) (positive? epsilon-value)
                          (finite-real? delta-value) (positive? delta-value))
                     (defined raw)
                     (undefined "epsilon-delta data must be finite with positive epsilon and delta"))]
                [_ (undefined "epsilon-delta data must be scalar values")])))]))))

;; eval-continuity-condition : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Reports an authored limit/value mismatch as a contradiction, never a display choice.
(define (eval-continuity-condition condition environment model computation lexical)
  (define raw (node-raw condition))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'continuity-condition)))
      (undefined "expected a continuity condition")
      (let* ([function (first (c-object-arguments raw))]
             [at (hash-ref (c-object-options raw) 'at #f)]
             [claim (hash-ref (c-object-options raw) 'limit-claim #f)]
             [justification (hash-ref (c-object-options raw) 'justification #f)]
             [claim-raw (node-raw claim)])
        (cond
          [(not (lookup-function function)) (undefined "continuity condition requires a function")]
          [(not (nonempty-justification? justification))
           (undefined "continuity condition requires a nonempty #:justification")]
          [(not (and (c-object? claim-raw) (eq? (c-object-kind claim-raw) 'limit-statement)))
           (undefined "continuity condition requires a limit statement")]
          [else
           (result-bind
            (eval-limit-statement claim environment model computation lexical)
            (lambda (_)
              (result-bind
               (eval-raw
                (list at
                      (hash-ref (c-object-options claim-raw) 'to #f)
                      (hash-ref (c-object-options claim-raw) 'value #f))
                environment model computation lexical)
               (lambda (values)
                 (match values
                   [(list input target claimed-value)
                    (cond
                      [(not (and (finite-real? input) (finite-real? target)
                                 (finite-real? claimed-value)))
                       (undefined "continuity requires finite input, target, and limit value")]
                      [(not (scalar-equivalent? input target computation))
                       (unresolved "continuity claim has a different limiting target")]
                      [else
                       (result-bind
                        (evaluate-function function input environment model computation lexical)
                        (lambda (actual-value)
                          (if (scalar-equivalent? actual-value claimed-value computation)
                              (defined raw)
                              (unresolved "continuity claim contradicts the function value"))))])]
                   [_ (undefined "continuity requires scalar claim data")])))))]))))

;; eval-asymptote-line : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Certifies only a supplied line whose finite/infinite shape matches its claim.
(define (eval-asymptote-line asymptote environment model computation lexical)
  (define raw (node-raw asymptote))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'asymptote-line)))
      (undefined "expected an asymptote line")
      (let* ([graph (first (c-object-arguments raw))]
             [line (hash-ref (c-object-options raw) 'line #f)]
             [claim (hash-ref (c-object-options raw) 'limit-claim #f)]
             [claim-raw (node-raw claim)])
        (cond
          [(not (graph-function graph)) (undefined "asymptote-line requires a graph")]
          [(not (and (c-object? claim-raw) (eq? (c-object-kind claim-raw) 'limit-statement)))
           (undefined "asymptote-line requires a limit statement")]
          [else
           (result-bind
            (eval-limit-statement claim environment model computation lexical)
            (lambda (_)
              (result-bind
               (eval-line line environment model computation lexical)
               (lambda (line-value)
                 (result-bind
                  (eval-raw
                   (list (hash-ref (c-object-options claim-raw) 'to #f)
                         (hash-ref (c-object-options claim-raw) 'value #f))
                   environment model computation lexical)
                  (lambda (values)
                    (match values
                      [(list target claimed-value)
                       (cond
                         [(and (eq? (car line-value) 'vertical)
                               (finite-real? target)
                               (or (eqv? claimed-value +inf.0) (eqv? claimed-value -inf.0))
                               (scalar-equivalent? (second line-value) target computation))
                          (defined raw)]
                         [(and (eq? (car line-value) 'line)
                               (= (second line-value) 0)
                               (or (eqv? target +inf.0) (eqv? target -inf.0))
                               (finite-real? claimed-value)
                               (scalar-equivalent? (third line-value) claimed-value computation))
                          (defined raw)]
                         [else
                          (unresolved "asymptote line does not match the supplied limit claim")])]
                      [_ (undefined "asymptote-line requires scalar limit data")])))))))]))))

;; calculus-snapshot-asymptote-geometry : calculus-snapshot? semantic-value? -> calculus-result?
;;   Resolves the certified supplied line only after the asymptote claim has
;;   passed its semantic compatibility checks.
(define (calculus-snapshot-asymptote-geometry snapshot asymptote)
  (check 'calculus-snapshot-asymptote-geometry calculus-snapshot? "calculus-snapshot?" snapshot)
  (define raw (node-raw asymptote))
  (if (not (and (c-object? raw) (eq? (c-object-kind raw) 'asymptote-line)))
      (undefined "expected asymptote-line")
      (let ([environment (calculus-snapshot-values snapshot)]
            [model (calculus-snapshot-model snapshot)]
            [computation (calculus-snapshot-computation snapshot)])
        (result-bind
         (eval-asymptote-line asymptote environment model computation (hash))
         (lambda (_)
           (eval-line (hash-ref (c-object-options raw) 'line #f)
                      environment model computation (hash)))))))

;; snapshot-frozen-environment : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Resolves one snapshot's immutable parameter assignment independently of
;;   the later sampled state.
(define (snapshot-frozen-environment snapshot environment model computation lexical)
  (define raw (node-raw snapshot))
  (cond
    ((not (and (c-object? raw) (eq? (c-object-kind raw) 'snapshot-of)))
     (undefined "expected a snapshot-of object"))
    ((not (= (length (c-object-arguments raw)) 1))
     (undefined "snapshot-of requires one mathematical object"))
    (else
     (define assignments (hash-ref (c-object-options raw) 'values '()))
     (if (not (list? assignments))
         (undefined "snapshot-of #:values must be a list of parameter assignments")
         (let loop ((remaining assignments)
                    (frozen (hash-ref environment snapshot-basis-key
                                      (initial-values model (hash)))))
           (if (null? remaining)
               (defined frozen)
               (let ((assignment (first remaining)))
                 (cond
                   ((not (and (pair? assignment)
                              (c-node? (car assignment))
                              (eq? (c-node-kind (car assignment)) 'parameter)))
                    (undefined "snapshot-of #:values requires direct parameter bindings"))
                   (else
                    (result-bind
                     (eval-raw (cdr assignment) frozen model computation lexical)
                     (lambda (value)
                       (if (valid-parameter-assignment?
                            (car assignment) value frozen model computation)
                           (loop (rest remaining)
                                 (hash-set frozen (c-node-id (car assignment)) value))
                           (undefined "snapshot-of value is outside its parameter contract")))))))))))))

;; eval-snapshot : semantic-value? hash? calculus-model? calculus-computation? hash? -> calculus-result?
;;   Re-evaluates one object using its fixed parameter assignment.
(define (eval-snapshot snapshot environment model computation lexical)
  (define raw (node-raw snapshot))
  (result-bind
   (snapshot-frozen-environment snapshot environment model computation lexical)
   (lambda (frozen)
     (eval-raw (first (c-object-arguments raw)) frozen model computation lexical))))

(define (eval-object object environment model computation lexical)
  (case (c-object-kind object)
    [(graph graph-restriction formula formula-of ref value point-label graph-label quantity-label value-readout
            interval-marker endpoint-marker approach-marker region-under region-between integral-region riemann-rectangles trapezoidal-regions
            partition-marks
            trace-of formula-occurrence quantity-correspondence in-view output-reading)
     (defined object)]
    [(snapshot-of) (eval-snapshot object environment model computation lexical)]
    [(point point-on axis-point projection root-point intersection-point point-on-line) (eval-point object environment model computation lexical)]
    [(feature-point) (eval-feature-point object environment model computation lexical)]
    [(error-segment) (eval-error-segment object environment model computation lexical)]
    [(slope-triangle) (eval-slope-triangle object environment model computation lexical)]
    [(segment line-through ray-through horizontal-line vertical-line chord secant tangent vertical-tangent normal) (eval-line object environment model computation lexical)]
    [(increment) (defined object)]
    [(definite-integral)
     (eval-integral (first (c-object-arguments object)) (hash-ref (c-object-options object) 'from) (hash-ref (c-object-options object) 'to)
                    (hash-ref (c-object-options object) 'antiderivative #f) environment model computation lexical)]
    [(trapezoidal-sum) (eval-trapezoidal-sum object environment model computation lexical)]
    [(riemann-sum) (defined object)]
    [(uniform-partition partition tag-partition) (defined object)]
    [(level-set) (eval-level-set object environment model computation lexical)]
    [(solution-inputs) (eval-solution-inputs object environment model computation lexical)]
    [(partial-sum)
     (eval-partial-sum (first (c-object-arguments object))
                       (hash-ref (c-object-options object) 'from #f)
                       (hash-ref (c-object-options object) 'to #f)
                       environment model computation lexical)]
    [(sequence-points) (eval-sequence-points object environment model computation lexical)]
    [(newton-diagram) (eval-newton-diagram object environment model computation lexical)]
    [(use-component)
     (result-bind
      (component-instance-valid? object environment model computation lexical)
      (lambda (_) (defined object)))]
    [(sign-claim)
     (eval-analysis-claim object 'sign-claim
                          '(positive negative zero nonnegative nonpositive)
                          environment model computation lexical)]
    [(monotonicity-claim)
     (eval-analysis-claim object 'monotonicity-claim
                          '(increasing decreasing nondecreasing nonincreasing)
                          environment model computation lexical)]
    [(concavity-claim)
     (eval-analysis-claim object 'concavity-claim '(up down)
                          environment model computation lexical)]
    [(sign-chart) (eval-sign-chart object environment model computation lexical)]
    [(input-band output-band) (eval-band object environment model computation lexical)]
    [(limit-statement) (eval-limit-statement object environment model computation lexical)]
    [(epsilon-delta-condition) (eval-epsilon-delta-condition object environment model computation lexical)]
    [(continuity-condition) (eval-continuity-condition object environment model computation lexical)]
    [(asymptote-line) (eval-asymptote-line object environment model computation lexical)]
    [(iteration-map newton-iteration) (defined object)]
    [(iteration-value)
     (eval-raw (second (c-object-arguments object)) environment model computation lexical)]
    [else (defined object)]))

;; -------------------------------------------------------------------------
;; Snapshot, timeline, and inspection

;; initial-values : calculus-model? hash? -> immutable-hash?
;;   Applies validated public parameter overrides to declaration-time values.
(define (initial-values model overrides)
  (unless (hash? overrides) (raise-argument-error 'calculus-model-at "hash?" overrides))
  (define base
    (for/fold ([state (hash)]) ([(name node) (in-hash (calculus-model-nodes model))])
      (if (eq? (c-node-kind node) 'parameter)
          (hash-set state name (c-param-spec-initial (c-node-data node)))
          state)))
  (for/fold ([state base]) ([(name value) (in-hash overrides)])
    (define node (hash-ref (calculus-model-nodes model) name #f))
    (unless (and node (eq? (c-node-kind node) 'parameter))
      (raise-arguments-error 'calculus-model-at "override names a public parameter" "address" name))
    (unless (finite-real? value)
      (raise-arguments-error 'calculus-model-at "override is a finite real" "value" value))
    (when (and (eq? (c-param-spec-kind (c-node-data node)) 'integer) (not (exact-integer? value)))
      (raise-arguments-error 'calculus-model-at "integer parameter override" "value" value))
    (define inside? (domain-contains? (c-param-spec-domain (c-node-data node)) value state model default-calculus-computation))
    (unless (and (eq? (calculus-result-status inside?) 'defined) (calculus-result-value inside?))
      (raise-arguments-error 'calculus-model-at "override is inside its parameter domain" "address" name "value" value))
    (hash-set state name value)))

;; calculus-model-at : calculus-model? keyword-options -> calculus-snapshot?
;;   Samples one model independently of views, timing, and native preparation.
(define (calculus-model-at model #:values [values (hash)] #:computation [computation default-calculus-computation])
  (check 'calculus-model-at calculus-model? "calculus-model?" model)
  (check 'calculus-model-at calculus-computation? "calculus-computation?" computation)
  (define initial (initial-values model values))
  (calculus-snapshot model (hash-set initial snapshot-basis-key initial) (hash) '() computation))

;; target-key : semantic-target? -> (or/c list? #f)
;;   Normalizes a public target to its stable presentation key.
(define (target-key target)
  (cond [(c-node? target) (list (c-node-id target))]
        [(c-part? target) (append (target-key (c-part-parent target)) (if (list? (c-part-name target)) (c-part-name target) (list (c-part-name target))))]
        [(and (c-object? target) (eq? (c-object-kind target) 'in-view)) (target-key (second (c-object-arguments target)))]
        [else #f]))

;; in-view-name : semantic-target? -> (or/c symbol? #f)
;;   Extracts the declared presentation container from an in-view wrapper while
;; leaving the underlying mathematical identity untouched.
(define (in-view-name target)
  (and (c-object? target)
       (eq? (c-object-kind target) 'in-view)
       (= (length (c-object-arguments target)) 2)
       (symbol? (first (c-object-arguments target)))
       (first (c-object-arguments target))))

;; view-target-key : symbol? list? -> list?
;; view-container-key : symbol? -> list?
;; view-membership-key : symbol? list? -> list?
;;   These private namespaces retain per-view presentation state without
;; cloning model nodes or confusing a view name with a public math address.
(define (view-target-key view key)
  (and (symbol? view) key (list 'calculus-view-target view key)))
(define (view-container-key view)
  (and (symbol? view) (list 'calculus-view-container view)))
(define (view-membership-key view key)
  (and (symbol? view) key (list 'calculus-view-membership view key)))

;; presentation-target-key : semantic-target? -> (or/c list? #f)
;;   A qualified target carries only presentation scope; an unqualified target
;; keeps the shared root/part key used by every explicit presentation.
(define (presentation-target-key target)
  (define key (target-key target))
  (if (in-view-name target)
      (view-target-key (in-view-name target) key)
      key))

;; presentation-visibility-key : semantic-target? -> (or/c list? #f)
;;   A graph/formula/number-line view is a presentation container; all other
;; targets use their global or explicitly view-qualified presentation key.
(define (presentation-visibility-key target)
  (cond [(c-view? target) (view-container-key (c-view-name target))]
        [else (presentation-target-key target)]))

(define missing-presentation-value (gensym 'missing-presentation-value))

;; target-root-key : list? -> list?
;;   Selects a target's root key for inherited visibility.
(define (target-root-key key) (and key (list (first key))))
;; presentation-state-key : symbol? semantic-target? -> (or/c list? #f)
;;   Separates non-visibility presentation state from public target paths. The
;;   semantic target still owns identity; this private prefix simply prevents a
;;   state slot from being mistaken for a drawable object address.
(define (presentation-state-key property target)
  (define key (presentation-target-key target))
  (and key (list 'calculus-presentation-state property key)))
;; label-preference-key : semantic-target? [symbol?] -> (or/c list? #f)
;;   Stores a label-only preference separately from mathematical object
;;   visibility.  A view-qualified command owns only that presentation scope.
(define (label-preference-key target [view #f])
  (define key (target-key target))
  (and key
       (list 'calculus-presentation-state 'label-visible
             (if view (view-target-key view key) (presentation-target-key target)))))
;; set-presentation-state : hash? symbol? list? boolean? -> hash?
;;   Applies one persistent or sampled presentation property to direct target
;;   identities without changing visibility inheritance.
(define (set-presentation-state presentation property targets value)
  (for/fold ([current presentation]) ([target (in-list targets)])
    (define key (presentation-state-key property target))
    (if key
        (if value
            (hash-set current key value)
            (hash-remove current key))
        current)))

;; motion-state-at : hash? semantic-target? (or/c symbol? #f) -> any/c
;; Reads one transient native-motion record with the same view-local fallback
;; rule used for emphasis.  Motion is presentation state only: it never enters
;; the mathematical value environment or changes a plan's endpoint semantics.
(define (motion-state-at presentation target property [view #f])
  (define key (target-key target))
  (define local-key (and view (view-target-key view key)))
  (define local
    (if local-key
        (hash-ref presentation
                  (list 'calculus-presentation-state property local-key)
                  missing-presentation-value)
        missing-presentation-value))
  (if (eq? local missing-presentation-value)
      (hash-ref presentation (presentation-state-key property target) #f)
      local))
;; label-preferred? : hash? semantic-target? -> boolean?
;;   Reads the persistent label preference, defaulting to visible without
;;   granting any visibility to the associated mathematical owner.
(define (label-preferred? presentation target)
  (define key (label-preference-key target))
  (if key (hash-ref presentation key #t) #t))
;; set-label-preference : hash? list? boolean? -> hash?
;;   Commits a label-only command without changing the parent object's state.
(define (set-label-preference presentation targets on?)
  (for/fold ([current presentation]) ([target (in-list targets)])
    (define key (label-preference-key target))
    (if key (hash-set current key on?) current)))

;; same-semantic-target? : semantic-value? semantic-value? -> boolean?
;;   Compares the stable semantic identities which can occur in an authored
;; correspondence without consulting a view or a rendered glyph.  Nodes use
;; their model names and parts retain their full lexical parent path.
(define (same-semantic-target? left right)
  (cond [(and (c-node? left) (c-node? right))
         (eq? (c-node-id left) (c-node-id right))]
        [(and (c-part? left) (c-part? right))
         (and (equal? (c-part-name left) (c-part-name right))
              (same-semantic-target? (c-part-parent left) (c-part-parent right)))]
        [else (equal? left right)]))

;; semantic-member? : semantic-value? list? -> boolean?
;;   Keeps quantity-link traversal identity-based rather than equating equal
;; numeric values from unrelated mathematical quantities.
(define (semantic-member? value values)
  (for/or ([candidate (in-list values)])
    (same-semantic-target? value candidate)))

;; formula-refers-to-quantity? : semantic-value? list? -> boolean?
;;   Looks through held Formula leaves only. This is deliberately structural:
;; matching characters such as two occurrences of "x" cannot create a link.
(define (formula-refers-to-quantity? value quantities)
  (cond [(semantic-member? value quantities) #t]
        [(c-expression? value)
         (for/or ([argument (in-list (c-expression-arguments value))])
           (formula-refers-to-quantity? argument quantities))]
        [(c-object? value)
         (case (c-object-kind value)
           [(ref value formula-occurrence)
            (for/or ([argument (in-list (c-object-arguments value))])
              (formula-refers-to-quantity? argument quantities))]
           [else #f])]
        [else #f]))

;; quantity-source-targets : semantic-value? -> list?
;;   Supplies the drawable construction behind a derived quantity. A slope,
;; for example, is linked to its retained secant/tangent object, while ordinary
;; arithmetic inputs are not indiscriminately highlighted.
(define (quantity-source-targets target)
  (define raw (node-raw target))
  (cond [(and (c-expression? raw)
              (memq (c-expression-op raw)
                    '(slope x-coordinate y-coordinate sum-value iterate-value)))
         (c-expression-arguments raw)]
        [(and (c-object? raw)
              (memq (c-object-kind raw)
                    '(slope x-coordinate y-coordinate sum-value iterate-value)))
         (c-object-arguments raw)]
        [else '()]))

;; expand-quantity-correspondences : calculus-model? semantic-value? -> list?
;;   Computes the transitive, author-declared quantity relation and the small
;; set of retained visual sources of those quantities.  No equality comparison
;; or renderer inspection participates in this relation.
(define (expand-quantity-correspondences model target)
  (let loop ([known (list target)])
    (define correspondence-targets
      (apply append
             (for/list ([node (in-hash-values (calculus-model-nodes model))])
               (define raw (node-raw node))
               (if (and (c-object? raw)
                        (eq? (c-object-kind raw) 'quantity-correspondence)
                        (for/or ([argument (in-list (c-object-arguments raw))])
                          (semantic-member? argument known)))
                   (c-object-arguments raw)
                   '()))))
    (define linked
      (append (apply append (map quantity-source-targets known))
              correspondence-targets))
    (define next
      (foldl (lambda (value current)
               (if (semantic-member? value current) current (append current (list value))))
             known linked))
    (if (= (length next) (length known)) known (loop next))))

;; quantity-highlight-targets : calculus-lesson? hash? semantic-value? -> list?
;;   Resolves a quantity action to the visible representations that author the
;; same quantity: direct objects, owned reading parts, Formula leaves, and
;; value readouts. An absent representation is intentionally a no-op.
(define (quantity-highlight-targets lesson presentation target)
  (define model (calculus-lesson-model lesson))
  (define quantities (expand-quantity-correspondences model target))
  (define (representation-refers? candidate)
    (or (semantic-member? candidate quantities)
        (for/or ([quantity (in-list quantities)])
          (and (c-part? quantity)
               (same-semantic-target? candidate (c-part-parent quantity))))
        (let ([raw (node-raw candidate)])
          (cond [(and (c-object? raw)
                      (memq (c-object-kind raw) '(formula formula-of)))
                 (formula-refers-to-quantity?
                  (first (c-object-arguments raw)) quantities)]
                [(and (c-object? raw)
                      (eq? (c-object-kind raw) 'value-readout))
                 (formula-refers-to-quantity?
                  (first (c-object-arguments raw)) quantities)]
                [else #f]))))
  (remove-duplicates
   (for*/list ([view (in-hash-values (calculus-lesson-views lesson))]
               [candidate (in-list (hash-ref (c-view-options view) 'objects '()))]
               #:when (and (representation-refers? candidate)
                           (presentation-visible? presentation candidate)))
     candidate)
   same-semantic-target?))
;; presentation-visible? : hash? semantic-target? -> boolean?
;;   Evaluates the same direct-or-root visibility inheritance used by public
;; snapshots, but for compiler diagnostics before a snapshot exists.
(define (presentation-visible? presentation target)
  (define (global-visible? key)
    ;; An explicit #f must mask inherited root visibility.  `hash-ref` with
    ;; #f as its default would accidentally turn a direct hide back into a
    ;; visible inherited root.
    (define direct (hash-ref presentation key missing-presentation-value))
    (if (eq? direct missing-presentation-value)
        (hash-ref presentation (target-root-key key) #f)
        direct))
  (define (view-visible? view key)
    (define scoped (hash-ref presentation (view-target-key view key)
                             missing-presentation-value))
    (if (eq? scoped missing-presentation-value)
        (global-visible? key)
        scoped))
  (cond
    [(c-view? target)
     (define name (c-view-name target))
     (define container
       (hash-ref presentation (view-container-key name)
                 missing-presentation-value))
     (cond
       [(not (eq? container missing-presentation-value)) container]
       [else
        ;; A declared view inherits the visibility of its member
        ;; presentations until the view itself is explicitly shown or hidden.
        (for/or ([(membership member?) (in-hash presentation)])
          (match membership
            [(list 'calculus-view-membership candidate key)
             (and (eq? candidate name) member? (view-visible? name key))]
            [_ #f]))])]
    [else
     (define key (target-key target))
     (and key
          (if (in-view-name target)
              (view-visible? (in-view-name target) key)
              (global-visible? key)))]))
;; set-presentation-visibility : hash? list? boolean? -> hash?
;;   Updates only direct persistent target visibility. Root inheritance remains
;; a query rule, so a later parent hide can still affect an untouched child.
(define (set-presentation-visibility presentation targets on?)
  (for/fold ([current presentation]) ([target (in-list targets)])
    (define key (presentation-visibility-key target))
    (if key (hash-set current key on?) current)))
;; persistent-action-delta : hash? c-action? -> c-action?
;;   Drops redundant persistent targets before timeline lowering. A command
;; with no remaining targets is a true no-op: it creates no event, state
;; change, ordinal, or duration. Mixed target lists retain only changed leaves.
(define (persistent-action-delta presentation action)
  (define kind (c-action-kind action))
  (define targets (c-action-targets action))
  (define changed
    (case kind
      [(show)
       (filter (lambda (target) (not (presentation-visible? presentation target)))
               targets)]
      [(hide)
       (filter (lambda (target) (presentation-visible? presentation target))
               targets)]
      [(show-label)
       (filter (lambda (target) (not (label-preferred? presentation target)))
               targets)]
      [(hide-label)
       (filter (lambda (target) (label-preferred? presentation target))
               targets)]
      [(deemphasize)
       (filter (lambda (target)
                 (not (hash-ref presentation
                                (presentation-state-key 'deemphasized target) #f)))
               targets)]
      [(normalize)
       (filter (lambda (target)
                 (hash-ref presentation
                           (presentation-state-key 'deemphasized target) #f))
               targets)]
      [else #f]))
  (and changed (c-action kind changed (c-action-options action))))
;; presentation-state-after-action : hash? c-action? -> hash?
;;   Mirrors persistent action effects for compile-time redundant-command
;; elimination without sampling a native frame or evaluating mathematical
;; geometry. Together children are already conflict-checked and may be merged
;; in source order for their disjoint presentation slots.
(define (presentation-state-after-action presentation action)
  (case (c-action-kind action)
    [(show read)
     (set-presentation-visibility presentation (c-action-targets action) #t)]
    [(hide)
     (set-presentation-visibility presentation (c-action-targets action) #f)]
    [(show-label)
     (set-label-preference presentation (c-action-targets action) #t)]
    [(hide-label)
     (set-label-preference presentation (c-action-targets action) #f)]
    [(deemphasize)
     (set-presentation-state presentation 'deemphasized (c-action-targets action) #t)]
    [(normalize)
     (set-presentation-state presentation 'deemphasized (c-action-targets action) #f)]
    [(limit-transition)
     (define targets (c-action-targets action))
     (if (= (length targets) 2)
         (set-presentation-visibility
          (set-presentation-visibility presentation (list (first targets)) #f)
          (list (second targets)) #t)
         presentation)]
    [(explain)
     (if (eq? (hash-ref (c-action-options action) 'mode 'collapsed) 'expanded)
         presentation
         (set-presentation-visibility presentation (c-action-targets action) #t))]
    [(together)
     (for/fold ([current presentation]) ([child (in-list (c-action-targets action))]
                                         #:when (c-action? child))
       (presentation-state-after-action current child))]
    [else presentation]))
;; presentation-state-after-events : hash? list? -> hash?
;;   Advances compile-time presentation state through the emitted leaf events.
(define (presentation-state-after-events presentation events)
  (for/fold ([current presentation]) ([event (in-list events)])
    (presentation-state-after-action current (c-event-action event))))
;; trace-prefix-key : semantic-target? -> (or/c list? #f)
;;   Reserves a private presentation slot for a trace's authored sweep prefix.
;;   Its nested shape cannot overlap an ordinary flat public target key.
(define (trace-prefix-key target)
  (define key (target-key target))
  (and key (list 'trace-prefix key)))
;; view-window-key : c-view? -> (or/c list? #f)
;;   Names one view's private camera-window presentation state.
(define (view-window-key view)
  (and (c-view? view) (c-view-name view) (list 'view-window (c-view-name view))))

;; resolve-view-reference : calculus-lesson? any/c -> (or/c c-view? #f)
;;   Resolves an authored focus/restore name to its one declared view.
(define (resolve-view-reference lesson target)
  (and (c-view? target)
       (c-view-name target)
       (hash-ref (calculus-lesson-views lesson) (c-view-name target) #f)))

;; finite-interval-bounds : any/c hash? calculus-model? calculus-computation?
;;                          -> (or/c (list/c finite-real? finite-real?) #f)
;;   Evaluates an authored finite, increasing interval without treating an open
;;   endpoint as a different camera coordinate.
(define (finite-interval-bounds domain values model computation)
  (and (c-domain? domain)
       (memq (c-domain-kind domain) '(closed open closed-open open-closed))
       (= (length (c-domain-arguments domain)) 2)
       (let ([left (eval-raw (first (c-domain-arguments domain)) values model computation)]
             [right (eval-raw (second (c-domain-arguments domain)) values model computation)])
         (and (eq? (calculus-result-status left) 'defined)
              (eq? (calculus-result-status right) 'defined)
              (finite-real? (calculus-result-value left))
              (finite-real? (calculus-result-value right))
              (< (calculus-result-value left) (calculus-result-value right))
              (list (calculus-result-value left) (calculus-result-value right))))))

;; view-window-values : c-view? hash? calculus-model? calculus-computation? -> (or/c list? #f)
;;   Resolves a graph view's declared x/y windows to four finite coordinates.
(define (view-window-values view values model computation)
  (and (c-view? view)
       (eq? (c-view-kind view) 'graph-view)
       (let ([x-bounds (finite-interval-bounds (hash-ref (c-view-options view) 'x #f)
                                               values model computation)]
             [y-bounds (finite-interval-bounds (hash-ref (c-view-options view) 'y #f)
                                               values model computation)])
         (and x-bounds y-bounds (append x-bounds y-bounds)))))

;; auto-y-graph-view? : any/c -> boolean?
;;   Marks the one camera case whose baseline is deliberately determined by
;; native preparation rather than by an authored finite y interval.
(define (auto-y-graph-view? view)
  (and (c-view? view)
       (eq? (c-view-kind view) 'graph-view)
       (eq? (hash-ref (c-view-options view) 'y #f) 'auto)))

;; finite-view-window? : any/c -> boolean?
;;   Separates ordinary sampled camera coordinates from the private symbolic
;; auto-window transition records retained until native preparation resolves
;; their frozen baseline.
(define (finite-view-window? window)
  (and (list? window)
       (= (length window) 4)
       (andmap finite-real? window)
       (< (first window) (second window))
       (< (third window) (fourth window))))

;; focus-target-window : c-action? hash? calculus-model? calculus-computation? calculus-lesson?
;;                       -> (or/c (cons/c c-view? list?) #f)
;;   Validates the one graph-view target and freezes the requested coordinates
;;   from the action's start environment.
(define (focus-target-window action values model computation lesson)
  (define targets (c-action-targets action))
  (define view (and (= (length targets) 1)
                    (resolve-view-reference lesson (first targets))))
  (define x-bounds
    (finite-interval-bounds (hash-ref (c-action-options action) 'x #f)
                            values model computation))
  (define y-bounds
    (finite-interval-bounds (hash-ref (c-action-options action) 'y #f)
                            values model computation))
  (and view
       (eq? (c-view-kind view) 'graph-view)
       x-bounds y-bounds
       (cons view (append x-bounds y-bounds))))

;; valid-restore-view? : c-action? calculus-lesson? -> boolean?
;;   A restore is meaningful only for one declared graph view.
(define (valid-restore-view? action lesson)
  (define targets (c-action-targets action))
  (define view (and (= (length targets) 1)
                    (resolve-view-reference lesson (first targets))))
  (and view (eq? (c-view-kind view) 'graph-view)))

;; trace-write-keys : c-action? -> list?
;;   Assigns the sweep capability and revealed locus to a trace action.
(define (trace-write-keys action)
  (append
   (for/list ([target (in-list (c-action-targets action))]
              #:do [(define parameter (trace-sweep-parameter target))]
              #:when parameter)
     (list 'parameter (c-node-id parameter)))
   (for/list ([target (in-list (c-action-targets action))]
              #:do [(define key (target-key target))]
              #:when key)
     (list 'presentation 'visibility key))))

;; presentation-write-keys : symbol? list? -> list?
;;   Associates persistent presentation state with stable semantic addresses.
(define (presentation-write-keys property targets)
  (for/list ([target (in-list targets)]
             #:do [(define key (presentation-visibility-key target))]
             #:when key)
    (list 'presentation property key)))

;; action-write-keys : c-action? -> list?
;;   Lists the semantic state slots a leaf action changes for together checks.
(define (action-write-keys action)
  (define kind (c-action-kind action))
  (define targets (c-action-targets action))
  (case kind
    [(vary set-parameter approach)
     (define parameter (action-parameter action))
     (if parameter (list (list 'parameter (c-node-id parameter))) '())]
    [(refine)
     (define parameter (refinement-count-parameter action))
     (if parameter (list (list 'parameter (c-node-id parameter))) '())]
    [(trace) (trace-write-keys action)]
    [(show hide read) (presentation-write-keys 'visibility targets)]
    [(show-label hide-label) (presentation-write-keys 'label-visibility targets)]
    [(deemphasize normalize) (presentation-write-keys 'emphasis targets)]
    [(highlight highlight-quantity compare) (presentation-write-keys 'highlight targets)]
    [(limit-transition) (presentation-write-keys 'visibility targets)]
    [(focus restore-view)
     (for/list ([target (in-list targets)]
                #:when (c-view? target))
       (list 'view (c-view-name target)))]
    [else '()]))

;; target-keys-overlap? : list? list? -> boolean?
;;   Tests ancestor/descendant overlap without using renderer geometry.
(define (target-keys-overlap? first second)
  (or (and (<= (length first) (length second))
           (equal? first (take second (length first))))
      (and (<= (length second) (length first))
           (equal? second (take first (length second))))))

;; write-keys-conflict? : list? list? -> boolean?
;;   Keeps parameter, presentation-property, and view-window writes distinct.
(define (write-keys-conflict? left right)
  (cond
    [(and (eq? (first left) 'parameter) (eq? (first right) 'parameter))
     (eq? (second left) (second right))]
    [(and (eq? (first left) 'presentation) (eq? (first right) 'presentation))
     (and (eq? (second left) (second right))
          (target-keys-overlap? (third left) (third right)))]
    [(and (eq? (first left) 'view) (eq? (first right) 'view))
     (eq? (second left) (second right))]
    [else #f]))

;; group-conflicts? : list? -> boolean?
;;   Detects any two together children that write an overlapping state slot.
(define (group-conflicts? events)
  (for*/or ([first-event (in-list events)]
            [second-event (in-list events)]
            #:when (< (c-event-ordinal first-event) (c-event-ordinal second-event)))
    (for*/or ([first-write (in-list (action-write-keys (c-event-action first-event)))]
              [second-write (in-list (action-write-keys (c-event-action second-event)))])
      (write-keys-conflict? first-write second-write))))

;; conflicting-event-groups : list? -> list?
;;   Returns together groups whose children cannot share a start state.
(define (conflicting-event-groups events)
  (define groups
    (remove-duplicates (filter values (map c-event-group events))))
  (for/list ([group (in-list groups)]
             #:when (group-conflicts? (filter (lambda (event)
                                                 (equal? (c-event-group event) group))
                                               events)))
    group))

;; together-diagnostics : list? -> list?
;;   Reports one stable error per rejected simultaneous action group.
(define (together-diagnostics events)
  (for/list ([group (in-list (conflicting-event-groups events))])
    (define group-events
      (filter (lambda (event) (equal? (c-event-group event) group)) events))
    (calculus-diagnostic 'error 'action-conflict #f #f
                         (c-event-start (first group-events))
                         "together children cannot write the same parameter, presentation property, or view window")))

;; expanded-explain-action? : any/c -> boolean?
;;   Keeps the enclosing-step and grouping restrictions structural, before any
;;   private component step can be spliced into the public timeline.
(define (expanded-explain-action? action)
  (and (c-action? action)
       (eq? (c-action-kind action) 'explain)
       (eq? (hash-ref (c-action-options action) 'mode 'collapsed) 'expanded)))

;; expanded-explain-inside-together? : any/c -> boolean?
;;   Finds prohibited expanded explanation descendants without rejecting the
;;   ordinary nested `together` combinations used by other action kinds.
(define (expanded-explain-inside-together? command [inside-together? #f])
  (cond
    [(not (c-action? command)) #f]
    [(and inside-together? (expanded-explain-action? command)) #t]
    [(eq? (c-action-kind command) 'together)
     (for/or ([child (in-list (c-action-targets command))])
       (expanded-explain-inside-together? child #t))]
    [else #f]))

;; component-explain-diagnostics : calculus-lesson? -> list?
;;   Expanded component exposition owns a caption/timing sequence, so it must
;;   be the sole command in its enclosing outer step and cannot join a parallel
;;   group. Failed expansion leaves no collapsed visibility fallback.
(define (component-explain-diagnostics lesson)
  (append-map
   (lambda (step)
     (define commands (c-step-commands step))
     (append
      (for/list ([command (in-list commands)]
                 #:when (and (expanded-explain-action? command)
                             (not (= (length commands) 1))))
        (calculus-diagnostic 'error 'component-explain #f #f #f
                             "expanded explain must be the only command in its enclosing step"))
      (for/list ([command (in-list commands)]
                 #:when (expanded-explain-inside-together? command))
        (calculus-diagnostic 'error 'component-explain #f #f #f
                             "expanded explain cannot occur inside together"))
      (for/list ([command (in-list commands)]
                 #:when (and (expanded-explain-action? command)
                             (not (expanded-component-exposition command))))
        (calculus-diagnostic 'error 'component-explain #f #f #f
                             "expanded explain requires one component instance with a nonempty exposition"))
      (for/list ([command (in-list commands)]
                 #:when (and (expanded-explain-action? command)
                             (not (memq (hash-ref (c-action-options command)
                                                  'auxiliaries 'hide)
                                        '(hide deemphasize keep)))))
        (calculus-diagnostic 'error 'component-auxiliaries #f #f #f
                             "expanded explain #:auxiliaries must be 'hide, 'deemphasize, or 'keep"))))
   (calculus-lesson-steps lesson)))

;; component-exposition-write-diagnostics : calculus-lesson? -> list?
;;   Makes the Parameter<...> capability boundary explicit during compilation
;;   instead of merely letting an unauthorized local command become inert.
(define (component-exposition-write-diagnostics lesson)
  (define (actions command)
    (cond
      [(not (c-action? command)) '()]
      [(eq? (c-action-kind command) 'together)
       (append-map actions (c-action-targets command))]
      [else (list command)]))
  (define (diagnostics-for-command command)
    (define expansion
      (and (expanded-explain-action? command)
           (expanded-component-exposition command)))
    (cond
      [(not expansion) '()]
      [else
       (define instance (first expansion))
       (define component (second expansion))
       (define steps (third expansion))
       (append-map
        (lambda (local-step)
          (for/list ([local-command
                      (in-list (append-map actions (c-step-commands local-step)))]
                     #:when (and (memq (c-action-kind local-command)
                                        '(vary approach set-parameter))
                                 (pair? (c-action-targets local-command))
                                 (not (component-writable-input-target
                                       instance component
                                       (first (c-action-targets local-command))))))
            (calculus-diagnostic 'error 'component-capability #f #f #f
                                 "component parameter actions require the matching direct Parameter input")))
        steps)]))
  (append-map
   (lambda (step)
     (append-map diagnostics-for-command (c-step-commands step)))
   (calculus-lesson-steps lesson)))

;; component-private-graph-presentable? : c-part? -> boolean?
;;   Restricts placement diagnostics to private leaves the native graph adapter
;;   can actually present. Pure scalar intermediates remain private semantic
;;   support data and do not demand an invented panel location.
(define (component-private-graph-presentable? part)
  (define node (calculus-component-private-part-node part))
  (and node
       (memq (c-node-kind node)
             '(graph graph-restriction point point-on axis-point projection
                     root-point intersection-point segment line-through ray-through
                     horizontal-line vertical-line chord secant tangent vertical-tangent
                     normal error-segment asymptote-line slope-triangle increment
                     epsilon-delta-condition riemann-rectangles trapezoidal-regions
                     partition-marks integral-region region-under region-between
                     sequence-points newton-diagram trace-of input-reading
                     coordinate-reading))))

;; component-private-placement-diagnostics : calculus-lesson? -> list?
;;   Requires one explicit, compatible caller graph view for every private
;;   construction that an expanded explanation may present. Renderer traversal
;;   order is never allowed to choose between two plausible panels.
(define (component-private-placement-diagnostics lesson)
  (apply append
         (for/list ([outer-step (in-list (calculus-lesson-steps lesson))])
           (apply append
                  (for/list ([command (in-list (c-step-commands outer-step))])
                    (define expansion
                      (and (= (length (c-step-commands outer-step)) 1)
                           (expanded-explain-action? command)
                           (expanded-component-exposition command)))
                    (if (not expansion)
                        '()
                        (let ([instance (first expansion)])
                          (for/list
                              ([part (in-list
                                      (calculus-component-private-presentation-parts instance))]
                               #:when
                               (and (component-private-graph-presentable? part)
                                    (not (= (length
                                              (calculus-component-private-presentation-view-names
                                               lesson instance part))
                                            1))))
                            (calculus-diagnostic
                             'error 'component-placement
                             (list (c-node-id instance) (second (c-part-name part)))
                             (c-step-id outer-step) #f
                             "private component construction requires one compatible graph view")))))))))

;; refine-count-expressions : c-action? -> list?
;;   Extracts the held count sequence so each requested transition gets one duration.
(define (refine-count-expressions action)
  (define counts (hash-ref (c-action-options action) 'counts '()))
  (cond
    [(and (c-expression? counts) (eq? (c-expression-op counts) 'list))
     (c-expression-arguments counts)]
    [(list? counts) counts]
    [else '()]))

;; duration-of : c-action? nonnegative-real? -> nonnegative-real?
;;   Resolves one action's semantic duration without native timing callbacks.
(define (duration-of action fallback)
  (case (c-action-kind action)
    [(set-parameter checkpoint) 0]
    [(pause) (first (c-action-targets action))]
    [(refine) (* fallback (length (refine-count-expressions action)))]
    [(together) #f]
    [else (hash-ref (c-action-options action) 'duration fallback)]))

;; component-local-address : semantic-target? -> (or/c (listof symbol?) #f)
;;   Identifies the private component path named by a source-level exposition
;;   target.  It never inspects presentation state.
(define (component-local-address target)
  (cond
    [(c-node? target) (list (c-node-id target))]
    [(c-part? target)
     (define parent-address (component-local-address (c-part-parent target)))
     (and parent-address
          (append parent-address
                  (if (list? (c-part-name target))
                      (c-part-name target)
                      (list (c-part-name target)))))]
    [else #f]))

;; component-presentation-target : c-node? calculus-component? semantic-target? -> any/c
;;   Rehomes exported private targets under their caller-visible instance and
;;   keeps non-exported model objects under a renderer-only private namespace.
;;   Thus a component cannot accidentally write a caller presentation whose
;;   spelling happens to match one of its implementation names.
(define (component-presentation-target instance component target)
  (define address (component-local-address target))
  (cond
    [(not (and address (pair? address))) #f]
    [(member (first address) (calculus-component-exports component))
     (for/fold ([public (c-part instance (first address))])
               ([part-name (in-list (rest address))])
       (c-part public part-name))]
    [else
     (define instance-result (component-instance-model instance))
     (and (eq? (calculus-result-status instance-result) 'defined)
          (hash-has-key? (calculus-model-nodes (calculus-result-value instance-result))
                         (first address))
          (c-part instance (cons 'private address)))]))

;; component-writable-input-target : c-node? calculus-component? any/c -> any/c
;;   Returns the original caller parameter only when the component explicitly
;;   declared the corresponding supplied argument as Parameter<...>. A scalar
;;   input that happens to depend on a parameter remains read-only.
(define (component-writable-input-target instance component target)
  (define raw (node-raw instance))
  (define supplied (and (c-object? raw) (rest (c-object-arguments raw))))
  (for/or ([declaration (in-list (calculus-component-inputs component))]
           [value (in-list supplied)])
    (and (pair? declaration)
         (component-input-kind-valid? (cdr declaration) value)
         (list? (cdr declaration))
         (= (length (cdr declaration)) 2)
         (eq? (first (cdr declaration)) 'Parameter)
         (equal? value target)
         value)))

;; rewrite-component-exposition-action : c-action? c-node? calculus-component? -> c-action?
;;   Preserves timing and non-target operands while translating only exported
;;   presentation targets.  This prevents a component explanation from gaining
;;   access to a caller's private names or parameter capability.
(define (rewrite-component-exposition-action action instance component)
  (define kind (c-action-kind action))
  (define rewritten-targets
    (if (eq? kind 'together)
        (for/list ([child (in-list (c-action-targets action))])
          (if (c-action? child)
              (rewrite-component-exposition-action child instance component)
              child))
        (for/list ([target (in-list (c-action-targets action))]
                   [index (in-naturals)])
          (cond
            [(and (zero? index)
                  (memq kind '(vary approach set-parameter)))
             (or (component-writable-input-target instance component target) #f)]
            ;; The remaining operands of a parameter command are mathematical
            ;; expressions evaluated in the caller state, not presentation
            ;; leaves to be namespaced under the component instance.
            [(memq kind '(vary approach set-parameter)) target]
            [(or (c-node? target) (c-part? target))
             (or (component-presentation-target instance component target) #f)]
            [else target]))))
  (c-action kind rewritten-targets (c-action-options action)))

;; expanded-component-exposition : c-action? -> (or/c list? #f)
;;   Returns an instance, declaration, and lexical private steps when `explain`
;;   explicitly requests expanded mode.  Empty or absent component exposition
;;   is intentionally left to ordinary collapsed explain behavior.
(define (expanded-component-exposition action)
  (and (eq? (c-action-kind action) 'explain)
       (eq? (hash-ref (c-action-options action) 'mode 'collapsed) 'expanded)
       (= (length (c-action-targets action)) 1)
       (let ([instance (first (c-action-targets action))])
         (and (c-node? instance)
              (let ([raw (node-raw instance)])
                (and (c-object? raw)
                     (eq? (c-object-kind raw) 'use-component)
                     (pair? (c-object-arguments raw))
                     (let ([component (first (c-object-arguments raw))])
                       (and (calculus-component? component)
                            (let ([steps-result (component-instance-exposition instance)])
                              (and (eq? (calculus-result-status steps-result) 'defined)
                                   (pair? (calculus-result-value steps-result))
                                   (list instance component
                                         (calculus-result-value steps-result)
                                         (hash-ref (c-action-options action)
                                                   'auxiliaries
                                                   'hide))))))))))))

;; component-private-cleanup-targets : c-node? calculus-component? list? -> list?
;;   Computes the private leaves still shown after a component's ordered local
;;   exposition. Redundant cleanup then has no event and consumes no time.
(define (component-private-cleanup-targets instance component steps)
  (define private-parts (calculus-component-private-presentation-parts instance))
  (define private-names
    (for/list ([part (in-list private-parts)])
      (second (c-part-name part))))
  (define (update action state)
    (cond
      [(not (c-action? action)) state]
      [(eq? (c-action-kind action) 'together)
       (for/fold ([current state]) ([child (in-list (c-action-targets action))])
         (update child current))]
      [(memq (c-action-kind action) '(show read hide))
       (for/fold ([current state]) ([target (in-list (c-action-targets action))])
         (define address (component-local-address target))
         (if (and address
                  (pair? address)
                  (member (first address) private-names))
             (hash-set current (first address)
                       (not (eq? (c-action-kind action) 'hide)))
             current))]
      [else state]))
  (define final-state
    (for/fold ([state (hash)]) ([step (in-list steps)])
      (for/fold ([current state]) ([command (in-list (c-step-commands step))])
        (update command current))))
  (filter (lambda (part)
            (hash-ref final-state (second (c-part-name part)) #f))
          private-parts))

;; checkpoint-target->address : any/c -> (or/c (listof symbol?) #f)
;;   Normalizes the source spelling accepted by `checkpoint` into the stable
;;   path representation used by calculus moments.  Component compilation can
;;   then prefix that path without treating a checkpoint name as a renderable
;;   semantic target.
(define (checkpoint-target->address target)
  (cond
    [(symbol? target) (list target)]
    [(and (list? target) (pair? target) (andmap symbol? target)) target]
    [else #f]))

;; prefix-component-checkpoint : c-action? list? -> c-action?
;;   Gives a component-local checkpoint its occurrence identity.  The prefix
;;   is the enclosing outer step followed by each expanded component instance
;;   and local step on the way to the command.
(define (prefix-component-checkpoint action prefix)
  (if (eq? (c-action-kind action) 'checkpoint)
      (c-action 'checkpoint
                (for/list ([target (in-list (c-action-targets action))])
                  (define address (checkpoint-target->address target))
                  (if address (append prefix address) target))
                (c-action-options action))
      action))

;; compile-component-exposition : c-node? calculus-component? list? symbol? real? real?
;;                                exact-nonnegative-integer? any/c list? procedure? procedure? -> values
;;   Inserts lexical component steps into the ordinary event timeline.  Nested
;;   steps keep their authored delays, durations, pauses, and `together`
;;   groups, so expanded explanation remains a semantic timeline operation.
(define (compile-component-exposition instance component steps auxiliaries start fallback ordinal group path
                                      milestone-sink caption-sink)
  (define-values (events end-time next-ordinal)
    (for/fold ([all-events '()] [current-time start] [next ordinal])
              ([step (in-list steps)])
      (define local-path (append path (list (c-node-id instance) (c-step-id step))))
      (milestone-sink 'step-start local-path current-time (sub1 next))
      (define step-start (+ current-time (or (c-step-read-delay step) 0)))
      (define command-fallback (or (c-step-duration step) fallback))
      (define-values (step-events after-commands step-next)
        (for/fold ([events '()] [time step-start] [current-ordinal next])
                  ([command (in-list (c-step-commands step))])
          (define rewritten
            (if (c-action? command)
                (prefix-component-checkpoint
                 (rewrite-component-exposition-action command instance component)
                 local-path)
                command))
          (define-values (command-events span command-next)
            (compile-command rewritten time command-fallback current-ordinal group
                             (= (length (c-step-commands step)) 1)
                             local-path milestone-sink caption-sink))
          (values (append events command-events)
                  (+ time span)
                  command-next)))
      (define step-end (+ after-commands (or (c-step-pause step) 0)))
      (milestone-sink 'step-end local-path after-commands (sub1 step-next))
      (caption-sink local-path (c-step-say step) current-time step-end)
      (values (append all-events step-events) step-end step-next)))
  (define cleanup-targets
    (if (memq auxiliaries '(hide deemphasize))
        (component-private-cleanup-targets instance component steps)
        '()))
  (if (null? cleanup-targets)
      (values events (- end-time start) next-ordinal)
      (let-values ([(cleanup-events cleanup-span cleanup-next)
                    (compile-command (c-action auxiliaries cleanup-targets (hash))
                                     end-time fallback next-ordinal #f #f path
                                     milestone-sink caption-sink)])
        (values (append events cleanup-events)
                (+ (- end-time start) cleanup-span)
                cleanup-next))))

;; compile-command : c-action? real? real? exact-nonnegative-integer? any/c boolean? list?
;;                    procedure? procedure? -> values
;;   Lowers one command or parallel group to stable leaf events.
(define (compile-command command start fallback ordinal [group #f] [allow-expanded? #t] [path '()]
                         [milestone-sink (lambda _ (void))]
                         [caption-sink (lambda _ (void))])
  (cond
    [(not (c-action? command)) (values '() 0 ordinal)]
    [(eq? (c-action-kind command) 'together)
     (define group-id (or group (list 'together ordinal)))
     (define-values (events spans next)
       (for/fold ([all '()] [span 0] [next ordinal]) ([child (in-list (c-action-targets command))])
         (define-values (child-events child-span child-next)
           (compile-command child start fallback next group-id #f path
                            milestone-sink caption-sink))
         (values (append all child-events) (max span child-span) child-next)))
     (values events spans next)]
    [else
     (define expanded (expanded-component-exposition command))
     (if (and expanded allow-expanded?)
         (compile-component-exposition (first expanded) (second expanded) (third expanded)
                                       (fourth expanded)
                                       start fallback ordinal group path
                                       milestone-sink caption-sink)
         (let ([span (duration-of command fallback)])
           (values (list (c-event ordinal start (+ start span) command group)) span (add1 ordinal))))]))

;; action-parameter : c-action? -> (or/c c-node? #f)
;;   Returns the writable semantic target when an action begins with one.
(define (action-parameter action)
  (and (pair? (c-action-targets action))
       (c-node? (first (c-action-targets action)))
       (eq? (c-node-kind (first (c-action-targets action))) 'parameter)
       (first (c-action-targets action))))

;; action-endpoint : c-action? -> any/c
;;   Selects the authored endpoint used to validate one parameter action.
(define (action-endpoint action)
  (case (c-action-kind action)
    [(vary) (hash-ref (c-action-options action) 'to #f)]
    [(approach) (hash-ref (c-action-options action) 'until #f)]
    [(set-parameter) (and (pair? (rest (c-action-targets action)))
                          (second (c-action-targets action)))]
    [else #f]))

;; domain-excluded-values : semantic-value? hash? calculus-model? calculus-computation? -> list?
;;   Collects statically evaluable exclusions so a continuous action can check
;;   its entire authored path rather than only its final value.
(define (domain-excluded-values domain environment model computation)
  (define raw (node-raw domain))
  (cond
    [(not (c-domain? raw)) '()]
    [(eq? (c-domain-kind raw) 'domain-except)
     (append
      (for/list ([hole (in-list (rest (c-domain-arguments raw)))]
                 #:do [(define result (eval-domain-number hole environment model computation))]
                 #:when (eq? (calculus-result-status result) 'defined))
        (calculus-result-value result))
      (domain-excluded-values (first (c-domain-arguments raw)) environment model computation))]
    [(memq (c-domain-kind raw) '(domain-union domain-intersection))
     (apply append
            (for/list ([child (in-list (c-domain-arguments raw))])
              (domain-excluded-values child environment model computation)))]
    [else '()]))

;; domain-path-crosses-exclusion? : c-domain? finite-real? finite-real? hash? calculus-model? calculus-computation? -> boolean?
;;   Detects an excluded interior value in a continuous action's direct path.
(define (domain-path-crosses-exclusion? domain start target environment model computation)
  (for/or ([hole (in-list (remove-duplicates
                           (domain-excluded-values domain environment model computation)))])
    (and (< (min start target) hole (max start target))
         (let ([included? (domain-contains? domain hole environment model computation)])
           (and (eq? (calculus-result-status included?) 'defined)
                (not (calculus-result-value included?)))))))

;; valid-continuous-parameter-target? : c-node? finite-real? finite-real? hash? calculus-model? calculus-computation? -> boolean?
;;   Enforces real-valued interpolation and valid paths during pure sampling.
(define (valid-continuous-parameter-target? parameter start target environment model computation)
  (and (eq? (c-param-spec-kind (c-node-data parameter)) 'real)
       (finite-real? target)
       (let ([inside? (domain-contains? (c-param-spec-domain (c-node-data parameter))
                                        target environment model computation)])
         (and (eq? (calculus-result-status inside?) 'defined)
              (calculus-result-value inside?)
              (not (domain-path-crosses-exclusion?
                    (c-param-spec-domain (c-node-data parameter)) start target
                    environment model computation))))))

;; valid-parameter-assignment? : c-node? any/c hash? calculus-model? calculus-computation? -> boolean?
;;   Checks a discrete assignment with the same kind/domain policy as planning.
(define (valid-parameter-assignment? parameter target environment model computation)
  (and (finite-real? target)
       (or (eq? (c-param-spec-kind (c-node-data parameter)) 'real)
           (exact-integer? target))
       (let ([inside? (domain-contains? (c-param-spec-domain (c-node-data parameter))
                                        target environment model computation)])
         (and (eq? (calculus-result-status inside?) 'defined)
              (calculus-result-value inside?)))))

;; valid-approach-side? : c-action? finite-real? finite-real? hash? calculus-model? calculus-computation? -> boolean?
;;   Ensures that an approach begins and stops on its explicitly authored side
;;   of a finite limiting target without ever evaluating at that target.
(define (valid-approach-side? action start stop environment model computation)
  (define target-expression (hash-ref (c-action-options action) 'to #f))
  (define target-result
    (and target-expression (eval-raw target-expression environment model computation)))
  (define side (hash-ref (c-action-options action) 'side #f))
  (and target-result
       (eq? (calculus-result-status target-result) 'defined)
       (finite-real? (calculus-result-value target-result))
       (let ([target (calculus-result-value target-result)])
         (case side
           [(left) (and (< start target) (< stop target))]
           [(right) (and (> start target) (> stop target))]
           [else #f]))))

;; event-state-before : c-event? list? pair? calculus-model? calculus-computation? [calculus-lesson?] -> pair?
;;   Reconstructs an action's start state from preceding source events without
;;   consulting rendered frames. A lesson supplies persistent presentation
;;   state when validation also depends on visibility or view membership.
(define (event-state-before event events initial model computation [lesson #f])
  (define preceding-events
    (for/list ([prior (in-list events)]
               #:break (>= (c-event-ordinal prior) (c-event-ordinal event))
               #:when (<= (c-event-end prior) (c-event-start event)))
      prior))
  (apply-events-at initial preceding-events
                   (c-event-start event) +inf.0 model computation lesson))

;; parameter-values-before : c-event? list? hash? calculus-model? calculus-computation? -> immutable-hash?
;;   Reconstructs the start parameter state for domain validation, including
;;   preceding zero-time assignments but never depending on rendered frames.
(define (parameter-values-before event events values model computation)
  (car (event-state-before event events (cons values (hash)) model computation)))

;; refinement-count-parameter : c-action? -> (or/c c-node? #f)
;;   Finds the direct integer capability owned by a uniform partition target.
(define (refinement-count-parameter action)
  (define partition
    (and (pair? (c-action-targets action)) (first (c-action-targets action))))
  (define raw (and (c-node? partition) (node-raw partition)))
  (define count
    (and (c-object? raw)
         (eq? (c-object-kind raw) 'uniform-partition)
         (hash-ref (c-object-options raw) 'count #f)))
  (and (c-node? count)
       (eq? (c-node-kind count) 'parameter)
       (eq? (c-param-spec-kind (c-node-data count)) 'integer)
       count))

;; refinement-dependent-targets : calculus-model? c-node? -> (listof c-node?)
;; Finds public constructions that transitively depend on the partition count.
;; The result is used only for transient carrier presentation; the committed
;; parameter and all mathematical object values remain the current snapshot.
(define (refinement-dependent-targets model parameter)
  (define parameter-id (c-node-id parameter))
  (define (depends-on? node seen)
    (cond [(not (c-node? node)) #f]
          [(member (c-node-id node) seen) #f]
          [(eq? (c-node-id node) parameter-id) #t]
          [else
           (for/or ([identifier (in-list (semantic-node-identifiers (node-raw node)))])
             (or (eq? identifier parameter-id)
                 (let ([dependency (hash-ref (calculus-model-nodes model) identifier #f)])
                   (and dependency
                        (depends-on? dependency (cons (c-node-id node) seen))))))]))
  (for/list ([node (in-hash-values (calculus-model-nodes model))]
             #:when (and (not (eq? node parameter)) (depends-on? node '())))
    node))

;; valid-refinement-counts? : c-action? hash? calculus-model? calculus-computation? -> boolean?
;;   Checks one nested sequence of direct integer partition counts.
(define (valid-refinement-counts? action environment model computation)
  (define parameter (refinement-count-parameter action))
  (define count-expression (hash-ref (c-action-options action) 'counts #f))
  (define result
    (and count-expression (eval-raw count-expression environment model computation)))
  (and parameter
       result
       (eq? (calculus-result-status result) 'defined)
       (let ([counts (calculus-result-value result)])
         (and (list? counts)
              (pair? counts)
              (let loop ([previous (hash-ref environment (c-node-id parameter))]
                         [remaining counts])
                (cond
                  [(null? remaining) #t]
                  [else
                   (define next (car remaining))
                   (define inside?
                     (and (exact-integer? next)
                          (positive? next)
                          (domain-contains? (c-param-spec-domain (c-node-data parameter))
                                            next environment model computation)))
                   (and (exact-integer? next)
                        (exact-integer? previous)
                        (positive? previous)
                        (> next previous)
                        (zero? (remainder next previous))
                        inside?
                        (eq? (calculus-result-status inside?) 'defined)
                        (calculus-result-value inside?)
                        (loop next (cdr remaining)))]))))))

;; refinement-diagnostics : calculus-model? hash? calculus-computation? list? -> list?
;;   Rejects nonnested or noninteger refinement descriptions before sampling.
(define (refinement-diagnostics model values computation events)
  (for/list ([event (in-list events)]
             #:when (and (eq? (c-action-kind (c-event-action event)) 'refine)
                         (not (valid-refinement-counts?
                               (c-event-action event)
                               (parameter-values-before event events values model computation)
                               model computation))))
    (calculus-diagnostic 'error 'refinement #f #f (c-event-end event)
                         "refine requires a direct integer parameter and strictly nested count multiples")))

;; action-domain-diagnostics : calculus-model? hash? calculus-computation? list? -> list?
;;   Checks parameter kind, authored stops, endpoints, and continuous paths
;;   before native output, while keeping invalid actions out of sampled states.
(define (action-domain-diagnostics model values computation events)
  (apply append
         (for/list ([event (in-list events)])
           (define action (c-event-action event))
           (define kind (c-action-kind action))
           (define parameter (action-parameter action))
           (cond
             [(not (and parameter (memq kind '(vary approach set-parameter)))) '()]
             [else
             (define endpoint (action-endpoint action))
              (define event-values
                (parameter-values-before event events values model computation))
              (define result (and endpoint (eval-raw endpoint event-values model computation)))
              (define valid-result?
                (and result
                     (eq? (calculus-result-status result) 'defined)
                     (finite-real? (calculus-result-value result))))
              (define target (and valid-result? (calculus-result-value result)))
              (define diagnostic
                (lambda (code message)
                  (calculus-diagnostic 'error code (c-node-id parameter) #f
                                       (c-event-end event) message)))
              (cond
                [(and (memq kind '(vary approach))
                      (eq? (c-param-spec-kind (c-node-data parameter)) 'integer))
                 (list (diagnostic 'parameter-kind
                                   "continuous parameter actions require a real parameter"))]
                [(and (eq? kind 'approach) (not valid-result?))
                 (list (diagnostic 'approach-stop
                                   "approach requires an authored finite #:until value"))]
                [(not valid-result?)
                 (list (diagnostic 'parameter-domain
                                   "parameter action endpoint is outside its declared domain"))]
                [(and (eq? (c-param-spec-kind (c-node-data parameter)) 'integer)
                      (not (exact-integer? target)))
                 (list (diagnostic 'parameter-kind
                                   "integer parameter assignments require an exact integer endpoint"))]
                [else
                 ;; `#:via` is part of one authored continuous route, not a
                 ;; draw-time hint.  Evaluate and validate each knot here as
                 ;; well as in the sampler so an invalid intermediate value
                 ;; cannot compile into a silent hold.
                 (define via-result
                   (if (eq? kind 'vary)
                       (eval-raw (hash-ref (c-action-options action) 'via '())
                                 event-values model computation)
                       (defined '())))
                 (define via-values
                   (and (eq? (calculus-result-status via-result) 'defined)
                        (calculus-result-value via-result)))
                 (define continuous?
                   (memq kind '(vary approach)))
                 (define knots
                   (and (list? via-values)
                        (append (list (hash-ref event-values (c-node-id parameter)))
                                via-values (list target))))
                 (cond
                   [(not (and (list? via-values) (andmap finite-real? via-values)))
                    (list (diagnostic 'parameter-domain
                                      "parameter action has a nonfinite #:via knot"))]
                   [(and continuous?
                         (not (valid-continuous-parameter-path?
                               parameter knots event-values model computation)))
                    (list (diagnostic 'parameter-path
                                      "continuous parameter action leaves its declared domain"))]
                   [(and (not continuous?)
                         (not (valid-parameter-assignment?
                               parameter target event-values model computation)))
                    (list (diagnostic 'parameter-domain
                                      "parameter action endpoint is outside its declared domain"))]
                   [(and (eq? kind 'approach)
                         (not (valid-approach-side?
                               action (hash-ref event-values (c-node-id parameter)) target
                               event-values model computation)))
                    (list (diagnostic 'approach-side
                                      "approach must start and stop on its authored side of #:to"))]
                   [else '()])])]))))

;; trace-sweep-parameter : semantic-value? -> (or/c c-node? #f)
;;   Extracts the direct parameter capability owned by a trace locus.
(define (trace-sweep-parameter target)
  (define raw (node-raw target))
  (define parameter
    (and (c-object? raw) (hash-ref (c-object-options raw) 'parameter #f)))
  (and (direct-real-parameter? parameter) parameter))

;; valid-trace-target? : semantic-value? hash? calculus-model? calculus-computation? -> boolean?
;;   A trace owns one direct real parameter over a nondegenerate closed sweep.
(define (valid-trace-target? target values model computation)
  (define raw (node-raw target))
  (define parameter (trace-sweep-parameter target))
  (define over
    (and (c-object? raw) (hash-ref (c-object-options raw) 'over #f)))
  (and (c-object? raw) (eq? (c-object-kind raw) 'trace-of)
       parameter
       (c-domain? over) (eq? (c-domain-kind over) 'closed)
       (= (length (c-domain-arguments over)) 2)
       (let ([left (eval-raw (first (c-domain-arguments over)) values model computation)]
             [right (eval-raw (second (c-domain-arguments over)) values model computation)])
         (and (eq? (calculus-result-status left) 'defined)
              (eq? (calculus-result-status right) 'defined)
              (finite-real? (calculus-result-value left))
              (finite-real? (calculus-result-value right))
              (< (calculus-result-value left) (calculus-result-value right))
              (= (hash-ref values (c-node-id parameter))
                 (calculus-result-value left))))))

;; trace-diagnostics : calculus-model? hash? calculus-computation? list? -> list?
;;   Rejects ambiguous trace sweeps before parameter sampling can use them.
(define (trace-diagnostics model values computation events)
  (apply append
         (for/list ([event (in-list events)]
                    #:when (eq? (c-action-kind (c-event-action event)) 'trace))
           (define environment
             (parameter-values-before event events values model computation))
           (for/list ([target (in-list (c-action-targets (c-event-action event)))]
                      #:unless (valid-trace-target? target environment model computation))
             (calculus-diagnostic 'error 'trace #f #f (c-event-end event)
                                  "trace requires a direct real parameter starting at a closed increasing sweep interval")))))

;; focus-diagnostics : calculus-lesson? calculus-model? hash? calculus-computation? list? -> list?
;;   Ensures camera actions name one declared graph view and finite increasing
;;   coordinate windows. Focus endpoints use exactly the action-start state.
(define (focus-diagnostics lesson model values computation events)
  (for/list ([event (in-list events)]
             #:when (memq (c-action-kind (c-event-action event)) '(focus restore-view))
             #:do [(define action (c-event-action event))]
             #:do [(define state
                     (event-state-before event events
                                         (cons values (initial-visibility lesson))
                                         model computation lesson))]
             #:when (or (and (eq? (c-action-kind action) 'focus)
                              (not (focus-target-window action (car state) model computation lesson)))
                         (and (eq? (c-action-kind action) 'restore-view)
                              (not (valid-restore-view? action lesson)))))
    (calculus-diagnostic 'error 'focus #f #f (c-event-end event)
                         "focus and restore-view require one declared graph view and finite increasing focus windows")))

;; emphasis-diagnostics : calculus-lesson? calculus-model? hash? calculus-computation? list? -> list?
;;   Rejects transient attention commands that would invent visibility. A
;;   compare also needs at least two already-visible authored targets; it may
;;   direct attention to their relation but cannot establish one mathematically.
(define (emphasis-diagnostics lesson model values computation events)
  (apply append
         (for/list ([event (in-list events)])
           (define action (c-event-action event))
           (define kind (c-action-kind action))
           (define visibility
             (cdr (event-state-before event events
                                      (cons values (initial-visibility lesson))
                                      model computation lesson)))
           (cond
             [(eq? kind 'highlight)
              (for/list ([target (in-list (c-action-targets action))]
                         #:unless (presentation-visible? visibility target))
                (calculus-diagnostic 'error 'highlight #f #f (c-event-start event)
                                     "highlight requires an already visible target"))]
             [(eq? kind 'compare)
              (if (and (>= (length (c-action-targets action)) 2)
                       (andmap (lambda (target)
                                 (presentation-visible? visibility target))
                               (c-action-targets action)))
                  '()
                  (list (calculus-diagnostic
                         'error 'compare #f #f (c-event-start event)
                         "compare requires at least two already visible targets")))]
             [else '()]))))

;; shared-graph-view? : calculus-lesson? semantic-value? semantic-value? -> boolean?
;;   Finds the required common graph-view membership for a native line handoff.
(define (shared-graph-view? lesson source target)
  (for/or ([view (in-hash-values (calculus-lesson-views lesson))])
    (define objects (hash-ref (c-view-options view) 'objects '()))
    (and (eq? (c-view-kind view) 'graph-view)
         (member source objects)
         (member target objects))))

;; valid-limit-transition? : c-action? hash? calculus-model? calculus-computation?
;;                            #:lesson (or/c calculus-lesson? #f)
;;                            #:visible (or/c immutable-hash? #f) -> boolean?
;;   Verifies a local line/claim relationship and, when presentation context is
;;   supplied, its shared-view and source-visible/target-hidden handoff state.
;;   It never turns a carrier into a mathematical limit value.
(define (valid-limit-transition? action environment model computation
                                 #:lesson [lesson #f] #:visible [visible #f])
  (define targets (c-action-targets action))
  (define claim (hash-ref (c-action-options action) 'claim #f))
  (define (value-of result)
    (and (eq? (calculus-result-status result) 'defined)
         (calculus-result-value result)))
  (and (= (length targets) 2)
       (let* ([source (first targets)]
              [target (second targets)]
              [claim-raw (node-raw claim)]
              [claim-expression
               (and (c-object? claim-raw)
                    (eq? (c-object-kind claim-raw) 'limit-statement)
                    (first (c-object-arguments claim-raw)))]
              [source-expression (and claim-expression (node-raw claim-expression))]
              [source-line (value-of (eval-line source environment model computation (hash)))]
              [target-line (value-of (eval-line target environment model computation (hash)))]
              [claim-valid? (value-of (eval-limit-statement claim environment model computation (hash)))]
              [claim-value
               (and (c-object? claim-raw)
                    (value-of (eval-raw (hash-ref (c-object-options claim-raw) 'value #f)
                                        environment model computation)))])
         (and claim-valid?
              (or (not lesson) (shared-graph-view? lesson source target))
              (or (not visible)
                  (let ([source-key (target-key source)]
                        [target-key* (target-key target)])
                    (and source-key
                         target-key*
                         (not (equal? source-key target-key*))
                         (hash-ref visible source-key #f)
                         (not (hash-ref visible target-key* #f)))))
              (finite-real? claim-value)
              (list? source-line) (list? target-line)
              (eq? (car source-line) 'line) (eq? (car target-line) 'line)
              (finite-real? (second source-line))
              (finite-real? (second target-line))
              (equal? (fourth source-line) (fourth target-line))
              (scalar-equivalent? (second target-line) claim-value computation)
              (or (and (c-expression? source-expression)
                       (eq? (c-expression-op source-expression) 'slope)
                       (equal? (first (c-expression-arguments source-expression)) source))
                  (and (c-expression? source-expression)
                       (eq? (c-expression-op source-expression) 'difference-quotient)))))))

;; limit-transition-diagnostics : calculus-lesson? calculus-model? hash? calculus-computation? list? -> list?
;;   Rejects a line handoff without a finite matching claim, shared graph view,
;;   or its required source-visible/target-hidden presentation state.
(define (limit-transition-diagnostics lesson model values computation events)
  (for/list ([event (in-list events)]
             #:when (and (eq? (c-action-kind (c-event-action event)) 'limit-transition)
                         (let ([state
                                (event-state-before
                                 event events
                                 (cons values (initial-visibility lesson))
                                 model computation lesson)])
                           (not (valid-limit-transition?
                                 (c-event-action event) (car state) model computation
                                 #:lesson lesson #:visible (cdr state))))))
    (calculus-diagnostic 'error 'limit-transition #f #f (c-event-end event)
                         "limit-transition requires a matching finite slope claim, shared graph view, visible source, and hidden target")))

;; theme-style-rules : calculus-theme? -> list?
;;   Flattens inherited presentation policy base-first so validation observes
;; the same complete rule set that the native adapter later resolves.
(define (theme-style-rules theme)
  (append (if (calculus-theme-data-base theme)
              (theme-style-rules (calculus-theme-data-base theme))
              '())
          (calculus-theme-data-rules theme)))

;; declared-style-address? : calculus-model? address? -> boolean?
;;   Style declarations must refer to a root that belongs to this lesson.
;; Deeper part paths remain semantic addresses and are checked by normal
;; snapshot inspection, which preserves their intentionally open public-part
;; vocabulary without granting styles access to an invented root.
(define (declared-style-address? model address)
  (and (style-address? address)
       (hash-has-key? (calculus-model-nodes model)
                      (if (symbol? address) address (first address)))))

;; style-diagnostics : calculus-lesson? calculus-profile? -> list?
;;   A style rule is immutable presentation data, but view and target selectors
;; are lesson-relative. Report their misspellings during headless compilation
;; rather than silently dropping policy in the renderer.
(define (style-diagnostics lesson profile)
  (define model (calculus-lesson-model lesson))
  (append-map
   (lambda (rule)
     (append
      (if (and (calculus-style-data-target rule)
               (not (declared-style-address?
                     model (calculus-style-data-target rule))))
          (list
           (calculus-diagnostic
            'error 'style-target (calculus-style-data-target rule) #f #f
            "style target must name a public lesson address"))
          '())
      (if (and (calculus-style-data-view rule)
               (not (hash-has-key? (calculus-lesson-views lesson)
                                   (calculus-style-data-view rule))))
          (list
           (calculus-diagnostic
            'error 'style-view #f #f #f
            "style view must name a declared lesson view"))
          '())))
   (theme-style-rules (calculus-profile-data-theme profile))))

;; view-policy-diagnostics : calculus-lesson? -> list?
;;   Validates the graph-view scale policy at the same headless boundary as
;; other declaration-relative presentation data. A renderer must not silently
;; reinterpret an unknown scale spelling as independent coordinates.
(define (view-policy-diagnostics lesson)
  (for/list ([view (in-hash-values (calculus-lesson-views lesson))]
             #:when (and (eq? (c-view-kind view) 'graph-view)
                         (not (memq (hash-ref (c-view-options view) 'scale 'independent)
                                    '(independent equal)))))
    (calculus-diagnostic 'error 'view-scale #f #f #f
                         "graph view scale must be 'independent or 'equal")))

;; compile-calculus-lesson : calculus-lesson? keyword-options -> calculus-plan?
;;   Lowers a headless lesson into immutable events, moments, and diagnostics.
(define (compile-calculus-lesson lesson #:profile [profile default-calculus-profile] #:values [value-overrides (hash)]
                                 #:computation [computation default-calculus-computation])
  (check 'compile-calculus-lesson calculus-lesson? "calculus-lesson?" lesson)
  (check 'compile-calculus-lesson calculus-profile? "calculus-profile?" profile)
  (check 'compile-calculus-lesson calculus-computation? "calculus-computation?" computation)
  (define model (calculus-lesson-model lesson))
  (define base-initial (initial-values model value-overrides))
  (define initial (hash-set base-initial snapshot-basis-key base-initial))
  (define timing (or (calculus-lesson-timing lesson) (calculus-profile-data-timing profile)))
  (define time (calculus-timing-data-opening-pause timing))
  (define ordinal 0)
  (define events '())
  (define moments (make-hash))
  (define compile-presentation (initial-visibility lesson))
  (define checkpoint-diagnostics '())
  (define captions '())
  ;; record-milestone! : symbol? list? real? exact-nonnegative-integer? -> void?
  ;;   Uses the same phase/address map for outer and expanded nested steps.
  (define (record-milestone! phase path at-time at-ordinal)
    (hash-set! moments (cons phase path) (cons at-time at-ordinal)))
  ;; record-caption! : list? any/c real? real? -> void?
  ;;   Captions are optional source strings; absent local captions simply let
  ;; an enclosing outer caption remain active during that component interval.
  (define (record-caption! path text start-time end-time)
    (when (and (string? text) (not (string=? text "")))
      (set! captions (cons (c-caption path text start-time end-time) captions))))
  ;; Every checkpoint is compiled as a zero-duration event.  Recording it from
  ;; the resulting leaves covers both ordinary outer steps and checkpoints
  ;; introduced by expanded component expositions, while preserving the
  ;; source-order cutoff that distinguishes simultaneous zero-time actions.
  (define (record-checkpoints! new-events)
    (for ([event (in-list new-events)]
          #:when (eq? (c-action-kind (c-event-action event)) 'checkpoint))
      (define targets (c-action-targets (c-event-action event)))
      (define address
        (and (= (length targets) 1)
             (checkpoint-target->address (first targets))))
      (cond
        [(not address)
         (set! checkpoint-diagnostics
               (cons (calculus-diagnostic
                      'error 'checkpoint #f #f (c-event-start event)
                      "checkpoint requires one symbol or nonempty symbol path")
                     checkpoint-diagnostics))]
        [(hash-has-key? moments (cons 'checkpoint address))
         (set! checkpoint-diagnostics
               (cons (calculus-diagnostic
                      'error 'duplicate-checkpoint address #f (c-event-start event)
                      "checkpoint paths must be unique, including component prefixes")
                     checkpoint-diagnostics))]
        [else
         (hash-set! moments (cons 'checkpoint address)
                    (cons (c-event-start event) (c-event-ordinal event)))])))
  (for ([step (in-list (calculus-lesson-steps lesson))])
    (define outer-path (list (c-step-id step)))
    (define outer-start time)
    (record-milestone! 'step-start outer-path time (sub1 ordinal))
    (set! time (+ time (or (c-step-read-delay step) (calculus-timing-data-read-delay timing))))
    (define fallback (or (c-step-duration step) (calculus-timing-data-action-duration timing)))
    (define step-commands (c-step-commands step))
    (for ([command (in-list step-commands)])
      (define persistent-delta
        (and (c-action? command)
             (persistent-action-delta compile-presentation command)))
      (define-values (new-events span next)
        (if (and persistent-delta
                 (null? (c-action-targets persistent-delta)))
            (values '() 0 ordinal)
            (compile-command (or persistent-delta command) time fallback ordinal #f
                             (= (length step-commands) 1)
                             outer-path record-milestone! record-caption!)))
      (record-checkpoints! new-events)
      (set! events (append events new-events))
      (set! time (+ time span))
      (set! ordinal next)
      (set! compile-presentation
            (if (null? new-events)
                compile-presentation
                (presentation-state-after-events compile-presentation new-events))))
    (record-milestone! 'step-end outer-path time (sub1 ordinal))
    (define outer-end (+ time (or (c-step-pause step) (calculus-timing-data-step-pause timing))))
    (record-caption! outer-path (c-step-say step) outer-start outer-end)
    (set! time outer-end))
  (define diagnostics
    (filter (lambda (diagnostic) diagnostic)
            (append (initial-presentation-diagnostics lesson)
                    (style-diagnostics lesson profile)
                    (view-policy-diagnostics lesson)
                    (reverse checkpoint-diagnostics)
                    (action-domain-diagnostics model initial computation events)
                    (refinement-diagnostics model initial computation events)
                    (trace-diagnostics model initial computation events)
                    (focus-diagnostics lesson model initial computation events)
                    (emphasis-diagnostics lesson model initial computation events)
                    (limit-transition-diagnostics lesson model initial computation events)
                    (component-explain-diagnostics lesson)
                    (component-exposition-write-diagnostics lesson)
                    (component-private-placement-diagnostics lesson)
                    (together-diagnostics events))))
  (calculus-plan lesson profile initial computation (immutable-list-copy events) time diagnostics
                 (make-immutable-hash (for/list ([(key value) (in-hash moments)]) (cons key value)))
                 (immutable-list-copy (reverse captions))))

;; address->object : calculus-model? address? -> semantic-target?
;;   Resolves a public root/part address without consulting rendered geometry.
(define (address->object model address)
  (define pieces (if (symbol? address) (list address) address))
  (unless (and (list? pieces) (pair? pieces) (andmap symbol? pieces))
    (raise-argument-error 'calculus-snapshot-ref "symbol? or nonempty list of symbols" address))
  (define root (hash-ref (calculus-model-nodes model) (first pieces) #f))
  (unless root (raise-arguments-error 'calculus-snapshot-ref "known public mathematical address" "address" address))
  (for/fold ([value root]) ([part (in-list (rest pieces))]) (c-part value part)))

;; interpolate-window : list? list? real? -> list?
;;   Produces one purely presentational camera window without changing any
;;   mathematical coordinate or graph domain.
(define (interpolate-window start target progress)
  (for/list ([from (in-list start)] [to (in-list target)])
    (+ from (* progress (- to from)))))

;; continuous-action-progress : real? real? real? calculus-profile? [c-action?] -> real?
;;   Applies the action-local easing when one is authored, otherwise the
;;   profile default, to a clamped timeline fraction.  It changes an
;;   intermediate demonstration state only: 0 and 1 remain the authored
;;   mathematical endpoints for every profile.
(define (continuous-action-progress start end time profile [action #f])
  (define linear-progress
    (if (= start end) 1 (min 1 (max 0 (/ (- time start) (- end start))))))
  (define easing (action-easing profile action))
  (ease-progress linear-progress easing))

;; action-easing : calculus-profile? (or/c #f c-action?) -> symbol?
;; Resolves the explicit `'profile` spelling to the selected profile instead
;; of accidentally treating it as an unrecognized linear easing.
(define (action-easing profile action)
  (define requested
    (if (and action (c-action? action)
             (hash-has-key? (c-action-options action) 'easing))
        (hash-ref (c-action-options action) 'easing)
        'profile))
  (if (eq? requested 'profile)
      (calculus-motion-data-parameter-easing
       (calculus-profile-data-motion profile))
      requested))

;; ease-progress : real? symbol? -> real?
;; Applies one documented easing to a local normalized route segment.
(define (ease-progress linear-progress easing)
  (case easing
    [(smoothstep) (* linear-progress linear-progress (- 3 (* 2 linear-progress)))]
    [else linear-progress]))

;; valid-continuous-parameter-path? : c-node? list? hash? calculus-model?
;;                                     calculus-computation? -> boolean?
;;   Validates every authored segment, including intermediate `#:via` knots,
;;   against the parameter contract before any partial value is sampled.
(define (valid-continuous-parameter-path? parameter knots environment model computation)
  (and (pair? knots)
       (andmap finite-real? knots)
       (for/and ([from (in-list knots)] [to (in-list (rest knots))])
         (valid-continuous-parameter-target? parameter from to
                                             environment model computation))))

;; interpolate-parameter-path : listof finite-real? real? -> finite-real?
;;   Moves by cumulative path length, not by the direct endpoint chord.  This
;;   keeps authored intermediate knots observable at their distance-proportional
;;   time even when a path reverses direction.
(define (interpolate-parameter-path knots progress [easing 'linear])
  (define lengths
    (for/list ([from (in-list knots)] [to (in-list (rest knots))])
      (abs (- to from))))
  (define total (apply + 0 lengths))
  (cond
    [(zero? total) (last knots)]
    [else
     (define travelled (* (min 1 (max 0 progress)) total))
     (let loop ([from (first knots)] [rest-knots (rest knots)]
                [remaining lengths] [covered 0])
       (define to (first rest-knots))
       (define length (first remaining))
       (cond
         [(zero? length)
          (if (null? (rest remaining)) to
              (loop to (rest rest-knots) (rest remaining) covered))]
         [(or (null? (rest remaining)) (<= travelled (+ covered length)))
          (define local-progress
            (ease-progress (/ (- travelled covered) length) easing))
          (+ from (* local-progress (- to from)))]
         [else (loop to (rest rest-knots) (rest remaining) (+ covered length))]))]))

;; apply-event : pair? c-event? real? calculus-model? calculus-computation?
;;                [calculus-lesson?] [calculus-profile?] -> pair?
;;   Computes one event's state at a requested time with no frame history.
(define (apply-event state event time model computation
                     [lesson #f] [profile default-calculus-profile])
  (define action (c-event-action event))
  (define kind (c-action-kind action))
  (define start (c-event-start event)) (define end (c-event-end event))
  (if (< time start) state
      (let ([values (car state)] [visible (cdr state)])
        (define motion (calculus-profile-data-motion profile))
        (define (set-visible targets on? #:clear-trace-prefix? [clear-trace-prefix? #f])
          (for/fold ([current visible]) ([target (in-list targets)])
            (define key (presentation-visibility-key target))
            (if key
                (let ([updated (hash-set current key on?)])
                  (if clear-trace-prefix?
                      (hash-remove updated (trace-prefix-key target))
                      updated))
                current)))
        (define (set-motion-records presentation records)
          ;; Each target may use a different reveal family, so these records
          ;; are installed one at a time rather than as a shared boolean flag.
          (for/fold ([current presentation]) ([entry (in-list records)])
            (define target (car entry))
            (define record (cdr entry))
            (define key (presentation-state-key 'motion target))
            (cond [(not key) current]
                  [record (hash-set current key record)]
                  [else (hash-remove current key)])))
        (define (motion-progress)
          (continuous-action-progress start end time profile action))
        (define (reveal-record target progress)
          ;; Component presentation parts retain the kind of their lexical
          ;; exported/private node.  Resolve that kind here so an exported
          ;; secant receives the same extend policy as a direct secant.
          (define node
            (or (and (c-node? target) target)
                (and (c-part? target)
                     (or (calculus-component-part-node target)
                         (calculus-component-private-part-node target)))))
          (cond [(and node (memq (c-node-kind node) '(graph graph-restriction)))
                 (list 'graph (calculus-motion-data-graph-reveal motion) progress)]
                [(and node
                      (memq (c-node-kind node)
                            '(segment line-through ray-through horizontal-line
                                      vertical-line chord secant tangent vertical-tangent
                                      normal error-segment asymptote-line)))
                 (list 'line (calculus-motion-data-line-reveal motion) progress)]
                [else (list 'fade 'fade progress)]))
        (define (active-reveals presentation targets)
          (if (< time end)
              (set-motion-records
               presentation
               (for/list ([target (in-list targets)])
                 (cons target (reveal-record target (motion-progress)))))
              (set-motion-records presentation
                                  (for/list ([target (in-list targets)])
                                    (cons target #f)))))
        (case kind
          [(show)
           (define revealed
             (set-visible (c-action-targets action) #t #:clear-trace-prefix? #t))
           (cons values (active-reveals revealed (c-action-targets action)))]
          [(show-label) (cons values (set-label-preference visible (c-action-targets action) #t))]
          [(hide) (cons values (set-visible (c-action-targets action) #f))]
          [(hide-label) (cons values (set-label-preference visible (c-action-targets action) #f))]
          [(read)
           (define revealed (set-visible (c-action-targets action) #t))
           (define reading-policy (calculus-motion-data-reading motion))
           (cons values
                 (if (< time end)
                     (set-motion-records
                      revealed
                      (for/list ([target (in-list (c-action-targets action))])
                        (cons target (list 'reading reading-policy (motion-progress)))))
                     (set-motion-records
                      revealed
                      (for/list ([target (in-list (c-action-targets action))])
                        (cons target #f)))))]
          [(deemphasize)
           (cons values
                 (set-presentation-state visible 'deemphasized
                                         (c-action-targets action) #t))]
          [(normalize)
           (cons values
                 (set-presentation-state visible 'deemphasized
                                         (c-action-targets action) #f))]
          [(highlight compare)
           ;; Highlights are intentionally sampled rather than committed:
           ;; the enclosing event leaves no persistent state once its authored
           ;; duration has elapsed.  This keeps random-access snapshots and
           ;; reverse frame requests independent of previous drawing history.
           (if (< time end)
               (let ([highlighted
                      (set-presentation-state visible 'highlighted
                                              (c-action-targets action) #t)])
                 (cons values
                       (if (and (eq? (calculus-motion-data-highlight motion) 'pulse)
                                (not (calculus-motion-data-reduced-motion? motion)))
                           (set-motion-records
                            highlighted
                            (for/list ([target (in-list (c-action-targets action))])
                              (cons target (list 'highlight 'pulse (motion-progress)))))
                           highlighted)))
               state)]
          [(highlight-quantity)
           ;; Resolve correspondences at the sampled action state. The action
           ;; highlights visible authored representations, never text with a
           ;; coincident numerical value and never an otherwise hidden object.
           (if (< time end)
               (cons values
                     (set-presentation-state
                      visible 'highlighted
                      (apply append
                             (for/list ([target (in-list (c-action-targets action))])
                               (quantity-highlight-targets lesson visible target)))
                      #t))
               state)]
          [(vary approach)
           (define parameter (first (c-action-targets action)))
           (define id (and (c-node? parameter) (c-node-id parameter)))
           (if (not id) state
               (let* ([initial (hash-ref values id)]
                      [target-expression (if (eq? kind 'approach) (hash-ref (c-action-options action) 'until)
                                             (hash-ref (c-action-options action) 'to))]
                      [target-result (eval-raw target-expression values model computation)]
                      [via-result
                       (if (eq? kind 'vary)
                           (eval-raw (hash-ref (c-action-options action) 'via '())
                                     values model computation)
                           (defined '()))])
                 (if (or (not (eq? (calculus-result-status target-result) 'defined))
                         (not (eq? (calculus-result-status via-result) 'defined))
                         (not (list? (calculus-result-value via-result)))
                         (not (valid-continuous-parameter-path?
                               parameter
                               (append (list initial) (calculus-result-value via-result)
                                       (list (calculus-result-value target-result)))
                               values model computation))
                         (and (eq? kind 'approach)
                              (not (valid-approach-side?
                                    action initial (calculus-result-value target-result)
                                    values model computation))))
                     state
                     (let* ([target (calculus-result-value target-result)]
                            [knots (append (list initial) (calculus-result-value via-result)
                                           (list target))]
                            ;; Segment selection uses elapsed linear route
                            ;; distance; easing is applied only inside the
                            ;; selected segment so authored knots retain their
                            ;; distance-timed moments under smoothstep.
                            [progress (if (= start end) 1
                                          (min 1 (max 0 (/ (- time start) (- end start)))))]
                            [easing (action-easing profile action)])
                       (cons (hash-set values id
                                       (interpolate-parameter-path knots progress easing))
                             visible)))))]
          [(set-parameter)
           (define parameter (first (c-action-targets action)))
           (define value-result (eval-raw (second (c-action-targets action)) values model computation))
           (if (and (c-node? parameter)
                    (eq? (c-node-kind parameter) 'parameter)
                    (eq? (calculus-result-status value-result) 'defined)
                    (valid-parameter-assignment?
                     parameter (calculus-result-value value-result) values model computation))
               (cons (hash-set values (c-node-id parameter) (calculus-result-value value-result)) visible) state)]
          [(refine)
           (define parameter (refinement-count-parameter action))
           (define count-expression (hash-ref (c-action-options action) 'counts #f))
           (define count-result
             (and count-expression (eval-raw count-expression values model computation)))
           (if (and parameter
                    count-result
                    (eq? (calculus-result-status count-result) 'defined)
                    (valid-refinement-counts? action values model computation))
               (let* ([counts (calculus-result-value count-result)]
                      [segment-duration (/ (- end start) (length counts))]
                      [completed
                       (min (length counts)
                            (max 0 (inexact->exact
                                    (floor (/ (- time start) segment-duration)))))] )
                 (define next-values
                   (if (zero? completed)
                       values
                       (hash-set values (c-node-id parameter)
                                 (list-ref counts (sub1 completed)))))
                 (define carrier-count
                   (and (< completed (length counts))
                        (list-ref counts completed)))
                 (define segment-start (+ start (* completed segment-duration)))
                 (define segment-progress
                   (if (zero? segment-duration)
                       1
                       (min 1 (max 0 (/ (- time segment-start) segment-duration)))))
                 (define carrier-targets
                   (refinement-dependent-targets model parameter))
                 ;; The count remains a committed mathematical integer until a
                 ;; segment endpoint. The transient record lets native output
                 ;; draw a subdivision carrier without inventing an
                 ;; intermediate noninteger partition count.
                 (cons next-values
                       (if (< time end)
                           (let ([refining
                                  (set-presentation-state
                                   visible 'refining carrier-targets #t)])
                             (set-motion-records
                              refining
                              (for/list ([target (in-list (cons parameter carrier-targets))])
                                (cons target
                                      (list 'refinement
                                            (calculus-motion-data-refinement motion)
                                            segment-progress
                                            carrier-count)))))
                           (let ([settled
                                  (set-presentation-state
                                   visible 'refining carrier-targets #f)])
                             (set-motion-records
                              settled
                              (for/list ([target (in-list (cons parameter carrier-targets))])
                                (cons target #f)))))))
               state)]
          [(limit-transition)
           (define targets (c-action-targets action))
           (if (valid-limit-transition? action values model computation
                                        #:lesson lesson #:visible visible)
               (let ([source-key (target-key (first targets))]
                     [target-key* (target-key (second targets))]
                     [policy (if (calculus-motion-data-reduced-motion? motion)
                                 'crossfade
                                 (calculus-motion-data-limit-transition motion))]
                     [progress (motion-progress)])
                 (cond
                   [(< time end)
                    ;; Both mathematically valid constructions coexist only
                    ;; during the visual handoff. Their transient records
                    ;; distinguish crossfade from the carrier policy.
                   (define transitional
                      (cond [(and source-key target-key*)
                             (hash-set (hash-set visible source-key #t) target-key* #t)]
                            [source-key (hash-set visible source-key #t)]
                            [target-key* (hash-set visible target-key* #t)]
                            [else visible]))
                    (define source-line-result
                      (eval-line (first targets) values model computation (hash)))
                    (define target-line-result
                      (eval-line (second targets) values model computation (hash)))
                    (define source-line
                      (and (eq? (calculus-result-status source-line-result) 'defined)
                           (calculus-result-value source-line-result)))
                    (define target-line
                      (and (eq? (calculus-result-status target-line-result) 'defined)
                           (calculus-result-value target-line-result)))
                    (cons values
                          (set-motion-records
                           transitional
                           (list (cons (first targets)
                                       (list 'limit policy 'source progress source-line target-line))
                                 (cons (second targets)
                                       (list 'limit policy 'target progress source-line target-line)))))]
                   [else
                    (define settled
                      (cond [(and source-key target-key*)
                             (hash-set (hash-set visible source-key #f) target-key* #t)]
                            [source-key (hash-set visible source-key #f)]
                            [target-key* (hash-set visible target-key* #t)]
                            [else visible]))
                    (cons values
                          (set-motion-records
                           settled
                           (list (cons (first targets) #f)
                                 (cons (second targets) #f))))]))
               state)]
          [(focus)
           (define target-window
             (and lesson (focus-target-window action values model computation lesson)))
           (if target-window
               (let* ([view (car target-window)]
                      [target (cdr target-window)]
                      [key (view-window-key view)]
                      [basis (hash-ref values snapshot-basis-key values)]
                      [stored-window (and key (hash-ref visible key #f))]
                      [start-window
                       (or stored-window
                           (view-window-values view basis model computation))]
                      [progress (if (or (calculus-motion-data-reduced-motion? motion)
                                        (eq? (calculus-motion-data-focus motion) 'cut))
                                    1
                                    (if (= start end) 1
                                        (min 1 (max 0 (/ (- time start) (- end start))))))] )
                 (cond
                   [(and key (finite-view-window? start-window))
                    (cons values (hash-set visible key
                                           (interpolate-window start-window target progress)))]
                   ;; Core remains headless: it records the exact target and
                   ;; progress while the render preparation layer supplies the
                   ;; one frozen auto-fit baseline.  The record is semantic
                   ;; camera state, never a frame-history or pixel estimate.
                   [(and key (auto-y-graph-view? view))
                    (cons values (hash-set visible key
                                           (list 'auto-focus stored-window target progress)))]
                   [else state]))
               state)]
          [(restore-view)
           (define view
             (and lesson (= (length (c-action-targets action)) 1)
                  (resolve-view-reference lesson (first (c-action-targets action)))))
           (define key (and view (view-window-key view)))
           (define basis (hash-ref values snapshot-basis-key values))
           (define baseline (and view (view-window-values view basis model computation)))
           (define stored-window (and key (hash-ref visible key #f)))
           (define start-window (or stored-window baseline))
           (define progress (if (or (calculus-motion-data-reduced-motion? motion)
                                    (eq? (calculus-motion-data-focus motion) 'cut))
                                1
                                (if (= start end) 1
                                    (min 1 (max 0 (/ (- time start) (- end start)))))))
           (cond
             [(and view key baseline (finite-view-window? start-window)
                   (valid-restore-view? action lesson))
              (cons values
                    (if (= progress 1)
                        (hash-remove visible key)
                        (hash-set visible key
                                  (interpolate-window start-window baseline progress))))]
             [(and view key stored-window (auto-y-graph-view? view)
                   (valid-restore-view? action lesson))
              (cons values
                    (if (= progress 1)
                        (hash-remove visible key)
                        (hash-set visible key
                                  (list 'auto-restore stored-window progress))))]
             [else state])]
          [(trace)
           (let loop ([remaining (c-action-targets action)]
                      [current-values values]
                      [current-visible visible])
             (cond
               [(null? remaining) (cons current-values current-visible)]
               [else
                (define target (first remaining))
                (define trace-object (node-raw target))
                (cond
                  [(not (valid-trace-target? target current-values model computation))
                   (loop (rest remaining) current-values current-visible)]
                  [else
                   (define parameter (hash-ref (c-object-options trace-object) 'parameter #f))
                   (define over (hash-ref (c-object-options trace-object) 'over #f))
                   (define id (and (c-node? parameter) (c-node-id parameter)))
                   (define left-result
                     (and (c-domain? over) (= (length (c-domain-arguments over)) 2)
                          (eval-raw (first (c-domain-arguments over)) current-values model computation)))
                   (define right-result
                     (and (c-domain? over) (= (length (c-domain-arguments over)) 2)
                          (eval-raw (second (c-domain-arguments over)) current-values model computation)))
                   (if (and id
                            (eq? (calculus-result-status left-result) 'defined)
                            (eq? (calculus-result-status right-result) 'defined))
                       (let* ([progress (continuous-action-progress start end time profile)]
                              [next-value (+ (calculus-result-value left-result)
                                             (* progress (- (calculus-result-value right-result)
                                                            (calculus-result-value left-result))))]
                              [next-values (hash-set current-values id next-value)]
                              [key (target-key target)]
                              [next-visible
                               (if key
                                   (hash-set (hash-set current-visible key #t)
                                             (trace-prefix-key target) next-value)
                                   current-visible)])
                         (loop (rest remaining) next-values next-visible))
                       (loop (rest remaining) current-values current-visible))])]))]
          [(explain)
           ;; A valid expanded explanation is spliced into events during
           ;; compilation. If it could not be expanded (for example, inside a
           ;; `together` group), it must not silently degrade to collapsed
           ;; root visibility.
           (if (eq? (hash-ref (c-action-options action) 'mode 'collapsed) 'expanded)
               state
               (cons values (set-visible (c-action-targets action) #t)))]
          [else state]))))

;; merge-group-state : pair? pair? pair? -> pair?
;;   Applies one child's disjoint writes, calculated from the common group
;;   start state, to the aggregate state without re-evaluating its inputs.
(define (merge-group-state base aggregate result)
  (define (merge-hash original merged changed)
    ;; Compare the union, not merely keys still present in `changed`: a
    ;; completed normalize/restore action expresses its essential update by
    ;; removing a key.  The dedicated absence sentinel keeps stored `#f`
    ;; values distinct from a deletion.
    (for/fold ([updated merged])
              ([key (in-list (remove-duplicates
                              (append (hash-keys original) (hash-keys changed))))])
      (define before (hash-ref original key missing-presentation-value))
      (define after (hash-ref changed key missing-presentation-value))
      (cond [(equal? before after) updated]
            [(eq? after missing-presentation-value) (hash-remove updated key)]
            [else (hash-set updated key after)])))
  (cons (merge-hash (car base) (car aggregate) (car result))
        (merge-hash (cdr base) (cdr aggregate) (cdr result))))

;; apply-events-at : pair? list? real? real? calculus-model? calculus-computation?
;;                    [calculus-lesson?] [calculus-profile?] -> pair?
;;   Samples sequential events in source order and together children from one
;;   pre-group state, skipping groups rejected during compilation.
(define (apply-events-at initial events time cutoff model computation
                         [lesson #f] [profile default-calculus-profile])
  (define conflicts (conflicting-event-groups events))
  (let loop ([remaining events] [state initial])
    (cond
      [(null? remaining) state]
      [else
       (define event (first remaining))
       (define eligible?
         (and (<= (c-event-start event) time)
              (<= (c-event-ordinal event) cutoff)))
       (cond
         [(not eligible?) (loop (rest remaining) state)]
         [(and (c-event-group event)
               (member (c-event-group event) conflicts))
          (loop (filter (lambda (candidate)
                          (not (equal? (c-event-group candidate)
                                       (c-event-group event))))
                        (rest remaining))
                state)]
         [(c-event-group event)
          (define group-events
            (filter (lambda (candidate)
                      (and (equal? (c-event-group candidate) (c-event-group event))
                           (<= (c-event-start candidate) time)
                           (<= (c-event-ordinal candidate) cutoff)))
                    remaining))
          (define group-state
            (for/fold ([merged state]) ([child (in-list group-events)])
              (merge-group-state state merged
                                 (apply-event state child time model computation lesson profile))))
          (loop (filter (lambda (candidate)
                          (not (equal? (c-event-group candidate)
                                       (c-event-group event))))
                        (rest remaining))
                group-state)]
         [else
          (loop (rest remaining)
                (apply-event state event time model computation lesson profile))])])))

;; initial-visibility : calculus-lesson? -> immutable-hash?
;;   Applies every persistent initial presentation command before the opening
;; pause. The historical field name remains for compatibility with the
;; snapshot record; it now holds visibility and namespaced presentation state.
(define (initial-visibility lesson)
  (define memberships
    (for*/fold ([visible (hash)]) ([(name view) (in-hash (calculus-lesson-views lesson))]
                                  [target (in-list (hash-ref (c-view-options view) 'objects '()))])
      (define key (target-key target))
      (if key
          (hash-set visible (view-membership-key name key) #t)
          visible)))
  (for/fold ([visible memberships]) ([command (in-list (calculus-lesson-initial lesson))])
    (cond
      [(not (c-action? command)) visible]
      [(eq? (c-action-kind command) 'show)
       (for/fold ([current visible]) ([target (in-list (c-action-targets command))])
         (define key (presentation-visibility-key target))
         (if key (hash-set current key #t) current))]
      [(eq? (c-action-kind command) 'hide)
       (for/fold ([current visible]) ([target (in-list (c-action-targets command))])
         (define key (presentation-visibility-key target))
         (if key (hash-set current key #f) current))]
      [(eq? (c-action-kind command) 'show-label)
       (set-label-preference visible (c-action-targets command) #t)]
      [(eq? (c-action-kind command) 'hide-label)
       (set-label-preference visible (c-action-targets command) #f)]
      [(eq? (c-action-kind command) 'deemphasize)
       (set-presentation-state visible 'deemphasized
                               (c-action-targets command) #t)]
      [(eq? (c-action-kind command) 'normalize)
       (set-presentation-state visible 'deemphasized
                               (c-action-targets command) #f)]
      [else visible])))

;; initial-presentation-diagnostics : calculus-lesson? -> list?
;;   Keeps initial state declarative: transient or mathematical actions may not
;;   be smuggled into the zero-time setup phase.
(define (initial-presentation-diagnostics lesson)
  (for/list ([command (in-list (calculus-lesson-initial lesson))]
             #:unless (and (c-action? command)
                           (memq (c-action-kind command)
                                 '(show hide show-label hide-label deemphasize normalize))))
    (calculus-diagnostic 'error 'initially #f #f #f
                         "initially permits only persistent presentation commands")))

;; resolve-moment : calculus-plan? calculus-moment? -> pair?
;;   Finds the stable time and same-time ordering for a named semantic phase.
(define (resolve-moment plan moment)
  (define entry (hash-ref (calculus-plan-moments plan) (cons (calculus-moment-kind moment) (calculus-moment-address moment)) #f))
  (unless entry (raise-arguments-error 'calculus-plan-sample "known step or checkpoint address" "address" (calculus-moment-address moment)))
  entry)

;; calculus-plan-caption : calculus-plan? location? -> (or/c string? #f)
;;   Selects the innermost active authored caption for a time or semantic
;; milestone. It reads immutable compilation records only, so native drawing
;; never needs frame history to reconstruct component narration.
(define (calculus-plan-caption plan at)
  (check 'calculus-plan-caption calculus-plan? "calculus-plan?" plan)
  (define caption-time
    (cond [(eq? at 'initial) 0]
          [(eq? at 'final) (calculus-plan-duration plan)]
          [(calculus-moment? at) (car (resolve-moment plan at))]
          [(and (finite-real? at) (<= 0 at (calculus-plan-duration plan))) at]
          [else
           (raise-arguments-error 'calculus-plan-caption
                                  "a valid time, 'initial, 'final, or calculus moment"
                                  "at" at)]))
  (define selected
    (for/fold ([best #f]) ([caption (in-list (calculus-plan-captions plan))]
                               #:when (and (<= (c-caption-start caption) caption-time)
                                           (<= caption-time (c-caption-end caption))))
      (cond [(not best) caption]
            [(> (length (c-caption-path caption)) (length (c-caption-path best))) caption]
            [(and (= (length (c-caption-path caption)) (length (c-caption-path best)))
                  (> (c-caption-start caption) (c-caption-start best))) caption]
            [else best])))
  (and selected (c-caption-text selected)))

;; calculus-plan-has-captions? : calculus-plan? -> boolean?
;;   Reports whether the compiled lesson contains authored narration.  The
;; rendering adapter uses this to reserve one stable caption band for every
;; frame of an annotated lesson, instead of making graph panels jump when a
;; caption begins or ends.
(define (calculus-plan-has-captions? plan)
  (check 'calculus-plan-has-captions? calculus-plan? "calculus-plan?" plan)
  (pair? (calculus-plan-captions plan)))

;; calculus-plan-sample : calculus-plan? keyword-options -> calculus-snapshot?
;;   Samples one right-continuous mathematical/presentation state headlessly.
(define (calculus-plan-sample plan #:at [at 'final])
  (check 'calculus-plan-sample calculus-plan? "calculus-plan?" plan)
  (define-values (time cutoff)
    (cond [(eq? at 'initial) (values 0 0)]
          [(eq? at 'final) (values (calculus-plan-duration plan) +inf.0)]
          [(calculus-moment? at) (define entry (resolve-moment plan at)) (values (car entry) (cdr entry))]
          [(and (finite-real? at) (<= 0 at (calculus-plan-duration plan))) (values at +inf.0)]
          [else (raise-arguments-error 'calculus-plan-sample "a valid time, 'initial, 'final, or calculus moment" "at" at)]))
  (define lesson (calculus-plan-lesson plan))
  (define model (calculus-lesson-model lesson))
  (define state
    (apply-events-at (cons (calculus-plan-values plan) (initial-visibility lesson))
                     (calculus-plan-events plan) time cutoff model
                     (calculus-plan-computation plan) lesson
                     (calculus-plan-profile plan)))
  (define diagnostics
    (for/list ([constraint (in-list (calculus-model-constraints model))]
               #:when #t
               #:do [(define result (eval-raw constraint (car state) model (calculus-plan-computation plan)))]
               #:when (or (not (eq? (calculus-result-status result) 'defined)) (not (calculus-result-value result))))
      (calculus-diagnostic 'error 'constraint #f #f time (or (calculus-result-message result) "mathematical constraint failed"))))
  (calculus-snapshot model (car state) (cdr state) diagnostics (calculus-plan-computation plan)))

;; calculus-step-start : step-address? -> calculus-moment?
;;   Selects a step's pre-command semantic phase.
(define (calculus-step-start address) (calculus-moment 'step-start (if (symbol? address) (list address) address)))
;; calculus-step-end : step-address? -> calculus-moment?
;;   Selects a step's settled pre-pause semantic phase.
(define (calculus-step-end address) (calculus-moment 'step-end (if (symbol? address) (list address) address)))
;; calculus-checkpoint : checkpoint-address? -> calculus-moment?
;;   Selects the semantic state named by a checkpoint action.
(define (calculus-checkpoint address) (calculus-moment 'checkpoint (if (symbol? address) (list address) address)))

;; calculus-snapshot-ref : calculus-snapshot? address? -> calculus-result?
;;   Evaluates one public mathematical root or part in the snapshot environment.
(define (calculus-snapshot-ref snapshot address)
  (check 'calculus-snapshot-ref calculus-snapshot? "calculus-snapshot?" snapshot)
  (eval-raw (address->object (calculus-snapshot-model snapshot) address)
            (calculus-snapshot-values snapshot) (calculus-snapshot-model snapshot)
            (calculus-snapshot-computation snapshot)))

;; calculus-snapshot-component-private-ref : calculus-snapshot? c-part? -> calculus-result?
;;   Evaluates a renderer-only private presentation in its component's lexical
;;   model. Public inspection still rejects the same `(private ...)` address.
(define (calculus-snapshot-component-private-ref snapshot part)
  (check 'calculus-snapshot-component-private-ref calculus-snapshot? "calculus-snapshot?" snapshot)
  (define private-address (component-private-part-address part))
  (cond
    [(not private-address) (undefined "expected a private component presentation")]
    [else
     (define instance (c-part-parent part))
     (result-bind
      (component-instance-valid? instance
                                 (calculus-snapshot-values snapshot)
                                 (calculus-snapshot-model snapshot)
                                 (calculus-snapshot-computation snapshot)
                                 (hash))
      (lambda (private-model)
        (define root
          (hash-ref (calculus-model-nodes private-model) (first private-address) #f))
        (if root
            (let ([target
                   (for/fold ([current root]) ([name (in-list (rest private-address))])
                     (c-part current name))])
              (eval-raw target
                        (calculus-snapshot-values snapshot)
                        private-model
                        (calculus-snapshot-computation snapshot)))
            (undefined "private component presentation is not declared"))))]))

;; calculus-snapshot-component-private-visible? : calculus-snapshot? c-part? -> boolean?
;;   Checks direct namespaced visibility only: a collapsed component root must
;;   never reveal its private construction objects by inheritance.
(define (calculus-snapshot-component-private-visible? snapshot part)
  (check 'calculus-snapshot-component-private-visible? calculus-snapshot? "calculus-snapshot?" snapshot)
  (define key (and (component-private-part-address part) (target-key part)))
  (and key (hash-ref (calculus-snapshot-visible snapshot) key #f)))

;; calculus-snapshot-presentation-state : calculus-snapshot? semantic-target? -> symbol?
;;   Supplies the native adapter with one effective visual state while keeping
;;   the public headless API centered on mathematical results and visibility.
;;   A transient highlight supersedes persistent deemphasis for its duration.
(define (calculus-snapshot-presentation-state snapshot target #:view [view #f])
  (check 'calculus-snapshot-presentation-state calculus-snapshot? "calculus-snapshot?" snapshot)
  (when view (check 'calculus-snapshot-presentation-state symbol? "view symbol" view))
  (define visible (calculus-snapshot-visible snapshot))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object (calculus-snapshot-model snapshot) target)
        target))
  (define (state-at property)
    (define local-key
      (and view (view-target-key view (target-key semantic-target))))
    (define local-value
      (if local-key
          (hash-ref visible
                    (list 'calculus-presentation-state property local-key)
                    missing-presentation-value)
          missing-presentation-value))
    (if (eq? local-value missing-presentation-value)
        (hash-ref visible (presentation-state-key property semantic-target) #f)
        local-value))
  (cond [(state-at 'highlighted) 'highlighted]
        [(state-at 'deemphasized) 'deemphasized]
        [(state-at 'refining) 'refining]
        [else 'normal]))

;; calculus-snapshot-motion-state : calculus-snapshot? semantic-target? -> any/c
;;                                     [#:view symbol?]
;; Provides a short-lived native choreography record such as
;; `(reading guided 1/2)` or `(line extend 3/4)`.  It is intentionally an
;; opaque presentation value: consumers use it to choose a visual extent or
;; opacity while headless mathematics stays the same at every progress value.
(define (calculus-snapshot-motion-state snapshot target #:view [view #f])
  (check 'calculus-snapshot-motion-state calculus-snapshot? "calculus-snapshot?" snapshot)
  (when view (check 'calculus-snapshot-motion-state symbol? "view symbol" view))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object (calculus-snapshot-model snapshot) target)
        target))
  (motion-state-at (calculus-snapshot-visible snapshot) semantic-target 'motion view))

;; calculus-snapshot-label-visible? : calculus-snapshot? semantic-target?
;;                                     [#:view symbol?] -> boolean?
;;   Resolves only the independent label preference.  Callers combine this
;;   with ordinary object visibility so `show-label` can never resurrect a
;;   hidden parent point, graph, or reading.
(define (calculus-snapshot-label-visible? snapshot target #:view [view #f])
  (check 'calculus-snapshot-label-visible? calculus-snapshot? "calculus-snapshot?" snapshot)
  (when view (check 'calculus-snapshot-label-visible? symbol? "view symbol" view))
  (define presentation (calculus-snapshot-visible snapshot))
  (define global-key (label-preference-key target))
  (define global-value (if global-key (hash-ref presentation global-key #t) #t))
  (define local-key (and view (label-preference-key target view)))
  (if local-key (hash-ref presentation local-key global-value) global-value))

;; formula-symbol : semantic-value? -> string?
;;   Retains a quantity's semantic identity in prepared text instead of trying
;;   to discover links by comparing rendered characters.
(define (formula-symbol value)
  (cond
    [(c-node? value) (symbol->string (c-node-id value))]
    [(c-part? value)
     (case (c-part-name value)
       [(dx run-label) "Δx"]
       [(dy rise-label) "Δy"]
       [(ratio) "Δy/Δx"]
       [(input) "x"]
       [(output) "y"]
       [else (format "~a" (c-part-name value))])]
    [(c-expression? value) (formula-held-text value #f #f #f)]
    [(symbol? value) (symbol->string value)]
    [(number? value) (number->string value)]
    [else "?"]))

;; formula-number-text : finite-real? symbol? any/c -> string?
;;   Formats the documented finite value forms while keeping exact and
;;   approximate result provenance separate from the requested notation.
(define (formula-number-text value format-kind digits)
  (cond
    [(not (finite-real? value)) "undefined"]
    [(eq? format-kind 'exact) (number->string value)]
    [(and (memq format-kind '(decimal scientific))
          (exact-nonnegative-integer? digits))
     (define decimal
       (real->decimal-string (exact->inexact value) digits))
     ;; A displayed negative zero is a presentation artifact, never a new
     ;; mathematical value or a change in result exactness.
     (if (regexp-match? #rx"^-0(?:\\.0*)?$" decimal)
         (string-append "0" (if (zero? digits) "" (string-append "." (make-string digits #\0))))
         decimal)]
    [else (number->string value)]))

;; formula-held-text : any/c calculus-snapshot? hash? calculus-model? -> string?
;;   Converts a held Formula expression to deterministic prepared text. It is
;;   intentionally not an algebra evaluator: ref and value leaves retain their
;;   different semantic roles, and every ordinary occurrence is traversed.
(define (formula-held-text expression snapshot environment model)
  (define computation (and snapshot (calculus-snapshot-computation snapshot)))
  (define (render-value target)
    (if (not snapshot)
        (formula-symbol target)
        (let ([result (eval-raw target environment model computation)])
          (if (eq? (calculus-result-status result) 'defined)
              (string-append (if (calculus-result-approximate? result) "≈" "")
                             (formula-number-text (calculus-result-value result) 'exact #f))
              "undefined"))))
  ;; `outer-precedence` preserves the held tree's mathematical grouping in
  ;; plain inspection text. The native adapter receives a separately prepared
  ;; TeX form; it never has to infer precedence from this display string.
  (define (render item [outer-precedence 0])
    (define (parenthesize text precedence)
      (if (< precedence outer-precedence) (format "(~a)" text) text))
    (cond
      [(c-expression? item)
       (define op (c-expression-op item))
       (define args (c-expression-arguments item))
       (case op
         [(+)
          (parenthesize (string-join (map (lambda (value) (render value 10)) args) " + ") 10)]
         [(-)
          (parenthesize
           (if (= (length args) 1)
               (string-append "−" (render (first args) 30))
               (string-join (map (lambda (value) (render value 11)) args) " − "))
           10)]
         [(*)
          (parenthesize (string-join (map (lambda (value) (render value 20)) args) " · ") 20)]
         [(/)
          (parenthesize
           (if (= (length args) 2)
               (format "(~a)/(~a)" (render (first args)) (render (second args)))
               (string-join (map render args) " / "))
           20)]
         [(expt)
          (parenthesize
           (if (= (length args) 2)
               (format "~a^~a" (render (first args) 30) (render (second args) 31))
               (string-join (map render args) " ^ "))
           30)]
         [(= < <= > >=) (parenthesize (string-join (map render args) (format " ~a " op)) 5)]
         [(sqrt) (format "√(~a)" (render (first args)))]
         [(abs) (format "|~a|" (render (first args)))]
         [(sin cos tan asin acos atan exp log)
          (format "~a(~a)" op (string-join (map render args) ", "))]
         [(list) (format "(~a)" (string-join (map render args) ", "))]
         [else (format "~a(~a)" op (string-join (map render args) ", "))])]
      [(and (c-object? item) (eq? (c-object-kind item) 'ref))
       (formula-symbol (first (c-object-arguments item)))]
      [(and (c-object? item) (eq? (c-object-kind item) 'value))
       (render-value (first (c-object-arguments item)))]
      [(or (c-node? item) (c-part? item)) (formula-symbol item)]
      [(string? item) item]
      [(symbol? item) (symbol->string item)]
      [(number? item) (number->string item)]
      [else "?"]))
  (render expression))

;; formula-tex-atom : string? -> string?
;;   Translates only atomic notation vocabulary. Compound mathematical
;; structure is emitted by `formula-held-tex` below, never reconstructed with
;; regular expressions from a flattened formula string.
(define (formula-tex-atom text)
  (define replacements
    (list (cons "Δx" "\\Delta x")
          (cons "Δy" "\\Delta y")
          (cons "Δ" "\\Delta ")
          (cons "≈" "\\approx ")
          (cons "≤" "\\le ")
          (cons "≥" "\\ge ")
          (cons "≠" "\\ne ")
          (cons "−" "-")
          (cons "′" "^{\\prime}")
          (cons "∞" "\\infty ")))
  (let loop ([remaining replacements] [result text])
    (if (null? remaining)
        result
        (loop (rest remaining)
              (string-replace result (caar remaining) (cdar remaining))))))

;; formula-held-tex : any/c calculus-snapshot? hash? calculus-model? -> string?
;;   Lowers the held Formula tree directly to grouped TeX. Every fraction,
;;   power, radical, and occurrence is traversed from the original semantic
;;   tree, so display syntax cannot change the taught expression's meaning.
(define (formula-held-tex expression snapshot environment model)
  (define computation (and snapshot (calculus-snapshot-computation snapshot)))
  (define (render-value target)
    (if (not snapshot)
        (formula-tex-atom (formula-symbol target))
        (let ([result (eval-raw target environment model computation)])
          (if (eq? (calculus-result-status result) 'defined)
              (string-append (if (calculus-result-approximate? result) "\\approx " "")
                             (formula-tex-atom
                              (formula-number-text (calculus-result-value result) 'exact #f)))
              "\\mathrm{undefined}"))))
  ;; TeX braces establish parser grouping but are not visible mathematical
  ;; delimiters.  This renderer carries precedence through the held tree and
  ;; writes visible parentheses where a reader needs them to recover the
  ;; original operation tree.
  (define (render item [outer-precedence 0])
    (define (parenthesize text precedence)
      (if (< precedence outer-precedence)
          (format "\\left(~a\\right)" text)
          text))
    (define (render-negative-number value)
      (define text (number->string value))
      (if (and (negative? value) (> outer-precedence 30))
          (format "\\left(~a\\right)" text)
          text))
    (cond
      [(c-expression? item)
       (define op (c-expression-op item))
       (define args (c-expression-arguments item))
       (case op
         [(+)
          (parenthesize (string-join (map (lambda (value) (render value 10)) args) " + ") 10)]
         [(-)
          (parenthesize
           (if (= (length args) 1)
               (format "-\\left(~a\\right)" (render (first args)))
               (string-join (map (lambda (value) (render value 11)) args) " - "))
           10)]
         [(*)
          (parenthesize
           (string-join (map (lambda (value) (render value 21)) args) "\\cdot ")
           20)]
         [(/)
          (parenthesize
           (cond [(= (length args) 1) (format "\\frac{1}{~a}" (render (first args)))]
                 [(= (length args) 2)
                  (format "\\frac{~a}{~a}" (render (first args)) (render (second args)))]
                 [else (string-join (map render args) " / ")])
           20)]
         [(expt)
          (parenthesize
           (if (= (length args) 2)
               (format "~a^{~a}" (render (first args) 31) (render (second args)))
               (string-join (map render args) " ^ "))
           30)]
         [(= < <= > >=) (parenthesize (string-join (map render args) (format " ~a " op)) 5)]
         [(sqrt) (format "\\sqrt{~a}" (render (first args)))]
         [(abs) (format "\\left|~a\\right|" (render (first args)))]
         [(sin cos tan asin acos atan exp log)
          (format "\\~a\\left(~a\\right)" op (string-join (map render args) ", "))]
         [(list) (format "\\left(~a\\right)" (string-join (map render args) ", "))]
         [else (format "\\operatorname{~a}\\left(~a\\right)"
                       op (string-join (map render args) ", "))])]
      [(and (c-object? item) (eq? (c-object-kind item) 'ref))
       (formula-tex-atom (formula-symbol (first (c-object-arguments item))))]
      [(and (c-object? item) (eq? (c-object-kind item) 'value))
       (render-value (first (c-object-arguments item)))]
      [(or (c-node? item) (c-part? item)) (formula-tex-atom (formula-symbol item))]
      [(string? item) (formula-tex-atom item)]
      [(symbol? item) (formula-tex-atom (symbol->string item))]
      [(number? item) (render-negative-number item)]
      [else "?"]))
  (render expression))

;; formula-of-text : semantic-value? calculus-snapshot? -> string?
;;   Covers the conventional supported Formula-of forms and never falls back to
;;   an opaque record representation.
(define (formula-of-text source snapshot)
  (define raw (node-raw source))
  (cond
    [(or (c-function? raw) (c-piecewise? raw))
     (format "~a(x)" (formula-symbol source))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'derivative-function))
     (format "~a′(x)" (formula-symbol (first (c-object-arguments raw))))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'definite-integral))
     (define function (first (c-object-arguments raw)))
     (define lower (hash-ref (c-object-options raw) 'from "?"))
     (define upper (hash-ref (c-object-options raw) 'to "?"))
     (format "∫_(~a)^(~a) ~a(x) dx"
             (formula-held-text lower snapshot
                                (and snapshot (calculus-snapshot-values snapshot))
                                (and snapshot (calculus-snapshot-model snapshot)))
             (formula-held-text upper snapshot
                                (and snapshot (calculus-snapshot-values snapshot))
                                (and snapshot (calculus-snapshot-model snapshot)))
             (formula-symbol function))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'limit-statement))
     (define function (first (c-object-arguments raw)))
     (define target (hash-ref (c-object-options raw) 'to "?"))
     (format "lim_(x→~a) ~a(x)"
             (formula-held-text target snapshot
                                (and snapshot (calculus-snapshot-values snapshot))
                                (and snapshot (calculus-snapshot-model snapshot)))
             (formula-symbol function))]
    [(or (c-node? source) (c-expression? source) (c-part? source))
     (formula-symbol source)]
    [else "unsupported formula"] ))

;; formula-of-tex : semantic-value? calculus-snapshot? -> string?
;;   Emits conventional Formula-of forms with their actual source data and
;;   bounds rather than placeholder prose.
(define (formula-of-tex source snapshot)
  (define raw (node-raw source))
  (define environment (and snapshot (calculus-snapshot-values snapshot)))
  (define model (and snapshot (calculus-snapshot-model snapshot)))
  (cond
    [(or (c-function? raw) (c-piecewise? raw))
     (format "~a(x)" (formula-tex-atom (formula-symbol source)))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'derivative-function))
     (format "~a^{\\prime}(x)"
             (formula-tex-atom (formula-symbol (first (c-object-arguments raw)))))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'definite-integral))
     (format "\\int_{~a}^{~a} ~a(x)\\,dx"
             (formula-held-tex (hash-ref (c-object-options raw) 'from "?") snapshot environment model)
             (formula-held-tex (hash-ref (c-object-options raw) 'to "?") snapshot environment model)
             (formula-tex-atom (formula-symbol (first (c-object-arguments raw)))))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'limit-statement))
     (format "\\lim_{x\\to ~a} ~a(x)"
             (formula-held-tex (hash-ref (c-object-options raw) 'to "?") snapshot environment model)
             (formula-tex-atom (formula-symbol (first (c-object-arguments raw)))))]
    [else (formula-tex-atom (formula-of-text source snapshot))]))

;; formula-target+model : calculus-snapshot? semantic-value? -> values
;;   Resolves a Formula presentation target and its component-local model once
;;   for both text inspection and structured TeX preparation.
(define (formula-target+model snapshot target)
  (define model (calculus-snapshot-model snapshot))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object model target)
        target))
  (cond
    [(c-part? semantic-target)
     (define component-node
       (or (calculus-component-part-node semantic-target)
           (calculus-component-private-part-node semantic-target)))
     (define instance-result
       (and component-node
            (component-instance-model (c-part-parent semantic-target))))
     (if (and component-node
              (eq? (calculus-result-status instance-result) 'defined))
         (values component-node (calculus-result-value instance-result))
         (values semantic-target model))]
    [else (values semantic-target model)]))

;; calculus-snapshot-formula-text : calculus-snapshot? semantic-value? -> calculus-result?
;;   Private preparation bridge for Formula and value-readout rows. It returns
;;   text derived from held semantic structure and current snapshot values, not
;;   from rendered glyph recognition or a second mathematical evaluator.
(define (calculus-snapshot-formula-text snapshot target)
  (check 'calculus-snapshot-formula-text calculus-snapshot? "calculus-snapshot?" snapshot)
  (define environment (calculus-snapshot-values snapshot))
  ;; A public component export is represented at the caller boundary by a
  ;; c-part, but Formula presentation must retain the declared object that
  ;; lives in the instantiated component model.  Evaluating the c-part itself
  ;; yields the export's descriptor (for example a value-readout), which is why
  ;; the previous bridge displayed ``undefined'' instead of its formatted
  ;; reading.  Select that declared node and its lexical model before
  ;; formatting; this remains a presentation lookup and never exposes a new
  ;; public inspection address.
  (define-values (formula-target formula-model)
    (formula-target+model snapshot target))
  (define raw (node-raw formula-target))
  (cond
    [(and (c-object? raw) (eq? (c-object-kind raw) 'formula))
     (defined (formula-held-text (first (c-object-arguments raw)) snapshot environment formula-model))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'formula-of))
     (defined (formula-of-text (first (c-object-arguments raw)) snapshot))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'value-readout))
     (define value-result
       (eval-raw (first (c-object-arguments raw)) environment formula-model
                 (calculus-snapshot-computation snapshot)))
     (define undefined-policy (hash-ref (c-object-options raw) 'undefined 'error))
     (if (eq? (calculus-result-status value-result) 'defined)
         (let* ([options (c-object-options raw)]
                [label (hash-ref options 'label (formula-symbol (first (c-object-arguments raw))))]
                [format-kind (hash-ref options 'format 'exact)]
                [digits (hash-ref options 'digits 3)]
                [prefix (if (calculus-result-approximate? value-result) "≈" "")])
           (defined (format "~a ~a~a" label prefix
                            (formula-number-text (calculus-result-value value-result)
                                                 format-kind digits))))
         (cond [(eq? undefined-policy 'label)
                (defined (format "~a undefined"
                                 (hash-ref (c-object-options raw) 'label
                                           (formula-symbol (first (c-object-arguments raw))))))]
               [(eq? undefined-policy 'error) value-result]
               [else (undefined "value-readout #:undefined must be 'error or 'label")]))]
    [else
     (let ([result (eval-raw formula-target environment formula-model (calculus-snapshot-computation snapshot))])
       (if (eq? (calculus-result-status result) 'defined)
           (defined (formula-number-text (calculus-result-value result) 'exact #f))
           result))]))

;; calculus-snapshot-formula-tex : calculus-snapshot? semantic-value? -> calculus-result?
;;   Supplies the formula backend with direct structured TeX preparation. The
;;   parallel text bridge remains for headless inspection and ordinary labels;
;;   this function deliberately does not parse that flattened text.
(define (calculus-snapshot-formula-tex snapshot target)
  (check 'calculus-snapshot-formula-tex calculus-snapshot? "calculus-snapshot?" snapshot)
  (define environment (calculus-snapshot-values snapshot))
  (define-values (formula-target formula-model)
    (formula-target+model snapshot target))
  (define raw (node-raw formula-target))
  (cond
    [(and (c-object? raw) (eq? (c-object-kind raw) 'formula))
     (defined (formula-held-tex (first (c-object-arguments raw)) snapshot environment formula-model))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'formula-of))
     (defined (formula-of-tex (first (c-object-arguments raw)) snapshot))]
    [(and (c-object? raw) (eq? (c-object-kind raw) 'value-readout))
     (define text-result (calculus-snapshot-formula-text snapshot target))
     (if (eq? (calculus-result-status text-result) 'defined)
         (defined (formula-tex-atom (calculus-result-value text-result)))
         text-result)]
    [else
     (define text-result (calculus-snapshot-formula-text snapshot target))
     (if (eq? (calculus-result-status text-result) 'defined)
         (defined (formula-tex-atom (calculus-result-value text-result)))
         text-result)]))

;; calculus-snapshot-formula-skeleton-tex : calculus-snapshot? semantic-value?
;;                                           exact-nonnegative-integer?
;;                                        -> calculus-result?
;; Produces one prepared mathematical skeleton for a live Formula.  Each
;; `(value ...)` occurrence becomes an explicitly sized invisible TeX nucleus;
;; fractions, powers, radicals, and every held glyph therefore stay on the
;; configured formula backend while native drawing updates only the field.
(define (calculus-snapshot-formula-skeleton-tex snapshot target reserve)
  (check 'calculus-snapshot-formula-skeleton-tex calculus-snapshot? "calculus-snapshot?" snapshot)
  (unless (exact-nonnegative-integer? reserve)
    (raise-argument-error 'calculus-snapshot-formula-skeleton-tex
                          "exact-nonnegative-integer? field reservation" reserve))
  (define environment (calculus-snapshot-values snapshot))
  (define-values (formula-target formula-model)
    (formula-target+model snapshot target))
  (define raw (node-raw formula-target))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'formula)))
     (unresolved "Formula skeleton requires a Formula row")]
    [else
     (define placeholder (format "\\phantom{~a}" (make-string reserve #\0)))
     (define (replace-live-leaves item)
       (cond
         [(c-expression? item)
          (c-expression (c-expression-op item)
                        (map replace-live-leaves (c-expression-arguments item)))]
         [(c-object? item)
          (if (eq? (c-object-kind item) 'value)
              placeholder
              (c-object (c-object-kind item)
                        (map replace-live-leaves (c-object-arguments item))
                        (for/hash ([(key value) (in-hash (c-object-options item))])
                          (values key (replace-live-leaves value)))))]
         [(pair? item) (cons (replace-live-leaves (car item))
                             (replace-live-leaves (cdr item)))]
         [else item]))
     (defined
      (formula-held-tex
       (replace-live-leaves (first (c-object-arguments raw)))
       snapshot environment formula-model))]))

;; calculus-snapshot-formula-fragments : calculus-snapshot? semantic-value?
;;                                        -> calculus-result?
;; Keeps live Formula values as explicit field fragments. The native adapter
;; prepares fixed-width slots for those fields, so a changing number cannot
;; request a new whole TeX formula or move the surrounding held notation.
;; Each successful value is a list of `(text string)` and `(field string)`
;; records in source order.
(define (calculus-snapshot-formula-fragments snapshot target)
  (check 'calculus-snapshot-formula-fragments calculus-snapshot? "calculus-snapshot?" snapshot)
  (define environment (calculus-snapshot-values snapshot))
  (define-values (formula-target formula-model)
    (formula-target+model snapshot target))
  (define raw (node-raw formula-target))
  (cond
    [(and (c-object? raw) (eq? (c-object-kind raw) 'formula))
     ;; Replace each live leaf with an unforgeable-in-practice private marker,
     ;; then reuse the exact same precedence-aware held-text renderer. This
     ;; avoids a second notation grammar for field layout and retains grouped
     ;; multiplication, powers, fractions, and radicals verbatim.
     (define nonce (symbol->string (gensym 'calculus-field-)))
     (define fields '())
     (define field-index 0)
     (define (next-marker)
       (define marker (format "\uE000~a-~a\uE001" nonce field-index))
       (set! field-index (add1 field-index))
       marker)
     (define (replace-live-leaves item)
       (cond
         [(c-expression? item)
          (c-expression (c-expression-op item)
                        (map replace-live-leaves (c-expression-arguments item)))]
         [(c-object? item)
          (cond [(eq? (c-object-kind item) 'value)
                 (define marker (next-marker))
                 (set! fields (append fields (list (cons marker item))))
                 marker]
                [else
                 (c-object (c-object-kind item)
                           (map replace-live-leaves (c-object-arguments item))
                           (for/hash ([(key value) (in-hash (c-object-options item))])
                             (values key (replace-live-leaves value))))])]
         [(pair? item) (cons (replace-live-leaves (car item))
                             (replace-live-leaves (cdr item)))]
         [else item]))
     (define text
       (formula-held-text (replace-live-leaves (first (c-object-arguments raw)))
                          snapshot environment formula-model))
     (define (field-text field)
       (formula-held-text field snapshot environment formula-model))
     (define (append-text fragments text-piece)
       (if (string=? text-piece "")
           fragments
           (append fragments (list (list 'text text-piece)))))
     (define (string-position text needle)
       ;; `string-contains?` reports only a boolean in racket/base; field
       ;; splitting needs the exact source-order offset without treating the
       ;; marker as a regular expression.
       (for/first ([index (in-range (add1 (- (string-length text)
                                             (string-length needle))))]
                   #:when (string=? needle
                                    (substring text index
                                               (+ index (string-length needle)))))
         index))
     (let loop ([remaining text] [unplaced fields] [fragments '()])
       (cond
         [(null? unplaced) (defined (append-text fragments remaining))]
         [else
          (define marker (caar unplaced))
          (define position (string-position remaining marker))
          ;; A marker generated during this evaluation must survive the held
          ;; text renderer. If a future renderer changes that invariant, make
          ;; the row explicitly unresolved instead of shifting glyphs.
          (if (not position)
              (unresolved "Formula field marker was not retained during preparation")
              (let* ([prefix (substring remaining 0 position)]
                     [after-start (+ position (string-length marker))]
                     [after (substring remaining after-start)]
                     [next-fragments
                      (append (append-text fragments prefix)
                              (list (list 'field (field-text (cdar unplaced)))))])
                (loop after (cdr unplaced) next-fragments)))]))]
    [else
     ;; A readout is one changing field with no symbolic suffix to stabilize.
     ;; It still takes this fragment path so drawing never asks the formula
     ;; backend to typeset a state-dependent whole row.
     (result-bind
      (calculus-snapshot-formula-text snapshot target)
      (lambda (text) (defined (list (list 'field text)))))]))

;; calculus-snapshot-label-text : calculus-snapshot? semantic-value? -> calculus-result?
;;   Supplies native annotation text from a held label declaration. It retains
;; a quantity's semantic name when no explicit text was authored, and never
;; recovers text by inspecting a prior native frame.
(define (calculus-snapshot-label-text snapshot target)
  (check 'calculus-snapshot-label-text calculus-snapshot? "calculus-snapshot?" snapshot)
  (define model (calculus-snapshot-model snapshot))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object model target)
        target))
  (define raw (node-raw semantic-target))
  (cond
    [(not (c-object? raw)) (undefined "expected a label")]
    [(memq (c-object-kind raw) '(point-label graph-label))
     (if (>= (length (c-object-arguments raw)) 2)
         (defined (formula-held-text (second (c-object-arguments raw)) snapshot
                                     (calculus-snapshot-values snapshot) model))
         (undefined "label requires text"))]
    [(eq? (c-object-kind raw) 'quantity-label)
     (define text (hash-ref (c-object-options raw) 'text #f))
     (defined (if text
                  (formula-held-text text snapshot (calculus-snapshot-values snapshot) model)
                  (formula-symbol (first (c-object-arguments raw)))))]
    [else (undefined "expected a label")]))

;; calculus-snapshot-label-anchor : calculus-snapshot? semantic-value?
;;                                    [#:default-input (or/c #f finite-real?)]
;;                                    -> calculus-result?
;;   Resolves an anchored annotation in the same immutable mathematical state
;; as its text.  In particular, a graph-label's #:at expression may depend on
;; a parameter, so the native adapter must receive the resulting point rather
;; than interpreting that held expression itself.  The optional default input
;; lets view layout choose a stable exposed graph position without duplicating
;; function evaluation outside the semantic core.
(define (calculus-snapshot-label-anchor snapshot target #:default-input [default-input #f])
  (check 'calculus-snapshot-label-anchor calculus-snapshot? "calculus-snapshot?" snapshot)
  (when default-input
    (check 'calculus-snapshot-label-anchor finite-real? "finite real default input" default-input))
  (define environment (calculus-snapshot-values snapshot))
  (define model (calculus-snapshot-model snapshot))
  (define computation (calculus-snapshot-computation snapshot))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object model target)
        target))
  (define raw (node-raw semantic-target))
  (cond
    [(not (c-object? raw)) (undefined "expected a label")]
    [(eq? (c-object-kind raw) 'point-label)
     (if (pair? (c-object-arguments raw))
         (eval-point (first (c-object-arguments raw)) environment model computation (hash))
         (undefined "point label requires an anchor"))]
    [(eq? (c-object-kind raw) 'quantity-label)
     (define anchor (hash-ref (c-object-options raw) 'at #f))
     (if anchor
         (eval-raw anchor environment model computation)
         (undefined "quantity label requires an anchor"))]
    [(eq? (c-object-kind raw) 'graph-label)
     (define input-expression
       (hash-ref (c-object-options raw) 'at default-input))
     (define graph
       (and (pair? (c-object-arguments raw))
            (first (c-object-arguments raw))))
     (cond [(not input-expression)
            (undefined "graph label requires an input anchor")]
           [(not (and graph (graph-function graph)))
            (undefined "graph label requires a graph anchor")]
           [else
            (result-bind
             (eval-raw input-expression environment model computation)
             (lambda (input)
               (if (not (finite-real? input))
                   (undefined "graph label input is not a finite real value")
                   (result-bind
                    (evaluate-graph graph input environment model computation)
                    (lambda (output)
                      (if (finite-real? output)
                          (defined (cons input output))
                          (undefined "graph label output is not a finite real value")))))))])]
    [else (undefined "expected a label")]))

;; marker-span-result : symbol? finite-real? finite-real? -> calculus-result?
;;   Retains endpoint inclusion as semantic data for one directly declared
;; finite interval.
(define (marker-span-result kind lower upper)
  (cond [(> lower upper) (unresolved "domain endpoints are crossed")]
        [(and (= lower upper) (not (eq? kind 'closed))) (defined '())]
        [else
         (defined
          (list
           (list 'span lower upper
                 (not (not (memq kind '(closed closed-open))))
                 (not (not (memq kind '(closed open-closed)))))))]))

;; marker-span? : any/c -> boolean?
;;   Recognizes one bounded semantic interval-marker piece.
(define (marker-span? value)
  (and (list? value) (= (length value) 5) (eq? (first value) 'span)
       (finite-real? (second value)) (finite-real? (third value))
       (boolean? (fourth value)) (boolean? (fifth value))))

;; marker-intersect-spans : marker-span? marker-span? -> (or/c marker-span? #f)
;;   Intersects two declared finite spans while retaining inclusion exactly at
;; ties. This is domain membership logic, not a graphical clipping shortcut.
(define (marker-intersect-spans left right)
  (define lower (max (second left) (second right)))
  (define upper (min (third left) (third right)))
  (define lower-included?
    (and (if (= lower (second left)) (fourth left) #t)
         (if (= lower (second right)) (fourth right) #t)))
  (define upper-included?
    (and (if (= upper (third left)) (fifth left) #t)
         (if (= upper (third right)) (fifth right) #t)))
  (and (or (< lower upper) (and (= lower upper) lower-included? upper-included?))
       (list 'span lower upper lower-included? upper-included?)))

;; marker-intersect-pieces : list? list? -> list?
;;   Treats an unbounded line as the identity interval for finite marker pieces.
(define (marker-intersect-pieces left right)
  (append-map
   (lambda (first-piece)
     (append-map
      (lambda (second-piece)
        (cond [(equal? first-piece (list 'line)) (list second-piece)]
              [(equal? second-piece (list 'line)) (list first-piece)]
              [(and (marker-span? first-piece) (marker-span? second-piece))
               (let ([piece (marker-intersect-spans first-piece second-piece)])
                 (if piece (list piece) '()))]
              [else '()]))
      right))
   left))

;; marker-subtract-hole : list? finite-real? -> list?
;;   Splits a finite member interval at one excluded input. A real-line piece
;; keeps its unbounded line plus an explicit semantic hole for native drawing.
(define (marker-subtract-hole pieces hole)
  (append-map
   (lambda (piece)
     (cond [(equal? piece (list 'line)) (list piece (list 'hole hole))]
           [(not (marker-span? piece)) (list piece)]
           [else
            (define lower (second piece))
            (define upper (third piece))
            (define lower-included? (fourth piece))
            (define upper-included? (fifth piece))
            (cond [(or (< hole lower) (> hole upper)) (list piece)]
                  [(= lower upper) '()]
                  [(= hole lower)
                   (list (list 'span lower upper #f upper-included?))]
                  [(= hole upper)
                   (list (list 'span lower upper lower-included? #f))]
                  [else
                   (list (list 'span lower hole lower-included? #f)
                         (list 'span hole upper #f upper-included?))])]))
   pieces))

;; marker-domain-pieces : semantic-value? hash? calculus-model? calculus-computation?
;;                        -> calculus-result?
;;   Normalizes the finite, directly representable part of a declared domain
;; into axis-marker spans. This is deliberately semantic data: open/closed
;; endpoints remain Boolean membership facts instead of native brush choices.
(define (marker-domain-pieces domain environment model computation)
  (define raw (node-raw domain))
  (cond
    [(not (c-domain? raw)) (undefined "interval marker requires a domain")]
    [(eq? (c-domain-kind raw) 'empty) (defined '())]
    [(eq? (c-domain-kind raw) 'real-line) (defined (list (list 'line)))]
    [(eq? (c-domain-kind raw) 'singleton)
     (result-bind
      (eval-domain-number (first (c-domain-arguments raw)) environment model computation)
      (lambda (value) (defined (list (list 'span value value #t #t)))))]
    [(memq (c-domain-kind raw) '(closed open closed-open open-closed))
     (result-bind
      (eval-domain-number (first (c-domain-arguments raw)) environment model computation)
      (lambda (lower)
        (result-bind
         (eval-domain-number (second (c-domain-arguments raw)) environment model computation)
         (lambda (upper)
           (marker-span-result (c-domain-kind raw) lower upper)))))]
    [(eq? (c-domain-kind raw) 'domain-union)
     (let loop ([remaining (c-domain-arguments raw)] [pieces '()])
       (cond [(null? remaining) (defined (immutable-list-copy (reverse pieces)))]
             [else
              (result-bind
               (marker-domain-pieces (car remaining) environment model computation)
               (lambda (next)
                 (loop (cdr remaining) (append (reverse next) pieces))))]))]
    [(eq? (c-domain-kind raw) 'domain-intersection)
     (let loop ([remaining (c-domain-arguments raw)] [pieces (list (list 'line))])
       (cond [(null? remaining) (defined pieces)]
             [else
              (result-bind
               (marker-domain-pieces (car remaining) environment model computation)
               (lambda (next)
                 (loop (cdr remaining) (marker-intersect-pieces pieces next))))]))]
    [(eq? (c-domain-kind raw) 'domain-except)
     (define arguments (c-domain-arguments raw))
     (if (null? arguments)
         (undefined "domain-except requires a base domain")
         (result-bind
          (marker-domain-pieces (first arguments) environment model computation)
          (lambda (base-pieces)
            (let loop ([holes (rest arguments)] [pieces base-pieces])
              (cond [(null? holes) (defined pieces)]
                    [else
                     (result-bind
                      (eval-domain-number (car holes) environment model computation)
                      (lambda (hole)
                        (loop (cdr holes) (marker-subtract-hole pieces hole))))])))))]
    [else
     (unresolved
      (format "interval-marker cannot realize domain kind ~a" (c-domain-kind raw)))]))

;; marker-domain-endpoint : list? finite-real? -> (or/c (cons/c #t boolean?) #f)
;;   Finds an authored finite endpoint and returns its inclusion separately
;; from absence. An open endpoint is a real boundary with the value #f.
(define (marker-domain-endpoint pieces input)
  (for/or ([piece (in-list pieces)])
    (and (list? piece)
         (= (length piece) 5)
         (eq? (first piece) 'span)
         (cond [(= input (second piece)) (cons #t (fourth piece))]
               [(= input (third piece)) (cons #t (fifth piece))]
               [else #f]))))

;; evaluate-transparent-endpoint : c-function? finite-real? hash? calculus-model?
;;                                  calculus-computation? -> calculus-result?
;;   Evaluates a directly held function body at an excluded finite boundary.
;; It deliberately excludes pieces, providers, and derived function objects:
;; they can require one-sided/branch evidence that a direct body evaluation
;; does not establish. This is semantic evaluation, not pixel interpolation.
(define (evaluate-transparent-endpoint source input environment model computation)
  (cond [(not (c-function? source))
         (unresolved "endpoint marker requires supported branch-limit evidence")]
        [else
         (define body (c-function-body source))
         (cond [(c-expression? body)
                (eval-raw body environment model computation
                          (hash (c-function-variable source) (defined input)))]
               [else
                (unresolved "endpoint marker requires a transparent held function body")])]))

;; calculus-snapshot-marker-geometry : calculus-snapshot? semantic-value? -> calculus-result?
;;   Exposes resolved marker geometry to native preparation without allowing
;; the adapter to guess domain inclusion, a graph boundary, or approach side.
;; Unsupported branch-limit endpoints remain unresolved instead of becoming a
;; visually plausible open circle.
(define (calculus-snapshot-marker-geometry snapshot target)
  (check 'calculus-snapshot-marker-geometry calculus-snapshot? "calculus-snapshot?" snapshot)
  (define environment (calculus-snapshot-values snapshot))
  (define model (calculus-snapshot-model snapshot))
  (define computation (calculus-snapshot-computation snapshot))
  (define semantic-target
    (if (or (symbol? target) (and (list? target) (pair? target)))
        (address->object model target)
        target))
  (define raw (node-raw semantic-target))
  (cond
    [(not (c-object? raw)) (undefined "expected a marker")]
    [(eq? (c-object-kind raw) 'interval-marker)
     (define axis (hash-ref (c-object-options raw) 'axis #f))
     (if (not (memq axis '(x y)))
         (undefined "interval marker axis must be 'x or 'y")
         (result-bind
          (marker-domain-pieces (first (c-object-arguments raw)) environment model computation)
          (lambda (pieces) (defined (list 'interval-marker axis pieces)))))]
    [(eq? (c-object-kind raw) 'approach-marker)
     (define axis (hash-ref (c-object-options raw) 'axis #f))
     (define side (hash-ref (c-object-options raw) 'side #f))
     (cond [(not (memq axis '(x y))) (undefined "approach marker axis must be 'x or 'y")]
           [(not (memq side '(left right))) (undefined "approach marker side must be 'left or 'right")]
           [else
            (result-bind
             (eval-raw (first (c-object-arguments raw)) environment model computation)
             (lambda (value)
               (if (finite-real? value)
                   (defined (list 'approach-marker axis side value))
                   (undefined "approach marker coordinate is not a finite real value"))))])]
    [(eq? (c-object-kind raw) 'endpoint-marker)
     (define graph (and (pair? (c-object-arguments raw))
                        (first (c-object-arguments raw))))
     (define function (and graph (graph-function graph)))
     (define source (and function (lookup-function function)))
     (define input (hash-ref (c-object-options raw) 'at #f))
     (cond [(not source) (undefined "endpoint marker requires a graph")]
           [(not input) (undefined "endpoint marker requires #:at")]
           [else
            (result-bind
             (eval-raw input environment model computation)
             (lambda (value)
               (if (not (finite-real? value))
                   (undefined "endpoint marker input is not a finite real value")
                   (result-bind
                    (marker-domain-pieces (graph-domain graph) environment model computation)
                    (lambda (pieces)
                      (define endpoint (marker-domain-endpoint pieces value))
                      (cond [(not endpoint)
                             (unresolved "endpoint marker input is not a declared graph boundary")]
                            [(cdr endpoint)
                             (result-bind
                              (evaluate-function function value environment model computation)
                              (lambda (output)
                                (if (finite-real? output)
                                    (defined (list 'endpoint-marker value output #t))
                                    (undefined "endpoint marker has no finite graph value"))))]
                            [else
                             (result-bind
                              (evaluate-transparent-endpoint source value environment model computation)
                              (lambda (output)
                                (if (finite-real? output)
                                    (defined (list 'endpoint-marker value output #f))
                                    (unresolved "endpoint marker has no supported finite branch limit"))))]))))))])]
    [else (undefined "expected a marker")]))

;; calculus-snapshot-newton-segments : calculus-snapshot? semantic-value? -> calculus-result?
;;   Converts an available finite Newton prefix into exact graph-to-axis
;;   construction segments. The renderer receives the evaluated construction,
;;   never permission to derive an additional iterate from screen geometry.
(define (calculus-snapshot-newton-segments snapshot diagram)
  (check 'calculus-snapshot-newton-segments calculus-snapshot? "calculus-snapshot?" snapshot)
  (define raw (node-raw diagram))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'newton-diagram)))
     (undefined "expected newton-diagram")]
    [else
     (define iteration (first (c-object-arguments raw)))
     (define iteration-raw (node-raw iteration))
     (cond
       [(not (and (c-object? iteration-raw)
                  (eq? (c-object-kind iteration-raw) 'newton-iteration)))
        (undefined "newton-diagram requires a Newton iteration")]
       [else
        (define environment (calculus-snapshot-values snapshot))
        (define model (calculus-snapshot-model snapshot))
        (define computation (calculus-snapshot-computation snapshot))
        (result-bind
         (eval-raw diagram environment model computation)
         (lambda (prefix)
           (let loop ([remaining prefix] [segments '()])
             (cond
               [(or (null? remaining) (null? (rest remaining)))
                (defined (immutable-list-copy (reverse segments)))]
               [else
                (define x (cdr (first remaining)))
                (define next-x (cdr (second remaining)))
                (result-bind
                 (evaluate-function (first (c-object-arguments iteration-raw))
                                    x environment model computation)
                 (lambda (y)
                   (if (and (finite-real? x) (finite-real? y) (finite-real? next-x))
                       (loop (rest remaining) (cons (list x y next-x) segments))
                       (undefined "Newton diagram has a nonfinite construction step"))))]))))])]))

;; calculus-snapshot-function-value : calculus-snapshot? any/c finite-real? -> calculus-result?
;;   Evaluates a held function in a sampled immutable mathematical environment.
;;   This internal native-adapter bridge never exposes the evaluator publicly.
(define (calculus-snapshot-function-value snapshot function input)
  (check 'calculus-snapshot-function-value calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-function-value finite-real? "finite real input" input)
  (evaluate-function function input
                     (calculus-snapshot-values snapshot)
                     (calculus-snapshot-model snapshot)
                     (calculus-snapshot-computation snapshot)))

;; calculus-snapshot-graph-value : calculus-snapshot? semantic-value? finite-real?
;;                                  -> calculus-result?
;;   Native preparation uses this graph-aware bridge so an explicit graph
;; restriction remains a mathematical undefined gap rather than a sampled path
;; that happens to extend beyond its declared domain.
(define (calculus-snapshot-graph-value snapshot graph input)
  (check 'calculus-snapshot-graph-value calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-graph-value finite-real? "finite real input" input)
  (evaluate-graph graph input
                  (calculus-snapshot-values snapshot)
                  (calculus-snapshot-model snapshot)
                  (calculus-snapshot-computation snapshot)))

;; calculus-snapshot-trace-points : calculus-snapshot? c-node? [#:samples exact-positive-integer?]
;;                                  -> (listof (or/c point? #f))
;;   Evaluates a locus at deterministic authored sweep coordinates for the
;;   native adapter.  The sweep parameter shadows only its sampled coordinate;
;;   every other parameter comes from the immutable snapshot.  #f records a
;;   mathematical gap, never a pixel-derived discontinuity.  An active trace
;;   uses its stored sweep prefix; a statically shown locus uses its full span.
(define (calculus-snapshot-trace-points snapshot locus #:samples [samples 160])
  (check 'calculus-snapshot-trace-points calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-trace-points c-node? "trace-of locus node" locus)
  (check 'calculus-snapshot-trace-points exact-positive-integer? "exact positive sample count" samples)
  (define raw (c-node-data locus))
  (define model (calculus-snapshot-model snapshot))
  (define values (calculus-snapshot-values snapshot))
  (define computation (calculus-snapshot-computation snapshot))
  (cond
    [(not (and (c-object? raw) (eq? (c-object-kind raw) 'trace-of))) '()]
    [else
     (define parameter (hash-ref (c-object-options raw) 'parameter #f))
     (define over (hash-ref (c-object-options raw) 'over #f))
     (define source (and (pair? (c-object-arguments raw)) (first (c-object-arguments raw))))
     (define parameter-id (and (c-node? parameter) (c-node-id parameter)))
     (define bounds
       (and parameter-id
            (c-domain? over)
            (= (length (c-domain-arguments over)) 2)
            (let ([left (eval-raw (first (c-domain-arguments over)) values model computation)]
                  [right (eval-raw (second (c-domain-arguments over)) values model computation)])
              (and (eq? (calculus-result-status left) 'defined)
                   (eq? (calculus-result-status right) 'defined)
                   (finite-real? (calculus-result-value left))
                   (finite-real? (calculus-result-value right))
                   (< (calculus-result-value left) (calculus-result-value right))
                   (cons (calculus-result-value left) (calculus-result-value right))))))
     (cond
       [(not bounds) '()]
       [else
        (define left (car bounds))
        (define right (cdr bounds))
        (define stored-prefix
          (hash-ref (calculus-snapshot-visible snapshot) (trace-prefix-key locus) #f))
        (define prefix
          (if (finite-real? stored-prefix)
              (min right (max left stored-prefix))
              right))
        (for/list ([index (in-range (add1 samples))])
          (define sweep-value (+ left (* (/ index samples) (- right left))))
          (cond
            [(> sweep-value prefix) #f]
            [else
             (define environment (hash-set values parameter-id sweep-value))
             (define inside? (domain-contains? over sweep-value environment model computation))
             (define result
               (and (eq? (calculus-result-status inside?) 'defined)
                    (calculus-result-value inside?)
                    (eval-raw source environment model computation)))
             (and result
                  (eq? (calculus-result-status result) 'defined)
                  (let ([point (calculus-result-value result)])
                    (and (pair? point)
                         (finite-real? (car point))
                         (finite-real? (cdr point))
                         point)))]))])]))

;; calculus-snapshot-view-window : calculus-snapshot? c-view? -> (or/c (list/c finite-real? finite-real? finite-real? finite-real?) #f)
;;   Returns the active graph-view camera window for the native adapter. #f
;;   means the prepared declared window is active; camera state never changes
;;   a model value, graph domain, or point coordinate.
(define (calculus-snapshot-view-window snapshot view)
  (check 'calculus-snapshot-view-window calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-view-window c-view? "graph view" view)
  (define window (hash-ref (calculus-snapshot-visible snapshot) (view-window-key view) #f))
  (and (finite-view-window? window) window))

;; calculus-snapshot-view-window-state : calculus-snapshot? c-view? -> any/c
;;   Private renderer bridge for a camera transition whose initial y window
;; comes from preparation-time auto fitting.  Public inspection keeps using
;; calculus-snapshot-view-window, which exposes only realized finite windows.
(define (calculus-snapshot-view-window-state snapshot view)
  (check 'calculus-snapshot-view-window-state calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-view-window-state c-view? "graph view" view)
  (hash-ref (calculus-snapshot-visible snapshot) (view-window-key view) #f))

;; calculus-snapshot-function-branch : calculus-snapshot? any/c finite-real? -> calculus-result?
;;   Identifies a selected piecewise source branch without inferring topology
;;   from pixels. Non-piecewise functions use the stable branch symbol 'sole.
(define (calculus-snapshot-function-branch snapshot function input)
  (check 'calculus-snapshot-function-branch calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-function-branch finite-real? "finite real input" input)
  (define model (calculus-snapshot-model snapshot))
  (define values (calculus-snapshot-values snapshot))
  (define computation (calculus-snapshot-computation snapshot))
  (define source (lookup-function function))
  (cond
    [(not source) (undefined "expected a calculus function")]
    [(not (c-piecewise? source)) (defined 'sole)]
    [else
     (result-bind
      (domain-contains? (c-piecewise-domain source) input values model computation)
      (lambda (inside?)
        (if (not inside?)
            (outside "input is outside the declared function domain")
            (let loop ([branches (c-piecewise-branches source)] [index 0])
              (cond
                [(null? branches)
                 (if (c-piecewise-else source) (defined 'else)
                     (undefined "no piecewise branch applies"))]
                [else
                 (result-bind
                  (eval-raw (caar branches) values model computation
                            (hash (c-piecewise-variable source) (defined input)))
                  (lambda (matches?)
                    (if matches? (defined index) (loop (cdr branches) (add1 index)))))])))))]))

;; calculus-snapshot-function-branch-value : calculus-snapshot? any/c (or/c exact-nonnegative-integer? 'else 'sole) finite-real? -> calculus-result?
;;   Evaluates one named piecewise source branch at an authored boundary without
;;   allowing native sampling to infer a missing endpoint from nearby pixels.
(define (calculus-snapshot-function-branch-value snapshot function branch input)
  (check 'calculus-snapshot-function-branch-value calculus-snapshot? "calculus-snapshot?" snapshot)
  (check 'calculus-snapshot-function-branch-value finite-real? "finite real input" input)
  (define model (calculus-snapshot-model snapshot))
  (define values (calculus-snapshot-values snapshot))
  (define computation (calculus-snapshot-computation snapshot))
  (define source (lookup-function function))
  (cond
    [(not source) (undefined "expected a calculus function")]
    [(not (c-piecewise? source))
     (if (eq? branch 'sole)
         (evaluate-function function input values model computation)
         (undefined "function has no named piecewise branch"))]
    [else
     (result-bind
      (domain-contains? (c-piecewise-domain source) input values model computation)
      (lambda (inside?)
        (if (not inside?)
            (outside "input is outside the declared function domain")
            (let ([lexical (hash (c-piecewise-variable source) (defined input))])
              (cond
                [(and (exact-nonnegative-integer? branch)
                      (< branch (length (c-piecewise-branches source))) )
                 (eval-raw (cdr (list-ref (c-piecewise-branches source) branch))
                           values model computation lexical)]
                [(and (eq? branch 'else) (c-piecewise-else source))
                 (eval-raw (c-piecewise-else source) values model computation lexical)]
                [else (undefined "unknown piecewise branch")])))))]))

;; calculus-snapshot-function-breaks : calculus-snapshot? semantic-value?
;;                                      -> calculus-result?
;;   Resolves only an opaque provider's declared finite discontinuity inputs.
;; They are topology evidence for the native adapter, not inferred values or a
;; substitute for the provider's actual mathematical definedness.
(define (calculus-snapshot-function-breaks snapshot function)
  (check 'calculus-snapshot-function-breaks calculus-snapshot? "calculus-snapshot?" snapshot)
  (define source (lookup-function function))
  (cond
    [(not source) (undefined "expected a calculus function")]
    [(not (and (c-object? source) (eq? (c-object-kind source) 'procedure-function)))
     (defined '())]
    [else
     (define breaks (hash-ref (c-object-options source) 'breaks #f))
     (if (not breaks)
         (defined '())
         (result-bind
          (eval-raw breaks
                    (calculus-snapshot-values snapshot)
                    (calculus-snapshot-model snapshot)
                    (calculus-snapshot-computation snapshot))
          (lambda (values)
            (if (and (list? values) (andmap finite-real? values))
                (defined (immutable-list-copy (sort (remove-duplicates values) <)))
                (undefined "procedure-function #:breaks must evaluate to finite real inputs")))))]))

;; snapshot-view-names : hash? list? -> list?
;;   Recovers declared presentation memberships carried in the immutable
;; snapshot, so public inspection does not need a renderer or live lesson.
(define (snapshot-view-names visible key)
  (sort
   (remove-duplicates
    (for/list ([(candidate value) (in-hash visible)]
               #:when (and (list? candidate)
                           (= (length candidate) 3)
                           (eq? (first candidate) 'calculus-view-membership)
                           (equal? (third candidate) key)))
      (second candidate)))
   symbol<?))

;; effective-global-visibility : hash? list? -> boolean?
;;   A direct child preference overrides its root/container preference; absent
;; preferences remain hidden. This prevents a global component show from
;; resurrecting an explicitly hidden public part.
(define (effective-global-visibility visible key)
  (define direct (hash-ref visible key missing-presentation-value))
  (cond [(not (eq? direct missing-presentation-value)) direct]
        [else
         (define root (target-root-key key))
         (define inherited (and root (hash-ref visible root missing-presentation-value)))
         (and (not (eq? inherited missing-presentation-value)) inherited)]))

;; effective-view-visibility : hash? symbol? list? -> boolean?
;;   Combines immutable membership, a view-container mask, a qualified child
;; preference, and the shared object's global preference in that order.
(define (effective-view-visibility visible view key)
  (define member? (hash-ref visible (view-membership-key view key) #f))
  (define container (hash-ref visible (view-container-key view) #t))
  (define local (hash-ref visible (view-target-key view key) missing-presentation-value))
  (and member? container
       (if (eq? local missing-presentation-value)
           (effective-global-visibility visible key)
           local)))

;; calculus-snapshot-visible? : calculus-snapshot? address? keyword-options -> boolean?
;;   Reports effective global or one named-view visibility independently of
;; mathematical value. View membership and masks are semantic snapshot data.
(define (calculus-snapshot-visible? snapshot address #:view [view #f])
  (check 'calculus-snapshot-visible? calculus-snapshot? "calculus-snapshot?" snapshot)
  (when view (check 'calculus-snapshot-visible? symbol? "view symbol" view))
  (define key (target-key (address->object (calculus-snapshot-model snapshot) address)))
  (define visible (calculus-snapshot-visible snapshot))
  (define views (snapshot-view-names visible key))
  (cond [view
         (unless (member view views)
           (raise-arguments-error 'calculus-snapshot-visible?
                                  "a view that explicitly presents the address"
                                  "view" view "address" address))
         (effective-view-visibility visible view key)]
        [else
         (for/or ([name (in-list views)])
           (effective-view-visibility visible name key))]))

;; semantic-datum : any/c -> immutable-datum?
;;   Converts supported semantic values to compact inspection data.
(define (semantic-datum value)
  (cond [(and (pair? value) (finite-real? (car value)) (finite-real? (cdr value)))
         (hash 'kind 'point 'x (car value) 'y (cdr value))]
        [(list? value) (map semantic-datum value)]
        [(c-node? value) (hash 'kind (c-node-kind value) 'id (c-node-id value))]
        [(c-object? value) (hash 'kind (c-object-kind value))]
        [(c-part? value) (hash 'kind 'part 'name (c-part-name value))]
        [else value]))
;; calculus-result->datum : calculus-result? -> immutable-hash?
;;   Exposes versioned, renderer-free inspection data for one result.
(define (calculus-result->datum result)
  (check 'calculus-result->datum calculus-result? "calculus-result?" result)
  (hash 'version 1 'status (calculus-result-status result) 'method (calculus-result-method result)
        'approximate? (calculus-result-approximate? result) 'value (and (eq? (calculus-result-status result) 'defined) (semantic-datum (calculus-result-value result)))
        'message (calculus-result-message result)))
