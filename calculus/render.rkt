#lang racket/base

;;;
;;; Calculus Native Rendering Adapter
;;;

;; This module is intentionally the only calculus module that imports native
;; pict, Visual, and scene facilities.  The headless calculus module remains
;; usable in test runners and analysis tools with no drawing dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "main.rkt"
         "private/core.rkt"
         (prefix-in native: "../main.rkt")
         (prefix-in panel: "../private/prepared-pict-visual.rkt")
         (only-in "../private/camera.rkt" make-camera)
         (only-in "../private/formula-visual.rkt" latex-formula)
         (only-in "../private/latex-formula-pict-renderer.rkt"
                  default-latex-formula-pict-renderer)
         (only-in "../private/pict-renderer.rkt"
                  pict-renderer?
                  render-visual-with-pict-renderer)
         (only-in "../private/derived-visual.rkt"
                  derived-visual
                  derived-context-value-ref)
         (prefix-in pict: pict)
         (except-in racket/class make-generic)
         racket/list
         racket/math
         racket/string
         (prefix-in draw: racket/draw))

;; Exports
(provide
 (all-from-out "main.rkt")
 calculus-render-quality calculus-render-quality?
 prepare-calculus-lesson prepare-calculus-plan
 prepared-calculus-lesson? prepared-lesson-plan
 prepared-lesson->scene prepared-lesson->pict prepared-lesson->visual
 lesson->scene lesson->pict lesson->visual)

;; current-render-theme : (parameter/c (or/c calculus-theme? #f))
;;   Keeps the selected pure theme available while a delayed `pict:dc` callback
;; draws one frame. No semantic state or prepared asset is stored in it.
(define current-render-theme (make-parameter #f))

;; current-render-reference-size : (parameter/c (or/c real? #f))
;;   Holds the smaller prepared canvas dimension while one native frame draws.
;; Relative cosmetic units use this stable output reference, never an
;; individual panel or a zoomed mathematical window.
(define current-render-reference-size (make-parameter #f))

;; current-render-style-context : parameter?
;;   Carries only the immutable semantic context for one delayed native draw.
;; It lets low-level shape painters consult presentation policy without
;; retaining a previous frame or an ad-hoc rendered-object identity.
(define current-render-style-context (make-parameter #f))

;; current-render-presentation-state : (parameter/c (or/c symbol? #f))
;;   Lets preparation resolve a finite set of state-qualified cosmetic assets
;; without fabricating a different semantic snapshot. Ordinary native draws
;; leave it unset and obtain the state from the current snapshot.
(define current-render-presentation-state (make-parameter #f))

;; theme-color : symbol? string? -> string?
;;   Resolves the documented base foreground/background values. Panel tones are
;; intentionally derived from a dark background until theme rules supply a
;; more specific panel selector.
(define (inherited-theme-value theme accessor)
  (cond [(not theme) #f]
        [(accessor theme) => values]
        [else (inherited-theme-value (calculus-theme-data-base theme) accessor)]))

(define (theme-color field fallback)
  (define value
    (case field
      [(background)
       (inherited-theme-value (current-render-theme)
                              calculus-theme-data-background)]
      [(foreground)
       (inherited-theme-value (current-render-theme)
                              calculus-theme-data-foreground)]
      [else #f]))
  (if (and (string? value) (regexp-match? #px"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$" value))
      value
      fallback))

;; theme-font-size : real? -> real?
;;   Resolves the inherited base annotation size before a local em style is
;; applied. Base themes reject em sizes, so this cannot become circular.
(define (theme-font-size reference)
  (define effective-reference (or (current-render-reference-size) reference))
  (define value
    (inherited-theme-value (current-render-theme)
                           calculus-theme-data-font-size))
  (cond [(not (calculus-length? value)) 15]
        [(eq? (calculus-length-unit value) 'px) (calculus-length-value value)]
        [(eq? (calculus-length-unit value) 'rel)
         (* effective-reference (calculus-length-value value))]
        [else 15]))

;; theme-font : real? -> font%
;;   Keeps a configured family entirely in the native adapter. It is never
;; part of formula semantics or the headless prepared plan.
(define (theme-font size)
  (define face
    (inherited-theme-value (current-render-theme)
                           calculus-theme-data-font-family))
  (make-object draw:font% (max 1 (inexact->exact (round size)))
               (and (string? face) face) 'modern 'normal 'normal))

;; theme-panel-background : -> string?
;;   Chooses a readable neutral panel without assigning a mathematical role to
;; a color. The documented light default remains byte-for-byte unchanged.
(define (theme-panel-background)
  (if (equal? (theme-color 'background "#FFFFFF") "#FFFFFF")
      "#FAFAFA"
      "#242A35"))

;; style-theme-rules : calculus-theme? -> list?
;;   Flattens inherited rules base-first, so a derived theme's equal-specificity
;; rule wins exactly by later source order.
(define (style-theme-rules theme)
  (if (not theme)
      '()
      (append (style-theme-rules (calculus-theme-data-base theme))
              (calculus-theme-data-rules theme))))

;; style-kind-for : any/c any/c -> symbol?
;;   Maps concrete semantic nodes to the small documented selector vocabulary.
(define (style-kind-for target node)
  (define kind (and node (c-node-kind node)))
  (cond [(memq kind '(graph graph-restriction)) 'graph]
        [(memq kind '(point point-on axis-point projection root-point intersection-point)) 'point]
        [(memq kind '(segment chord error-segment)) 'segment]
        [(memq kind '(line-through ray-through horizontal-line vertical-line secant tangent vertical-tangent normal)) 'line]
        [(memq kind '(input-reading output-reading coordinate-reading)) 'guide]
        [(memq kind '(point-label graph-label quantity-label)) 'label]
        [(memq kind '(interval-marker endpoint-marker approach-marker partition-marks
                                        sign-chart solution-inputs level-set)) 'marker]
        [(memq kind '(integral-region region-under region-between trapezoidal-regions)) 'region]
        [(eq? kind 'riemann-rectangles) 'rectangle]
        [(eq? kind 'sequence-points) 'point]
        [(eq? kind 'value-readout) 'readout]
        [(memq kind '(formula formula-of)) 'formula]
        [else #f]))

;; style-role-for : calculus-lesson? any/c -> (or/c symbol? #f)
;;   Looks up authored roles by public address. A role remains presentational and
;; therefore cannot alter the target's mathematical evaluator.
(define (style-role-for lesson target)
  (define address (target-address target))
  (or (for/or ([assignment (in-list (calculus-lesson-roles lesson))])
        (and (equal? (target-address (car assignment)) address) (cdr assignment)))
      'primary))

;; style-specificity : calculus-style? -> exact-nonnegative-integer?
;;   Encodes the Reference's lexicographic selector priority: view, target,
;; state, role, kind. Later source order resolves only an equal score.
(define (style-specificity rule)
  (+ (if (calculus-style-data-view rule) 16 0)
     (if (calculus-style-data-target rule) 8 0)
     (if (calculus-style-data-state rule) 4 0)
     (if (calculus-style-data-role rule) 2 0)
     (if (calculus-style-data-kind rule) 1 0)))

;; render-style-value : symbol? any/c -> any/c
;;   Resolves one cosmetic property independently, avoiding a style rule for
;; e.g. opacity from erasing a more-specific marker-radius rule. It is called
;; only from the native adapter and never feeds presentation data back into the
;; headless plan.
(define (render-style-value property fallback)
  (define context (current-render-style-context))
  (cond [(not context) fallback]
        [else
         (define lesson (list-ref context 0))
         (define snapshot (list-ref context 1))
         (define view (list-ref context 2))
         (define target (list-ref context 3))
         (define node (list-ref context 4))
         (define address (target-address target))
         (define kind
           (if (and (>= (length context) 6) (symbol? (list-ref context 5)))
               (list-ref context 5)
               (style-kind-for target node)))
         (define role (style-role-for lesson target))
         (define state
           (or (current-render-presentation-state)
               (calculus-snapshot-presentation-state snapshot target
                                                    #:view (and (c-view? view)
                                                                (c-view-name view)))))
         (define accessor
           (case property
             [(stroke) calculus-style-data-stroke]
             [(fill) calculus-style-data-fill]
             [(stroke-width) calculus-style-data-stroke-width]
             [(dash) calculus-style-data-dash]
             [(opacity) calculus-style-data-opacity]
             [(marker-radius) calculus-style-data-marker-radius]
             [(font-size) calculus-style-data-font-size]
             [(label-gap) calculus-style-data-label-gap]
             [else (lambda (_) 'inherit)]))
         (define winner
           (for/fold ([best #f]) ([rule (in-list (style-theme-rules (current-render-theme)))])
             (define matches?
               (and (or (not (calculus-style-data-view rule))
                        (eq? (calculus-style-data-view rule) (c-view-name view)))
                    (or (not (calculus-style-data-target rule))
                        (equal? (calculus-style-data-target rule) address))
                    (or (not (calculus-style-data-state rule))
                        (eq? (calculus-style-data-state rule) state))
                    (or (not (calculus-style-data-role rule))
                        (eq? (calculus-style-data-role rule) role))
                    (or (not (calculus-style-data-kind rule))
                        (eq? (calculus-style-data-kind rule) kind))))
             (cond [(not matches?) best]
                   [(eq? (accessor rule) 'inherit) best]
                   [(or (not best)
                        (>= (style-specificity rule) (style-specificity best))) rule]
                   [else best])))
         (if winner (accessor winner) fallback)]))

;; render-style-length : symbol? real? real? -> real?
;;   Resolves a cosmetic style dimension in the current prepared output. It
;; centralizes unit conversion so marker and line widths never vary with a
;; mathematical camera window.
(define (render-style-length property fallback reference)
  (define value (render-style-value property fallback))
  (if (calculus-length? value)
      (layout-length->pixels value reference)
      value))

;; motion-progress : any/c symbol? -> (or/c real? #f)
;; Extracts the normalized progress recorded by the headless sampler.  Native
;; paint never advances this state itself, so sparse, reverse, and process
;; frame requests all receive the identical choreography sample.
(define (motion-progress record family)
  (and (list? record)
       (pair? record)
       (eq? (first record) family)
       (let ([value
              (case family
                ;; Limit records retain source/target geometry after progress
                ;; so a rotate-carrier can be derived without reevaluation.
                [(limit) (and (>= (length record) 4) (list-ref record 3))]
                [(refinement) (and (>= (length record) 3) (list-ref record 2))]
                [else (and (pair? (rest record)) (last record))])])
         (and (real? value) (max 0 (min 1 value))))))

;; motion-opacity : any/c -> real?
;; Turns only transient presentation records into alpha.  The mathematical
;; source, visibility endpoint, and style opacity remain separate.
(define (motion-opacity record)
  (cond
    [(and (list? record) (= (length record) 3) (eq? (first record) 'fade))
     (or (motion-progress record 'fade) 1)]
    [(and (list? record) (= (length record) 3)
          (memq (first record) '(graph line))
          (eq? (second record) 'fade))
     ;; Graph and line reveal records keep their kind for the matching extent
     ;; painter, but fade uses the same alpha semantics as a generic reveal.
     (or (motion-progress record (first record)) 1)]
    [(and (list? record) (>= (length record) 4) (eq? (first record) 'limit))
     (define policy (second record))
     (define role (third record))
     (define progress (or (motion-progress record 'limit) 1))
     (cond [(eq? policy 'rotate-carrier)
            (case role [(source) 1] [(target) 0] [else 1])]
           [else
            (case role [(source) (- 1 progress)] [(target) progress] [else 1])])]
    [(and (list? record) (= (length record) 3) (eq? (first record) 'highlight))
     ;; A pulse is bounded and visual only. At its endpoints the ordinary
     ;; highlight outline remains available; reduced motion omits this record.
     (+ 1/2 (* 1/2 (sin (* pi (or (motion-progress record 'highlight) 1)))))]
    [else 1]))


;;;
;;; Immutable Prepared Records
;;;

;; calculus-render-quality-data captures only native curve-sampling policy.
(struct calculus-render-quality-data (curve-tolerance max-depth) #:transparent)
;;  - curve-tolerance  positive-real?  maximum native chord deviation in pixels
;;  - max-depth        exact-positive-integer?  bounded native subdivision depth

;; prepared-formula-row-data is a native-only, immutable Formula asset.
;; Text remains available for semantic diagnostics while the Picts are produced
;; through the configured existing formula renderer, once per static source and
;; documented presentation state.
(struct prepared-formula-row-data (text tex fonts picts) #:transparent)

;; prepared-dynamic-formula-row-data records source-order fragments and a
;; reservation established from the authored parameter-path samples. It
;; deliberately contains no whole-row backend Pict: live values are painted
;; through fixed native slots at actual sample time.
(struct prepared-dynamic-formula-row-data (shape field-reserve skeleton-picts) #:transparent)

;; prepared-calculus-lesson-data owns one semantic plan and one pixel layout.
(struct prepared-calculus-lesson-data
  (plan width height formula-backend quality auto-windows static-graph-geometries
        static-formula-assets dynamic-formula-layouts)
  #:transparent)
;;  - plan             calculus-plan?  immutable headless plan prepared for output
;;  - width            exact-positive-integer?  target output width in pixels
;;  - height           exact-positive-integer?  target output height in pixels
;;  - formula-backend  pict renderer selected for prepared mathematical notation
;;  - quality          calculus-render-quality-data?  curve preparation policy
;;  - auto-windows     immutable hash from graph-view names to frozen fitted
;;                     `(xmin xmax ymin ymax)` windows, never frame history
;;  - static-graph-geometries immutable sampled graph paths whose transitive
;;                     parameter dependency set is empty; keys include the
;;                     prepared world window but never frame request order
;;  - static-formula-assets immutable held Formula text, TeX source, and
;;                     pre-rendered picts with no live `value` leaves, keyed by
;;                     presentation view and target address
;;  - dynamic-formula-layouts prepared source-order native text/field slots
;;                     for live values; fields reserve width without invoking
;;                     a formula backend during later frame drawing

;; calculus-render-quality? : any/c -> boolean?
;;   Recognizes a validated native curve-sampling policy.
(define calculus-render-quality? calculus-render-quality-data?)

;; prepared-calculus-lesson? : any/c -> boolean?
;;   Recognizes a lesson with resolved output dimensions and semantic plan.
(define prepared-calculus-lesson? prepared-calculus-lesson-data?)

;; positive-real-value? : any/c -> boolean?
;;   Accepts finite real values appropriate for native configuration.
(define (positive-real-value? value)
  (and (real? value) (rational? value) (positive? value)))

;; calculus-render-quality : [#:curve-tolerance positive-real?]
;;                            [#:max-depth exact-positive-integer?]
;;                         -> calculus-render-quality?
;;   Builds a bounded rendering policy without changing mathematical accuracy.
(define (calculus-render-quality #:curve-tolerance [curve-tolerance 1/2]
                                 #:max-depth [max-depth 18])
  (unless (positive-real-value? curve-tolerance)
    (raise-argument-error 'calculus-render-quality "positive finite real curve tolerance" curve-tolerance))
  (unless (exact-positive-integer? max-depth)
    (raise-argument-error 'calculus-render-quality "exact-positive-integer? maximum depth" max-depth))
  (calculus-render-quality-data curve-tolerance max-depth))

;; check-dimensions : symbol? any/c any/c -> void?
;;   Rejects dimensions that cannot name one unambiguous pixel target.
(define (check-dimensions who width height)
  (unless (exact-positive-integer? width)
    (raise-argument-error who "exact-positive-integer? width" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error who "exact-positive-integer? height" height)))

;; raise-plan-errors! : symbol? calculus-plan? -> void?
;;   Enforces the strict native boundary before preparation can turn an already
;;   rejected performed action into an apparently usable picture.
(define (raise-plan-errors! who plan)
  (define errors
    (filter (lambda (diagnostic)
              (eq? (calculus-diagnostic-severity diagnostic) 'error))
            (calculus-plan-diagnostics plan)))
  (when (pair? errors)
    (define first-error (first errors))
    (raise-arguments-error
     who "a calculus plan without error diagnostics"
     "code" (calculus-diagnostic-code first-error)
     "address" (calculus-diagnostic-address first-error)
     "message" (calculus-diagnostic-message first-error))))

;; prepare-calculus-lesson : calculus-lesson? ... -> prepared-calculus-lesson?
;;   Compiles one lesson and binds its native layout to the supplied dimensions.
(define (prepare-calculus-lesson lesson
                                 #:profile [profile default-calculus-profile]
                                 #:values [values (hash)]
                                 #:computation [computation default-calculus-computation]
                                 #:width [width 1280]
                                 #:height [height 720]
                                 #:formula-backend [formula-backend 'default]
                                 #:quality [quality (calculus-render-quality)])
  (unless (calculus-lesson? lesson)
    (raise-argument-error 'prepare-calculus-lesson "calculus-lesson?" lesson))
  (check-dimensions 'prepare-calculus-lesson width height)
  (unless (calculus-render-quality? quality)
    (raise-argument-error 'prepare-calculus-lesson "calculus-render-quality?" quality))
  (prepare-calculus-plan
   (compile-calculus-lesson lesson #:profile profile #:values values #:computation computation)
   #:width width #:height height #:formula-backend formula-backend #:quality quality))

;; prepare-calculus-plan : calculus-plan? ... -> prepared-calculus-lesson?
;;   Resolves a native layout around an already compiled, headless plan.
(define (prepare-calculus-plan plan
                               #:width [width 1280]
                               #:height [height 720]
                               #:formula-backend [formula-backend 'default]
                               #:quality [quality (calculus-render-quality)])
  (unless (calculus-plan? plan)
    (raise-argument-error 'prepare-calculus-plan "calculus-plan?" plan))
  (check-dimensions 'prepare-calculus-plan width height)
  (unless (calculus-render-quality? quality)
    (raise-argument-error 'prepare-calculus-plan "calculus-render-quality?" quality))
  (raise-plan-errors! 'prepare-calculus-plan plan)
  ;; Validate the backend at the documented preparation boundary, before any
  ;; panel rasterization can hide an original backend diagnostic.
  (define formula-renderer
    (formula-backend->renderer 'prepare-calculus-plan formula-backend))
  (define auto-windows (prepare-auto-view-windows plan))
  (prepared-calculus-lesson-data
   plan width height formula-renderer quality auto-windows
   (prepare-static-graph-geometries plan auto-windows width height quality)
   (prepare-static-formula-assets plan width height formula-renderer)
   (prepare-dynamic-formula-layouts plan width height formula-renderer)))

;; prepared-lesson-plan : prepared-calculus-lesson? -> calculus-plan?
;;   Returns the exact headless plan that supplied the prepared composition.
(define (prepared-lesson-plan prepared)
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson-plan "prepared-calculus-lesson?" prepared))
  (prepared-calculus-lesson-data-plan prepared))


;;;
;;; Shared Pict Composition
;;;

;; target-address : any/c -> (or/c symbol? (non-empty-listof symbol?) #f)
;;   Converts semantic target records to their public inspection address.
(define (target-address target)
  (cond
    [(c-node? target) (c-node-id target)]
    [(c-part? target)
     (define parent (target-address (c-part-parent target)))
     (and parent
          (append (if (list? parent) parent (list parent))
                  (if (list? (c-part-name target))
                      (c-part-name target)
                      (list (c-part-name target)))))]
    [else #f]))

;; interval-bounds : any/c real? real? -> (values real? real?)
;;   Extracts ordinary authored view endpoints, with a stable fallback range.
(define (interval-bounds domain lower upper)
  (cond
    [(and (c-domain? domain)
          (memq (c-domain-kind domain) '(closed open closed-open open-closed))
          (= (length (c-domain-arguments domain)) 2)
          (andmap real? (c-domain-arguments domain)))
     (values (exact->inexact (first (c-domain-arguments domain)))
             (exact->inexact (second (c-domain-arguments domain))))]
    [else (values lower upper)]))

;; view-objects : c-view? -> list?
;;   Reads the documented object list from a prepared view descriptor.
(define (view-objects view)
  (define objects (hash-ref (c-view-options view) 'objects '()))
  (if (list? objects) objects '()))

;; formula-expression-has-live-value? : any/c -> boolean?
;;   Recognizes only Formula's explicit `(value ...)` leaves. A plain semantic
;; reference remains symbolic even when the referenced quantity changes, so it
;; can safely share one prepared notation row across frames.
(define (formula-expression-has-live-value? expression)
  (cond
    [(c-expression? expression)
     (for/or ([argument (in-list (c-expression-arguments expression))])
       (formula-expression-has-live-value? argument))]
    [(c-object? expression)
     (or (eq? (c-object-kind expression) 'value)
         (for/or ([argument (in-list (c-object-arguments expression))])
           (formula-expression-has-live-value? argument))
         (for/or ([option (in-hash-values (c-object-options expression))])
           (formula-expression-has-live-value? option)))]
    [(pair? expression)
     (or (formula-expression-has-live-value? (car expression))
         (formula-expression-has-live-value? (cdr expression)))]
    [else #f]))

;; static-formula-row? : any/c -> boolean?
;;   Identifies formula-view rows whose text is wholly held. Formula-of is
;; conventional notation and therefore static; value-readout and unknown rows
;; remain live by construction.
(define (static-formula-row? target)
  (define raw (and (c-node? target) (c-node-data target)))
  (and (c-object? raw)
       (case (c-object-kind raw)
         [(formula)
          (and (pair? (c-object-arguments raw))
               (not (formula-expression-has-live-value?
                     (first (c-object-arguments raw)))))]
         [(formula-of) #t]
         [else #f])))

;; formula-row-key : c-view? any/c -> (or/c list? #f)
;;   Separates repeated presentations of one mathematical Formula, whose
;; native style or visibility can differ by view without changing its text.
(define (formula-row-key view target)
  (define address (target-address target))
  (and address (list (c-view-name view) address)))

;; formula-row-font : real? -> font%
;;   Resolves a Formula font from the current immutable presentation context.
;; It is shared by live rows while static rows receive the same work during
;; preparation, one time for each documented presentation state.
(define (formula-row-font-size reference)
  (define base-font-size (theme-font-size reference))
  (define font-size (render-style-value 'font-size 15))
  (if (calculus-length? font-size)
      (layout-length->pixels font-size reference base-font-size)
      font-size))

(define (formula-row-font reference)
  (define size (formula-row-font-size reference))
  (theme-font size))

;; formula-row-base-color : symbol? -> string?
;; Keeps the same snapshot state palette in static preparation and live panel
;; painting, so a cached TeX artifact is never reused under the wrong color.
(define (formula-row-base-color presentation-state)
  (case presentation-state
    [(deemphasized) "#7A7A7A"]
    [(highlighted) "#B45309"]
    [else (theme-color 'foreground "#202124")]))

;; formula-backend->renderer : symbol? any/c -> pict-renderer?
;; The calculus adapter reuses Animate's existing formula-Pict renderer
;; protocol. It deliberately does not create a separate TeX/Typst registry.
(define (formula-backend->renderer who backend)
  (cond
    [(eq? backend 'default) default-latex-formula-pict-renderer]
    [(pict-renderer? backend) backend]
    [else
     (raise-argument-error who "'default or a formula-capable pict-renderer?" backend)]))

;; formula-text->tex : string? -> string?
;; The semantic bridge returns plain text for headless inspection. At the
;; native boundary, translate its conventional mathematical glyph vocabulary
;; to TeX. Ordinary graph annotations remain ordinary upright text; this is
;; used only for Formula and value-readout panels.
(define (formula-text->tex text)
  (define normalized
    (for/fold ([result text])
              ([replacement
                (in-list
                 (list (cons "Δx" "\\Delta x")
                       (cons "Δy" "\\Delta y")
                       (cons "Δ" "\\Delta ")
                       (cons "∫" "\\int ")
                       (cons "√" "\\sqrt")
                       (cons "≈" "\\approx ")
                       (cons "≤" "\\le ")
                       (cons "≥" "\\ge ")
                       (cons "≠" "\\ne ")
                       (cons "·" "\\cdot ")
                       (cons "−" "-")
                       (cons "′" "^{\\prime}")
                       (cons "₀" "_{0}")
                       (cons "₁" "_{1}")
                       (cons "₂" "_{2}")
                       (cons "₃" "_{3}")
                       (cons "₄" "_{4}")
                       (cons "₅" "_{5}")
                       (cons "₆" "_{6}")
                       (cons "₇" "_{7}")
                       (cons "₈" "_{8}")
                       (cons "₉" "_{9}")
                       (cons "ₙ" "_{n}")
                       (cons "∞" "\\infty ")))])
      (string-replace result (car replacement) (cdr replacement))))
  ;; Held division syntax already identifies its numerator and denominator.
  ;; Retain that distinction in TeX rather than painting literal slashes.
  (define fractions
    (regexp-replace*
     #px"\\(([^()]*)\\)/\\(([^()]*)\\)"
     normalized
     (lambda (_whole numerator denominator)
       (format "\\frac{~a}{~a}" numerator denominator))))
  ;; Math mode ignores ordinary spaces. Preserve a readout's label/value gap.
  (regexp-replace* #px" +" fractions (lambda (_whole) "\\;")))

;; render-formula-pict : pict-renderer? string? real? exact-positive-integer?
;;                       exact-positive-integer? string? -> pict?
;; A unit-scale camera lets the Formula row's configured pixel font size become
;; the formula Visual's native size. LaTeX Picts are self-painted bitmaps, so
;; their foreground must be part of the TeX source rather than a Pict colorize
;; wrapper (which cannot recolor their embedded black pixels).
(define (render-formula-pict backend tex font-size width height foreground)
  (define camera
    (make-camera #:width width #:height height #:world-width width #:background "white"))
  (define rgb
    (substring foreground 1 7))
  (render-visual-with-pict-renderer
   backend
   (latex-formula
    (format "{\\color[HTML]{~a} ~a}" rgb tex)
    #:id 'calculus-formula-row
    #:font-size (max 1 font-size)
    #:preamble "\\usepackage{xcolor}")
   camera))

;; prepare-static-formula-assets : calculus-plan? exact-positive-integer?
;;                                  exact-positive-integer? -> immutable-hash?
;;   Resolves constant Formula text and its state-qualified TeX/Pict assets
;; before any frame is sampled. Dynamic value fields are purposefully absent,
;; preventing an initial reading from being reused at a later parameter value.
(define (prepare-static-formula-assets plan width height formula-backend)
  (define lesson (calculus-plan-lesson plan))
  (define profile (calculus-plan-profile plan))
  (define snapshot (calculus-plan-sample plan #:at 'initial))
  (for/fold ([cache (hash)])
            ([view (in-hash-values (calculus-lesson-views lesson))]
             #:when (eq? (c-view-kind view) 'formula-view))
    (for/fold ([next-cache cache]) ([target (in-list (view-objects view))])
      (define key (formula-row-key view target))
      (cond
        [(or (not key) (not (static-formula-row? target))
             (hash-has-key? next-cache key))
         next-cache]
        [else
         (define text-result (calculus-snapshot-formula-text snapshot target))
         (define tex-result (calculus-snapshot-formula-tex snapshot target))
         (if (and (eq? (calculus-result-status text-result) 'defined)
                  (eq? (calculus-result-status tex-result) 'defined))
             (hash-set
             next-cache key
              (prepared-formula-row-data
               (calculus-result-value text-result)
               (calculus-result-value tex-result)
               (for/hash ([state (in-list '(normal deemphasized highlighted refining))])
                 (values
                  state
                  (parameterize
                      ([current-render-theme (calculus-profile-data-theme profile)]
                       [current-render-reference-size (min width height)]
                       [current-render-style-context
                        (list lesson snapshot view target (and (c-node? target) target))]
                       [current-render-presentation-state state])
                    (formula-row-font (min width height)))))
               (for/hash ([state (in-list '(normal deemphasized highlighted refining))])
                 (values
                  state
                  (parameterize
                      ([current-render-theme (calculus-profile-data-theme profile)]
                       [current-render-reference-size (min width height)]
                       [current-render-style-context
                        (list lesson snapshot view target (and (c-node? target) target))]
                       [current-render-presentation-state state])
                    (render-formula-pict
                     formula-backend
                     (calculus-result-value tex-result)
                     (formula-row-font-size (min width height))
                     width height
                     (let* ([base-color (formula-row-base-color state)]
                            [fill (render-style-value 'fill base-color)])
                       (if (string? fill) fill base-color))))))))
             next-cache)]))))

;; prepare-dynamic-formula-layouts : calculus-plan? -> immutable-hash?
;; Captures source-order text/field topology and every authored event boundary
;; once. A live field reserves the largest observed authored value, rather than
;; a fixed character count; a later value that exceeds this declaration raises
;; an explicit native-layout error instead of overlapping its suffix.
(define (prepare-dynamic-formula-layouts plan width height formula-backend)
  (define lesson (calculus-plan-lesson plan))
  (define profile (calculus-plan-profile plan))
  (define sample-times
    (remove-duplicates
     (append (list 'initial 'final)
             (append-map
              (lambda (event) (list (c-event-start event) (c-event-end event)))
              (calculus-plan-events plan)))))
  (define snapshots
    (for/list ([time (in-list sample-times)])
      (calculus-plan-sample plan #:at time)))
  (for/fold ([layouts (hash)])
            ([view (in-hash-values (calculus-lesson-views lesson))]
             #:when (eq? (c-view-kind view) 'formula-view))
    (for/fold ([next layouts]) ([target (in-list (view-objects view))])
      (define key (formula-row-key view target))
      (cond
        [(or (not key) (static-formula-row? target) (hash-has-key? next key)) next]
        [else
         (define fragments-result
           (calculus-snapshot-formula-fragments (first snapshots) target))
         (if (and (eq? (calculus-result-status fragments-result) 'defined)
                  (list? (calculus-result-value fragments-result)))
             (let* ([fragments (calculus-result-value fragments-result)]
                    [shape (for/list ([fragment (in-list fragments)]) (first fragment))]
                    [all-fragments
                     (for/list ([snapshot (in-list snapshots)])
                       (calculus-snapshot-formula-fragments snapshot target))]
                    [compatible?
                     (andmap
                      (lambda (result)
                        (and (eq? (calculus-result-status result) 'defined)
                             (list? (calculus-result-value result))
                             (equal? shape
                                     (for/list ([fragment (in-list (calculus-result-value result))])
                                       (first fragment)))))
                      all-fragments)]
                    [field-lengths
                     (if compatible?
                         (append-map
                          (lambda (result)
                            (for/list ([fragment (in-list (calculus-result-value result))]
                                       #:when (and (list? fragment)
                                                   (= (length fragment) 2)
                                                   (eq? (first fragment) 'field)
                                                   (string? (second fragment))))
                              (string-length (second fragment))))
                          all-fragments)
                         '())]
                    [reserve (if (pair? field-lengths) (apply max field-lengths) 0)])
               (if compatible?
                   (let ([skeleton-result
                          (calculus-snapshot-formula-skeleton-tex
                           (first snapshots) target reserve)])
                     (define skeleton-picts
                       (if (eq? (calculus-result-status skeleton-result) 'defined)
                           (for/hash ([state (in-list '(normal deemphasized highlighted refining))])
                             (define pict
                               (parameterize
                                   ([current-render-theme (calculus-profile-data-theme profile)]
                                    [current-render-reference-size (min width height)]
                                    [current-render-style-context
                                     (list lesson (first snapshots) view target
                                           (and (c-node? target) target))]
                                    [current-render-presentation-state state])
                                 (define base-color (formula-row-base-color state))
                                 (define fill (render-style-value 'fill base-color))
                                 (render-formula-pict
                                  formula-backend
                                  (calculus-result-value skeleton-result)
                                  (formula-row-font-size (min width height))
                                  width height
                                  (if (string? fill) fill base-color))))
                             (values state pict))
                           (hash)))
                     (hash-set next key
                               (prepared-dynamic-formula-row-data
                                shape reserve skeleton-picts)))
                   next))
             ;; The strict plan boundary already handles invalid performed
             ;; actions. A malformed optional row gets the ordinary readable
             ;; fallback at draw time, but never a late backend invocation.
             next)]))))

;; private-component-presentation? : any/c -> boolean?
;;   Recognizes the renderer-only namespace emitted by expanded component
;;   exposition. It is never a public inspection address.
(define (private-component-presentation? target)
  (and (c-part? target)
       (list? (c-part-name target))
       (pair? (c-part-name target))
       (eq? (first (c-part-name target)) 'private)))

;; component-instance-target : any/c -> (or/c c-node? #f)
;;   Walks a public component part back to the containing instance without
;;   confusing ordinary nested public parts with new mathematical objects.
(define (component-instance-target target)
  (cond
    [(c-node? target) target]
    [(c-part? target) (component-instance-target (c-part-parent target))]
    [else #f]))

;; view-presentation-objects : calculus-lesson? calculus-snapshot? c-view? -> list?
;;   Adds a visible private component construction only to its one compatible
;; graph view. A collapsed component root never inherits visibility to private
;; leaves, and ambiguous placement is left absent for the compiler diagnostic.
(define (view-presentation-objects lesson snapshot view)
  (define declared (view-objects view))
  (define private
    (append-map
     (lambda (target)
       (define instance (component-instance-target target))
       (if instance
           (filter (lambda (part)
                     (and (calculus-snapshot-component-private-visible? snapshot part)
                          (equal? (calculus-component-private-presentation-view-names
                                   lesson instance part)
                                  (list (c-view-name view)))))
                   (calculus-component-private-presentation-parts instance))
           '()))
     declared))
  (remove-duplicates (append declared private)))

;; presentation-visible? : calculus-snapshot? any/c address? c-view? -> boolean?
;;   Keeps private expanded leaves out of the public address resolver while
;;   retaining the ordinary root/part visibility behavior for authored views.
(define (presentation-visible? snapshot target address view)
  (if (private-component-presentation? target)
      (calculus-snapshot-component-private-visible? snapshot target)
      (and address (calculus-snapshot-visible? snapshot address #:view (c-view-name view)))))

;; snapshot-defined-value : calculus-snapshot? address -> any/c
;;   Returns a defined public result's value or #f for partial mathematical data.
(define (snapshot-defined-value snapshot target)
  (define result
    (if (private-component-presentation? target)
        (calculus-snapshot-component-private-ref snapshot target)
        (calculus-snapshot-ref snapshot
                              (if (or (symbol? target)
                                      (and (list? target) (pair? target)))
                                  target
                                  (target-address target)))))
  (and (eq? (calculus-result-status result) 'defined)
       (calculus-result-value result)))

;; graph-view-auto-y? : c-view? -> boolean?
;;   Identifies the documented request for a preparation-time vertical fit.
;; The x window remains an authored finite coordinate interval, which makes
;; representative graph sampling reproducible and independent of screen size.
(define (graph-view-auto-y? view)
  (and (c-view? view)
       (eq? (c-view-kind view) 'graph-view)
       (eq? (hash-ref (c-view-options view) 'y #f) 'auto)))

;; finite-declared-x-bounds : c-view? -> (or/c (list/c real? real?) #f)
;;   Keeps auto fitting tied to an explicit finite horizontal exposition range.
(define (finite-declared-x-bounds view)
  (define domain (hash-ref (c-view-options view) 'x #f))
  (and (c-domain? domain)
       (memq (c-domain-kind domain) '(closed open closed-open open-closed))
       (= (length (c-domain-arguments domain)) 2)
       (let ([lower (first (c-domain-arguments domain))]
             [upper (second (c-domain-arguments domain))])
         (and (finite-world-number? lower)
              (finite-world-number? upper)
              (< lower upper)
              (list lower upper)))))

;; presentation-target-node : calculus-model? any/c address? -> (or/c c-node? #f)
;;   Shares the graph-panel lookup for ordinary targets and expanded component
;; leaves, while values themselves still come only from the outer snapshot.
(define (presentation-target-node model target address)
  (define root (if (list? address) (first address) address))
  (or (and (c-part? target)
           (or (calculus-component-part-node target)
               (calculus-component-private-part-node target)))
      (hash-ref (calculus-model-nodes model) root #f)))

;; graph-fit-y-values : calculus-snapshot? c-node? real? real? integer? -> list?
;;   Samples declared graph evidence at a bounded, deterministic set of input
;; coordinates. It is deliberately a preparation estimate, not a continuity
;; proof or an excuse to join unresolved topology.
(define (graph-fit-y-values snapshot node xmin xmax samples)
  (define raw (and (c-node? node) (c-node-data node)))
  (if (not (and (c-object? raw)
                (memq (c-object-kind raw) '(graph graph-restriction))))
      '()
      (let* ([function (calculus-graph-source-function node)]
             [break-result (and function (calculus-snapshot-function-breaks snapshot function))]
             [provider-breaks
              (if (and break-result
                       (eq? (calculus-result-status break-result) 'defined))
                  (calculus-result-value break-result)
                  '())]
             [inputs
              (sort
               (remove-duplicates
                (append
                 (for/list ([index (in-range samples)])
                   (+ xmin (* (- xmax xmin) (/ index (sub1 samples)))))
                 (filter (lambda (boundary) (<= xmin boundary xmax))
                         (append (graph-boundaries function) provider-breaks))))
               <)])
        (for/list ([input (in-list inputs)]
                   #:do [(define result
                           (calculus-snapshot-graph-value snapshot node input))]
                   #:when (and (eq? (calculus-result-status result) 'defined)
                               (finite-world-number? (calculus-result-value result))))
          (calculus-result-value result)))))

;; target-fit-y-values : calculus-snapshot? calculus-model? any/c real? real? integer? -> list?
;;   Collects finite, bounded evidence only. Infinite lines and bands are
;; intentionally absent: fitting their extent would turn presentation into an
;; arbitrary theorem about an unbounded object.
(define (target-fit-y-values snapshot model target xmin xmax samples)
  (define address (target-address target))
  (define node (and address (presentation-target-node model target address)))
  (define value-target (if (private-component-presentation? target) target address))
  (define (point-y-values value)
    (if (and (pair? value)
             (finite-world-number? (car value))
             (finite-world-number? (cdr value))
             (<= xmin (car value) xmax))
        (list (cdr value))
        '()))
  (cond
    [(not node) '()]
    [(memq (c-node-kind node) '(graph graph-restriction))
     (graph-fit-y-values snapshot node xmin xmax samples)]
    [(memq (c-node-kind node)
           '(point point-on axis-point projection root-point intersection-point))
     (point-y-values (snapshot-defined-value snapshot value-target))]
    [(memq (c-node-kind node) '(input-reading coordinate-reading))
     (point-y-values
      (snapshot-defined-value
       snapshot
       (append (if (list? address) address (list address)) (list 'point))))]
    [(eq? (c-node-kind node) 'sequence-points)
     (define points (snapshot-defined-value snapshot value-target))
     (if (list? points) (append-map point-y-values points) '())]
    [(eq? (c-node-kind node) 'trace-of)
     (append-map point-y-values (calculus-snapshot-trace-points snapshot node))]
    [(memq (c-node-kind node) '(integral-region region-under region-between))
     (define result (calculus-snapshot-region-samples snapshot node))
     (if (eq? (calculus-result-status result) 'defined)
         (append-map
          (lambda (sample)
            (if (and (list? sample) (pair? sample)
                     (finite-world-number? (first sample))
                     (<= xmin (first sample) xmax))
                (filter finite-world-number? (rest sample))
                '()))
          (calculus-result-value result))
         '())]
    [(label-node? node)
     (point-y-values
      (let ([result
             (calculus-snapshot-label-anchor
              snapshot node #:default-input (/ (+ xmin xmax) 2))])
        (and (eq? (calculus-result-status result) 'defined)
             (calculus-result-value result))))]
    [else '()]))

;; auto-fit-times : calculus-plan? exact-positive-integer? -> list?
;;   Includes timeline endpoints in addition to the profile's representative
;; grid, so a short named reveal cannot evade a frozen auto-fit window.
(define (auto-fit-times plan samples)
  (define duration (calculus-plan-duration plan))
  (sort
   (remove-duplicates
    (append (for/list ([index (in-range samples)])
              (* duration (/ index (sub1 samples))))
            (append-map (lambda (event) (list (c-event-start event) (c-event-end event)))
                        (calculus-plan-events plan))))
   <))

;; padded-fit-bounds : (listof real?) -> (or/c (list/c real? real?) #f)
;;   Leaves a small fixed breathing margin for markers/labels. A constant
;; finite object receives a symmetric unit-scale range rather than a singular
;; transform.
(define (padded-fit-bounds values)
  (and (pair? values)
       (let* ([lower (apply min values)]
              [upper (apply max values)]
              [span (- upper lower)]
              [padding (if (zero? span)
                           (max 1 (* 1/20 (max 1 (abs lower))))
                           (* 1/20 span))])
         (list (- lower padding) (+ upper padding)))))

;; prepare-auto-view-windows : calculus-plan? -> immutable-hash?
;;   Computes all requested auto-fit windows once while preparing the plan.
;; A later reverse/sparse frame request only looks up this immutable result.
(define (prepare-auto-view-windows plan)
  (define lesson (calculus-plan-lesson plan))
  (define profile (calculus-plan-profile plan))
  (define model (calculus-lesson-model lesson))
  (define samples (calculus-layout-data-fit-samples
                   (calculus-profile-data-layout profile)))
  (define snapshots
    (for/list ([time (in-list (auto-fit-times plan samples))])
      (calculus-plan-sample plan #:at time)))
  (for/hash ([view (in-list (hash-values (calculus-lesson-views lesson)))]
             #:when (graph-view-auto-y? view))
    (define x-bounds (finite-declared-x-bounds view))
    (unless x-bounds
      (raise-arguments-error
       'prepare-calculus-plan
       "#:y 'auto requires an explicit finite #:x interval"
       "view" (c-view-name view)))
    (define xmin (first x-bounds))
    (define xmax (second x-bounds))
    (define y-bounds
      (padded-fit-bounds
       (append-map
        (lambda (snapshot)
          (append-map
           (lambda (target)
             (define address (target-address target))
             (define node (and address (presentation-target-node model target address)))
             (if (and address
                      (presentation-visible? snapshot target address view)
                      (or (not (label-node? node))
                          (label-anchor-visible? snapshot node view)))
                 (target-fit-y-values snapshot model target xmin xmax samples)
                 '()))
           (view-presentation-objects lesson snapshot view)))
        snapshots)))
    (unless y-bounds
      (raise-arguments-error
       'prepare-calculus-plan
       "cannot determine a finite #:y 'auto fit; declare #:y explicitly"
       "view" (c-view-name view)))
    (values (c-view-name view) (append x-bounds y-bounds))))

;; static-graph-baseline-window : c-view? immutable-hash? -> prepared-view-window?
;;   Selects the prepared baseline world window for a declared graph view.
(define (static-graph-baseline-window view auto-windows)
  (or (hash-ref auto-windows (c-view-name view) #f)
      (let-values ([(xmin xmax)
                    (interval-bounds (hash-ref (c-view-options view) 'x #f) -5 5)]
                   [(ymin ymax)
                    (interval-bounds (hash-ref (c-view-options view) 'y #f) -5 5)])
        (list xmin xmax ymin ymax))))

;; prepare-static-graph-geometries : calculus-plan? immutable-hash? exact-positive-integer?
;;                                    exact-positive-integer? calculus-render-quality-data?
;;                                 -> immutable-hash?
;;   Precomputes only graphs with no transitive writable-parameter dependency.
;; Each key includes the world window, so a later focus/camera window never
;; reuses a path sampled for incompatible clipping or pixel mapping.
(define (prepare-static-graph-geometries plan auto-windows width height quality)
  (define lesson (calculus-plan-lesson plan))
  (define model (calculus-lesson-model lesson))
  (define snapshot (calculus-plan-sample plan #:at 'initial))
  (for/fold ([cache (hash)])
            ([view (in-hash-values (calculus-lesson-views lesson))]
             #:when (eq? (c-view-kind view) 'graph-view))
    (define window (static-graph-baseline-window view auto-windows))
    (define xmin (first window))
    (define xmax (second window))
    (define ymin (third window))
    (define ymax (fourth window))
    (for/fold ([next-cache cache]) ([target (in-list (view-objects view))])
      (define address (target-address target))
      (define node (and address (presentation-target-node model target address)))
      (if (and node
               (memq (c-node-kind node) '(graph graph-restriction))
               (null? (calculus-graph-parameter-dependencies lesson node)))
          (let ([key (graph-geometry-key node xmin xmax ymin ymax
                                         width height quality)])
            (if (hash-has-key? next-cache key)
                next-cache
                (hash-set next-cache key
                          (sample-static-graph-geometry
                           snapshot node xmin xmax ymin ymax width height quality))))
          next-cache))))

;; hex-color : string? -> color%
;;   Converts the documented CSS-style palette literal into the color objects
;;   required by racket/draw; passing the string directly paints black.
(define (hex-color text)
  (unless (and (string? text) (regexp-match? #px"^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$" text))
    (raise-argument-error 'hex-color "#RRGGBB[AA] color string" text))
  (define (byte start)
    (string->number (substring text start (+ start 2)) 16))
  (draw:make-color (byte 1) (byte 3) (byte 5)
                   (if (= (string-length text) 9)
                       (/ (byte 7) 255)
                       1)))

;; draw-dashed-line : drawing-context% real? real? real? real? (listof real?) -> void?
;;   Paints a documented dash pattern in output pixels. racket/draw's stock pen
;; styles cannot represent author-supplied lengths, so this remains a cosmetic
;; realization after semantic clipping has already chosen the endpoints.
(define (draw-dashed-line context x1 y1 x2 y2 dash)
  (define dx (- x2 x1))
  (define dy (- y2 y1))
  (define length (sqrt (+ (* dx dx) (* dy dy))))
  (when (positive? length)
    (let loop ([offset 0] [pattern dash] [paint? #t])
      (when (< offset length)
        (define run (min (car pattern) (- length offset)))
        (when paint?
          (define start (/ offset length))
          (define end (/ (+ offset run) length))
          (send context draw-line (+ x1 (* dx start)) (+ y1 (* dy start))
                (+ x1 (* dx end)) (+ y1 (* dy end))))
        (loop (+ offset run)
              (if (null? (cdr pattern)) dash (cdr pattern))
              (not paint?))))))

;; draw-line-segment : drawing-context% real? real? real? real? string? real? -> void?
;;   Draws one native segment with the matching presentational dash while the
;; held semantic source remains wholly independent of pixel paint.
(define (draw-line-segment context x1 y1 x2 y2 color width)
  (send context set-pen (new draw:pen% [color (hex-color color)] [width width] [style 'solid]))
  (define dash (render-style-value 'dash 'solid))
  (if (list? dash)
      (draw-dashed-line context x1 y1 x2 y2 dash)
      (send context draw-line x1 y1 x2 y2)))

;; function-source : any/c -> any/c
;;   Removes a public node wrapper before inspecting held function topology.
(define (function-source function)
  (if (c-node? function) (c-node-data function) function))

;; equality-branch-boundary : any/c symbol? -> (or/c real? #f)
;;   Extracts a declared equality boundary involving a held function variable.
(define (equality-branch-boundary condition variable)
  (and (c-expression? condition)
       (eq? (c-expression-op condition) '=)
       (= (length (c-expression-arguments condition)) 2)
       (let ([left (first (c-expression-arguments condition))]
             [right (second (c-expression-arguments condition))])
         (cond [(and (c-expression? left) (eq? (c-expression-op left) 'var)
                     (equal? (c-expression-arguments left) (list variable)) (real? right)) right]
               [(and (c-expression? right) (eq? (c-expression-op right) 'var)
                     (equal? (c-expression-arguments right) (list variable)) (real? left)) left]
               [else #f]))))

;; division-boundaries : any/c symbol? -> list?
;;   Finds simple held-variable divisors, which are guaranteed graph gaps.
(define (division-boundaries expression variable)
  (cond
    [(not (c-expression? expression)) '()]
    [else
     (append
      (if (eq? (c-expression-op expression) '/)
          (for/list ([denominator (in-list (rest (c-expression-arguments expression)))]
                     #:when (and (c-expression? denominator)
                                 (eq? (c-expression-op denominator) 'var)
                                 (equal? (c-expression-arguments denominator) (list variable))))
            0)
          '())
      (append-map (lambda (argument) (division-boundaries argument variable))
                  (c-expression-arguments expression)))]))

;; graph-boundaries : any/c -> list?
;;   Supplies mandatory known graph samples independently of adaptive pixel sampling.
(define (graph-boundaries function)
  (define source (function-source function))
  (cond
    [(c-piecewise? source)
     (filter real?
             (map (lambda (branch)
                    (equality-branch-boundary (car branch) (c-piecewise-variable source)))
                  (c-piecewise-branches source)))]
    [(c-function? source)
     (division-boundaries (c-function-body source) (c-function-variable source))]
    [else '()]))

;; piecewise-equality-boundaries : any/c -> list?
;;   Retains source branch IDs for equality boundaries with a possible isolated value.
(define (piecewise-equality-boundaries function)
  (define source (function-source function))
  (if (c-piecewise? source)
      (for/list ([branch (in-list (c-piecewise-branches source))]
                 [index (in-naturals)]
                 #:do [(define boundary
                          (equality-branch-boundary (car branch)
                                                    (c-piecewise-variable source)))]
                 #:when (real? boundary))
        (cons boundary index))
      '()))

;; draw-closed-point : drawing-context% real? real? [string?] -> void?
;;   Paints an included graph endpoint or isolated value from semantic topology.
(define (draw-closed-point context x y [color "#2166C2"])
  (send context set-pen (new draw:pen% [color (hex-color color)] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color color)] [style 'solid]))
  (send context draw-ellipse (- x 3) (- y 3) 6 6))

;; draw-open-point : drawing-context% real? real? [string?] -> void?
;;   Paints an excluded graph endpoint without adding a mathematical value.
(define (draw-open-point context x y [color "#2166C2"])
  (send context set-pen (new draw:pen% [color (hex-color color)] [width 2] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color (theme-panel-background))] [style 'solid]))
  (send context draw-ellipse (- x 4) (- y 4) 8 8))

;; prepared-graph-geometry captures world coordinates only.  Pixel placement,
;; styling, and endpoint paint stay in the active frame so cached mathematics
;; cannot accidentally freeze a profile or panel layout.
(struct prepared-graph-geometry (segments closed-points open-points) #:transparent)

;; graph-geometry-key : c-node? real? real? real? real? exact-positive-integer?
;;                       exact-positive-integer? calculus-render-quality-data?
;;                    -> immutable-list?
;;   Includes every clipping and curve-pixel policy condition that can change
;; sampled geometry.  It deliberately excludes frame time and unrelated
;; presentation state.
(define (graph-geometry-key node xmin xmax ymin ymax width height quality)
  (list (c-node-id node) xmin xmax ymin ymax
        width height
        (calculus-render-quality-data-curve-tolerance quality)
        (calculus-render-quality-data-max-depth quality)))

;; sample-static-graph-geometry : calculus-snapshot? c-node? real? real? real? real?
;;                              exact-positive-integer? exact-positive-integer?
;;                              calculus-render-quality-data?
;;                           -> prepared-graph-geometry?
;;   Evaluates the semantic graph once.  It preserves topology in world
;; coordinates, allowing a prepared cache to be safely reused at new pixels.
;; The bounded adaptive subdivision controls only the visual chord error; it
;; never changes the exact graph evaluator or invents a connection through an
;; unresolved topology boundary.
(define (sample-static-graph-geometry snapshot node xmin xmax ymin ymax
                                      width height quality)
  (define function (calculus-graph-source-function node))
  (define break-result
    (and function (calculus-snapshot-function-breaks snapshot function)))
  (define provider-breaks
    (if (and break-result
             (eq? (calculus-result-status break-result) 'defined))
        (calculus-result-value break-result)
        '()))
  ;; The coarse lattice preserves reliable discovery of ordinary visible spans;
  ;; adaptive work is reserved for intervals with semantic evidence instead of
  ;; spending the entire depth budget below or above a clipped panel.
  (define coarse-samples 32)
  (define curve-tolerance
    (calculus-render-quality-data-curve-tolerance quality))
  (define max-depth
    (calculus-render-quality-data-max-depth quality))
  (define segments '())
  (define closed-points '())
  (define open-points '())
  (define equality-boundaries (piecewise-equality-boundaries function))
  (define sample-inputs
    (sort (remove-duplicates
           (append (for/list ([index (in-range (add1 coarse-samples))])
                     (+ xmin (* (- xmax xmin) (/ index coarse-samples))))
                   (filter (lambda (boundary) (<= xmin boundary xmax))
                           (append (graph-boundaries function) provider-breaks))))
          <))
  ;; A declared opaque-provider break is topological evidence, not merely an
  ;; undefined sample to chase toward the subdivision limit. Keeping the
  ;; adjacent coarse chords out of that interval leaves one explicit visible
  ;; gap after stroke expansion and prevents a cubic endpoint from appearing
  ;; continuous at the excluded input.
  (define (provider-break-at? x)
    (for/or ([break (in-list provider-breaks)]) (= x break)))
  ;; graph-point : real? -> (or/c graph-point? #f)
  ;; Retains the source branch ID with each defined coordinate.  A provider
  ;; break is a mandatory discontinuity even if its implementation happens to
  ;; return a finite value at that input.
  (define (graph-point x)
    ;; Windows are prepared in inexact display coordinates while providers may
    ;; report exact break locations. Numeric equality, rather than `member`'s
    ;; structural equality, keeps the same declared break out of both sample
    ;; representations and therefore out of a smooth path run.
    (and (not (provider-break-at? x))
         (let ([result (calculus-snapshot-graph-value snapshot node x)]
               [branch-result (calculus-snapshot-function-branch snapshot function x)])
           (and (eq? (calculus-result-status result) 'defined)
                (eq? (calculus-result-status branch-result) 'defined)
                (real? (calculus-result-value result))
                (let ([y (calculus-result-value result)])
                  (and (<= ymin y ymax)
                       (list x y (calculus-result-value branch-result))))))))
  ;; chord-deviation : graph-point? graph-point? graph-point? -> nonnegative-real?
  ;; Measures the midpoint's perpendicular deviation in prepared output
  ;; pixels.  The full target size is a conservative upper bound for panels;
  ;; it avoids a frame-dependent layout decision during graph sampling.
  (define (chord-deviation from middle to)
    (define (pixel-x point)
      (* width (/ (- (first point) xmin) (- xmax xmin))))
    (define (pixel-y point)
      (* height (- 1 (/ (- (second point) ymin) (- ymax ymin)))))
    (define x1 (pixel-x from))
    (define y1 (pixel-y from))
    (define x2 (pixel-x to))
    (define y2 (pixel-y to))
    (define xm (pixel-x middle))
    (define ym (pixel-y middle))
    (define denominator (sqrt (+ (sqr (- x2 x1)) (sqr (- y2 y1)))))
    (if (zero? denominator)
        (sqrt (+ (sqr (- xm x1)) (sqr (- ym y1))))
        (/ (abs (- (* (- x2 x1) (- y1 ym))
                   (* (- x1 xm) (- y2 y1))))
           denominator)))
  ;; subdivision-needed? : graph-point? graph-point? graph-point? -> boolean?
  ;; Different source branches, a missing midpoint, or an excessive chord
  ;; deviation all require a further bounded investigation.  At the configured
  ;; depth limit the interval is simply left unresolved rather than bridged.
  (define (subdivision-needed? from middle to)
    (or (not from) (not middle) (not to)
        (not (and (equal? (third from) (third middle))
                  (equal? (third middle) (third to))))
        (> (chord-deviation from middle to) curve-tolerance)))
  ;; A missing endpoint may still contain a visible, well-defined span after
  ;; clipping.  It receives the same finite subdivision budget, but no segment
  ;; can be emitted until both endpoint samples are semantically defined.
  (define (collect-interval! left-x right-x depth)
    (cond
      [(or (provider-break-at? left-x) (provider-break-at? right-x))
       (void)]
      [else
       (define from (graph-point left-x))
       (define to (graph-point right-x))
       (define midpoint-x (/ (+ left-x right-x) 2))
       (define middle (graph-point midpoint-x))
       (cond
         [(and from to middle
               (not (subdivision-needed? from middle to)))
          (set! segments (cons (list from to) segments))]
         [(and (not from) (not middle) (not to))
          ;; No endpoint or midpoint is visible/defined. The coarse lattice has
          ;; already bounded this search; recursing here would turn an entirely
          ;; clipped curve into exponential provider work without producing paint.
          (void)]
         [(< depth max-depth)
          (collect-interval! left-x midpoint-x (add1 depth))
          (collect-interval! midpoint-x right-x (add1 depth))]
         [else (void)])]))
  (for ([left (in-list sample-inputs)] [right (in-list (rest sample-inputs))])
    (collect-interval! left right 0))
  (for ([x (in-list sample-inputs)])
    (define result (calculus-snapshot-graph-value snapshot node x))
    (define branch-result (calculus-snapshot-function-branch snapshot function x))
    (define next
      (and (eq? (calculus-result-status result) 'defined)
           (eq? (calculus-result-status branch-result) 'defined)
           (real? (calculus-result-value result))
           (let ([y (calculus-result-value result)])
             (and (<= ymin y ymax)
                  (list x y (calculus-result-value branch-result))))))
    (define equality-boundary (assoc x equality-boundaries))
    (when (and next equality-boundary
               (equal? (third next) (cdr equality-boundary)))
      (set! closed-points (cons next closed-points)))
    (void))
  (for ([boundary+branch (in-list equality-boundaries)])
    (define boundary (car boundary+branch))
    (define selected
      (calculus-snapshot-function-branch snapshot function boundary))
    (define excluded
      (calculus-snapshot-function-branch-value snapshot function 'else boundary))
    (when (and (eq? (calculus-result-status selected) 'defined)
               (equal? (calculus-result-value selected) (cdr boundary+branch))
               (eq? (calculus-result-status excluded) 'defined)
               (real? (calculus-result-value excluded))
               (<= ymin (calculus-result-value excluded) ymax))
      (set! open-points
            (cons (list boundary (calculus-result-value excluded)) open-points))))
  (prepared-graph-geometry (reverse segments)
                           (reverse closed-points)
                           (reverse open-points)))

;; draw-prepared-graph-geometry : drawing-context% prepared-graph-geometry? ... -> void?
;;   Maps immutable world geometry to this frame's current panel pixels.
(define (graph-segments->runs segments)
  ;; The adaptive sampler emits topology-safe line *chords*.  They are not the
  ;; visual primitive: contiguous chords from one semantic branch form an
  ;; ordered sample run that can be interpolated as one smooth cubic path.
  ;; A missing chord or a branch change deliberately flushes the run, so this
  ;; never rounds a cusp or connects across a discontinuity.
  (define (flush reversed-points runs)
    (if (and (pair? reversed-points) (pair? (cdr reversed-points)))
        (cons (reverse reversed-points) runs)
        runs))
  (define reversed-runs
    (let loop ([remaining segments] [current '()] [runs '()])
      (cond
        [(null? remaining) (flush current runs)]
        [else
         (define segment (car remaining))
         (define start (first segment))
         (define end (second segment))
         (cond
           [(null? current)
            (loop (cdr remaining) (list end start) runs)]
           [(equal? (car current) start)
            (loop (cdr remaining) (cons end current) runs)]
           [else
            (loop remaining '() (flush current runs))])])) )
  (reverse reversed-runs))

;; graph-smooth-control-coordinate : real? real? real? -> real?
;; Uses the same Catmull-Rom-to-cubic control construction as the established
;; sampled function-graph renderer. Exact arithmetic is retained where it is
;; available, so preparation remains deterministic across frames.
(define (graph-smooth-control-coordinate base positive negative)
  (+ base (/ (- positive negative) 6)))

;; graph-run->smooth-path : list? real? real? real? real? ... -> dc-path%
;; Converts one topology-preserving world-coordinate run into a single native
;; cubic path. Controls are clamped to the declared window, matching the host
;; coordinate-series policy and preventing visual overshoot beyond the panel.
(define (graph-run->smooth-path run xmin xmax ymin ymax pixel-x pixel-y)
  (define points (list->vector run))
  (define point-count (vector-length points))
  (define path (new draw:dc-path%))
  (define (world-x point) (first point))
  (define (world-y point) (second point))
  (define (clamp value lower upper) (max lower (min upper value)))
  (define (control start end previous following index)
    (cond
      [(= point-count 2)
       (values (+ (world-x start) (* 1/3 (- (world-x end) (world-x start))))
               (+ (world-y start) (* 1/3 (- (world-y end) (world-y start))))
               (+ (world-x start) (* 2/3 (- (world-x end) (world-x start))))
               (+ (world-y start) (* 2/3 (- (world-y end) (world-y start)))))]
      [else
       (values
        (graph-smooth-control-coordinate (world-x start) (world-x end) (world-x previous))
        (graph-smooth-control-coordinate (world-y start) (world-y end) (world-y previous))
        (graph-smooth-control-coordinate (world-x end) (world-x start) (world-x following))
        (graph-smooth-control-coordinate (world-y end) (world-y start) (world-y following)))]))
  (define first-point (vector-ref points 0))
  (send path move-to (pixel-x (world-x first-point)) (pixel-y (world-y first-point)))
  (for ([index (in-range (sub1 point-count))])
    (define start (vector-ref points index))
    (define end (vector-ref points (add1 index)))
    (define previous (if (zero? index) start (vector-ref points (sub1 index))))
    (define following
      (if (= (+ index 2) point-count) end (vector-ref points (+ index 2))))
    (define-values (control1-x control1-y control2-x control2-y)
      (control start end previous following index))
    (send path curve-to
          (pixel-x (clamp control1-x xmin xmax))
          (pixel-y (clamp control1-y ymin ymax))
          (pixel-x (clamp control2-x xmin xmax))
          (pixel-y (clamp control2-y ymin ymax))
          (pixel-x (world-x end))
          (pixel-y (world-y end))))
  path)

(define (draw-prepared-graph-geometry context geometry xmin xmax ymin ymax
                                      left top width height color stroke-width
                                      [reveal-progress #f])
  (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
  (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
  (define all-segments (prepared-graph-geometry-segments geometry))
  ;; A trace reveal retains the topology-safe source chord order and paints a
  ;; prefix only. It never creates a new interpolating polyline across a gap.
  (define segments
    (if (and (real? reveal-progress) (< reveal-progress 1))
        (take all-segments
              (min (length all-segments)
                   (max 0 (inexact->exact
                           (ceiling (* (max 0 reveal-progress)
                                       (length all-segments)))))))
        all-segments))
  (define dash (render-style-value 'dash 'solid))
  (cond
    ;; The current style vocabulary permits an arbitrary dash list. Racket's
    ;; DC paths cannot preserve that exact phase policy over cubic segments, so
    ;; keep its documented segment treatment rather than silently changing a
    ;; caller's dash semantics. Ordinary graph strokes (the default) are
    ;; smooth cubic paths.
    [(list? dash)
     (for ([segment (in-list segments)])
       (define from (first segment))
       (define to (second segment))
       (draw-line-segment context
                          (pixel-x (first from)) (pixel-y (second from))
                          (pixel-x (first to)) (pixel-y (second to))
                          color stroke-width))]
    [else
     (define previous-smoothing (send context get-smoothing))
     (dynamic-wind
       (lambda () (send context set-smoothing 'smoothed))
       (lambda ()
         (send context set-pen
               (new draw:pen% [color (hex-color color)] [width stroke-width] [style 'solid]))
         (send context set-brush (new draw:brush% [style 'transparent]))
         (for ([run (in-list (graph-segments->runs segments))])
           (send context draw-path
                 (graph-run->smooth-path run xmin xmax ymin ymax pixel-x pixel-y)
                 0 0 'odd-even)))
       (lambda () (send context set-smoothing previous-smoothing)))])
  (when (or (not (real? reveal-progress)) (>= reveal-progress 1))
    (for ([point (in-list (prepared-graph-geometry-closed-points geometry))])
      (draw-closed-point context (pixel-x (first point)) (pixel-y (second point)) color))
    (for ([point (in-list (prepared-graph-geometry-open-points geometry))])
      (draw-open-point context (pixel-x (first point)) (pixel-y (second point)) color))))

;; draw-graph : drawing-context% calculus-snapshot? c-node? ...
;;              calculus-render-quality-data? exact-positive-integer?
;;              exact-positive-integer? -> void?
;;   Uses prepared static geometry when no writable parameter can affect the
;; graph; dynamic graphs remain evaluated directly from the requested snapshot.
(define (draw-graph context snapshot node xmin xmax ymin ymax left top width height
                    quality sampling-width sampling-height
                    [static-geometries (hash)]
                    [reveal-progress #f])
  (define raw (c-node-data node))
  (when (and (c-object? raw) (memq (c-object-kind raw) '(graph graph-restriction)))
    (define preferred-color (render-style-value 'stroke "#2166C2"))
    ;; A graph's topology remains visible even if a cosmetic rule requests no
    ;; stroke; endpoints still distinguish included from excluded values.
    (define graph-color (if (string? preferred-color) preferred-color "#2166C2"))
    (define preferred-width (render-style-value 'stroke-width 2))
    (define graph-width
      (max 1 (if (calculus-length? preferred-width)
                 (layout-length->pixels preferred-width (min width height))
                 preferred-width)))
    (define geometry
      (hash-ref static-geometries
                (graph-geometry-key node xmin xmax ymin ymax
                                    sampling-width sampling-height quality)
                (lambda ()
                  (sample-static-graph-geometry
                   snapshot node xmin xmax ymin ymax
                   sampling-width sampling-height quality))))
    (draw-prepared-graph-geometry context geometry xmin xmax ymin ymax
                                  left top width height graph-color graph-width
                                  reveal-progress)))

;; draw-point : drawing-context% calculus-snapshot? address ... -> void?
;;   Draws one defined point and intentionally omits partial point values.
(define (draw-point context snapshot address xmin xmax ymin ymax left top width height)
  (define point (snapshot-defined-value snapshot address))
  (when (and (pair? point) (real? (car point)) (real? (cdr point))
             (<= xmin (car point) xmax) (<= ymin (cdr point) ymax))
    (define x (+ left (* width (/ (- (car point) xmin) (- xmax xmin)))))
    (define y (+ top height (* -1 height (/ (- (cdr point) ymin) (- ymax ymin)))))
    (define fill (render-style-value 'fill "#B3261E"))
    (define stroke (render-style-value 'stroke fill))
    (define marker-radius (render-style-value 'marker-radius 4))
    (define radius
      (if (calculus-length? marker-radius)
          (layout-length->pixels marker-radius (min width height))
          marker-radius))
    (define stroke-color (if (string? stroke) stroke "#B3261E"))
    (define fill-color (if (string? fill) fill stroke-color))
    (send context set-pen
          (new draw:pen% [color (hex-color stroke-color)] [width 1]
               [style (if (eq? stroke 'none) 'transparent 'solid)]))
    (send context set-brush
          (new draw:brush% [color (hex-color fill-color)]
               [style (if (eq? fill 'none) 'transparent 'solid)]))
    (send context draw-ellipse (- x radius) (- y radius) (* 2 radius) (* 2 radius))))

;; finite-world-number? : any/c -> boolean?
;;   Keeps malformed or nonfinite semantic values out of native coordinates.
(define (finite-world-number? value)
  (and (real? value) (rational? value)))

;; clip-parametric-extent : pair? real? real? real? real? real? real? real? real?
;;                            real? real? -> (or/c (list/c pair? pair?) #f)
;;   Clips p + t(dx,dy) to a graph window and authored t extent.  One helper
;;   covers infinite lines, rays, and finite segments without letting the
;;   drawing backend redefine their mathematical extents.
(define (clip-parametric-extent p dx dy xmin xmax ymin ymax t-min t-max)
  (define (clip-axis origin delta lower upper current-min current-max)
    (cond
      [(zero? delta)
       (and (<= lower origin upper) (cons current-min current-max))]
      [else
       (define t1 (/ (- lower origin) delta))
       (define t2 (/ (- upper origin) delta))
       (define next-min (max current-min (min t1 t2)))
       (define next-max (min current-max (max t1 t2)))
       (and (<= next-min next-max) (cons next-min next-max))]))
  (define x-range (clip-axis (car p) dx xmin xmax t-min t-max))
  (and x-range
       (let ([y-range (clip-axis (cdr p) dy ymin ymax (car x-range) (cdr x-range))])
         (and y-range
              (let ([start (car y-range)] [end (cdr y-range)])
                (list (cons (+ (car p) (* start dx)) (+ (cdr p) (* start dy)))
                      (cons (+ (car p) (* end dx)) (+ (cdr p) (* end dy)))))))))

;; clipped-line-extent : any/c real? real? real? real? -> (or/c (list/c pair? pair?) #f)
;;   Converts semantic geometry records into a clipped finite drawing extent.
(define (clipped-line-extent line xmin xmax ymin ymax)
  (define (valid-point? point)
    (and (pair? point)
         (finite-world-number? (car point))
         (finite-world-number? (cdr point))))
  (define (clip p dx dy low high)
    (and (valid-point? p)
         (finite-world-number? dx)
         (finite-world-number? dy)
         (clip-parametric-extent p dx dy xmin xmax ymin ymax low high)))
  (cond
    [(and (list? line) (pair? line))
     (case (car line)
       [(line)
        (and (= (length line) 4)
             (finite-world-number? (second line))
             (finite-world-number? (third line))
             (valid-point? (fourth line))
             (clip (fourth line) 1 (second line) -inf.0 +inf.0))]
       [(vertical)
        (and (= (length line) 3)
             (finite-world-number? (second line))
             (valid-point? (third line))
             (clip (third line) 0 1 -inf.0 +inf.0))]
       [(segment)
        (and (= (length line) 3)
             (valid-point? (second line))
             (valid-point? (third line))
             (clip (second line)
                   (- (car (third line)) (car (second line)))
                   (- (cdr (third line)) (cdr (second line)))
                   0 1))]
       [(ray)
        (and (= (length line) 3)
             (valid-point? (second line))
             (valid-point? (third line))
             (clip (second line)
                   (- (car (third line)) (car (second line)))
                   (- (cdr (third line)) (cdr (second line)))
                   0 +inf.0))]
       [else #f])]
    [else #f]))

;; draw-clipped-extent : drawing-context% (or/c (list/c pair? pair?) #f) string? ... -> void?
;;   Paints one already-clipped semantic extent, including a visible mark for
;;   the documented zero-length segment case.
(define (draw-clipped-extent context extent color xmin xmax ymin ymax left top width height
                             [stroke-width 2])
  (when extent
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define start (first extent))
    (define end (second extent))
    (define start-x (pixel-x (car start)))
    (define start-y (pixel-y (cdr start)))
    (if (equal? start end)
        (begin
          (send context set-pen (new draw:pen% [color (hex-color color)] [width (max 1 stroke-width)] [style 'solid]))
          (send context set-brush (new draw:brush% [color (hex-color color)] [style 'solid]))
          (send context draw-ellipse (- start-x 2) (- start-y 2) 4 4))
        (draw-line-segment context start-x start-y
                           (pixel-x (car end)) (pixel-y (cdr end)) color stroke-width))))

;; draw-geometric-line : drawing-context% calculus-snapshot? c-node? symbol? ... -> void?
;;   Paints the semantic extent of a visible authored line object.  The core
;;   evaluates the geometry; this adapter only clips it to the current view.
(define (draw-geometric-line context snapshot node address xmin xmax ymin ymax left top width height
                             [color-override #f] [reveal-progress #f] [motion-state #f])
  (define (rotating-carrier-line)
    ;; Limit-transition validation guarantees finite source/target lines with
    ;; the same mathematical anchor. The carrier interpolates only their
    ;; presentation slope and reuses that anchor; it is never a new model
    ;; object or a claim about an intermediate limiting value.
    (and (list? motion-state)
         (>= (length motion-state) 6)
         (eq? (first motion-state) 'limit)
         (eq? (second motion-state) 'rotate-carrier)
         (eq? (third motion-state) 'source)
         (let ([progress (or (motion-progress motion-state 'limit) 1)]
               [source (list-ref motion-state 4)]
               [target (list-ref motion-state 5)])
           (and (list? source) (list? target)
                (= (length source) 4) (= (length target) 4)
                (eq? (first source) 'line) (eq? (first target) 'line)
                (pair? (fourth source))
                (let* ([anchor (fourth source)]
                       [slope (+ (second source)
                                 (* progress (- (second target) (second source))))]
                       [intercept (- (cdr anchor) (* slope (car anchor)))])
                  (list 'line slope intercept anchor))))))
  (define semantic-line
    (or (rotating-carrier-line) (snapshot-defined-value snapshot address)))
  (define complete-extent
    (clipped-line-extent semantic-line xmin xmax ymin ymax))
  ;; Extending a line uses a prefix of its exact already-clipped extent. This
  ;; is a presentation crop, not a changed slope, intercept, or endpoint.
  (define extent
    (if (and complete-extent (real? reveal-progress) (< reveal-progress 1))
        (let ([start (first complete-extent)] [end (second complete-extent)]
              [progress (max 0 reveal-progress)])
          (list start
                (cons (+ (car start) (* progress (- (car end) (car start))))
                      (+ (cdr start) (* progress (- (cdr end) (cdr start)))))))
        complete-extent))
  (define color
    (or color-override
        (case (c-node-kind node)
          [(tangent vertical-tangent) "#B3261E"]
          [(secant) "#6A1B9A"]
          [(chord segment error-segment) "#0B6E4F"]
          [(ray-through) "#A65E00"]
          [else "#5F6368"])))
  (define styled-color (render-style-value 'stroke color))
  (define styled-width (render-style-value 'stroke-width 2))
  (define stroke-width
    (if (calculus-length? styled-width)
        (layout-length->pixels styled-width (min width height))
        styled-width))
  (draw-clipped-extent context extent
                       (cond [color-override color-override]
                             [(string? styled-color) styled-color]
                             [else color])
                       xmin xmax ymin ymax left top width height
                       (max 1 stroke-width)))

;; draw-asymptote : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Displays only a claim-certified supplied asymptote line; an unresolved
;;   relationship never becomes a plausible decorative guide.
(define (draw-asymptote context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-asymptote-geometry snapshot node))
  (when (eq? (calculus-result-status result) 'defined)
    (draw-clipped-extent context
                         (clipped-line-extent (calculus-result-value result) xmin xmax ymin ymax)
                         "#5F6368" xmin xmax ymin ymax left top width height)))

;; draw-slope-triangle : drawing-context% calculus-snapshot? address? ... -> void?
;;   Realizes the headless triangle's two directed segment parts without
;;   recomputing a screen-space rise or run.
(define (draw-slope-triangle context snapshot address xmin xmax ymin ymax left top width height)
  (for ([part-name (in-list '(horizontal vertical))])
    (define extent
      (clipped-line-extent
       (snapshot-defined-value snapshot
                               (append (if (list? address) address (list address))
                                       (list part-name)))
                           xmin xmax ymin ymax))
    (draw-clipped-extent context extent "#A65E00"
                         xmin xmax ymin ymax left top width height)))

;; draw-increment : drawing-context% calculus-snapshot? address? ... -> void?
;;   Connects the increment's headless from/to parts as one directed geometric
;;   relationship. Quantity parts remain available separately for readouts.
(define (draw-increment context snapshot address xmin xmax ymin ymax left top width height)
  (define root-address (if (list? address) address (list address)))
  (define from (snapshot-defined-value snapshot (append root-address (list 'from))))
  (define to (snapshot-defined-value snapshot (append root-address (list 'to))))
  (draw-clipped-extent context
                       (clipped-line-extent (and from to (list 'segment from to))
                                            xmin xmax ymin ymax)
                       "#5F6368" xmin xmax ymin ymax left top width height))

;; draw-epsilon-delta-band : drawing-context% calculus-snapshot? address ... -> void?
;;   Draws the two clipped boundaries of an unbounded semantic band.  Leaving
;;   the interior transparent preserves graph evidence already drawn beneath it.
(define (draw-epsilon-delta-band context snapshot address xmin xmax ymin ymax left top width height)
  (define band (snapshot-defined-value snapshot address))
  (when (and (list? band)
             (= (length band) 3)
             (memq (first band) '(input-band output-band))
             (finite-world-number? (second band))
             (finite-world-number? (third band)))
    (define lower (second band))
    (define upper (third band))
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (case (first band)
      [(input-band)
       (when (<= xmin lower xmax)
         (draw-line-segment context (pixel-x lower) top (pixel-x lower) (+ top height) "#A65E00" 1))
       (when (<= xmin upper xmax)
         (draw-line-segment context (pixel-x upper) top (pixel-x upper) (+ top height) "#A65E00" 1))]
      [(output-band)
       (when (<= ymin lower ymax)
         (draw-line-segment context left (pixel-y lower) (+ left width) (pixel-y lower) "#6A1B9A" 1))
       (when (<= ymin upper ymax)
         (draw-line-segment context left (pixel-y upper) (+ left width) (pixel-y upper) "#6A1B9A" 1))])))

;; draw-riemann-rectangles : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Paints signed cells derived from exact partition/tag/function semantics.
;;   The renderer clips cells only to the active camera; it never estimates a
;;   height from the graph's sampled stroke.
(define (draw-riemann-rectangles context snapshot node xmin xmax ymin ymax left top width height
                                 [refinement-state #f])
  (define result (calculus-snapshot-riemann-cells snapshot node))
  (define refinement-policy
    (and (list? refinement-state)
         (= (length refinement-state) 4)
         (eq? (first refinement-state) 'refinement)
         (second refinement-state)))
  (define refinement-progress
    (and refinement-policy (motion-progress refinement-state 'refinement)))
  (define carrier-count
    (and (list? refinement-state)
         (= (length refinement-state) 4)
         (eq? (first refinement-state) 'refinement)
         (exact-positive-integer? (fourth refinement-state))
         (fourth refinement-state)))
  (define carrier-result
    (and carrier-count
         (calculus-snapshot-riemann-carrier-cells snapshot node carrier-count)))
  (when (eq? (calculus-result-status result) 'defined)
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define original-alpha (send context get-alpha))
    (define (paint-cells cells opacity guides? [bodies? #t])
      (send context set-alpha (* original-alpha opacity))
      (for ([cell (in-list cells)])
        (define cell-left (first cell))
        (define cell-right (second cell))
        (define signed-height (third cell))
        (when (and (finite-world-number? cell-left)
                   (finite-world-number? cell-right)
                   (finite-world-number? signed-height))
          (define clipped-left (max xmin cell-left))
          (define clipped-right (min xmax cell-right))
          (define lower (max ymin (min 0 signed-height)))
          (define upper (min ymax (max 0 signed-height)))
          (when (and (< clipped-left clipped-right) (< lower upper))
            (when bodies?
              (define cell-positive? (positive? signed-height))
              (define default-stroke (if cell-positive? "#2166C2" "#B3261E"))
              (define default-fill (if cell-positive? "#D9E8FF" "#FFE3E3"))
              (define stroke (render-style-value 'stroke default-stroke))
              (define fill (render-style-value 'fill default-fill))
              (define stroke-width
                (max 1 (render-style-length 'stroke-width 1 (min width height))))
              (send context set-pen
                    (new draw:pen% [color (hex-color (if (string? stroke) stroke default-stroke))]
                         [width stroke-width]
                         [style (if (eq? stroke 'none) 'transparent 'solid)]))
              (send context set-brush
                    (new draw:brush% [color (hex-color (if (string? fill) fill default-fill))]
                         [style (if (eq? fill 'none) 'transparent 'solid)]))
              (send context draw-rectangle (pixel-x clipped-left) (pixel-y upper)
                    (- (pixel-x clipped-right) (pixel-x clipped-left))
                    (- (pixel-y lower) (pixel-y upper))))
            (when (and guides? carrier-count
                       (positive? (length cells))
                       (zero? (remainder carrier-count (length cells))))
              (define subdivisions (/ carrier-count (length cells)))
              ;; Cuts appear according to local refinement progress.  Their
              ;; endpoints are clipped with the same rectangle body bounds.
              (define visible-cuts
                (inexact->exact
                 (ceiling (* (or refinement-progress 1) (sub1 subdivisions)))))
              (for ([index (in-range 1 (add1 (min (sub1 subdivisions) visible-cuts)))])
                (define cut (+ cell-left (* (/ index subdivisions)
                                            (- cell-right cell-left))))
                (when (<= xmin cut xmax)
                  (draw-line-segment context (pixel-x cut) (pixel-y lower)
                                     (pixel-x cut) (pixel-y upper)
                                     "#A65E00" 1)))))))
      (send context set-alpha original-alpha))
    (define old-cells (calculus-result-value result))
    (define new-cells
      (and carrier-result
           (eq? (calculus-result-status carrier-result) 'defined)
           (calculus-result-value carrier-result)))
    (case refinement-policy
      [(crossfade)
       (paint-cells old-cells (- 1 (or refinement-progress 0)) #f)
       (when new-cells (paint-cells new-cells (or refinement-progress 0) #f))]
      [(subdivide)
       (paint-cells old-cells 1 #f)
       ;; The exact prospective cells fade in behind the committed count;
       ;; their alpha supplies an actual child-height transition instead of a
       ;; frame-one grid followed by an endpoint jump.
       (when new-cells (paint-cells new-cells (or refinement-progress 0) #f))
       ;; Overlay only the semantic guides after the translucent prospective
       ;; layer, so a carrier remains legible without repainting old cells.
       (paint-cells old-cells 1 #t #f)]
      [else (paint-cells old-cells 1 #f)])))

;; clip-world-polygon : (listof pair?) real? real? real? real? -> (listof pair?)
;;   Clips a world-space polygon against the visible rectangle with
;;   Sutherland-Hodgman intersections.  This changes only which portion is
;;   painted; it never moves an offscreen vertex onto an unrelated boundary.
(define (clip-world-polygon points xmin xmax ymin ymax)
  (define (clip input inside? intersection)
    (cond [(null? input) '()]
          [else
           (let loop ([previous (last input)] [remaining input] [output '()])
             (cond [(null? remaining) (reverse output)]
                   [else
                    (define current (first remaining))
                    (define previous-inside? (inside? previous))
                    (define current-inside? (inside? current))
                    (define next-output
                      (cond [(and previous-inside? current-inside?)
                             (cons current output)]
                            [(and previous-inside? (not current-inside?))
                             (cons (intersection previous current) output)]
                            [(and (not previous-inside?) current-inside?)
                             (cons current (cons (intersection previous current) output))]
                            [else output]))
                    (loop current (rest remaining) next-output)]))]))
  (define (at-x boundary from to)
    (define ratio (/ (- boundary (car from)) (- (car to) (car from))))
    (cons boundary (+ (cdr from) (* ratio (- (cdr to) (cdr from))))))
  (define (at-y boundary from to)
    (define ratio (/ (- boundary (cdr from)) (- (cdr to) (cdr from))))
    (cons (+ (car from) (* ratio (- (car to) (car from)))) boundary))
  (clip
   (clip
    (clip
     (clip points (lambda (point) (>= (car point) xmin))
           (lambda (from to) (at-x xmin from to)))
     (lambda (point) (<= (car point) xmax))
     (lambda (from to) (at-x xmax from to)))
    (lambda (point) (>= (cdr point) ymin))
    (lambda (from to) (at-y ymin from to)))
   (lambda (point) (<= (cdr point) ymax))
   (lambda (from to) (at-y ymax from to))))

;; draw-world-polygon : drawing-context% (listof pair?) string? string? ... -> void?
;;   Maps a finite, precisely clipped world-space polygon to the active graph
;;   panel. Source points are supplied by semantic trapezoid/region geometry,
;;   never recovered from a sampled graph path.
(define (draw-world-polygon context points fill-color stroke-color xmin xmax ymin ymax left top width height)
  (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
  (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
  (define (make-point point)
    (define native-point (new draw:point%))
    (send native-point set-x (pixel-x (car point)))
    (send native-point set-y (pixel-y (cdr point)))
    native-point)
  (define clipped (clip-world-polygon points xmin xmax ymin ymax))
  (when (and (>= (length clipped) 3)
             (andmap (lambda (point)
                       (and (pair? point)
                            (finite-world-number? (car point))
                            (finite-world-number? (cdr point))))
                     clipped))
    (define stroke (render-style-value 'stroke stroke-color))
    (define fill (render-style-value 'fill fill-color))
    (define stroke-width
      (max 1 (render-style-length 'stroke-width 1 (min width height))))
    (send context set-pen
          (new draw:pen% [color (hex-color (if (string? stroke) stroke stroke-color))]
               [width stroke-width]
               [style (if (eq? stroke 'none) 'transparent 'solid)]))
    (send context set-brush
          (new draw:brush% [color (hex-color (if (string? fill) fill fill-color))]
               [style (if (eq? fill 'none) 'transparent 'solid)]))
    (send context draw-polygon (map make-point clipped))))

;; draw-trapezoidal-regions : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Renders each signed trapezoidal contribution.  A cell crossing the axis is
;;   split at its exact affine zero so positive and negative areas stay distinct.
(define (draw-trapezoidal-regions context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-trapezoid-cells snapshot node))
  (define (paint points sign)
    (draw-world-polygon context points
                        (if (positive? sign) "#D9E8FF" "#FFE3E3")
                        (if (positive? sign) "#2166C2" "#B3261E")
                        xmin xmax ymin ymax left top width height))
  (when (eq? (calculus-result-status result) 'defined)
    (for ([cell (in-list (calculus-result-value result))])
      (define cell-left (first cell))
      (define cell-right (second cell))
      (define left-height (third cell))
      (define right-height (fourth cell))
      (when (and (finite-world-number? cell-left)
                 (finite-world-number? cell-right)
                 (finite-world-number? left-height)
                 (finite-world-number? right-height)
                 (< cell-left cell-right))
        (cond
          [(and (>= left-height 0) (>= right-height 0)
                (or (positive? left-height) (positive? right-height)))
           (paint (list (cons cell-left 0) (cons cell-left left-height)
                        (cons cell-right right-height) (cons cell-right 0)) 1)]
          [(and (<= left-height 0) (<= right-height 0)
                (or (negative? left-height) (negative? right-height)))
           (paint (list (cons cell-left 0) (cons cell-left left-height)
                        (cons cell-right right-height) (cons cell-right 0)) -1)]
          [else
           (define zero-x
             (+ cell-left
                (* (- cell-right cell-left)
                   (/ (- left-height) (- right-height left-height)))))
           (if (positive? left-height)
               (begin
                 (paint (list (cons cell-left 0) (cons cell-left left-height) (cons zero-x 0)) 1)
                 (paint (list (cons zero-x 0) (cons cell-right right-height) (cons cell-right 0)) -1))
               (begin
                 (paint (list (cons cell-left 0) (cons cell-left left-height) (cons zero-x 0)) -1)
                 (paint (list (cons zero-x 0) (cons cell-right right-height) (cons cell-right 0)) 1)))])))))

;; draw-partition-marks : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Places fixed-size endpoint ticks on the mathematical x-axis (or the lower
;;   view edge when that axis is outside the selected camera).
(define (draw-partition-marks context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-partition-points snapshot node))
  (when (eq? (calculus-result-status result) 'defined)
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define axis-y
      (+ top height (* -1 height (/ (- (if (<= ymin 0 ymax) 0 ymin) ymin) (- ymax ymin)))))
    (for ([point (in-list (calculus-result-value result))]
          #:when (and (finite-world-number? point) (<= xmin point xmax)))
      (draw-line-segment context (pixel-x point) (- axis-y 4) (pixel-x point) (+ axis-y 4) "#5F6368" 1))))

;; draw-region : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Paints snapshot-derived region strips. Undefined samples reset the strip,
;;   and crossings are split at their affine mathematical intersection so no
;;   polygon pretends one graph is globally above the other.
(define (draw-region context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-region-samples snapshot node))
  (define kind (c-node-kind node))
  (define (paint-under points sign)
    (draw-world-polygon context points
                        (if (positive? sign) "#D9E8FF" "#FFE3E3")
                        (if (positive? sign) "#2166C2" "#B3261E")
                        xmin xmax ymin ymax left top width height))
  (define (paint-between points)
    (draw-world-polygon context points "#E7D8FF" "#6A1B9A"
                        xmin xmax ymin ymax left top width height))
  (define (under-strip previous next)
    (define x0 (first previous))
    (define y0 (second previous))
    (define x1 (first next))
    (define y1 (second next))
    (cond
      ;; A zero-width accumulation region may legitimately produce an all-zero
      ;; strip at its authored endpoint.  It has no fill geometry and, unlike a
      ;; sign crossing, no affine zero to solve for.
      [(and (zero? y0) (zero? y1)) (void)]
      [(and (>= y0 0) (>= y1 0) (or (positive? y0) (positive? y1)))
       (paint-under (list (cons x0 0) (cons x0 y0) (cons x1 y1) (cons x1 0)) 1)]
      [(and (<= y0 0) (<= y1 0) (or (negative? y0) (negative? y1)))
       (paint-under (list (cons x0 0) (cons x0 y0) (cons x1 y1) (cons x1 0)) -1)]
      [else
       (define zero-x (+ x0 (* (- x1 x0) (/ (- y0) (- y1 y0)))))
       (if (positive? y0)
           (begin
             (paint-under (list (cons x0 0) (cons x0 y0) (cons zero-x 0)) 1)
             (paint-under (list (cons zero-x 0) (cons x1 y1) (cons x1 0)) -1))
           (begin
             (paint-under (list (cons x0 0) (cons x0 y0) (cons zero-x 0)) -1)
             (paint-under (list (cons zero-x 0) (cons x1 y1) (cons x1 0)) 1)))]))
  (define (between-strip previous next)
    (define x0 (first previous))
    (define left0 (second previous))
    (define right0 (third previous))
    (define x1 (first next))
    (define left1 (second next))
    (define right1 (third next))
    (define difference0 (- left0 right0))
    (define difference1 (- left1 right1))
    (define (paint first-sample second-sample)
      (paint-between (list (cons (first first-sample) (second first-sample))
                           (cons (first first-sample) (third first-sample))
                           (cons (first second-sample) (third second-sample))
                           (cons (first second-sample) (second second-sample)))))
    (if (or (zero? difference0) (zero? difference1) (positive? (* difference0 difference1)))
        (paint previous next)
        (let* ([fraction (/ difference0 (- difference0 difference1))]
               [cross-x (+ x0 (* fraction (- x1 x0)))]
               [cross-y (+ left0 (* fraction (- left1 left0)))]
               [cross (list cross-x cross-y cross-y)])
          (paint previous cross)
          (paint cross next))))
  (when (eq? (calculus-result-status result) 'defined)
    (define previous #f)
    (for ([sample (in-list (calculus-result-value result))])
      (when (and previous sample)
        (if (eq? kind 'region-between)
            (between-strip previous sample)
            (under-strip previous sample)))
      (set! previous sample))))

;; draw-sequence-points : drawing-context% calculus-snapshot? symbol? ... -> void?
;;   Realizes sequence samples as isolated markers: it intentionally draws no
;;   joining polyline, preserving the sequence's discrete mathematical domain.
(define (draw-sequence-points context snapshot address xmin xmax ymin ymax left top width height)
  (define points (snapshot-defined-value snapshot address))
  (when (list? points)
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define fill (render-style-value 'fill "#6A1B9A"))
    (define stroke (render-style-value 'stroke fill))
    (define marker-radius (render-style-length 'marker-radius 3 (min width height)))
    (define fill-color (if (string? fill) fill "#6A1B9A"))
    (define stroke-color (if (string? stroke) stroke fill-color))
    (send context set-pen
          (new draw:pen% [color (hex-color stroke-color)] [width 1]
               [style (if (eq? stroke 'none) 'transparent 'solid)]))
    (send context set-brush
          (new draw:brush% [color (hex-color fill-color)]
               [style (if (eq? fill 'none) 'transparent 'solid)]))
    (for ([point (in-list points)]
          #:when (and (pair? point)
                      (finite-world-number? (car point))
                      (finite-world-number? (cdr point))
                      (<= xmin (car point) xmax)
                      (<= ymin (cdr point) ymax)))
      (define x (pixel-x (car point)))
      (define y (pixel-y (cdr point)))
      (send context draw-ellipse (- x marker-radius) (- y marker-radius)
            (* 2 marker-radius) (* 2 marker-radius)))))

;; draw-newton-diagram : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Draws each supplied finite Newton construction as the tangent segment from
;;   the graph point to its exact next axis intercept. Missing updates remain
;;   absent rather than being extrapolated by the native layer.
(define (draw-newton-diagram context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-newton-segments snapshot node))
  (when (eq? (calculus-result-status result) 'defined)
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (for ([segment (in-list (calculus-result-value result))])
      (define x (first segment))
      (define y (second segment))
      (define next-x (third segment))
      (draw-clipped-extent context (clipped-line-extent (list 'segment (cons x y) (cons next-x 0))
                                                         xmin xmax ymin ymax)
                           "#6A1B9A" xmin xmax ymin ymax left top width height)
      (when (and (<= xmin x xmax) (<= ymin y ymax))
        (send context set-pen (new draw:pen% [color (hex-color "#B3261E")] [width 1] [style 'solid]))
        (send context set-brush (new draw:brush% [color (hex-color "#B3261E")] [style 'solid]))
        (send context draw-ellipse (- (pixel-x x) 3) (- (pixel-y y) 3) 6 6))
      (when (and (<= xmin next-x xmax) (<= ymin 0 ymax))
        (send context set-pen (new draw:pen% [color (hex-color "#6A1B9A")] [width 1] [style 'solid]))
        (send context set-brush (new draw:brush% [color (hex-color "#FAFAFA")] [style 'solid]))
        (send context draw-ellipse (- (pixel-x next-x) 3) (- (pixel-y 0) 3) 6 6)))))

;; draw-trace : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Draws a locus from its semantic sweep definition.  The private core bridge
;;   supplies a complete static locus or an active trace prefix without relying
;;   on any previously rendered frame; #f samples deliberately split gaps.
(define (draw-trace context snapshot node xmin xmax ymin ymax left top width height)
  (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
  (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
  (define previous #f)
  (for ([point (in-list (calculus-snapshot-trace-points snapshot node))])
    (define next
      (and point
           (<= xmin (car point) xmax)
           (<= ymin (cdr point) ymax)
           (cons (pixel-x (car point)) (pixel-y (cdr point)))))
    (when (and previous next)
      (draw-line-segment context (car previous) (cdr previous)
                         (car next) (cdr next) "#0B6E4F" 2))
    (set! previous next)))

;; draw-reading : drawing-context% calculus-snapshot? address? ... -> void?
;;   Renders input and coordinate readings from their shared semantic point and
;;   coordinate-guide parts. It never derives guides from a nearby pixel sample.
(define (draw-reading context snapshot address xmin xmax ymin ymax left top width height
                      [color "#6A6A6A"] [guided-progress #f])
  (define root-address (if (list? address) address (list address)))
  (define point (snapshot-defined-value snapshot (append root-address (list 'point))))
  (when (and (pair? point) (real? (car point)) (real? (cdr point))
             (<= xmin (car point) xmax) (<= ymin (cdr point) ymax))
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define styled-color
      (if (equal? color "#6A6A6A")
          (render-style-value 'stroke color)
          color))
    (define guide-color (if (string? styled-color) styled-color color))
    (define guide-width
      (max 1 (render-style-length 'stroke-width 1 (min width height))))
    (define dash (render-style-value 'dash 'inherit))
    (define guided? (real? guided-progress))
    (define progress (if guided? (max 0 (min 1 guided-progress)) 1))
    ;; Guided readings stage input guide -> graph point -> output guide.  The
    ;; simultaneous policy takes the existing complete construction path.
    (define input-progress (min 1 (* 3 progress)))
    (define point-visible? (or (not guided?) (>= progress 1/3)))
    (define output-progress (max 0 (min 1 (* 3 (- progress 2/3)))))
    (define x (car point))
    (define y (cdr point))
    (define (draw-guide from-x from-y to-x to-y)
      (cond [(eq? dash 'inherit)
             (send context set-pen
                   (new draw:pen% [color (hex-color guide-color)] [width guide-width] [style 'dot]))
             (send context draw-line (pixel-x from-x) (pixel-y from-y)
                   (pixel-x to-x) (pixel-y to-y))]
            [else
             (draw-line-segment context (pixel-x from-x) (pixel-y from-y)
                                (pixel-x to-x) (pixel-y to-y) guide-color guide-width)]))
    (when (positive? input-progress)
      (draw-guide x 0 x (* input-progress y)))
    (when point-visible?
      (draw-point context snapshot (append root-address (list 'point))
                  xmin xmax ymin ymax left top width height))
    (when (positive? output-progress)
      (draw-guide 0 y (* output-progress x) y))))

;; label-node? : any/c -> boolean?
;;   Limits native annotation handling to the three explicitly anchored label
;; constructions. Their text/anchor semantics stay in the headless core.
(define (label-node? node)
  (and (c-node? node)
       (memq (c-node-kind node) '(point-label graph-label quantity-label))))

;; label-anchor : c-node? -> semantic-target?
;;   Returns the declared mathematical owner of a label. A graph label is
;; owned by its graph, while a quantity label explicitly names its anchor.
(define (label-anchor node)
  (define raw (and (c-node? node) (c-node-data node)))
  (and (c-object? raw)
       (case (c-object-kind raw)
         [(point-label graph-label) (and (pair? (c-object-arguments raw))
                                         (first (c-object-arguments raw)))]
         [(quantity-label) (hash-ref (c-object-options raw) 'at #f)]
         [else #f])))

;; label-anchor-visible? : calculus-snapshot? c-node? -> boolean?
;;   Showing a label cannot resurrect a hidden point or graph. The native
;; adapter enforces that ownership rule before it places any glyphs.
(define (label-anchor-visible? snapshot node view)
  (define anchor (label-anchor node))
  (define address (and anchor (target-address anchor)))
  (and address
       (calculus-snapshot-visible? snapshot address #:view (c-view-name view))
       ;; Label commands own a separate preference channel.  Both the owner
       ;; and an explicitly named label can suppress its glyphs, but neither
       ;; preference can make an invisible owner appear.
       (calculus-snapshot-label-visible? snapshot anchor #:view (c-view-name view))
       (calculus-snapshot-label-visible? snapshot node #:view (c-view-name view))))

;; label-placement is one native, nonsemantic annotation decision.
;;  - x/y        pixel top-left placement for the upright text
;;  - anchor-x/y exact mapped semantic anchor used only for a leader segment
;;  - leader?    true when collision avoidance selected a non-primary slot
(struct label-placement (x y anchor-x anchor-y leader?) #:transparent)

;; label-box-overlaps? : list? list? -> boolean?
;;   Uses strict rectangle intersection, so edge-touching labels remain valid.
(define (label-box-overlaps? left-box right-box)
  (and (< (first left-box) (third right-box))
       (< (first right-box) (third left-box))
       (< (second left-box) (fourth right-box))
       (< (second right-box) (fourth left-box))))

;; label-resolved-values : calculus-snapshot? c-node? real? real? -> (or/c list? #f)
;;   Resolves the mathematical anchor and held text before native placement;
;; the layout pass never evaluates a function, parameter, or formula itself.
(define (label-resolved-values snapshot node xmin xmax)
  (define raw (c-node-data node))
  (define anchor-result
    (calculus-snapshot-label-anchor
     snapshot node
     #:default-input (and (eq? (c-object-kind raw) 'graph-label)
                           (/ (+ xmin xmax) 2))))
  (define anchor-point
    (and (eq? (calculus-result-status anchor-result) 'defined)
         (calculus-result-value anchor-result)))
  (define text-result (calculus-snapshot-label-text snapshot node))
  (and (pair? anchor-point)
       (finite-world-number? (car anchor-point))
       (finite-world-number? (cdr anchor-point))
       (<= xmin (car anchor-point) xmax)
       (eq? (calculus-result-status text-result) 'defined)
       (string? (calculus-result-value text-result))
       (list anchor-point (calculus-result-value text-result))))

;; plan-label-placements : drawing-context% calculus-lesson? calculus-snapshot?
;;                          calculus-model? c-view? list? real? ... -> immutable-hash?
;;   Selects the first nonoverlapping slot from a fixed candidate order after
;; sorting by stable label ID.  It depends only on the sampled semantic state,
;; view map, and style data, never on request or paint order.  A bounded
;; fallback still records a leader instead of silently moving its anchor.
(define (plan-label-placements context lesson snapshot model view targets
                               xmin xmax ymin ymax left top width height)
  (define original-font (send context get-font))
  (define primary-labels
    (sort
     (for/list ([target (in-list targets)]
                #:do [(define address (target-address target))
                      (define node (and address
                                        (presentation-target-node model target address)))]
                #:when (and (label-node? node)
                            (presentation-visible? snapshot target address view)
                            (label-anchor-visible? snapshot node view)))
       (list target address node))
     string<?
     #:key (lambda (entry) (format "~s" (second entry)))))
  (define placements
    (let loop ([remaining primary-labels] [occupied '()] [result (hash)])
      (cond
        [(null? remaining) result]
        [else
         (define entry (first remaining))
         (define target (first entry))
         (define address (second entry))
         (define node (third entry))
         (define placement
           (parameterize ([current-render-style-context
                           (list lesson snapshot view target node)])
             (define resolved (label-resolved-values snapshot node xmin xmax))
             (and resolved
                  (let* ([anchor (first resolved)]
                         [text (second resolved)]
                         [font-size (render-style-value 'font-size 15)]
                         [size (if (calculus-length? font-size)
                                   (layout-length->pixels font-size (min width height))
                                   font-size)]
                         [gap-value (render-style-value 'label-gap (calculus-px 5))]
                         [gap (if (calculus-length? gap-value)
                                  (layout-length->pixels gap-value (min width height) size)
                                  gap-value)]
                         [anchor-x (+ left (* width (/ (- (car anchor) xmin) (- xmax xmin))))]
                         [anchor-y (+ top height
                                      (* -1 height (/ (- (cdr anchor) ymin) (- ymax ymin))))])
                    (send context set-font (theme-font size))
                    (define-values (text-width text-height _descent _leading)
                      (send context get-text-extent text))
                    ;; Candidate coordinates are text top-left corners.  The
                    ;; stable clockwise order leaves the conventional NE slot
                    ;; unchanged whenever it fits.
                    (define candidates
                      (list (list (+ anchor-x gap) (- anchor-y gap text-height))
                            (list (- anchor-x gap text-width) (- anchor-y gap text-height))
                            (list (+ anchor-x gap) (+ anchor-y gap))
                            (list (- anchor-x gap text-width) (+ anchor-y gap))
                            (list (+ anchor-x gap) (- anchor-y (/ text-height 2)))
                            (list (- anchor-x gap text-width) (- anchor-y (/ text-height 2)))))
                    (define (box candidate)
                      (list (first candidate) (second candidate)
                            (+ (first candidate) text-width) (+ (second candidate) text-height)))
                    (define (inside-panel? candidate)
                      (define candidate-box (box candidate))
                      (and (<= left (first candidate-box))
                           (<= top (second candidate-box))
                           (<= (third candidate-box) (+ left width))
                           (<= (fourth candidate-box) (+ top height))))
                    (define selected-index
                      (or (for/first ([candidate (in-list candidates)] [index (in-naturals)]
                                      #:when (and (inside-panel? candidate)
                                                  (not (for/or ([used (in-list occupied)])
                                                         (label-box-overlaps? (box candidate) used)))))
                            index)
                          0))
                    (define selected (list-ref candidates selected-index))
                    (list (label-placement (first selected) (second selected)
                                           anchor-x anchor-y (positive? selected-index))
                          (box selected))))))
         (if placement
             (loop (rest remaining) (cons (second placement) occupied)
                   (hash-set result (c-node-id node) (first placement)))
             (loop (rest remaining) occupied result))])))
  (send context set-font original-font)
  placements)

;; draw-label : drawing-context% calculus-snapshot? c-node? ...
;;              [label-placement?] -> void?
;;   Paints a previously selected deterministic candidate.  A direct caller
;; without a graph-panel plan retains the documented top-right default.
(define (draw-label context snapshot node xmin xmax ymin ymax left top width height
                    [placement #f])
  (define resolved (label-resolved-values snapshot node xmin xmax))
  (when resolved
    (define anchor-point (first resolved))
    (define label-text (second resolved))
    (when (<= ymin (cdr anchor-point) ymax)
    (define font-size (render-style-value 'font-size 15))
    (define size
      (if (calculus-length? font-size)
          (layout-length->pixels font-size (min width height))
          font-size))
    (define gap-value (render-style-value 'label-gap (calculus-px 5)))
    (define gap
      (if (calculus-length? gap-value)
          (layout-length->pixels gap-value (min width height) size)
          gap-value))
    (define fill (render-style-value 'fill (theme-color 'foreground "#202124")))
    (define opacity (render-style-value 'opacity 1))
    (define original-alpha (send context get-alpha))
    (define x (+ left (* width (/ (- (car anchor-point) xmin) (- xmax xmin)))))
    (define y (+ top height (* -1 height (/ (- (cdr anchor-point) ymin) (- ymax ymin)))))
    (define draw-x (if placement (label-placement-x placement) (+ x gap)))
    (define draw-y (if placement (label-placement-y placement) (- y gap size)))
    (send context set-alpha (* original-alpha opacity))
    (send context set-font (theme-font size))
    (when (string? fill)
      (send context set-text-foreground (hex-color fill))
      (when (and placement (label-placement-leader? placement))
        (draw-line-segment context (label-placement-anchor-x placement)
                           (label-placement-anchor-y placement)
                           (+ draw-x (/ size 3)) (+ draw-y (/ size 2)) fill 1))
      (send context draw-text label-text draw-x draw-y))
    (send context set-alpha original-alpha)
    (send context set-text-foreground (hex-color (theme-color 'foreground "#202124"))))))

;; draw-marker-circle : drawing-context% real? real? boolean? string? string? real? -> void?
;;   Paints inclusion only after the semantic bridge has determined it. An open
;; circle is never substituted for an unresolved endpoint.
(define (draw-marker-circle context x y included? fill stroke radius)
  (send context set-pen (new draw:pen% [color (hex-color stroke)] [width 2] [style 'solid]))
  (send context set-brush
        (new draw:brush% [color (hex-color (if included? fill (theme-panel-background)))]
             [style 'solid]))
  (send context draw-ellipse (- x radius) (- y radius) (* 2 radius) (* 2 radius)))

;; draw-marker : drawing-context% calculus-snapshot? c-node? ... -> void?
;;   Realizes already-resolved axis spans, certified endpoints, and approach
;; direction. The renderer clips and styles this data but does not decide
;; membership, function values, or which way an approach points.
(define (draw-marker context snapshot node xmin xmax ymin ymax left top width height)
  (define result (calculus-snapshot-marker-geometry snapshot node))
  (when (eq? (calculus-result-status result) 'defined)
    (define geometry (calculus-result-value result))
    (define stroke (render-style-value 'stroke "#6A1B9A"))
    (define fill (render-style-value 'fill stroke))
    (define color (if (string? stroke) stroke "#6A1B9A"))
    (define marker-fill (if (string? fill) fill color))
    (define radius (render-style-length 'marker-radius 4 (min width height)))
    (define stroke-width
      (max 1 (render-style-length 'stroke-width 2 (min width height))))
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
    (define (axis-y) (pixel-y (if (<= ymin 0 ymax) 0 ymin)))
    (define (axis-x) (pixel-x (if (<= xmin 0 xmax) 0 xmin)))
    (define (span-axis pieces axis)
      (for ([piece (in-list pieces)])
        (cond [(and (list? piece) (equal? piece (list 'line)))
               (if (eq? axis 'x)
                   (draw-line-segment context left (axis-y) (+ left width) (axis-y) color stroke-width)
                   (draw-line-segment context (axis-x) top (axis-x) (+ top height) color stroke-width))]
              [(and (list? piece) (= (length piece) 2) (eq? (first piece) 'hole)
                    (finite-world-number? (second piece)))
               (if (eq? axis 'x)
                   (when (<= xmin (second piece) xmax)
                     (draw-marker-circle context (pixel-x (second piece)) (axis-y)
                                         #f marker-fill color radius))
                   (when (<= ymin (second piece) ymax)
                     (draw-marker-circle context (axis-x) (pixel-y (second piece))
                                         #f marker-fill color radius)))]
              [(and (list? piece) (= (length piece) 5) (eq? (first piece) 'span))
               (define lower (second piece))
               (define upper (third piece))
               (define lower-included? (fourth piece))
               (define upper-included? (fifth piece))
               (cond [(eq? axis 'x)
                      (when (<= (max xmin lower) (min xmax upper))
                        (draw-line-segment context (pixel-x (max xmin lower)) (axis-y)
                                           (pixel-x (min xmax upper)) (axis-y) color stroke-width))
                      (when (<= xmin lower xmax)
                        (draw-marker-circle context (pixel-x lower) (axis-y)
                                            lower-included? marker-fill color radius))
                      (when (and (not (= lower upper)) (<= xmin upper xmax))
                        (draw-marker-circle context (pixel-x upper) (axis-y)
                                            upper-included? marker-fill color radius))]
                     [else
                      (when (<= (max ymin lower) (min ymax upper))
                        (draw-line-segment context (axis-x) (pixel-y (max ymin lower))
                                           (axis-x) (pixel-y (min ymax upper)) color stroke-width))
                      (when (<= ymin lower ymax)
                        (draw-marker-circle context (axis-x) (pixel-y lower)
                                            lower-included? marker-fill color radius))
                      (when (and (not (= lower upper)) (<= ymin upper ymax))
                        (draw-marker-circle context (axis-x) (pixel-y upper)
                                            upper-included? marker-fill color radius))])]
              [else (void)])))
    (cond
      [(and (list? geometry) (= (length geometry) 3)
            (eq? (first geometry) 'interval-marker))
       (span-axis (third geometry) (second geometry))]
      [(and (list? geometry) (= (length geometry) 4)
            (eq? (first geometry) 'endpoint-marker)
            (finite-world-number? (second geometry))
            (finite-world-number? (third geometry))
            (<= xmin (second geometry) xmax) (<= ymin (third geometry) ymax))
       (draw-marker-circle context (pixel-x (second geometry)) (pixel-y (third geometry))
                           (fourth geometry) marker-fill color radius)]
      [(and (list? geometry) (= (length geometry) 4)
            (eq? (first geometry) 'approach-marker)
            (finite-world-number? (fourth geometry)))
       (define axis (second geometry))
       (define side (third geometry))
       (define coordinate (fourth geometry))
       (define tip-x (if (eq? axis 'x) (pixel-x coordinate) (axis-x)))
       (define tip-y (if (eq? axis 'x) (axis-y) (pixel-y coordinate)))
       (define direction (if (eq? side 'left) 1 -1))
       (define run 18)
       (when (and (if (eq? axis 'x) (<= xmin coordinate xmax) (<= ymin coordinate ymax)))
         (if (eq? axis 'x)
             (begin
               (draw-line-segment context (- tip-x (* direction run)) tip-y tip-x tip-y color stroke-width)
               (draw-line-segment context tip-x tip-y (- tip-x (* direction 6)) (- tip-y 5) color stroke-width)
               (draw-line-segment context tip-x tip-y (- tip-x (* direction 6)) (+ tip-y 5) color stroke-width))
             (begin
               (draw-line-segment context tip-x (+ tip-y (* direction run)) tip-x tip-y color stroke-width)
               (draw-line-segment context tip-x tip-y (- tip-x 5) (+ tip-y (* direction 6)) color stroke-width)
               (draw-line-segment context tip-x tip-y (+ tip-x 5) (+ tip-y (* direction 6)) color stroke-width))))]
      [else (void)])))

;; draw-highlight-ring : drawing-context% calculus-snapshot? any/c ... -> void?
;;   Marks point-like highlighted targets without approximating their position
;;   from pixels. Nonpoint targets retain their semantic highlighted state for
;;   formula/native styling but do not receive an invented graph marker.
(define (draw-highlight-ring context snapshot target xmin xmax ymin ymax left top width height)
  (define point (snapshot-defined-value snapshot target))
  (when (and (pair? point) (real? (car point)) (real? (cdr point))
             (<= xmin (car point) xmax) (<= ymin (cdr point) ymax))
    (define x (+ left (* width (/ (- (car point) xmin) (- xmax xmin)))))
    (define y (+ top height (* -1 height (/ (- (cdr point) ymin) (- ymax ymin)))))
    (send context set-pen (new draw:pen% [color (hex-color "#D97706")] [width 2] [style 'solid]))
    (send context set-brush (new draw:brush% [color (hex-color "#FFFFFF")] [style 'transparent]))
    (send context draw-ellipse (- x 8) (- y 8) 16 16)))

;; prepared-view-window? : any/c -> boolean?
;;   Recognizes one finite camera rectangle after preparation has selected its
;; output-independent auto-fit baseline.
(define (prepared-view-window? window)
  (and (list? window)
       (= (length window) 4)
       (andmap finite-world-number? window)
       (< (first window) (second window))
       (< (third window) (fourth window))))

;; interpolate-prepared-window : list? list? real? -> list?
;;   Interpolates only semantic world coordinates.  It remains independent of
;; panel pixels, layout, and the order in which frames are requested.
(define (interpolate-prepared-window start target progress)
  (for/list ([from (in-list start)] [to (in-list target)])
    (+ from (* (- to from) progress))))

;; resolve-prepared-view-window : any/c (or/c prepared-view-window? #f)
;;                                 -> (or/c prepared-view-window? #f)
;;   Resolves the core's private auto-camera transition descriptors against the
;; one fit frozen when the lesson was prepared.  A descriptor preserves its
;; semantic start/target/progress; this adapter merely supplies the prepared
;; baseline that a headless snapshot intentionally does not invent.
(define (resolve-prepared-view-window state auto-window [fuel 8])
  (cond
    [(prepared-view-window? state) state]
    [(or (not (positive? fuel)) (not (list? state))) auto-window]
    [(and (= (length state) 4) (eq? (first state) 'auto-focus)
          (prepared-view-window? (third state))
          (finite-world-number? (fourth state)))
     (define start
       (or (resolve-prepared-view-window (second state) auto-window (sub1 fuel))
           auto-window))
     (and (prepared-view-window? start)
          (interpolate-prepared-window
           start (third state) (min 1 (max 0 (fourth state)))))]
    [(and (= (length state) 3) (eq? (first state) 'auto-restore)
          (finite-world-number? (third state)))
     (define start (resolve-prepared-view-window (second state) auto-window (sub1 fuel)))
     (and (prepared-view-window? start)
          (prepared-view-window? auto-window)
          (interpolate-prepared-window
           start auto-window (min 1 (max 0 (third state)))))]
    [else auto-window]))

;; The graph painter needs the model, but a snapshot deliberately exposes only
;; inspection operations.  Keep the small model-aware walker separate so the
;; actual drawing loop is easy to audit.
(define (draw-graph-panel/model context lesson snapshot model view left top width height
                                [prepared-auto-window #f]
                                [quality (calculus-render-quality)]
                                [sampling-width width]
                                [sampling-height height]
                                [static-geometries (hash)])
  (define active-window
    (resolve-prepared-view-window
     (calculus-snapshot-view-window-state snapshot view)
     prepared-auto-window))
  (define-values (xmin xmax)
    (if active-window
        (values (first active-window) (second active-window))
        (if prepared-auto-window
            (values (first prepared-auto-window) (second prepared-auto-window))
            (interval-bounds (hash-ref (c-view-options view) 'x #f) -5 5))))
  (define-values (ymin ymax)
    (if active-window
        (values (third active-window) (fourth active-window))
        (if prepared-auto-window
            (values (third prepared-auto-window) (fourth prepared-auto-window))
            (interval-bounds (hash-ref (c-view-options view) 'y #f) -5 5))))
  (send context set-pen (new draw:pen% [color (hex-color "#D0D0D0")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color (theme-panel-background))] [style 'solid]))
  (send context draw-rectangle left top width height)
  ;; Equal scale letterboxes the declared mathematical window inside its panel.
  ;; It changes only the coordinate-to-pixel map; the window and every native
  ;; construction still use the same headless coordinates and clipping bounds.
  (define-values (plot-left plot-top plot-width plot-height)
    (if (eq? (hash-ref (c-view-options view) 'scale 'independent) 'equal)
        (let* ([x-span (- xmax xmin)]
               [y-span (- ymax ymin)]
               [pixels-per-unit (min (/ width x-span) (/ height y-span))]
               [scaled-width (* x-span pixels-per-unit)]
               [scaled-height (* y-span pixels-per-unit)])
          (values (+ left (/ (- width scaled-width) 2))
                  (+ top (/ (- height scaled-height) 2))
                  scaled-width scaled-height))
        (values left top width height)))
  (let ([left plot-left] [top plot-top] [width plot-width] [height plot-height])
    (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
    (define (pixel-y y) (+ top height (* -1 height (/ (- y ymin) (- ymax ymin)))))
  (parameterize ([current-render-style-context
                  (list lesson snapshot view #f #f 'axis)])
    (define axis-color (render-style-value 'stroke "#8A8A8A"))
    (define axis-width
      (max 1 (render-style-length 'stroke-width 1 (min width height))))
    (when (<= xmin 0 xmax)
      (draw-line-segment context (pixel-x 0) top (pixel-x 0) (+ top height)
                         (if (string? axis-color) axis-color "#8A8A8A") axis-width))
    (when (<= ymin 0 ymax)
      (draw-line-segment context left (pixel-y 0) (+ left width) (pixel-y 0)
                         (if (string? axis-color) axis-color "#8A8A8A") axis-width)))
  (define graph-targets (view-presentation-objects lesson snapshot view))
  (define label-placements
    (plan-label-placements context lesson snapshot model view graph-targets
                           xmin xmax ymin ymax left top width height))
  (for ([target (in-list graph-targets)])
    (define address (target-address target))
    (when (and (presentation-visible? snapshot target address view)
               (or (not (label-node? (and (c-node? target) target)))
                   (label-anchor-visible? snapshot target view)))
      (define presentation-state
        (calculus-snapshot-presentation-state snapshot target #:view (c-view-name view)))
      (define motion-state
        (calculus-snapshot-motion-state snapshot target #:view (c-view-name view)))
      (define original-alpha (send context get-alpha))
      (define root (if (list? address) (first address) address))
      (define root-node (hash-ref (calculus-model-nodes model) root #f))
      ;; A component export keeps its caller-visible address, but its declared
      ;; kind lives in the lexical component model. Native preparation reads
      ;; that kind only; all values still come from the outer snapshot address.
      (define node
        (or (and (c-part? target)
                 (or (calculus-component-part-node target)
                     (calculus-component-private-part-node target)))
            root-node))
      (define value-target (if (private-component-presentation? target) target address))
      (parameterize ([current-render-style-context
                      (list lesson snapshot view target node)])
        (define style-opacity (render-style-value 'opacity 1))
        (send context set-alpha
              (* original-alpha
                 (if (eq? presentation-state 'deemphasized) 0.32 1)
                 (motion-opacity motion-state)
                 style-opacity))
        (cond
          [(and node (memq (c-node-kind node) '(graph graph-restriction)))
           (draw-graph context snapshot node xmin xmax ymin ymax left top width height
                       quality sampling-width sampling-height static-geometries
                       (and (list? motion-state)
                            (eq? (first motion-state) 'graph)
                            (eq? (second motion-state) 'trace)
                            (motion-progress motion-state 'graph)))]
          [(label-node? node)
           (draw-label context snapshot node xmin xmax ymin ymax left top width height
                       (hash-ref label-placements (c-node-id node) #f))]
          [(and node (memq (c-node-kind node)
                           '(interval-marker endpoint-marker approach-marker)))
           (draw-marker context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (memq (c-node-kind node) '(point point-on axis-point projection root-point intersection-point)))
           (draw-point context snapshot value-target xmin xmax ymin ymax left top width height)]
          [(and node
                (memq (c-node-kind node)
                      '(segment line-through ray-through horizontal-line vertical-line
                                chord secant tangent vertical-tangent normal error-segment)))
           (draw-geometric-line
            context snapshot node value-target xmin xmax ymin ymax left top width height #f
            (and (list? motion-state)
                 (eq? (first motion-state) 'line)
                 (eq? (second motion-state) 'extend)
                 (motion-progress motion-state 'line))
            motion-state)]
          [(and node (eq? (c-node-kind node) 'asymptote-line))
           (draw-asymptote context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'slope-triangle))
           (draw-slope-triangle context snapshot address xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'increment))
           (draw-increment context snapshot address xmin xmax ymin ymax left top width height)]
          [(and node
                (eq? (c-node-kind node) 'epsilon-delta-condition)
                (list? address)
                (= (length address) 2)
                (memq (second address) '(input-band output-band)))
           (draw-epsilon-delta-band context snapshot address xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'riemann-rectangles))
           (draw-riemann-rectangles context snapshot node xmin xmax ymin ymax left top width height
                                    motion-state)]
          [(and node (eq? (c-node-kind node) 'trapezoidal-regions))
           (draw-trapezoidal-regions context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'partition-marks))
           (draw-partition-marks context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (memq (c-node-kind node) '(integral-region region-under region-between)))
           (draw-region context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'sequence-points))
           (draw-sequence-points context snapshot address xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'newton-diagram))
           (draw-newton-diagram context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (eq? (c-node-kind node) 'trace-of))
           (draw-trace context snapshot node xmin xmax ymin ymax left top width height)]
          [(and node (memq (c-node-kind node) '(input-reading coordinate-reading)))
           (draw-reading context snapshot address xmin xmax ymin ymax left top width height
                         "#6A6A6A"
                         (and (list? motion-state)
                              (eq? (first motion-state) 'reading)
                              (eq? (second motion-state) 'guided)
                              (motion-progress motion-state 'reading)))]
          [(and (list? address) (= (length address) 2) (eq? (second address) 'point))
           (draw-point context snapshot address xmin xmax ymin ymax left top width height)]
          [else (void)])
        (when (eq? presentation-state 'highlighted)
          (cond [(and node
                      (memq (c-node-kind node)
                            '(point point-on axis-point projection root-point intersection-point)))
                 (draw-highlight-ring context snapshot value-target
                                      xmin xmax ymin ymax left top width height)]
                [(and node
                      (memq (c-node-kind node)
                            '(segment line-through ray-through horizontal-line vertical-line
                                      chord secant tangent vertical-tangent normal error-segment)))
                 ;; The outline is an exact second draw of the same semantic
                 ;; extent, not a screen-space approximation of a linked slope.
                 (draw-geometric-line context snapshot node value-target
                                      xmin xmax ymin ymax left top width height "#D97706")]
                [(and node (memq (c-node-kind node) '(input-reading coordinate-reading)))
                 (draw-reading context snapshot address
                               xmin xmax ymin ymax left top width height "#D97706")]
                [else (void)]))
        ;; No outer alpha is used by the adapter; restoring the baseline after
        ;; each object makes the result independent of prior draw order.
        (send context set-alpha original-alpha))))))

;; draw-number-line-panel/model : drawing-context% calculus-lesson? calculus-snapshot? calculus-model? c-view? ... -> void?
;;   Gives number-line views their own semantic preparation path. Scalar values
;;   and selected solution lists become markers; they are not formatted text
;;   pretending to be placed at mathematical coordinates.
(define (draw-number-line-panel/model context lesson snapshot model view left top width height)
  (define-values (xmin xmax)
    (interval-bounds (hash-ref (c-view-options view) 'range #f) -5 5))
  (send context set-pen (new draw:pen% [color (hex-color "#D0D0D0")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color (theme-panel-background))] [style 'solid]))
  (send context draw-rectangle left top width height)
  (define (pixel-x x) (+ left (* width (/ (- x xmin) (- xmax xmin)))))
  (define axis-y (+ top (/ height 2)))
  (parameterize ([current-render-style-context
                  (list lesson snapshot view #f #f 'axis)])
    (define axis-color (render-style-value 'stroke "#8A8A8A"))
    (define axis-width
      (max 1 (render-style-length 'stroke-width 1 (min width height))))
    (define axis-opacity (render-style-value 'opacity 1))
    (define original-alpha (send context get-alpha))
    (send context set-alpha (* original-alpha axis-opacity))
    (draw-line-segment context left axis-y (+ left width) axis-y
                       (if (string? axis-color) axis-color "#8A8A8A") axis-width)
    (send context set-alpha original-alpha))
  (for ([target (in-list (view-objects view))])
    (define address (target-address target))
    (when (and address (calculus-snapshot-visible? snapshot address #:view (c-view-name view)))
      (define root (if (list? address) (first address) address))
      (define node (hash-ref (calculus-model-nodes model) root #f))
      (parameterize ([current-render-style-context
                      (list lesson snapshot view target node)])
        (define presentation-state
          (calculus-snapshot-presentation-state snapshot target #:view (c-view-name view)))
        (define motion-state
          (calculus-snapshot-motion-state snapshot target #:view (c-view-name view)))
        (define style-opacity (render-style-value 'opacity 1))
        (define original-alpha (send context get-alpha))
        (send context set-alpha
              (* original-alpha
                 (if (eq? presentation-state 'deemphasized) 0.32 1)
                 (motion-opacity motion-state)
                 style-opacity))
        (cond
        [(and node (eq? (c-node-kind node) 'sign-chart))
         (define intervals-result
           (calculus-snapshot-sign-chart-intervals snapshot node))
         (when (eq? (calculus-result-status intervals-result) 'defined)
           (for ([interval (in-list (calculus-result-value intervals-result))])
             (define lower (first interval))
             (define upper (second interval))
             (define sign (third interval))
             (define clipped-lower (max xmin lower))
             (define clipped-upper (min xmax upper))
             (when (<= clipped-lower clipped-upper)
               (define default-color
                 (cond [(memq sign '(positive nonnegative)) "#2166C2"]
                       [(memq sign '(negative nonpositive)) "#B3261E"]
                       [else "#6A1B9A"]))
               (define stroke (render-style-value 'stroke default-color))
               (define stroke-width
                 (max 1 (render-style-length 'stroke-width 5 (min width height))))
               (draw-line-segment
                context
                (pixel-x clipped-lower)
                axis-y
                (pixel-x clipped-upper)
                axis-y
                (if (string? stroke) stroke default-color)
                stroke-width))))]
        [else
         (define value (snapshot-defined-value snapshot address))
         (define coordinates
           (cond
             [(finite-world-number? value) (list value)]
             [(and node (memq (c-node-kind node) '(solution-inputs level-set)) (list? value))
              (filter finite-world-number? value)]
             [else '()]))
         (when (pair? coordinates)
           (define fill (render-style-value 'fill "#6A1B9A"))
           (define stroke (render-style-value 'stroke fill))
           (define radius
             (render-style-length 'marker-radius 4 (min width height)))
           (define fill-color (if (string? fill) fill "#6A1B9A"))
           (define stroke-color (if (string? stroke) stroke fill-color))
           (send context set-pen
                 (new draw:pen% [color (hex-color stroke-color)] [width 1]
                      [style (if (eq? stroke 'none) 'transparent 'solid)]))
           (send context set-brush
                 (new draw:brush% [color (hex-color fill-color)]
                      [style (if (eq? fill 'none) 'transparent 'solid)]))
           (for ([coordinate (in-list coordinates)] #:when (<= xmin coordinate xmax))
             (define x (pixel-x coordinate))
             (send context draw-ellipse (- x radius) (- axis-y radius)
                   (* 2 radius) (* 2 radius))))])
        ;; Object opacity is transient native policy.  Resetting it after
        ;; every semantic target prevents a prior marker from dimming later
        ;; independent number-line evidence.
        (send context set-alpha original-alpha)))))

;; value->display-string : any/c -> string?
;;   Gives formula panels a concise, deterministic textual inspection value.
(define (value->display-string value)
  (cond [(number? value) (number->string value)]
        [(boolean? value) (if value "true" "false")]
        [(pair? value) (format "(~a, ~a)" (car value) (cdr value))]
        [else "—"]))

;; draw-formula-panel : drawing-context% calculus-snapshot? c-view? ...
;;                       immutable-hash? -> void?
;;   Draws native Formula/readout rows from held semantic structure and current
;;   snapshot values. Immutable Formula rows use prepared TeX/Pict assets;
;;   live values use prepared native field positions and never invoke a TeX
;;   backend while a frame is being painted.
(define (draw-formula-panel context lesson snapshot view left top width height
                            [static-formula-assets (hash)]
                            [formula-backend default-latex-formula-pict-renderer]
                            [prepared-width (inexact->exact (ceiling width))]
                            [prepared-height (inexact->exact (ceiling height))]
                            [dynamic-formula-layouts (hash)])
  (send context set-pen (new draw:pen% [color (hex-color "#D0D0D0")] [width 1] [style 'solid]))
  (send context set-brush (new draw:brush% [color (hex-color (theme-panel-background))] [style 'solid]))
  (send context draw-rectangle left top width height)
  (send context set-text-foreground (hex-color (theme-color 'foreground "#202124")))
  (for ([target (in-list (view-objects view))] [index (in-naturals)])
    (define address (target-address target))
    (when (and address (calculus-snapshot-visible? snapshot address #:view (c-view-name view)))
      (parameterize ([current-render-style-context
                      (list lesson snapshot view target (and (c-node? target) target))])
        (define presentation-state
          (calculus-snapshot-presentation-state snapshot target #:view (c-view-name view)))
        (define motion-state
          (calculus-snapshot-motion-state snapshot target #:view (c-view-name view)))
        (define prepared-asset
          (hash-ref static-formula-assets (formula-row-key view target) #f))
        (define dynamic-layout
          (hash-ref dynamic-formula-layouts (formula-row-key view target) #f))
        (define prepared-text
          (and prepared-asset (prepared-formula-row-data-text prepared-asset)))
        (define prepared-tex
          (and prepared-asset (prepared-formula-row-data-tex prepared-asset)))
        (define text-result
          (and (not prepared-text)
               (calculus-snapshot-formula-text snapshot target)))
        (define tex-result
          (and (not prepared-tex) (not dynamic-layout)
               (calculus-snapshot-formula-tex snapshot target)))
        (define text
          (or prepared-text
              (if (and text-result
                       (eq? (calculus-result-status text-result) 'defined))
                  (calculus-result-value text-result)
                  "undefined")))
        (define tex
          (or prepared-tex
              (and tex-result
                   (eq? (calculus-result-status tex-result) 'defined)
                   (calculus-result-value tex-result))
              ;; A malformed non-Formula row retains the previous readable
              ;; fallback, but ordinary Formula trees always use the direct
              ;; structured bridge above.
              (formula-text->tex text)))
        (define base-color (formula-row-base-color presentation-state))
        (define fill (render-style-value 'fill base-color))
        (define font
          (or (and prepared-asset
                   (hash-ref (prepared-formula-row-data-fonts prepared-asset)
                             presentation-state #f))
                    (formula-row-font (min width height))))
        (define opacity (render-style-value 'opacity 1))
        (define original-alpha (send context get-alpha))
        (send context set-alpha (* original-alpha opacity (motion-opacity motion-state)))
        (send context set-font font)
        (when (string? fill)
          (send context set-text-foreground (hex-color fill))
          (define prepared-pict
            (and prepared-asset
                 (hash-ref (prepared-formula-row-data-picts prepared-asset)
                           presentation-state #f)))
          (cond
            [prepared-pict
             (pict:draw-pict prepared-pict context
                             (+ left 16) (+ top 16 (* 30 index)))]
            [dynamic-layout
             (define fragments-result
               (calculus-snapshot-formula-fragments snapshot target))
             (define fragments
               (and (eq? (calculus-result-status fragments-result) 'defined)
                    (calculus-result-value fragments-result)))
             (define expected-shape
               (prepared-dynamic-formula-row-data-shape dynamic-layout))
             (define skeleton-pict
               (hash-ref (prepared-dynamic-formula-row-data-skeleton-picts dynamic-layout)
                         presentation-state #f))
             (if (and (list? fragments)
                      (equal? expected-shape
                              (for/list ([fragment (in-list fragments)]) (first fragment))))
                 (let* ([reserve (prepared-dynamic-formula-row-data-field-reserve dynamic-layout)]
                        [overflow
                         (for/or ([fragment (in-list fragments)])
                           (and (eq? (first fragment) 'field)
                                (string? (second fragment))
                                (> (string-length (second fragment)) reserve)))])
                   (when overflow
                     (raise-arguments-error
                      'prepared-lesson->pict
                      "a live Formula value within its prepared authored-path reservation"
                      "address" address
                      "reserved-characters" reserve))
                   (define origin-x (+ left 16))
                   (define origin-y (+ top 16 (* 30 index)))
                   (define reserve-sample (make-string reserve #\0))
                   (define-values (reserved-width _reserved-height _reserved-descent _reserved-leading)
                     (send context get-text-extent reserve-sample))
                   ;; The skeleton preserves TeX fractions, powers, radicals,
                   ;; and held occurrence layout.  It was created during
                   ;; preparation with an invisible fixed-width field.
                   (when skeleton-pict
                     (pict:draw-pict skeleton-pict context origin-x origin-y))
                   (let loop ([remaining fragments] [cursor origin-x])
                     (unless (null? remaining)
                       (define fragment (first remaining))
                       (define kind (first fragment))
                       (define fragment-text (second fragment))
                       ;; A skeleton already owns every held mathematical
                       ;; fragment.  Only its live numeric field is drawn at
                       ;; sampling time; readouts without a skeleton retain
                       ;; their one-field native path.
                       (when (or (not skeleton-pict) (eq? kind 'field))
                         (send context draw-text fragment-text cursor origin-y))
                       (define-values (text-width _text-height _text-descent _text-leading)
                         (send context get-text-extent fragment-text))
                       (loop (rest remaining)
                             (+ cursor (if (eq? kind 'field)
                                           reserved-width
                                           text-width))))))
                 ;; A source-shape mismatch is rendered as the one readable
                 ;; diagnostic field. It does not fall back to a late formula
                 ;; backend call or silently move a trusted symbolic suffix.
                 (send context draw-text "undefined" (+ left 16) (+ top 16 (* 30 index))))]
            [else
             ;; Dynamic values deliberately take the prepared numeric-field
             ;; path rather than asking the TeX backend to typeset a new whole
             ;; formula while a frame is being drawn. Static Formula rows keep
             ;; their structured TeX Picts above; a live row's changing field
             ;; is a native numeric annotation and retains stable baseline
             ;; placement at its reserved row origin.
             (send context set-text-foreground (hex-color fill))
             (send context draw-text text (+ left 16) (+ top 16 (* 30 index)))]))
        (send context set-alpha original-alpha))))
  (send context set-text-foreground (hex-color (theme-color 'foreground "#202124"))))

;; lesson-views : calculus-lesson? calculus-profile? -> list?
;;   Applies an authored panel order first, then a deterministic name order for
;;   omitted views. This keeps panel identity independent of frame sampling.
(define (lesson-views lesson profile)
  (define table (calculus-lesson-views lesson))
  (define available (sort (hash-keys table) symbol<?))
  (define requested
    (let ([order (calculus-layout-data-panel-order
                  (calculus-profile-data-layout profile))])
      (if (list? order)
          (filter (lambda (name) (member name available)) order)
          '())))
  (define names
    (append requested (filter (lambda (name) (not (member name requested))) available)))
  (for/list ([name (in-list names)]) (hash-ref table name)))

;; layout-length->pixels : calculus-length? real? -> real?
;;   Resolves only the documented presentation units, with relative dimensions
;;   anchored to the currently prepared output rather than a mutable frame.
(define (layout-length->pixels length reference [em-size (theme-font-size reference)])
  (define effective-reference (or (current-render-reference-size) reference))
  (case (calculus-length-unit length)
    [(px) (calculus-length-value length)]
    [(rel) (* effective-reference (calculus-length-value length))]
    [(em) (* em-size (calculus-length-value length))]
    [else 0]))

;; render-snapshot->pict : prepared-calculus-lesson? calculus-snapshot? [#:caption (or/c string? #f)] -> pict?
;;   Creates one native pict from one semantic state and its already-resolved
;; semantic caption, without consulting prior frames.
(define (demanded-native-node? node)
  ;; Graph strokes may lawfully contain topology gaps and Formula/readout rows
  ;; may explicitly display an undefined result. Every named geometric or
  ;; explanatory object below, however, has requested concrete mathematical
  ;; data and must not disappear merely because a painter received `#f`.
  (and (c-node? node)
       (memq (c-node-kind node)
             '(point point-on axis-point projection root-point intersection-point
                     point-on-line segment line-through ray-through horizontal-line
                     vertical-line chord secant tangent vertical-tangent normal
                     error-segment input-reading output-reading coordinate-reading
                     interval-marker endpoint-marker approach-marker slope-triangle
                     epsilon-delta-condition riemann-rectangles trapezoidal-regions
                     integral-region region-under region-between partition-marks
                     sequence-points newton-diagram trace-of asymptote-line
                     value-readout))))

;; demanded-native-result : calculus-snapshot? c-node? any/c address? boolean?
;;                          -> calculus-result?
;; Uses the same typed semantic bridge consumed by each painter.  Root
;; descriptors are intentionally insufficient for composites such as readings
;; and regions: a descriptor may exist while its requested geometry does not.
(define (demanded-native-result snapshot node target address private?)
  ;; Typed bridges accept the semantic node/part, while reading parts retain
  ;; their public address for the ordinary snapshot resolver below.
  (define semantic-target (if private? target node))
  (case (c-node-kind node)
    [(input-reading output-reading coordinate-reading)
     (calculus-snapshot-ref
      snapshot
      (append (if (list? address) address (list address)) (list 'point)))]
    [(interval-marker endpoint-marker approach-marker)
     (calculus-snapshot-marker-geometry snapshot semantic-target)]
    [(riemann-rectangles)
     (calculus-snapshot-riemann-cells snapshot semantic-target)]
    [(trapezoidal-regions)
     (calculus-snapshot-trapezoid-cells snapshot semantic-target)]
    [(partition-marks)
     (calculus-snapshot-partition-points snapshot semantic-target)]
    [(integral-region region-under region-between)
     (calculus-snapshot-region-samples snapshot semantic-target)]
    [(asymptote-line)
     (calculus-snapshot-asymptote-geometry snapshot semantic-target)]
    [(value-readout)
     ;; The core bridge preserves an author-selected `#:undefined 'label`,
     ;; while its default/error policy returns the original nondefined result.
     (calculus-snapshot-formula-text snapshot semantic-target)]
    [else
     (if private?
         (calculus-snapshot-component-private-ref snapshot target)
         (calculus-snapshot-ref snapshot address))]))

;; validate-demanded-snapshot! : prepared-calculus-lesson? calculus-snapshot? -> void?
;;   Rejects strict native conversion when a visible named construction lacks
;;   its demanded mathematical value. Legal hidden objects, formula undefined
;; displays, and graph discontinuity topology remain unaffected.
(define (validate-demanded-snapshot! prepared snapshot)
  (define plan (prepared-lesson-plan prepared))
  (define lesson (calculus-plan-lesson plan))
  (define model (calculus-lesson-model lesson))
  (for* ([view (in-hash-values (calculus-lesson-views lesson))]
         [target (in-list (view-presentation-objects lesson snapshot view))])
    (define address (target-address target))
    (define node
      (or (and (c-part? target)
               (or (calculus-component-part-node target)
                   (calculus-component-private-part-node target)))
          (and address
               (hash-ref (calculus-model-nodes model)
                         (if (list? address) (first address) address) #f))))
    (define private? (private-component-presentation? target))
    (define visible?
      (if private?
          (calculus-snapshot-component-private-visible? snapshot target)
          (and address
               (calculus-snapshot-visible? snapshot address #:view (c-view-name view)))))
    (when (and address node (demanded-native-node? node) visible?)
      (define result
        (demanded-native-result snapshot node target address private?))
      (unless (eq? (calculus-result-status result) 'defined)
        (raise-arguments-error
         'prepared-lesson->pict "defined mathematical data for every visible demanded object"
         "address" address
         "status" (calculus-result-status result)
         "message" (calculus-result-message result)))))
  (for ([diagnostic (in-list (calculus-snapshot-diagnostics snapshot))]
        #:when (eq? (calculus-diagnostic-severity diagnostic) 'error))
    (raise-arguments-error
     'prepared-lesson->pict "a sampled calculus state without error diagnostics"
     "code" (calculus-diagnostic-code diagnostic)
     "address" (calculus-diagnostic-address diagnostic)
     "message" (calculus-diagnostic-message diagnostic))))

(define (render-snapshot->pict prepared snapshot #:caption [caption #f])
  (define plan (prepared-lesson-plan prepared))
  (define lesson (calculus-plan-lesson plan))
  (define profile (calculus-plan-profile plan))
  (define model (calculus-lesson-model lesson))
  (define auto-windows (prepared-calculus-lesson-data-auto-windows prepared))
  (define static-graph-geometries
    (prepared-calculus-lesson-data-static-graph-geometries prepared))
  (define static-formula-assets
    (prepared-calculus-lesson-data-static-formula-assets prepared))
  (define dynamic-formula-layouts
    (prepared-calculus-lesson-data-dynamic-formula-layouts prepared))
  (define formula-backend
    (prepared-calculus-lesson-data-formula-backend prepared))
  (define width (prepared-calculus-lesson-data-width prepared))
  (define height (prepared-calculus-lesson-data-height prepared))
  (define quality (prepared-calculus-lesson-data-quality prepared))
  (define views (lesson-views lesson profile))
  (pict:dc
   (lambda (context x y)
     (define original-pen (send context get-pen))
     (define original-brush (send context get-brush))
     (define original-font (send context get-font))
     (define original-foreground (send context get-text-foreground))
     (parameterize ([current-render-theme (calculus-profile-data-theme profile)]
                    [current-render-reference-size (min width height)])
       (dynamic-wind
        void
        (lambda ()
        (send context set-pen
              (new draw:pen% [color (hex-color (theme-color 'background "#FFFFFF"))]
                   [width 1] [style 'solid]))
        (send context set-brush
              (new draw:brush% [color (hex-color (theme-color 'background "#FFFFFF"))]
                     [style 'solid]))
        (send context draw-rectangle x y width height)
        (define layout (calculus-profile-data-layout profile))
        (define arrangement
          (let ([declared (calculus-layout-data-arrangement layout)])
            (if (eq? declared 'auto)
                (if (and (>= width height) (<= (length views) 3)) 'side-by-side 'stacked)
                declared)))
        ;; Preserve the established classroom minimum margin at compact output
        ;; sizes while allowing larger relative margins in custom profiles.
        (define margin (max 32
                            (layout-length->pixels (calculus-layout-data-margin layout)
                                                   (min width height))))
        (define count (max 1 (length views)))
        (define panel-gap (layout-length->pixels (calculus-layout-data-gap layout)
                                                 (min width height)))
        (define captions?
          (and (calculus-layout-data-captions? layout)
               (calculus-plan-has-captions? plan)))
        (define caption-height
          (if captions?
              (layout-length->pixels (calculus-layout-data-caption-height layout)
                                     (min width height))
              0))
        (define content-width (- width (* 2 margin)))
        (define content-height (- height (* 2 margin) caption-height))
        (define panel-width
          (if (eq? arrangement 'stacked)
              content-width
              (/ (- content-width (* (sub1 count) panel-gap)) count)))
        (define panel-height
          (if (eq? arrangement 'stacked)
              (/ (- content-height (* (sub1 count) panel-gap)) count)
              content-height))
        (for ([view (in-list views)] [index (in-naturals)])
          (define left (+ x margin (if (eq? arrangement 'stacked) 0
                                      (* index (+ panel-width panel-gap)))))
          (define top (+ y margin (if (eq? arrangement 'stacked)
                                     (* index (+ panel-height panel-gap)) 0)))
          (cond [(eq? (c-view-kind view) 'graph-view)
                 (draw-graph-panel/model
                  context lesson snapshot model view left top panel-width panel-height
                  (hash-ref auto-windows (c-view-name view) #f)
                  quality width height
                  static-graph-geometries)]
                [(eq? (c-view-kind view) 'number-line-view)
                 (draw-number-line-panel/model context lesson snapshot model view left top panel-width panel-height)]
                [else
                 (draw-formula-panel context lesson snapshot view left top panel-width panel-height
                                     static-formula-assets formula-backend width height
                                     dynamic-formula-layouts)]))
        (when (and captions? caption)
          (send context set-text-foreground
                (hex-color (theme-color 'foreground "#202124")))
          (send context set-font (make-object draw:font% 15 'modern 'normal 'normal))
          (send context draw-text caption
                (+ x margin)
                (+ y (- height margin caption-height) 4))))
        (lambda ()
          (send context set-pen original-pen)
          (send context set-brush original-brush)
          (send context set-font original-font)
          (send context set-text-foreground original-foreground)))))
   width height))


;;;
;;; Public Prepared Output
;;;

;; prepared-lesson->pict : prepared-calculus-lesson? [#:at location] -> pict?
;;   Produces the shared prepared composition at one headless semantic moment.
(define (prepared-lesson->pict prepared #:at [at 'final])
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->pict "prepared-calculus-lesson?" prepared))
  (define plan (prepared-lesson-plan prepared))
  (define snapshot (calculus-plan-sample plan #:at at))
  (validate-demanded-snapshot! prepared snapshot)
  (render-snapshot->pict prepared
                         snapshot
                         #:caption (calculus-plan-caption plan at)))

;; native-camera : prepared-calculus-lesson? -> camera?
;;   Chooses a one-pixel-per-world-unit camera for the prepared pict panel.
(define (native-camera prepared)
  (native:make-camera #:width (prepared-calculus-lesson-data-width prepared)
                      #:height (prepared-calculus-lesson-data-height prepared)
                      #:world-width (prepared-calculus-lesson-data-width prepared)
                      #:background "white"))

;; prepared-lesson->visual : prepared-calculus-lesson? [#:at location] -> Visual
;;   Wraps the prepared pict in Animate's standard Visual protocol.
(define (prepared-lesson->visual prepared #:at [at 'final])
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->visual "prepared-calculus-lesson?" prepared))
  (panel:prepared-pict-panel (prepared-lesson->pict prepared #:at at)
                             #:width (prepared-calculus-lesson-data-width prepared)
                             #:height (prepared-calculus-lesson-data-height prepared)
                             #:id 'calculus-prepared-panel))

;; prepared-lesson->scene : prepared-calculus-lesson? -> scene?
;;   Builds one time-driven native panel from the same immutable prepared plan
;;   used for stills. The host sampler supplies the actual requested time, so
;;   24, 30, and 60 fps renders all evaluate the same continuous calculus
;;   lesson rather than holding a precomputed 30-fps image sequence.
(define (prepared-lesson->scene prepared)
  (unless (prepared-calculus-lesson? prepared)
    (raise-argument-error 'prepared-lesson->scene "prepared-calculus-lesson?" prepared))
  (define plan (prepared-lesson-plan prepared))
  (define duration (calculus-plan-duration plan))
  ;; The parameter is a semantic clock owned solely by this adapter. The
  ;; derived Visual reads its sampled value and creates the already-prepared
  ;; composition for that exact calculus time; it does not retain a prior
  ;; frame, discretize time, or alter the lesson's mathematical state.
  (define time-parameter (native:parameter 'calculus-prepared-time 0))
  (define initial-panel (prepared-lesson->visual prepared #:at 'initial))
  (define sampled-panel
    (derived-visual
     initial-panel
     (lambda (context _template)
       (define sampled-time (derived-context-value-ref context time-parameter))
       (prepared-lesson->visual
        prepared
        #:at (min duration (max 0 sampled-time))))))
  (define initial-scene
    (native:scene-add
     (native:scene-set-value
      (native:make-scene #:camera (native-camera prepared))
      time-parameter)
     sampled-panel))
  (if (zero? duration)
      initial-scene
      (native:scene-play initial-scene
                         #:duration duration #:easing native:linear
                         (native:value-to time-parameter duration))))

;; lesson->pict : calculus-lesson? ... -> pict?
;;   Prepares one standalone still with precisely the preparation keywords.
(define (lesson->pict lesson
                      #:at [at 'final]
                      #:profile [profile default-calculus-profile]
                      #:values [values (hash)]
                      #:computation [computation default-calculus-computation]
                      #:width [width 1280]
                      #:height [height 720]
                      #:formula-backend [formula-backend 'default]
                      #:quality [quality (calculus-render-quality)])
  (prepared-lesson->pict
   (prepare-calculus-lesson lesson
                            #:profile profile #:values values #:computation computation
                            #:width width #:height height
                            #:formula-backend formula-backend #:quality quality)
   #:at at))

;; lesson->visual : calculus-lesson? ... -> Visual
;;   Convenience counterpart of lesson->pict with the same preparation contract.
(define (lesson->visual lesson
                        #:at [at 'final]
                        #:profile [profile default-calculus-profile]
                        #:values [values (hash)]
                        #:computation [computation default-calculus-computation]
                        #:width [width 1280]
                        #:height [height 720]
                        #:formula-backend [formula-backend 'default]
                        #:quality [quality (calculus-render-quality)])
  (prepared-lesson->visual
   (prepare-calculus-lesson lesson
                            #:profile profile #:values values #:computation computation
                            #:width width #:height height
                            #:formula-backend formula-backend #:quality quality)
   #:at at))

;; lesson->scene : calculus-lesson? ... -> scene?
;;   Prepares exactly once for this call without adding encoding or worker knobs.
(define (lesson->scene lesson
                       #:profile [profile default-calculus-profile]
                       #:values [values (hash)]
                       #:computation [computation default-calculus-computation]
                       #:width [width 1280]
                       #:height [height 720]
                       #:formula-backend [formula-backend 'default]
                       #:quality [quality (calculus-render-quality)])
  (prepared-lesson->scene
   (prepare-calculus-lesson lesson
                            #:profile profile #:values values #:computation computation
                            #:width width #:height height
                            #:formula-backend formula-backend #:quality quality)))
