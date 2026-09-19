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
 ;; Profiles and numerical policy.
 calculus-profile calculus-profile? calculus-theme calculus-theme? calculus-style calculus-style?
 calculus-layout calculus-layout? calculus-motion calculus-motion? calculus-timing calculus-timing?
 calculus-computation calculus-computation? calculus-px calculus-rel calculus-em calculus-length?
 classroom-light-profile classroom-dark-profile textbook-profile default-calculus-profile
 light-calculus-theme dark-calculus-theme default-calculus-computation
 ;; The declaration macros use these private implementation bindings.
 make-model bind-model-value make-lesson make-component make-held-function
 make-piecewise-function make-generic calculus-real-line
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
 calculus-snapshot-function-value calculus-snapshot-function-branch calculus-snapshot-function-branch-value
 calculus-plan-lesson calculus-plan-events c-event-start c-event-end
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
;;  - inputs        immutable declared typed input syntax data
;;  - bindings      immutable internal model syntax data
;;  - exports       immutable public export-name list
;;  - constraints   immutable component constraint data
;;  - exposition    immutable optional step data
;; calculus-lesson joins one model to views, presentation, and exposition.
(struct calculus-lesson (model views roles initial timing steps) #:transparent)
;;  - model         immutable calculus-model
;;  - views         immutable stable-name to c-view map
;;  - roles         immutable ordered presentation role assignments
;;  - initial       immutable persistent initial c-action list
;;  - timing        optional calculus-timing override
;;  - steps         immutable ordered c-step list
;; c-event is a lowered leaf action with exact temporal placement.
(struct c-event (ordinal start end action) #:transparent)
;;  - ordinal       stable same-time ordering index
;;  - start         exact or finite action start time
;;  - end           exact or finite action end time
;;  - action        source c-action descriptor
;; calculus-moment identifies a semantic phase independent of numeric ties.
(struct calculus-moment (kind address) #:transparent)
;;  - kind          'step-start, 'step-end, or 'checkpoint
;;  - address       stable public step/checkpoint path
;; calculus-plan is a compiled headless lesson with no native objects.
(struct calculus-plan (lesson profile values computation events duration diagnostics moments) #:transparent)
;;  - lesson        source immutable calculus-lesson
;;  - profile       selected immutable presentation profile
;;  - values        immutable initial parameter-value map
;;  - computation   selected immutable numerical policy
;;  - events        immutable ordered c-event list
;;  - duration      total nonnegative lesson duration
;;  - diagnostics   immutable compilation diagnostics
;;  - moments       immutable phase/address to time-and-order map
;; calculus-snapshot is one immutable inspectable semantic state.
(struct calculus-snapshot (model values visible diagnostics computation) #:transparent)
;;  - model         snapshot's immutable calculus-model
;;  - values        immutable current parameter-value map
;;  - visible       immutable presentation target visibility map
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
;; result-bind : calculus-result? procedure? -> calculus-result?
;;   Sequences only defined mathematical outcomes.
(define (result-bind result proc)
  (if (eq? (calculus-result-status result) 'defined)
      (proc (calculus-result-value result))
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

;; calculus-style : keyword-options -> calculus-style?
;;   Constructs a pure selector-based presentation rule.
(define (calculus-style #:kind [kind #f] #:role [role #f] #:state [state #f]
                       #:target [target #f] #:view [view #f]
                       #:stroke [stroke 'inherit] #:fill [fill 'inherit]
                       #:stroke-width [stroke-width 'inherit] #:dash [dash 'inherit]
                       #:opacity [opacity 'inherit] #:marker-radius [marker-radius 'inherit]
                       #:font-size [font-size 'inherit] #:label-gap [label-gap 'inherit])
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
  (when font-size (check 'calculus-theme calculus-length? "calculus-length?" font-size))
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
    [(closed open closed-open open-closed singleton domain-union domain-intersection domain-except integers)
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
    [(or (c-object? raw) (c-part? raw)) (c-node name (semantic-kind raw) raw (hash))]
    [else (raise-arguments-error 'model "unsupported immutable mathematical value" "binding" name "value" raw)]))

;; make-model : list? list? -> calculus-model?
;;   Builds an immutable unique-name mathematical dependency model.
(define (make-model bindings [constraints '()])
  (define names (map car bindings))
  (unless (= (length names) (length (remove-duplicates names)))
    (raise-arguments-error 'model "duplicate model binding" "names" names))
  (define nodes (make-immutable-hash bindings))
  (calculus-model nodes (immutable-list-copy constraints)))

;; make-lesson : calculus-model? list? list? list? any/c list? -> calculus-lesson?
;;   Joins a mathematical model to abstract views and exposition data.
(define (make-lesson model views roles initial timing steps)
  (check 'define-calculus-lesson calculus-model? "calculus-model?" model)
  (unless (pair? views) (raise-arguments-error 'define-calculus-lesson "requires at least one view" "views" views))
  (calculus-lesson model (make-immutable-hash views) roles initial timing (immutable-list-copy steps)))

;; make-component : symbol? list? list? list? list? list? -> calculus-component?
;;   Records a pure reusable calculus component descriptor.
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
        [(and (c-object? raw) (memq (c-object-kind raw) '(restrict-function compose-functions difference-function derivative-function antiderivative-function accumulation-function linearization approximation-error procedure-function))) raw]
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
  (cond [(c-function? function) (c-function-domain function)]
        [(c-piecewise? function) (c-piecewise-domain function)]
        [(and (c-object? function) (eq? (c-object-kind function) 'restrict-function))
         (c-domain 'domain-intersection
                   (list (function-domain (first (c-object-arguments function)))
                         (second (c-object-arguments function))))]
        [(and (c-object? function) (hash-has-key? (c-object-options function) 'domain)) (hash-ref (c-object-options function) 'domain)]
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
     (result-bind (eval-raw base environment model computation lexical)
                  (lambda (a)
                    (result-bind (evaluate-function function a environment model computation lexical)
                                 (lambda (fa)
                                   (result-bind (evaluate-function derivative a environment model computation lexical)
                                                (lambda (slope) (finite-number-result (+ fa (* slope (- input a))) 'definition #f)))))))]
    [(approximation-error)
     (result-bind (evaluate-function (first args) input environment model computation lexical)
                  (lambda (left) (result-bind (evaluate-function (second args) input environment model computation lexical)
                                               (lambda (right) (finite-number-result (- left right) 'definition #f)))))]
    [else (unresolved (format "unsupported function operation ~a" (c-object-kind source)))]))

;; differentiate : any/c symbol? -> (or/c c-expression? finite-real? #f)
;;   Builds the documented conservative symbolic derivative for a held expression.
(define (differentiate expression variable)
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
       [(+) (apply expression* '+ (map (lambda (item) (differentiate item variable)) arguments))]
       [(-) (apply expression* '- (map (lambda (item) (differentiate item variable)) arguments))]
       [(*)
        (if (null? arguments)
            0
            (apply expression* '+
                   (for/list ([index (in-range (length arguments))])
                     (apply expression* '*
                            (for/list ([item (in-list arguments)] [position (in-naturals)])
                              (if (= index position) (differentiate item variable) item))))))]
       [(expt)
        (if (and (= (length arguments) 2) (exact-nonnegative-integer? (second arguments)))
            (expression* '* (second arguments)
                         (expression* 'expt (first arguments) (sub1 (second arguments)))
                         (differentiate (first arguments) variable))
            #f)]
       [(sin) (expression* '* (expression* 'cos (first arguments)) (differentiate (first arguments) variable))]
       [(cos) (expression* '* -1 (expression* 'sin (first arguments)) (differentiate (first arguments) variable))]
       [(exp) (expression* '* (expression* 'exp (first arguments)) (differentiate (first arguments) variable))]
       [(log) (expression* '/ (differentiate (first arguments) variable) (first arguments))]
       [(sqrt) (expression* '/ (differentiate (first arguments) variable)
                             (expression* '* 2 (expression* 'sqrt (first arguments))))]
       [else #f])]
    [else 0]))

(define (eval-derivative descriptor input environment model computation lexical)
  (define source (first (c-object-arguments descriptor)))
  (define options (c-object-options descriptor))
  (define method (hash-ref options 'method 'symbolic))
  (case method
    [(supplied) (evaluate-function (hash-ref options 'using) input environment model computation lexical)]
    [(numeric)
     (define h (hash-ref options 'step (calculus-computation-data-derivative-step computation)))
     (result-bind (evaluate-function source (+ input h) environment model computation lexical)
                  (lambda (right)
                    (result-bind (evaluate-function source (- input h) environment model computation lexical)
                                 (lambda (left) (finite-number-result (/ (- right left) (* 2 h)) 'numeric #t)))))]
    [else
     (define source-function (lookup-function source))
     (if (and (c-function? source-function) (c-expression? (c-function-body source-function)))
         (let ([derived (differentiate (c-function-body source-function) (c-function-variable source-function))])
           (if derived
               (eval-raw derived environment model computation (hash-set lexical (c-function-variable source-function) (defined input)))
               (unresolved "symbolic differentiation is unsupported for this expression" 'symbolic)))
         (unresolved "symbolic differentiation requires a held function" 'symbolic))]))

(define (graph-function graph)
  (define source (node-raw graph))
  (and (c-object? source) (memq (c-object-kind source) '(graph graph-restriction))
       (first (c-object-arguments source))))

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
        (define function (graph-function graph))
        (result-bind (eval-raw (hash-ref options 'x) environment model computation lexical)
                     (lambda (x) (result-bind (evaluate-function function x environment model computation lexical)
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
                     (lambda (v) (result-bind (evaluate-function (graph-function graph) v environment model computation lexical)
                                               (lambda (y) (if (scalar-equivalent? y 0 computation)
                                                               (defined (cons v y))
                                                               (unresolved "candidate is not a root"))))))]
       [(intersection-point)
        (define x (hash-ref options 'x))
        (result-bind (eval-raw x environment model computation lexical)
                     (lambda (v)
                       (result-bind (evaluate-function (graph-function (first args)) v environment model computation lexical)
                                    (lambda (left)
                                      (result-bind (evaluate-function (graph-function (second args)) v environment model computation lexical)
                                                   (lambda (right)
                                                     (if (scalar-equivalent? left right computation)
                                                         (defined (cons v left))
                                                         (unresolved "candidate is not an intersection"))))))))]
       [(point-on-line)
        (result-bind (eval-line (first args) environment model computation lexical)
                     (lambda (line) (if (eq? (car line) 'vertical) (undefined "x does not select a point on a vertical line")
                                        (result-bind (eval-raw (hash-ref options 'x) environment model computation lexical)
                                                     (lambda (x) (defined (cons x (+ (third line) (* (second line) x)))))))))]
       [else (undefined (format "unsupported point kind ~a" (c-object-kind raw)))] )]))

(define (line-through-points p q kind)
  (if (equal? p q)
      (if (eq? kind 'segment)
          (defined (list 'segment p q))
          (undefined "coincident points do not determine a line"))
      (let ([dx (- (car q) (car p))] [dy (- (cdr q) (cdr p))])
        (if (= dx 0) (defined (list 'vertical (car p) p))
            (defined (list 'line (/ dy dx) (- (cdr p) (* (/ dy dx) (car p))) p))))))

(define (eval-line line environment model computation lexical)
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
           (result-bind (eval-point (hash-ref options 'at) environment model computation lexical)
                        (lambda (p) (result-bind (evaluate-function (hash-ref options 'derivative) (car p) environment model computation lexical)
                                                 (lambda (m) (defined (list 'line m (- (cdr p) (* m (car p))) p))))))]
          [(vertical-tangent) (result-bind (eval-point (hash-ref options 'at) environment model computation lexical)
                                            (lambda (p) (defined (list 'vertical (car p) p))))]
          [(normal)
           (result-bind (eval-line (first args) environment model computation lexical)
                        (lambda (source)
                          (if (eq? (car source) 'vertical)
                              (defined (list 'line 0 (cdr (third source)) (third source)))
                              (if (= (second source) 0)
                                  (defined (list 'vertical (car (third source)) (third source)))
                                  (defined (list 'line
                                                 (/ -1 (second source))
                                                 (+ (cdr (third source))
                                                    (* (/ 1 (second source)) (car (third source))))
                                                 (third source)))))))]
          [else (undefined "expected a line")]))))

(define (eval-slope line environment model computation lexical)
  (result-bind (eval-line line environment model computation lexical)
               (lambda (value) (if (eq? (car value) 'vertical) (undefined "vertical line has no finite slope")
                                   (defined (second value))))))

(define (eval-part part environment model computation lexical)
  (define parent (node-raw (c-part-parent part)))
  (define name (c-part-name part))
  (cond
    [(and (list? name) (pair? name) (eq? (car name) 'branches))
     (c-part (c-part-parent part) name)]
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
                                  (lambda (x) (evaluate-function (graph-function graph) x environment model computation lexical)))]
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
       [(epsilon-delta-condition)
        (case name
          [(epsilon) (eval-raw (hash-ref (c-object-options parent) 'epsilon) environment model computation lexical)]
          [(delta) (eval-raw (hash-ref (c-object-options parent) 'delta) environment model computation lexical)]
          [else (defined (c-part parent name))])]
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

(define (simpson function a b environment model computation lexical)
  (define budget (calculus-computation-data-integration-budget computation))
  ;; Simpson's rule needs an even positive interval count and one more
  ;; integrand evaluation than intervals, all within the declared budget.
  (define n (min 2048 (* 2 (quotient (sub1 budget) 2))))
  (cond
    [(< n 2) (unresolved "numeric integration budget is too small" 'numeric)]
    [else
     (define h (/ (- b a) n))
     (let loop ([index 0] [total 0])
       (cond
         [(> index n) (finite-number-result (* (/ h 3) total) 'numeric #t)]
         [else
          (define weight (cond [(or (= index 0) (= index n)) 1]
                               [(odd? index) 4]
                               [else 2]))
          (result-bind
           (evaluate-function function (+ a (* index h)) environment model computation lexical)
           (lambda (sample)
             (loop (add1 index) (+ total (* weight sample)))))]))]))

(define (eval-integral function from to antiderivative environment model computation lexical)
  (result-bind
   (eval-raw from environment model computation lexical)
   (lambda (a)
     (result-bind
      (eval-raw to environment model computation lexical)
      (lambda (b)
        (cond
          [(= a b) (defined 0)]
          [antiderivative
           (result-bind
            (evaluate-function antiderivative b environment model computation lexical)
            (lambda (fb)
              (result-bind
               (evaluate-function antiderivative a environment model computation lexical)
               (lambda (fa) (finite-number-result (- fb fa) 'supplied #f)))))]
          [else (simpson function a b environment model computation lexical)]))))))

(define (eval-area region environment model computation lexical)
  (define raw (node-raw region))
  (if (and (c-object? raw) (memq (c-object-kind raw) '(region-under integral-region region-between)))
      (let ([graph (first (c-object-arguments raw))]
            [from (hash-ref (c-object-options raw) 'from)]
            [to (hash-ref (c-object-options raw) 'to)])
        (result-bind (eval-raw from environment model computation lexical)
                     (lambda (a) (result-bind (eval-raw to environment model computation lexical)
                                              (lambda (b)
                                                (simpson (make-held-function 'x (c-expression 'abs (list (c-expression 'value-at (list (graph-function graph) (c-expression 'var (list 'x))))))) a b environment model computation lexical))))))
      (undefined "expected a region")))

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

;; newton-derivative-compatible? : semantic-value? semantic-value? -> boolean?
;;   Requires Newton's declared derivative to retain the same function source.
(define (newton-derivative-compatible? function derivative)
  (define raw (node-raw derivative))
  (and (c-object? raw)
       (eq? (c-object-kind raw) 'derivative-function)
       (= (length (c-object-arguments raw)) 1)
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
                      (not (newton-derivative-compatible?
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
                        (evaluate-function (graph-function graph) x environment model computation lexical)
                        (lambda (y) (defined (cons x y))))))])]))

(define (eval-object object environment model computation lexical)
  (case (c-object-kind object)
    [(graph graph-restriction formula formula-of ref value point-label graph-label quantity-label value-readout
            interval-marker endpoint-marker approach-marker input-band output-band limit-statement epsilon-delta-condition
            continuity-condition asymptote-line region-under region-between integral-region riemann-rectangles trapezoidal-regions
            partition-marks
            trace-of formula-occurrence quantity-correspondence snapshot-of in-view output-reading slope-triangle)
     (defined object)]
    [(point point-on axis-point projection root-point intersection-point point-on-line) (eval-point object environment model computation lexical)]
    [(feature-point) (eval-feature-point object environment model computation lexical)]
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
  (calculus-snapshot model (initial-values model values) (hash) '() computation))

;; target-key : semantic-target? -> (or/c list? #f)
;;   Normalizes a public target to its stable presentation key.
(define (target-key target)
  (cond [(c-node? target) (list (c-node-id target))]
        [(c-part? target) (append (target-key (c-part-parent target)) (if (list? (c-part-name target)) (c-part-name target) (list (c-part-name target))))]
        [(and (c-object? target) (eq? (c-object-kind target) 'in-view)) (target-key (second (c-object-arguments target)))]
        [else #f]))
;; target-root-key : list? -> list?
;;   Selects a target's root key for inherited visibility.
(define (target-root-key key) (and key (list (first key))))

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

;; compile-command : c-action? real? real? exact-nonnegative-integer? -> values
;;   Lowers one command or parallel group to stable leaf events.
(define (compile-command command start fallback ordinal)
  (cond
    [(not (c-action? command)) (values '() 0 ordinal)]
    [(eq? (c-action-kind command) 'together)
     (define-values (events spans next)
       (for/fold ([all '()] [span 0] [next ordinal]) ([child (in-list (c-action-targets command))])
         (define-values (child-events child-span child-next) (compile-command child start fallback next))
         (values (append all child-events) (max span child-span) child-next)))
     (values events spans next)]
    [else
     (define span (duration-of command fallback))
     (values (list (c-event ordinal start (+ start span) command)) span (add1 ordinal))]))

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

;; parameter-values-before : c-event? list? hash? calculus-model? calculus-computation? -> immutable-hash?
;;   Reconstructs the start state for endpoint and side validation, including
;;   preceding zero-time assignments but never depending on rendered frames.
(define (parameter-values-before event events values model computation)
  (car
   (for/fold ([state (cons values (hash))]) ([prior (in-list events)]
                                             #:break (>= (c-event-ordinal prior)
                                                        (c-event-ordinal event)))
     (if (<= (c-event-end prior) (c-event-start event))
         (apply-event state prior (c-event-end prior) model computation)
         state))))

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
                [else
                 (define inside?
                   (domain-contains? (c-param-spec-domain (c-node-data parameter))
                                     target event-values model computation))
                 (cond
                   [(not (and (eq? (calculus-result-status inside?) 'defined)
                              (calculus-result-value inside?)))
                    (list (diagnostic 'parameter-domain
                                      "parameter action endpoint is outside its declared domain"))]
                   [(and (memq kind '(vary approach))
                         (domain-path-crosses-exclusion?
                          (c-param-spec-domain (c-node-data parameter))
                          (hash-ref event-values (c-node-id parameter)) target
                          event-values model computation))
                    (list (diagnostic 'parameter-path
                                      "continuous parameter action crosses an excluded domain value"))]
                   [(and (eq? kind 'approach)
                         (not (valid-approach-side?
                               action (hash-ref event-values (c-node-id parameter)) target
                               event-values model computation)))
                    (list (diagnostic 'approach-side
                                      "approach must start and stop on its authored side of #:to"))]
                   [else '()])])]))))

;; compile-calculus-lesson : calculus-lesson? keyword-options -> calculus-plan?
;;   Lowers a headless lesson into immutable events, moments, and diagnostics.
(define (compile-calculus-lesson lesson #:profile [profile default-calculus-profile] #:values [values (hash)]
                                 #:computation [computation default-calculus-computation])
  (check 'compile-calculus-lesson calculus-lesson? "calculus-lesson?" lesson)
  (check 'compile-calculus-lesson calculus-profile? "calculus-profile?" profile)
  (check 'compile-calculus-lesson calculus-computation? "calculus-computation?" computation)
  (define model (calculus-lesson-model lesson))
  (define initial (initial-values model values))
  (define timing (or (calculus-lesson-timing lesson) (calculus-profile-data-timing profile)))
  (define time (calculus-timing-data-opening-pause timing))
  (define ordinal 0)
  (define events '())
  (define moments (make-hash))
  (for ([step (in-list (calculus-lesson-steps lesson))])
    (hash-set! moments (cons 'step-start (list (c-step-id step))) (cons time ordinal))
    (set! time (+ time (or (c-step-read-delay step) (calculus-timing-data-read-delay timing))))
    (define fallback (or (c-step-duration step) (calculus-timing-data-action-duration timing)))
    (for ([command (in-list (c-step-commands step))])
      (cond [(and (c-action? command) (eq? (c-action-kind command) 'checkpoint))
             (hash-set! moments (cons 'checkpoint (list (first (c-action-targets command)))) (cons time ordinal))]
            [else (define-values (new-events span next) (compile-command command time fallback ordinal))
                  (set! events (append events new-events)) (set! time (+ time span)) (set! ordinal next)]))
    (hash-set! moments (cons 'step-end (list (c-step-id step))) (cons time ordinal))
    (set! time (+ time (or (c-step-pause step) (calculus-timing-data-step-pause timing)))))
  (define diagnostics
    (filter (lambda (diagnostic) diagnostic)
            (append (action-domain-diagnostics model initial computation events)
                    (refinement-diagnostics model initial computation events))))
  (calculus-plan lesson profile initial computation (immutable-list-copy events) time diagnostics
                 (make-immutable-hash (for/list ([(key value) (in-hash moments)]) (cons key value)))))

;; address->object : calculus-model? address? -> semantic-target?
;;   Resolves a public root/part address without consulting rendered geometry.
(define (address->object model address)
  (define pieces (if (symbol? address) (list address) address))
  (unless (and (list? pieces) (pair? pieces) (andmap symbol? pieces))
    (raise-argument-error 'calculus-snapshot-ref "symbol? or nonempty list of symbols" address))
  (define root (hash-ref (calculus-model-nodes model) (first pieces) #f))
  (unless root (raise-arguments-error 'calculus-snapshot-ref "known public mathematical address" "address" address))
  (for/fold ([value root]) ([part (in-list (rest pieces))]) (c-part value part)))

;; apply-event : pair? c-event? real? calculus-model? calculus-computation? -> pair?
;;   Computes one event's state at a requested time with no frame history.
(define (apply-event state event time model computation)
  (define action (c-event-action event))
  (define kind (c-action-kind action))
  (define start (c-event-start event)) (define end (c-event-end event))
  (if (< time start) state
      (let ([values (car state)] [visible (cdr state)])
        (define (set-visible targets on?)
          (for/fold ([current visible]) ([target (in-list targets)])
            (define key (target-key target))
            (if key (hash-set current key on?) current)))
        (case kind
          [(show show-label) (cons values (set-visible (c-action-targets action) #t))]
          [(hide hide-label) (cons values (set-visible (c-action-targets action) #f))]
          [(read) (cons values (set-visible (c-action-targets action) #t))]
          [(vary approach)
           (define parameter (first (c-action-targets action)))
           (define id (and (c-node? parameter) (c-node-id parameter)))
           (if (not id) state
               (let* ([initial (hash-ref values id)]
                      [target-expression (if (eq? kind 'approach) (hash-ref (c-action-options action) 'until)
                                             (hash-ref (c-action-options action) 'to))]
                      [target-result (eval-raw target-expression values model computation)])
                 (if (or (not (eq? (calculus-result-status target-result) 'defined))
                         (not (valid-continuous-parameter-target?
                               parameter initial (calculus-result-value target-result)
                               values model computation))
                         (and (eq? kind 'approach)
                              (not (valid-approach-side?
                                    action initial (calculus-result-value target-result)
                                    values model computation))))
                     state
                     (let ([target (calculus-result-value target-result)]
                           [progress (if (= start end) 1 (min 1 (max 0 (/ (- time start) (- end start)))))] )
                       (cons (hash-set values id (+ initial (* progress (- target initial)))) visible)))))]
          [(set-parameter)
           (define parameter (first (c-action-targets action)))
           (define value-result (eval-raw (second (c-action-targets action)) values model computation))
           (if (and (c-node? parameter) (eq? (calculus-result-status value-result) 'defined))
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
                 (cons (if (zero? completed)
                           values
                           (hash-set values (c-node-id parameter)
                                     (list-ref counts (sub1 completed))))
                       visible))
               state)]
          [(trace)
           (define progressed-values
             (for/fold ([current values]) ([target (in-list (c-action-targets action))])
               (define trace-object (node-raw target))
               (if (and (c-object? trace-object) (eq? (c-object-kind trace-object) 'trace-of))
                   (let* ([parameter (hash-ref (c-object-options trace-object) 'parameter #f)]
                          [over (hash-ref (c-object-options trace-object) 'over #f)]
                          [id (and (c-node? parameter) (c-node-id parameter))])
                     (if (and id (c-domain? over)
                              (memq (c-domain-kind over) '(closed open closed-open open-closed))
                              (= (length (c-domain-arguments over)) 2))
                         (let ([left-result (eval-raw (first (c-domain-arguments over)) current model computation)]
                               [right-result (eval-raw (second (c-domain-arguments over)) current model computation)])
                           (if (and (eq? (calculus-result-status left-result) 'defined)
                                    (eq? (calculus-result-status right-result) 'defined))
                               (let ([progress (if (= start end) 1 (min 1 (max 0 (/ (- time start) (- end start)))))])
                                 (hash-set current id (+ (calculus-result-value left-result)
                                                         (* progress (- (calculus-result-value right-result)
                                                                        (calculus-result-value left-result))))))
                               current))
                         current))
                   current)))
           (cons progressed-values (set-visible (c-action-targets action) #t))]
          [(explain) (cons values (set-visible (c-action-targets action) #t))]
          [else state]))))

;; initial-visibility : calculus-lesson? -> immutable-hash?
;;   Applies only persistent initial show commands to a fresh presentation map.
(define (initial-visibility lesson)
  (for/fold ([visible (hash)]) ([command (in-list (calculus-lesson-initial lesson))])
    (if (and (c-action? command) (memq (c-action-kind command) '(show show-label)))
        (for/fold ([current visible]) ([target (in-list (c-action-targets command))])
          (define key (target-key target)) (if key (hash-set current key #t) current))
        visible)))

;; resolve-moment : calculus-plan? calculus-moment? -> pair?
;;   Finds the stable time and same-time ordering for a named semantic phase.
(define (resolve-moment plan moment)
  (define entry (hash-ref (calculus-plan-moments plan) (cons (calculus-moment-kind moment) (calculus-moment-address moment)) #f))
  (unless entry (raise-arguments-error 'calculus-plan-sample "known step or checkpoint address" "address" (calculus-moment-address moment)))
  entry)

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
  (define state (cons (calculus-plan-values plan) (initial-visibility lesson)))
  (for ([event (in-list (calculus-plan-events plan))]
        #:when (and (<= (c-event-start event) time) (<= (c-event-ordinal event) cutoff)))
    (set! state (apply-event state event time model (calculus-plan-computation plan))))
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

;; calculus-snapshot-visible? : calculus-snapshot? address? keyword-options -> boolean?
;;   Reports effective persistent visibility independently of mathematical value.
(define (calculus-snapshot-visible? snapshot address #:view [view #f])
  (check 'calculus-snapshot-visible? calculus-snapshot? "calculus-snapshot?" snapshot)
  (define key (target-key (address->object (calculus-snapshot-model snapshot) address)))
  (and key (or (hash-ref (calculus-snapshot-visible snapshot) key #f)
               (hash-ref (calculus-snapshot-visible snapshot) (target-root-key key) #f))))

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
