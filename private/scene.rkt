#lang racket/base

;;;
;;; Scene Timeline
;;;

;; Defines immutable scenes, chronological clips, local Visual-animation timing,
;; sequential/parallel/lagged/style animation composition, named semantic-value
;; animation, and arbitrary-time sampling.
;;
;; Every play clip stores complete starting Visual and camera states together
;; with compiled animation endpoints. Sampling one frame never depends on
;; sampling earlier frames. The local scheduler compiles timed and composed
;; Visual/scalar requests against the exact semantic state at their local start
;; time, then samples them directly at any requested local time. Nested timed wrappers provide
;; explicit child spans that are scaled inside their parent composition.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "animation.rkt"
         "animation-order.rkt"
         "camera-animation.rkt"
         "camera.rkt"
         "formula-parts-visual.rkt"
         "formula-style.rkt"
         "geometry.rkt"
         "parameter.rkt"
         "scene-state.rkt"
         "visual-selection.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out scene)
         timed
         timed-animation-request?
         succession
         succession-animation-request?
         animation-group
         animation-group-animation-request?
         lagged-start
         lagged-start-animation-request?
         stagger-map
         reveal-subsets
         reveal-formula-parts
         repeat-animation
         ping-pong
         camera-shake
         style-to
         style-to-animation-request?
         make-scene
         scene-add
         scene-remove
         scene-ref
         scene-visual-at
         scene-set-value
         scene-remove-value
         scene-value-at
         scene-current-value
         scene-set-camera
         scene-play
         scene-wait
         scene-sample
         scene-camera-at
         scene-sample-with-camera
         scene-clip-at
         scene-clip-index-at
         scene-animation-inspections-at
         scene-clip-count)


;;;
;;; Data Representation
;;;

(struct timed-animation-request (request start duration easing)
  #:transparent)

;; timed-animation-request wraps one Visual leaf or composition with local timing.
;;  - request   timable-request?                 Visual/camera request/composition to schedule.
;;  - start     nonnegative finite real?        local delay/timing units.
;;  - duration  positive finite real?           active duration/timing units.
;;  - easing    (or/c false/c (-> real? real?)) local mapping; #f inherits the
;;                                                enclosing scene-play easing.

(struct succession-animation-request (requests)
  #:transparent)

;; succession-animation-request stores one immutable sequential composition.
;;  - requests  (listof composition-child-request?)
;;              direct children in chronological order; ordering is significant.

(struct animation-group-animation-request (requests)
  #:transparent)

;; animation-group-animation-request stores one immutable parallel composition.
;;  - requests  (listof composition-child-request?)
;;              direct children sharing one local interval; ordering remains
;;              significant for deterministic equal-start compilation.

(struct lagged-start-animation-request (requests lag-ratio)
  #:transparent)

;; lagged-start-animation-request stores one immutable staggered composition.
;;  - requests   (listof composition-child-request?)
;;               direct children in stagger order.
;;  - lag-ratio  nonnegative finite real?
;;               start offset as a multiple of the previous direct child's span.

(struct style-to-animation-request (requests)
  #:transparent)

;; style-to-animation-request stores one parallel bundle of existing primitive
;; style requests. Keeping the leaves primitive reuses AS/AT exact endpoint,
;; protocol validation, and per-component conflict semantics.

(struct visual-request-spec (request start duration easing)
  #:transparent)

;; visual-request-spec is one validated, resolved local Visual schedule entry.

(struct scheduled-visual-animation (duration easing animation)
  #:transparent)

;; scheduled-visual-animation stores one compiled Visual leaf relative to the
;; containing batch start.

(struct active-scheduled-visual-animation (start scheduled)
  #:transparent)

;; active-scheduled-visual-animation pairs a compiled leaf with its local start
;; while direct event sampling walks the schedule.

(struct scheduled-visual-batch (start introductions animations)
  #:transparent)

;; scheduled-visual-batch groups Visual leaves that begin at the same local time.
;;  - start          nonnegative finite real?       local batch start.
;;  - introductions  (listof visual?)               invisible/empty structural
;;                                                   placeholders installed at
;;                                                   exactly batch start.
;;  - animations     (listof scheduled-visual-animation?)

(struct scheduled-camera-animation (start duration easing animation)
  #:transparent)

;; scheduled-camera-animation stores one compiled camera leaf in the local
;; scheduler. Its from-value is the exact camera state at start, while its
;; easing applies only over [start,start+duration].
;;  - start      nonnegative finite real?       local start time.
;;  - duration   positive finite real?          local active duration.
;;  - easing     (-> real? real?)               local progress mapping.
;;  - animation  compiled-camera-animation?     one component transition.

(struct play-clip
  (start-time
   duration
   start-state
   start-camera
   animations
   camera-animations
   easing)
  #:transparent)

;; play-clip represents the historical interval of simultaneous animation.
;;  - start-time         nonnegative finite real?  absolute clip start time.
;;  - duration           positive finite real?     clip duration.
;;  - start-state        scene-state?              complete Visual start state.
;;  - start-camera       camera?                   complete camera start state.
;;  - animations         (listof compiled-animation?)
;;                       Visual components compiled in request order.
;;  - camera-animations  (listof compiled-camera-animation?)
;;                       camera components compiled in request order.
;;  - easing             (-> real? real?)  shared progress mapping.

(struct timed-play-clip
  (start-time
   duration
   start-state
   start-camera
   visual-batches
   camera-animations
   easing)
  #:transparent)

;; timed-play-clip represents one locally scheduled Visual/scalar interval. It
;; extends the SCENE-AN scheduler with nested sequential/parallel/lagged/style
;; expansion and explicit timed-child scaling for both Visual and camera
;; leaves. camera-follow samples the actual locally scheduled Visual state.

(struct wait-clip (start-time duration state camera)
  #:transparent)

;; wait-clip represents one interval with unchanged Visual and camera states.
;;  - start-time  nonnegative finite real?  absolute clip start time.
;;  - duration    positive finite real?     clip duration.
;;  - state       scene-state?              Visual state held for the interval.
;;  - camera      camera?                   camera held for the interval.

(struct scene (clips current-state current-camera duration)
  #:transparent)

;; scene represents an immutable animation timeline.
;;  - clips           (listof (or/c play-clip? timed-play-clip? wait-clip?))
;;                    clips in chronological order; ordering is significant.
;;  - current-state   scene-state?              Visual state after final action.
;;  - current-camera  camera?                   camera after final action.
;;  - duration        nonnegative finite real?  total timeline duration.


;;;
;;; Public Animation Composition
;;;

; timed : timable-request?
;         [#:start nonnegative-real?]
;         [#:duration positive-real?]
;         [#:easing (or/c false/c (-> real? real?))]
;         -> timed-animation-request?
;;   Adds local timing to one Visual/camera leaf or composition. A false easing
;;   inherits the enclosing timing context. Another timed wrapper is not
;;   accepted, but style and sequential/parallel/lagged compositions may be
;;   wrapped directly.
(define (timed request
               #:start [start 0]
               #:duration [duration 1]
               #:easing [easing #f])
  (unless (timable-visual-request? request)
    (raise-argument-error
     'timed
     "Visual/scalar or camera animation request, style transition, or sequential/parallel/lagged composition"
     request))
  (check-nonnegative-time 'timed start)
  (check-positive-duration 'timed duration)
  (when easing
    (check-easing 'timed easing))
  (timed-animation-request request start duration easing))

; succession : composition-child-request? ... -> succession-animation-request?
;;   Composes Visual animations sequentially. Untimed direct children receive one
;;   timing unit; a timed direct child contributes start+duration units. The parent
;;   interval scales those spans proportionally, and nested compositions recurse.
(define (succession . animations)
  (define requests
    (normalize-animation-requests animations))
  (check-composition-children 'succession animations requests)
  (succession-animation-request
   (for/list ([request (in-list requests)])
     request)))

; animation-group : composition-child-request? ...
;                   -> animation-group-animation-request?
;;   Composes Visual animations in parallel. Untimed direct children have one-unit
;;   spans; timed children may have longer spans. All start together and the parent
;;   interval scales against the longest span. Composition forms may nest freely.
(define (animation-group . animations)
  (define requests
    (normalize-animation-requests animations))
  (check-composition-children 'animation-group animations requests)
  (animation-group-animation-request
   (for/list ([request (in-list requests)])
     request)))

; lagged-start : [#:lag-ratio nonnegative-real?]
;                 composition-child-request? ...
;                 -> lagged-start-animation-request?
;;   Composes Visual animations with staggered starts. Consecutive raw starts are
;;   offset by lag-ratio times the previous direct child's intrinsic span, then
;;   the whole raw schedule is scaled to its assigned interval. Thus r=0 is
;;   parallel timing and r=1 is succession timing, including unequal timed spans.
(define (lagged-start #:lag-ratio [lag-ratio 1/4] . animations)
  (check-nonnegative-time 'lagged-start lag-ratio)
  (define requests
    (normalize-animation-requests animations))
  (check-composition-children 'lagged-start animations requests)
  (lagged-start-animation-request
   (for/list ([request (in-list requests)])
     request)
   lag-ratio))

; stagger-map : (or/c list? vector?) procedure?
;               [#:lag-ratio nonnegative-real?]
;               [#:order (or/c 'forward 'reverse animation-order?)]
;               -> lagged-start-animation-request?
;;   Eagerly maps a one- or two-argument request factory over an ordered
;;   target collection, then delegates the completed children to lagged-start.
;;   The factory always runs in source order; #:order changes only scheduling
;;   order.  Choosing the two-argument call when both arities are accepted
;;   makes the original source index available deterministically.
(define (stagger-map targets make-request
                     #:lag-ratio [lag-ratio 1/4]
                     #:order [order 'forward])
  (define source-targets
    (normalize-stagger-targets targets 'stagger-map))
  (check-nonnegative-time 'stagger-map lag-ratio)
  (check-stagger-order order)
  (define children
    (call-stagger-factory source-targets make-request 'stagger-map))
  (lagged-start
   #:lag-ratio lag-ratio
   (order-stagger-children children order)))

; reveal-subsets : (or/c list? vector?) procedure?
;                  [#:order (or/c 'forward 'reverse animation-order?)]
;                  [#:lag-ratio nonnegative-real?]
;                  [#:cumulative? boolean?]
;                  -> lagged-start-animation-request?
;; Eagerly maps an entry constructor over a concrete source collection. In
;; cumulative mode it is exactly stagger-map. In one-at-a-time mode every
;; scheduled entry after the first starts a matching fade-out of the prior
;; scheduled target, while retaining the ordinary lagged-start timing model.
(define (reveal-subsets targets make-entry
                        #:order [order 'forward]
                        #:lag-ratio [lag-ratio 1]
                        #:cumulative? [cumulative? #t])
  (define source-targets
    (normalize-stagger-targets targets 'reveal-subsets))
  (check-nonnegative-time 'reveal-subsets lag-ratio)
  (check-stagger-order order 'reveal-subsets)
  (unless (boolean? cumulative?)
    (raise-argument-error 'reveal-subsets "boolean?" cumulative?))
  (define entries
    (call-stagger-factory source-targets make-entry 'reveal-subsets))
  (cond
    [cumulative?
     (lagged-start
      #:lag-ratio lag-ratio
      (order-stagger-children entries order))]
    [else
     (define ordered-targets
       (order-stagger-children source-targets order))
     (define ordered-entries
       (order-stagger-children entries order))
     (lagged-start
      #:lag-ratio lag-ratio
      (for/list ([entry (in-list ordered-entries)]
                 [previous-target
                  (in-list (cons #f ordered-targets))])
        (if previous-target
            (animation-group entry (fade-out previous-target))
            entry)))]))

; reveal-formula-parts : formula-assembly-visual?
;                        (or/c list? vector?) procedure?
;                        [#:order (or/c 'forward 'reverse animation-order?)]
;                        [#:lag-ratio nonnegative-real?]
;                        -> lagged-start-animation-request?
;; Resolves stable formula part names or root-relative semantic selections,
;; then delegates the eager factory expansion and scheduling to stagger-map.
;; It deliberately has no symbolic effect registry: callers choose the same
;; concrete request factory used by every other mapped composition.
(define (reveal-formula-parts formula selections make-request
                              #:order [order 'forward]
                              #:lag-ratio [lag-ratio 1/5])
  (unless (formula-assembly-visual? formula)
    (raise-argument-error
     'reveal-formula-parts "formula-assembly-visual?" formula))
  (define raw-selections
    (normalize-stagger-targets selections 'reveal-formula-parts))
  (define formula-root
    (list (visual-id formula)))
  (define targets
    (for/list ([selection (in-list raw-selections)])
      (cond
        [(symbol? selection)
         (formula-select formula selection)]
        [(visual-selection? selection)
         (unless (equal? (visual-selection-root selection) formula-root)
           (raise-arguments-error
            'reveal-formula-parts
            "a semantic selection rooted at the supplied formula"
            "formula-id" (visual-id formula)
            "selection-root" (visual-selection-root selection)))
         (when (visual-selection-empty? selection)
           (raise-arguments-error
            'reveal-formula-parts
            "a nonempty semantic formula selection"
            "selection" selection))
         selection]
        [(visual-path? selection)
         (unless (and (pair? selection)
                      (eq? (car selection) (visual-id formula)))
           (raise-arguments-error
            'reveal-formula-parts
            "a formula part path beginning with the supplied formula identity"
            "formula-id" (visual-id formula)
            "selection" selection))
         selection]
        [else
         (raise-argument-error
          'reveal-formula-parts
          "symbol?, visual-path?, or visual-selection?"
          selection)])))
  (stagger-map targets make-request #:order order #:lag-ratio lag-ratio))

; repeat-animation : composition-child-request? exact-positive-integer?
;                    -> succession-animation-request?
;; Eagerly repeats one immutable request through ordinary succession. Each copy
;; therefore compiles against the exact endpoint of its predecessor.
(define (repeat-animation request count)
  (unless (composition-child-request? request)
    (raise-argument-error 'repeat-animation "composition-child-request?" request))
  (unless (and (exact-integer? count) (positive? count))
    (raise-argument-error 'repeat-animation "positive exact integer" count))
  (apply succession (make-list count request)))

; ping-pong : composition-child-request? composition-child-request?
;             [#:count exact-positive-integer?] -> succession-animation-request?
;; Pairs directions supplied explicitly by the author. No attempt is made to
;; infer a reverse animation from a destination-relative request.
(define (ping-pong forward backward #:count [count 1])
  (unless (composition-child-request? forward)
    (raise-argument-error 'ping-pong "composition-child-request?" forward))
  (unless (composition-child-request? backward)
    (raise-argument-error 'ping-pong "composition-child-request?" backward))
  (unless (and (exact-integer? count) (positive? count))
    (raise-argument-error 'ping-pong "positive exact integer" count))
  (apply succession
         (apply append
                (make-list count (list forward backward)))))

; camera-shake : [#:amplitude nonnegative-finite-real?]
;                [#:samples exact-positive-integer?]
;                [#:seed exact-integer?]
;                [#:decay (or/c 'none 'linear 'smooth)]
;                -> succession-animation-request?
;; Eagerly produces relative camera deltas between deterministic offset samples.
;; The first and final offsets are zero, so the primary camera's exact endpoint
;; is its source center without mutable random or integration state.
(define (camera-shake #:amplitude [amplitude 1/10]
                      #:samples [samples 12]
                      #:seed [seed 0]
                      #:decay [decay 'linear])
  (check-nonnegative-time 'camera-shake amplitude)
  (unless (and (exact-integer? samples) (positive? samples))
    (raise-argument-error 'camera-shake "positive exact integer" samples))
  (unless (exact-integer? seed)
    (raise-argument-error 'camera-shake "exact integer" seed))
  (unless (memq decay '(none linear smooth))
    (raise-argument-error 'camera-shake "(or/c 'none 'linear 'smooth)" decay))
  (define offsets
    (for/list ([index (in-range (add1 samples))])
      (cond
        [(or (zero? index) (= index samples)) origin]
        [else (camera-shake-offset amplitude samples seed decay index)])))
  (apply succession
         (for/list ([from (in-list offsets)]
                    [to (in-list (cdr offsets))])
           (camera-pan-by (vec2- to from)))))

(define camera-shake-modulus 2147483648)
(define camera-shake-multiplier 1103515245)
(define camera-shake-increment 12345)

(define (camera-shake-random seed index salt)
  (define state
    (modulo (+ seed (* 2 index) salt) camera-shake-modulus))
  (/ (modulo (+ (* camera-shake-multiplier state) camera-shake-increment)
             camera-shake-modulus)
     camera-shake-modulus))

(define (camera-shake-offset amplitude samples seed decay index)
  (define fraction (/ index samples))
  (define envelope
    (case decay
      [(none) 1]
      [(linear) (- 1 fraction)]
      [(smooth)
       (define inverse (- 1 fraction))
       (* inverse inverse (- 3 (* 2 inverse)))]))
  (define magnitude (* amplitude envelope))
  (vec2 (* magnitude (- (* 2 (camera-shake-random seed index 0)) 1))
        (* magnitude (- (* 2 (camera-shake-random seed index 1)) 1))))

; style-to : (or/c symbol? visual?)
;            [#:fill (or/c false/c color-spec?)]
;            [#:stroke (or/c false/c color-spec?)]
;            [#:stroke-width (or/c false/c stroke-width?)]
;            [#:opacity (or/c false/c opacity?)]
;            -> style-to-animation-request?
;;   Bundles a nonempty subset of absolute style changes into one parallel
;;   composition node. Primitive constructors perform all capability/value
;;   checks, immediately for direct Visual targets and later for symbolic ones.
(define (style-to target
                  #:fill [fill #f]
                  #:stroke [stroke #f]
                  #:stroke-width [stroke-width #f]
                  #:opacity [opacity #f])
  (define requests
    (append
     (if (eq? fill #f)
         '()
         (list (fill-color-to target fill)))
     (if (eq? stroke #f)
         '()
         (list (stroke-color-to target stroke)))
     (if (eq? stroke-width #f)
         '()
         (list (stroke-width-to target stroke-width)))
     (if (eq? opacity #f)
         '()
         (list (fade-to target opacity)))))
  (when (null? requests)
    (raise-arguments-error
     'style-to
     "at least one style property is required"
     "target" target))
  (style-to-animation-request requests))


;;;
;;; Scene Construction
;;;

; make-scene : [scene-state?] [#:camera camera?] -> scene?
;;   Creates a zero-duration scene with initial Visual and camera states.
(define (make-scene [initial-state empty-scene-state]
                    #:camera [camera default-camera])
  (unless (scene-state? initial-state)
    (raise-argument-error 'make-scene "scene-state?" initial-state))
  (unless (camera? camera)
    (raise-argument-error 'make-scene "camera?" camera))
  (scene '() initial-state camera 0))

; scene-add : scene? visual? ... -> scene?
;;   Adds Visuals instantaneously at the current scene time.
(define (scene-add scn . visuals)
  (unless (scene? scn)
    (raise-argument-error 'scene-add "scene?" scn))
  (define updated-state
    (for/fold ([state (scene-current-state scn)])
              ([visual (in-list visuals)])
      (scene-state-add state visual)))
  (struct-copy scene scn [current-state updated-state]))

; scene-remove : scene? (or/c visual? symbol?) ... -> scene?
;;   Removes top-level targets instantaneously at the current scene time.
(define (scene-remove scn . targets)
  (unless (scene? scn)
    (raise-argument-error 'scene-remove "scene?" scn))
  (define updated-state
    (for/fold ([state (scene-current-state scn)])
              ([target (in-list targets)])
      (scene-state-remove state target)))
  (struct-copy scene scn [current-state updated-state]))

; scene-ref : scene? (or/c visual? symbol? visual-path?) -> visual?
;;   Resolves one Visual from the scene's current endpoint state.
(define (scene-ref scn target)
  (unless (scene? scn)
    (raise-argument-error 'scene-ref "scene?" scn))
  (scene-state-resolved-ref (scene-current-state scn) target))

; scene-visual-at : scene? (or/c visual? symbol? visual-path?) nonnegative-real?
;                    -> visual?
;;   Resolves one Visual directly from an arbitrary sampled scene state.
(define (scene-visual-at scn target time)
  (unless (scene? scn)
    (raise-argument-error 'scene-visual-at "scene?" scn))
  (scene-state-resolved-ref (scene-sample scn time) target))

; scene-set-value : scene? scene-parameter? -> scene?
;                   scene? (or/c symbol? scene-parameter?) interpolable? -> scene?
;;   Adds a parameter's initial value or replaces one named semantic value
;;   instantaneously at the current scene time.
(define scene-set-value
  (case-lambda
    [(scn parameter-value)
     (unless (scene? scn)
       (raise-argument-error 'scene-set-value "scene?" scn))
     (unless (scene-parameter? parameter-value)
       (raise-argument-error 'scene-set-value "scene-parameter?" parameter-value))
     (scene-set-value scn
                      parameter-value
                      (parameter-initial-value parameter-value))]
    [(scn target value)
     (unless (scene? scn)
       (raise-argument-error 'scene-set-value "scene?" scn))
     (struct-copy scene scn
                  [current-state
                   (scene-state-value-set
                    (scene-current-state scn)
                    target
                    value)])]))

; scene-remove-value : scene? (or/c symbol? scene-parameter?) -> scene?
;;   Removes one named semantic value instantaneously at the current scene time.
(define (scene-remove-value scn target)
  (unless (scene? scn)
    (raise-argument-error 'scene-remove-value "scene?" scn))
  (struct-copy scene scn
               [current-state
                (scene-state-value-remove
                 (scene-current-state scn)
                 target)]))

; scene-current-value : scene? (or/c symbol? scene-parameter?) -> interpolable?
;;   Returns one named semantic value from the scene's stored endpoint state.
(define (scene-current-value scn target)
  (unless (scene? scn)
    (raise-argument-error 'scene-current-value "scene?" scn))
  (scene-state-value-ref (scene-current-state scn) target))

; scene-value-at : scene? (or/c symbol? scene-parameter?) nonnegative-real? -> interpolable?
;;   Samples one named semantic value directly at absolute scene time.
(define (scene-value-at scn target time)
  (scene-state-value-ref (scene-sample scn time) target))

; scene-set-camera : scene? camera? -> scene?
;;   Replaces the current camera instantaneously without appending a clip.
(define (scene-set-camera scn camera)
  (unless (scene? scn)
    (raise-argument-error 'scene-set-camera "scene?" scn))
  (unless (camera? camera)
    (raise-argument-error 'scene-set-camera "camera?" camera))
  (struct-copy scene scn [current-camera camera]))

; scene-play : scene?
;              [#:duration (or/c false/c positive-real?)]
;              [#:easing (-> real? real?)]
;              (or/c animation-request?
;                    timed-animation-request?
;                    succession-animation-request?
;                    animation-group-animation-request?
;                    lagged-start-animation-request?
;                    style-to-animation-request?
;                    camera-animation-request?) ...
;              -> scene?
;;   Appends one play clip. Historical requests remain simultaneous. If at least
;;   one timed request or composition is present, Visual/scalar requests use the
;;   local scheduler while ordinary Visual requests still span the full clip.
(define (scene-play scn
                    #:duration [duration #f]
                    #:easing [easing linear]
                    . animations)
  (unless (scene? scn)
    (raise-argument-error 'scene-play "scene?" scn))
  (check-easing 'scene-play easing)
  (define requests
    (normalize-animation-requests animations))
  (when (null? requests)
    (raise-arguments-error
     'scene-play
     "at least one animation is required"
     "animations" animations))
  (unless (andmap supported-scene-play-request? requests)
    (raise-argument-error
     'scene-play
     "list of Visual/scalar, timed, style/composition, or camera animation requests"
     requests))
  ;; Manim Write chooses one second for fewer than fifteen leaves and two
  ;; seconds otherwise.  Only a direct write-in opts into that convention;
  ;; historic requests retain the one-second default and any explicit duration
  ;; always takes precedence.
  (define resolved-duration
    (or duration
        (for/or ([request (in-list requests)]
                 #:when (animation-request? request))
          (animation-request-default-duration request))
        1))
  (check-positive-duration 'scene-play resolved-duration)
  (if (ormap scheduled-scene-play-request? requests)
      (scene-play/scheduled scn resolved-duration easing requests)
      (scene-play/legacy scn resolved-duration easing requests)))

; scene-play/legacy : scene? positive-real? easing? list? -> scene?
;;   Preserves the exact SCENE-AM simultaneous-play implementation.
(define (scene-play/legacy scn duration easing requests)
  (define visual-requests
    (filter animation-request? requests))
  (define camera-requests
    (filter camera-animation-request? requests))
  (define-values (start-state compiled-animations)
    (compile-animation-requests (scene-current-state scn)
                                visual-requests))
  (define start-camera
    (scene-current-camera scn))
  (define motion-end-state
    (if (ormap camera-follow-request? camera-requests)
        (apply-compiled-animations start-state
                                   compiled-animations
                                   1
                                   linear)
        start-state))
  (define compiled-camera-animations
    (compile-camera-animation-requests start-camera
                                       start-state
                                       motion-end-state
                                       camera-requests))
  (define clip
    (play-clip (scene-duration scn)
               duration
               start-state
               start-camera
               compiled-animations
               compiled-camera-animations
               easing))
  (define endpoint-progress
    (scene-eased-progress easing 1))
  (define (endpoint-easing _progress)
    endpoint-progress)
  (define endpoint-motion-state
    (and
     (compiled-camera-animations-require-scene-state?
      compiled-camera-animations)
     (apply-compiled-animations start-state
                                compiled-animations
                                1
                                endpoint-easing)))
  (define end-state
    (complete-compiled-animations start-state
                                  compiled-animations
                                  endpoint-easing))
  (define end-camera
    (complete-compiled-camera-animations start-camera
                                         compiled-camera-animations
                                         endpoint-easing
                                         endpoint-motion-state))
  (scene (append (scene-clips scn) (list clip))
         end-state
         end-camera
         (+ (scene-duration scn) duration)))

; scene-play/scheduled : scene? positive-real? easing? list? -> scene?
;;   Compiles locally scheduled Visual leaves against exact local start states.
(define (scene-play/scheduled scn duration easing requests)
  ;; One expansion calculates the local timing tree for both Visual and camera
  ;; leaves. Keeping a single source of spans means a camera in a succession or
  ;; lagged group receives exactly the same interval as an equivalent Visual.
  (define scheduled-specs
    (append-map
     (lambda (request)
       (request->visual-specs request duration easing))
     requests))
  (define visual-specs
    (filter (lambda (spec)
              (animation-request?
               (visual-request-spec-request spec)))
            scheduled-specs))
  (define camera-specs
    (filter (lambda (spec)
              (camera-animation-request?
               (visual-request-spec-request spec)))
            scheduled-specs))
  (check-scheduled-component-conflicts visual-specs)
  (check-scheduled-removal-boundaries visual-specs)
  (check-scheduled-camera-component-conflicts camera-specs)
  (define start-state
    (scene-current-state scn))
  (define visual-batches
    (compile-scheduled-visual-batches start-state visual-specs))
  (define end-state
    (sample-scheduled-visual-state start-state visual-batches duration))
  (define start-camera
    (scene-current-camera scn))
  (define compiled-camera-animations
    (compile-scheduled-camera-animations
     start-camera
     start-state
     visual-batches
     camera-specs))
  (define clip
    (timed-play-clip (scene-duration scn)
                     duration
                     start-state
                     start-camera
                     visual-batches
                     compiled-camera-animations
                     easing))
  (define end-camera
    (sample-scheduled-camera
     start-camera
     compiled-camera-animations
     duration
     (lambda (local-time)
       (sample-scheduled-visual-state
        start-state visual-batches local-time
        #:finalize-at-time? #f))))
  (scene (append (scene-clips scn) (list clip))
         end-state
         end-camera
         (+ (scene-duration scn) duration)))

; scene-wait : scene? positive-real? -> scene?
;;   Appends an interval that holds the current Visual and camera states.
(define (scene-wait scn duration)
  (unless (scene? scn)
    (raise-argument-error 'scene-wait "scene?" scn))
  (check-positive-duration 'scene-wait duration)
  (define clip
    (wait-clip (scene-duration scn)
               duration
               (scene-current-state scn)
               (scene-current-camera scn)))
  (scene (append (scene-clips scn) (list clip))
         (scene-current-state scn)
         (scene-current-camera scn)
         (+ (scene-duration scn) duration)))


;;;
;;; Scheduled Visual Compilation
;;;

; request->visual-specs : (or/c animation-request?
;                                 camera-animation-request?
;                                 timed-animation-request?
;                                 succession-animation-request?
;                                 animation-group-animation-request?
;                                 lagged-start-animation-request?)
;                         positive-real? easing?
;                         -> (listof visual-request-spec?)
;;   Resolves one top-level Visual or camera request into concrete local schedule
;;   leaves. The historical name remains because SCENE-AN introduced this as the
;;   Visual scheduler; callers filter the resulting leaves by request kind.
;;   Top-level timed values keep their literal second-based start/duration. A
;;   timed composition scales its descendants into that explicit active interval.
(define (request->visual-specs request clip-duration clip-easing)
  (cond
    [(timed-animation-request? request)
     (define start
       (timed-animation-request-start request))
     (define duration
       (timed-animation-request-duration request))
     (define end
       (+ start duration))
     (when (> end clip-duration)
       (raise-arguments-error
        'scene-play
        "a timed animation must fit inside the enclosing play clip"
        "start" start
        "duration" duration
        "animation-end" end
        "clip-duration" clip-duration))
     (expand-timed-content
      (timed-animation-request-request request)
      start
      duration
      (or (timed-animation-request-easing request)
          clip-easing))]
    [(or (animation-request? request)
         (camera-animation-request? request))
     (list
      (visual-request-spec request 0 clip-duration clip-easing))]
    [(succession-animation-request? request)
     (succession->visual-specs request 0 clip-duration clip-easing)]
    [(animation-group-animation-request? request)
     (animation-group->visual-specs request 0 clip-duration clip-easing)]
    [(lagged-start-animation-request? request)
     (lagged-start->visual-specs request 0 clip-duration clip-easing)]
    [(style-to-animation-request? request)
     (style-to->visual-specs request 0 clip-duration clip-easing)]
    [else
     (raise-argument-error
      'request->visual-specs
      "Visual/scalar or camera request, timed composition, style transition, or composition animation request"
      request)]))

; style-to->visual-specs : style-to-animation-request?
;                          nonnegative-real? positive-real? easing?
;                          -> (listof visual-request-spec?)
;;   Expands unified style syntax to the existing independent primitive leaves.
(define (style-to->visual-specs style-request start duration easing)
  (animation-group->visual-specs
   (animation-group-animation-request
    (style-to-animation-request-requests style-request))
   start
   duration
   easing))

; composition-direct-child-span : composition-child-request? -> positive-real?
;;   Gives one direct child its intrinsic timing span before the parent interval
;;   is scaled. Historical unwrapped children remain one unit, so AO-AQ trees
;;   keep their old equal-share semantics. A timed child contributes its explicit
;;   delay plus active duration. Bare nested compositions still count as one
;;   direct child unless the caller wraps that composition with timed.
(define (composition-direct-child-span request)
  (if (timed-animation-request? request)
      (+ (timed-animation-request-start request)
         (timed-animation-request-duration request))
      1))

; composition-scale : symbol? positive-real? positive-real? -> positive-real?
;;   Returns the proportional mapping from intrinsic child units to the concrete
;;   interval allocated by the parent composition.
(define (composition-scale who duration intrinsic-duration)
  (define scale
    (/ duration intrinsic-duration))
  (unless (and (finite-real? scale)
               (positive? scale))
    (raise-arguments-error
     'scene-play
     "composition duration scale must be positive and finite"
     "composition" who
     "duration" duration
     "intrinsic-duration" intrinsic-duration))
  scale)

; succession->visual-specs : succession-animation-request?
;                            nonnegative-real? positive-real? easing?
;                            -> (listof visual-request-spec?)
;;   Expands a succession into consecutive child intervals. Unwrapped children
;;   retain equal shares. Nested timed children reserve start+duration intrinsic
;;   units, so explicit durations act as proportional weights inside the parent.
(define (succession->visual-specs succession-request start duration easing)
  (define requests
    (succession-animation-request-requests succession-request))
  (define spans
    (map composition-direct-child-span requests))
  (define intrinsic-duration
    (apply + spans))
  (define scale
    (composition-scale 'succession duration intrinsic-duration))
  (define interval-end
    (+ start duration))
  (define child-count
    (length requests))
  (let loop ([remaining-requests requests]
             [remaining-spans spans]
             [child-start start]
             [index 0]
             [specs '()])
    (cond
      [(null? remaining-requests)
       specs]
      [else
       (define child-duration
         (if (= index (sub1 child-count))
             (- interval-end child-start)
             (* (car remaining-spans) scale)))
       (unless (and (finite-real? child-duration)
                    (positive? child-duration))
         (raise-arguments-error
          'scene-play
          "succession child duration must be positive and finite"
          "duration" duration
          "child-index" index))
       (define child-specs
         (composition-request->visual-specs
          (car remaining-requests)
          child-start
          child-duration
          easing))
       (loop (cdr remaining-requests)
             (cdr remaining-spans)
             (+ child-start child-duration)
             (add1 index)
             (append specs child-specs))])))

; animation-group->visual-specs : animation-group-animation-request?
;                                  nonnegative-real? positive-real? easing?
;                                  -> (listof visual-request-spec?)
;;   Expands a parallel group. All children start together, while explicit timed
;;   child spans scale proportionally against the longest direct child. With no
;;   timed children every span is one and AP's full-interval behavior is exact.
(define (animation-group->visual-specs group-request start duration easing)
  (define requests
    (animation-group-animation-request-requests group-request))
  (define spans
    (map composition-direct-child-span requests))
  (define intrinsic-duration
    (apply max spans))
  (define scale
    (composition-scale 'animation-group duration intrinsic-duration))
  (apply
   append
   (for/list ([request (in-list requests)]
              [span (in-list spans)])
     (define child-duration
       (if (= span intrinsic-duration)
           duration
           (* span scale)))
     (composition-request->visual-specs
      request
      start
      child-duration
      easing))))

; lagged-start->visual-specs : lagged-start-animation-request?
;                              nonnegative-real? positive-real? easing?
;                              -> (listof visual-request-spec?)
;;   Expands a staggered group using each direct child's intrinsic span. Child 0
;;   starts at zero; each later raw start advances by lag-ratio times the prior
;;   child's span. The raw envelope is then scaled to the assigned outer interval.
;;   With unit spans this is exactly the SCENE-AQ formula. Consequently r=0 and
;;   r=1 remain parallel and succession timing even with explicit child spans.
(define (lagged-start->visual-specs lagged-request start duration easing)
  (define requests
    (lagged-start-animation-request-requests lagged-request))
  (define lag-ratio
    (lagged-start-animation-request-lag-ratio lagged-request))
  ;; Preserve the advertised limiting cases as exact scheduler identities, not
  ;; merely algebraically equivalent formulas. This also prevents inexact child
  ;; spans from introducing ulp-sized gaps/overlaps at r=0 or r=1.
  (cond
    [(zero? lag-ratio)
     (animation-group->visual-specs
      (animation-group-animation-request requests)
      start
      duration
      easing)]
    [(= lag-ratio 1)
     (succession->visual-specs
      (succession-animation-request requests)
      start
      duration
      easing)]
    [else
     (define spans
       (map composition-direct-child-span requests))
     (define raw-starts
       (let loop ([remaining-spans spans]
                  [raw-start 0]
                  [starts '()])
         (cond
           [(null? remaining-spans)
            (reverse starts)]
           [else
            (loop (cdr remaining-spans)
                  (+ raw-start (* lag-ratio (car remaining-spans)))
                  (cons raw-start starts))])))
     (define raw-ends
       (map + raw-starts spans))
     (define intrinsic-duration
       (apply max raw-ends))
     (define scale
       (composition-scale 'lagged-start duration intrinsic-duration))
     (define interval-end
       (+ start duration))
     (apply
      append
      (for/list ([request (in-list requests)]
                 [span (in-list spans)]
                 [raw-start (in-list raw-starts)]
                 [raw-end (in-list raw-ends)]
                 [index (in-naturals)])
        (define child-start
          (+ start (* raw-start scale)))
        ;; Any child that reaches the raw envelope endpoint is corrected against
        ;; the exact assigned endpoint, retaining AQ's inexact safeguard.
        (define child-duration
          (if (= raw-end intrinsic-duration)
              (- interval-end child-start)
              (* span scale)))
        (unless (and (finite-real? child-duration)
                     (positive? child-duration))
          (raise-arguments-error
           'scene-play
           "lagged-start child duration must be positive and finite"
           "duration" duration
           "child-index" index
           "lag-ratio" lag-ratio))
        (composition-request->visual-specs
         request
         child-start
         child-duration
         easing)))]))

; composition-request->visual-specs :
;   composition-child-request? nonnegative-real? positive-real? easing?
;   -> (listof visual-request-spec?)
;;   Expands one child inside the interval allocated by its parent composition.
;;   A nested timed wrapper scales its intrinsic start/duration proportionally
;;   into that interval and may contain either one leaf or one composition.
(define (composition-request->visual-specs request start duration easing)
  (cond
    [(timed-animation-request? request)
     (define intrinsic-start
       (timed-animation-request-start request))
     (define intrinsic-duration
       (timed-animation-request-duration request))
     (define intrinsic-span
       (+ intrinsic-start intrinsic-duration))
     (define scale
       (composition-scale 'timed duration intrinsic-span))
     (define active-start
       (+ start (* intrinsic-start scale)))
     ;; The timed child's active interval is the tail of its direct-child span,
     ;; so correct it against the exact assigned endpoint.
     (define active-duration
       (- (+ start duration) active-start))
     (expand-timed-content
      (timed-animation-request-request request)
      active-start
      active-duration
      (or (timed-animation-request-easing request)
          easing))]
    [(or (animation-request? request)
         (camera-animation-request? request))
     (list (visual-request-spec request start duration easing))]
    [(succession-animation-request? request)
     (succession->visual-specs request start duration easing)]
    [(animation-group-animation-request? request)
     (animation-group->visual-specs request start duration easing)]
    [(lagged-start-animation-request? request)
     (lagged-start->visual-specs request start duration easing)]
    [(style-to-animation-request? request)
     (style-to->visual-specs request start duration easing)]
    [else
     (raise-argument-error
      'composition-request->visual-specs
      "Visual/scalar or camera request, timed composition, style transition, or sequential/parallel/lagged composition"
      request)]))

; expand-timed-content : timable-request? nonnegative-real? positive-real?
;                        easing? -> (listof visual-request-spec?)
;;   Places the active content of a timed wrapper in one concrete interval.
(define (expand-timed-content request start duration easing)
  (cond
    [(or (animation-request? request)
         (camera-animation-request? request))
     (list (visual-request-spec request start duration easing))]
    [(succession-animation-request? request)
     (succession->visual-specs request start duration easing)]
    [(animation-group-animation-request? request)
     (animation-group->visual-specs request start duration easing)]
    [(lagged-start-animation-request? request)
     (lagged-start->visual-specs request start duration easing)]
    [(style-to-animation-request? request)
     (style-to->visual-specs request start duration easing)]
    [else
     (raise-argument-error
      'expand-timed-content
      "Visual/scalar or camera animation request, style transition, or sequential/parallel/lagged composition"
      request)]))

; compile-scheduled-visual-batches : scene-state? (listof visual-request-spec?)
;                                    -> (listof scheduled-visual-batch?)
;;   Compiles equal-start leaves together, so fade-in/create placeholders are
;;   available to simultaneous component requests exactly as in historical play.
(define (compile-scheduled-visual-batches start-state specs)
  (define grouped-specs
    (group-visual-specs-by-start specs))
  (let loop ([remaining grouped-specs]
             [compiled-batches '()])
    (cond
      [(null? remaining)
       compiled-batches]
      [else
       (define batch-specs
         (car remaining))
       (define batch-start
         (visual-request-spec-start (car batch-specs)))
       (define state-at-start
         (sample-scheduled-visual-state
          start-state
          compiled-batches
          batch-start))
       (define requests
         (for/list ([spec (in-list batch-specs)])
           (visual-request-spec-request spec)))
       (define-values (prepared-state compiled-animations)
         (compile-animation-requests state-at-start requests))
       (define introductions
         (scene-state-introductions state-at-start prepared-state))
       (define scheduled-animations
         (for/list ([spec (in-list batch-specs)]
                    [animation (in-list compiled-animations)])
           (scheduled-visual-animation
            (visual-request-spec-duration spec)
            (visual-request-spec-easing spec)
            animation)))
       (loop (cdr remaining)
             (append compiled-batches
                     (list
                      (scheduled-visual-batch
                       batch-start
                       introductions
                       scheduled-animations))))])))

; group-visual-specs-by-start : (listof visual-request-spec?) -> (listof list?)
;;   Sorts by local start while preserving request order among exact ties.
(define (group-visual-specs-by-start specs)
  (define starts
    (sort
     (remove-duplicates
      (for/list ([spec (in-list specs)])
        (visual-request-spec-start spec))
      =)
     <))
  (for/list ([start (in-list starts)])
    ;; Filtering the original request list preserves caller order within one
    ;; exact start batch independently of sort implementation details.
    (filter
     (lambda (spec)
       (= (visual-request-spec-start spec) start))
     specs)))

; scene-state-introductions : scene-state? scene-state? -> (listof visual?)
;;   Returns newly added Visuals in their prepared drawing order.
(define (scene-state-introductions before after)
  (for/list ([id (in-list (scene-state-drawing-order after))]
             #:unless (hash-has-key? (scene-state-visuals-by-id before) id))
    (scene-state-ref after id)))

; sample-scheduled-visual-state : scene-state?
;                                 (listof scheduled-visual-batch?)
;                                 nonnegative-real?
;                                 -> scene-state?
;;   Samples a compiled local Visual schedule directly at local-time. Event
;;   boundaries are processed semantically: old component endpoints first, then
;;   structural finalization, then same-time introductions and new progress-zero
;;   values. No rendered or earlier sampled frame is required.
(define (sample-scheduled-visual-state start-state batches local-time
                                       #:finalize-at-time?
                                       [finalize-at-time? #t])
  (define events
    (scheduled-event-times-through batches local-time))
  (let loop ([state start-state]
             [active '()]
             [remaining-events events]
             [last-event #f])
    (cond
      [(null? remaining-events)
       (if (and last-event (< last-event local-time))
           (sample-active-scheduled-components state active local-time)
           state)]
      [else
       (define event-time
         (car remaining-events))
       ;; Existing active leaves reach this boundary before any structural end
       ;; rule runs. This is what makes same-boundary fade-out + movement
       ;; independent of request start order.
       (define boundary-component-state
         (sample-active-scheduled-components state active event-time))
       (define ending
         (filter
          (lambda (entry)
            (and (<= (active-scheduled-end entry) event-time)
                 ;; Camera-follow needs the pre-removal motion value at its
                 ;; own endpoint, just as historical full-clip follow does.
                 ;; Earlier endpoints are still finalized normally.
                 (or finalize-at-time?
                     (< event-time local-time))))
          active))
       (define finalized-state
         (for/fold ([finalized boundary-component-state])
                   ([entry (in-list ending)])
           (finalize-compiled-animation
            finalized
            (scheduled-visual-animation-animation
             (active-scheduled-visual-animation-scheduled entry)))))
       (define continuing
         (filter
          (lambda (entry)
            (or (> (active-scheduled-end entry) event-time)
                (and (not finalize-at-time?)
                     (= event-time local-time)
                     (= (active-scheduled-end entry) event-time))))
          active))
       (define starting-batches
         (filter
          (lambda (batch)
            (= (scheduled-visual-batch-start batch) event-time))
          batches))
       (define introduced-state
         (for*/fold ([prepared finalized-state])
                    ([batch (in-list starting-batches)]
                     [visual
                      (in-list
                       (scheduled-visual-batch-introductions batch))])
           (scene-state-add prepared visual)))
       (define new-active
         (for*/list ([batch (in-list starting-batches)]
                     [scheduled
                      (in-list
                       (scheduled-visual-batch-animations batch))])
           (active-scheduled-visual-animation event-time scheduled)))
       ;; Evaluate local easing at progress zero exactly at a start boundary.
       ;; This preserves the historical rule that unusual easing functions need
       ;; not map zero to zero.
       (define started-state
         (sample-active-scheduled-components
          introduced-state
          new-active
          event-time))
       (loop started-state
             (append continuing new-active)
             (cdr remaining-events)
             event-time)])))

; scheduled-event-times-through : (listof scheduled-visual-batch?) finite-real?
;                                 -> (listof finite-real?)
;;   Returns sorted unique local starts and ends no later than local-time.
(define (scheduled-event-times-through batches local-time)
  (define raw-times
    (append
     (for/list ([batch (in-list batches)]
                #:when (<= (scheduled-visual-batch-start batch) local-time))
       (scheduled-visual-batch-start batch))
     (for*/list ([batch (in-list batches)]
                 [scheduled
                  (in-list (scheduled-visual-batch-animations batch))]
                 #:when
                 (<= (+ (scheduled-visual-batch-start batch)
                        (scheduled-visual-animation-duration scheduled))
                     local-time))
       (+ (scheduled-visual-batch-start batch)
          (scheduled-visual-animation-duration scheduled)))))
  (sort (remove-duplicates raw-times =) <))

; active-scheduled-end : active-scheduled-visual-animation? -> finite-real?
;;   Returns one active leaf's local endpoint.
(define (active-scheduled-end entry)
  (+ (active-scheduled-visual-animation-start entry)
     (scheduled-visual-animation-duration
      (active-scheduled-visual-animation-scheduled entry))))

; sample-active-scheduled-components : scene-state? list? finite-real?
;                                      -> scene-state?
;;   Samples ordinary component values for active leaves in deterministic
;;   start/request order, without applying structural endpoint rules.
(define (sample-active-scheduled-components state active local-time)
  (for/fold ([sampled state])
            ([entry (in-list active)])
    (sample-scheduled-visual-animation-components
     sampled
     (active-scheduled-visual-animation-scheduled entry)
     (active-scheduled-visual-animation-start entry)
     local-time)))

; sample-scheduled-visual-animation-components : scene-state?
;                                                scheduled-visual-animation?
;                                                finite-real?
;                                                finite-real?
;                                                -> scene-state?
;;   Samples one local leaf's ordinary component values, clamping at its local
;;   endpoint but deliberately postponing structural completion.
(define (sample-scheduled-visual-animation-components
         state scheduled start local-time)
  (define duration
    (scheduled-visual-animation-duration scheduled))
  (define easing
    (scheduled-visual-animation-easing scheduled))
  (define animation
    (scheduled-visual-animation-animation scheduled))
  (define end
    (+ start duration))
  (define progress
    (cond
      [(<= local-time start) 0]
      [(>= local-time end) 1]
      [else
       (/ (- local-time start) duration)]))
  (apply-compiled-animations
   state
   (list animation)
   progress
   easing))


;;;
;;; Scheduled Camera Compilation and Sampling
;;;

; compile-scheduled-camera-animations : camera? scene-state?
;                                        (listof scheduled-visual-batch?)
;                                        (listof visual-request-spec?)
;                                        -> (listof scheduled-camera-animation?)
;;   Compiles locally timed camera leaves in start/request order. Each leaf is
;;   based on the exact camera and Visual states at its local start, so a later
;;   pan or zoom begins from the completed value of an earlier one rather than
;;   from the enclosing clip start.
(define (compile-scheduled-camera-animations start-camera
                                              start-state
                                              visual-batches
                                              specs)
  (define ordered-specs
    (append-map
     (lambda (batch) batch)
     (group-visual-specs-by-start specs)))
  (let loop ([remaining ordered-specs]
             [compiled '()])
    (cond
      [(null? remaining)
       compiled]
      [else
       (define spec
         (car remaining))
       (define local-start
         (visual-request-spec-start spec))
       (define local-duration
         (visual-request-spec-duration spec))
       (define local-end
         (+ local-start local-duration))
       (define (visual-motion-state-at local-time)
         (sample-scheduled-visual-state
          start-state visual-batches local-time
          #:finalize-at-time? #f))
       (define camera-at-start
         (sample-scheduled-camera
          start-camera
          compiled
          local-start
          visual-motion-state-at))
       (define compiled-leaf
         (compile-camera-animation-requests
          camera-at-start
          (visual-motion-state-at local-start)
          (visual-motion-state-at local-end)
          (list (visual-request-spec-request spec))))
       (loop
        (cdr remaining)
        (append
         compiled
         (list
          (scheduled-camera-animation
           local-start
           local-duration
           (visual-request-spec-easing spec)
           (car compiled-leaf)))))])))

; sample-scheduled-camera : camera?
;                           (listof scheduled-camera-animation?)
;                           nonnegative-real?
;                           (-> nonnegative-real? scene-state?)
;                           -> camera?
;;   Samples the latest started transition for each camera component. Scheduled
;;   component conflicts guarantee that those selections never overlap on the
;;   same component; a pan/follow and a zoom may, however, run together.
(define (sample-scheduled-camera start-camera animations local-time state-at)
  (define width-entry
    (latest-scheduled-camera-entry animations local-time 'world-width))
  (define center-entry
    (latest-scheduled-camera-entry animations local-time 'center))
  (define camera-with-width
    (if width-entry
        (sample-scheduled-camera-entry
         start-camera width-entry local-time state-at)
        start-camera))
  (cond
    [(not center-entry)
     camera-with-width]
    [(eq? center-entry width-entry)
     ;; A camera-fit supplies both components together and has already been
     ;; sampled above.
     camera-with-width]
    [else
     (sample-scheduled-camera-entry
      camera-with-width center-entry local-time state-at)]))

; latest-scheduled-camera-entry : (listof scheduled-camera-animation?)
;                                 nonnegative-real? symbol?
;                                 -> (or/c scheduled-camera-animation? false/c)
;;   Returns the latest entry begun by local-time that writes component. The
;;   compile order is chronological and preserves user order for equal starts.
(define (latest-scheduled-camera-entry animations local-time component)
  (for/fold ([latest #f])
            ([entry (in-list animations)]
             #:when
             (and (<= (scheduled-camera-animation-start entry) local-time)
                  (memq component
                        (compiled-camera-animation-components
                         (scheduled-camera-animation-animation entry)))))
    entry))

; sample-scheduled-camera-entry : camera? scheduled-camera-animation?
;                                  nonnegative-real?
;                                  (-> nonnegative-real? scene-state?)
;                                  -> camera?
;;   Samples one scheduled leaf. A completed follow receives the Visual motion
;;   state at its own endpoint, preventing it from accidentally tracking later
;;   unrelated movement after its scheduled interval ends.
(define (sample-scheduled-camera-entry camera entry local-time state-at)
  (define start
    (scheduled-camera-animation-start entry))
  (define duration
    (scheduled-camera-animation-duration entry))
  (define end
    (+ start duration))
  (define effective-time
    (min local-time end))
  (define progress
    (cond
      [(<= effective-time start) 0]
      [(>= effective-time end) 1]
      [else
       (/ (- effective-time start) duration)]))
  (apply-compiled-camera-animations
   camera
   (list (scheduled-camera-animation-animation entry))
   progress
   (scheduled-camera-animation-easing entry)
   (state-at effective-time)))

;;;
;;; Timeline Sampling
;;;

; scene-sample : scene? nonnegative-real? -> scene-state?
;;   Returns the complete Visual scene state at absolute time.
(define (scene-sample scn time)
  (check-scene-sample-arguments 'scene-sample scn time)
  (cond
    [(scene-endpoint-time? scn time)
     (scene-current-state scn)]
    [else
     (clip->state-at
      (scene-clip-at/internal 'scene-sample scn time)
      time)]))

; scene-camera-at : scene? nonnegative-real? -> camera?
;;   Returns the complete camera state at absolute time.
(define (scene-camera-at scn time)
  (check-scene-sample-arguments 'scene-camera-at scn time)
  (cond
    [(scene-endpoint-time? scn time)
     (scene-current-camera scn)]
    [else
     (clip->camera-at
      (scene-clip-at/internal 'scene-camera-at scn time)
      time)]))

; scene-sample-with-camera : scene? nonnegative-real?
;                            -> (values scene-state? camera?)
;;   Returns Visual and camera states using the clip's timing semantics.
(define (scene-sample-with-camera scn time)
  (check-scene-sample-arguments 'scene-sample-with-camera scn time)
  (cond
    [(scene-endpoint-time? scn time)
     (values (scene-current-state scn)
             (scene-current-camera scn))]
    [else
     (clip->scene-values-at
      (scene-clip-at/internal 'scene-sample-with-camera scn time)
      time)]))

; scene-endpoint-time? : scene? nonnegative-real? -> boolean?
;;   Reports whether time selects the scene's stored endpoint values.
(define (scene-endpoint-time? scn time)
  (or (null? (scene-clips scn))
      (= time (scene-duration scn))))

; scene-clip-at/internal : symbol? scene? nonnegative-real?
;                 -> (or/c play-clip? timed-play-clip? wait-clip?)
;;   Returns the timeline clip at time or raises an error for a broken timeline.
(define (scene-clip-at/internal who scn time)
  (define clip
    (find-clip-at scn time))
  (unless clip
    (raise-arguments-error
     who
     "no timeline clip covers the requested time"
     "time" time))
  clip)

; scene-clip-at : scene? nonnegative-real?
;                 -> (or/c play-clip? timed-play-clip? wait-clip? false/c)
;; Returns the clip selected by `time`.  Normal boundaries use the clip that
;; begins there; the exact scene endpoint returns the final completed clip so
;; inspection clients can still explain its final transition.  An empty scene
;; has no clip and returns #f.
(define (scene-clip-at scn time)
  (check-scene-sample-arguments 'scene-clip-at scn time)
  (cond
    [(null? (scene-clips scn)) #f]
    [(= time (scene-duration scn)) (last (scene-clips scn))]
    [else (find-clip-at scn time)]))

; scene-clip-index-at : scene? nonnegative-real? -> (or/c exact-nonnegative-integer? false/c)
;; Returns the zero-based index of `scene-clip-at`, or #f for an empty scene.
(define (scene-clip-index-at scn time)
  (define clip (scene-clip-at scn time))
  (and clip
       (for/first ([candidate (in-list (scene-clips scn))]
                   [index (in-naturals)]
                   #:when (eq? candidate clip))
         index)))

; scene-animation-inspections-at : scene? nonnegative-real?
;;                                  -> (listof animation-inspection?)
;; Retrieves retained inspection data for the animations relevant at `time`.
;; Scheduled clips include only their currently active leaves, except at the
;; exact scene endpoint where the final clip's complete metadata is retained.
(define (scene-animation-inspections-at scn time)
  (define clip (scene-clip-at scn time))
  (cond
    [(not clip) '()]
    [(play-clip? clip)
     (compiled-animations->inspections (play-clip-animations clip))]
    [(timed-play-clip? clip)
     (define local-time
       (timed-clip-local-time clip time))
     (define endpoint?
       (= time (scene-duration scn)))
     (append*
      (for/list ([batch (in-list (timed-play-clip-visual-batches clip))]
                 #:when (or endpoint?
                            (<= (scheduled-visual-batch-start batch)
                                local-time)))
        (compiled-animations->inspections
         (for/list ([scheduled
                     (in-list (scheduled-visual-batch-animations batch))]
                    #:when
                    (or endpoint?
                        (< local-time
                           (+ (scheduled-visual-batch-start batch)
                              (scheduled-visual-animation-duration scheduled)))))
           (scheduled-visual-animation-animation scheduled)))))]
    [else '()]))

(define (compiled-animations->inspections animations)
  (filter values
          (for/list ([animation (in-list animations)])
            (compiled-animation-inspection animation))))

; scene-clip-count : scene? -> exact-nonnegative-integer?
;;   Returns the number of chronological clips in scene.
(define (scene-clip-count scn)
  (unless (scene? scn)
    (raise-argument-error 'scene-clip-count "scene?" scn))
  (length (scene-clips scn)))

; find-clip-at : scene? nonnegative-real?
;                -> (or/c play-clip? timed-play-clip? wait-clip? false/c)
;;   Finds the half-open clip interval containing time.
(define (find-clip-at scn time)
  (for/first ([clip (in-list (scene-clips scn))]
              #:when (clip-contains? clip time))
    clip))

; clip->state-at : (or/c play-clip? timed-play-clip? wait-clip?) real?
;                  -> scene-state?
;;   Samples only the Visual state of clip at absolute time.
(define (clip->state-at clip time)
  (cond
    [(play-clip? clip)
     (define animations
       (play-clip-animations clip))
     (if (null? animations)
         (play-clip-start-state clip)
         (apply-compiled-animations
          (play-clip-start-state clip)
          animations
          (clip-progress clip time)
          (play-clip-easing clip)))]
    [(timed-play-clip? clip)
     (sample-scheduled-visual-state
      (timed-play-clip-start-state clip)
      (timed-play-clip-visual-batches clip)
      (timed-clip-local-time clip time))]
    [(wait-clip? clip)
     (wait-clip-state clip)]
    [else
     (raise-argument-error
      'clip->state-at
      "(or/c play-clip? timed-play-clip? wait-clip?)"
      clip)]))

; clip->camera-at : (or/c play-clip? timed-play-clip? wait-clip?) real? -> camera?
;;   Samples only the camera state of clip at absolute time.
(define (clip->camera-at clip time)
  (cond
    [(play-clip? clip)
     (define camera-animations
       (play-clip-camera-animations clip))
     (cond
       [(null? camera-animations)
        (play-clip-start-camera clip)]
       [(compiled-camera-animations-require-scene-state?
         camera-animations)
        (define-values (_sampled-state sampled-camera)
          (clip->scene-values-at clip time))
        sampled-camera]
       [else
        (apply-compiled-camera-animations
         (play-clip-start-camera clip)
         camera-animations
         (clip-progress clip time)
         (play-clip-easing clip))])]
    [(timed-play-clip? clip)
     (define local-time
       (timed-clip-local-time clip time))
     (sample-scheduled-camera
      (timed-play-clip-start-camera clip)
      (timed-play-clip-camera-animations clip)
      local-time
      (lambda (sample-time)
        (sample-scheduled-visual-state
         (timed-play-clip-start-state clip)
         (timed-play-clip-visual-batches clip)
         sample-time
         #:finalize-at-time? #f)))]
    [(wait-clip? clip)
     (wait-clip-camera clip)]
    [else
     (raise-argument-error
      'clip->camera-at
      "(or/c play-clip? timed-play-clip? wait-clip?)"
      clip)]))

; clip->scene-values-at : (or/c play-clip? timed-play-clip? wait-clip?) real?
;                           -> (values scene-state? camera?)
;;   Samples Visual and camera states of clip at absolute time.
(define (clip->scene-values-at clip time)
  (cond
    [(play-clip? clip)
     (define progress
       (clip-progress clip time))
     (define eased-progress
       (scene-eased-progress (play-clip-easing clip)
                             progress))
     (define sampled-state
       (apply-compiled-animations
        (play-clip-start-state clip)
        (play-clip-animations clip)
        eased-progress
        linear
        #:write-progress progress
        #:write-scene-rate-func (play-clip-easing clip)))
     (values
      sampled-state
      (apply-compiled-camera-animations
       (play-clip-start-camera clip)
       (play-clip-camera-animations clip)
       eased-progress
       linear
       sampled-state))]
    [(timed-play-clip? clip)
     (define local-time
       (timed-clip-local-time clip time))
     (define sampled-state
       (sample-scheduled-visual-state
        (timed-play-clip-start-state clip)
        (timed-play-clip-visual-batches clip)
        local-time))
     (values
      sampled-state
      (sample-scheduled-camera
       (timed-play-clip-start-camera clip)
       (timed-play-clip-camera-animations clip)
       local-time
       (lambda (sample-time)
         (sample-scheduled-visual-state
          (timed-play-clip-start-state clip)
          (timed-play-clip-visual-batches clip)
          sample-time
          #:finalize-at-time? #f))))]
    [(wait-clip? clip)
     (values (wait-clip-state clip)
             (wait-clip-camera clip))]
    [else
     (raise-argument-error
      'clip->scene-values-at
      "(or/c play-clip? timed-play-clip? wait-clip?)"
      clip)]))

; clip-progress : play-clip? real? -> real?
;;   Returns normalized progress for time within a historical play clip.
(define (clip-progress clip time)
  (/ (- time (play-clip-start-time clip))
     (play-clip-duration clip)))

; timed-clip-local-time : timed-play-clip? real? -> real?
;;   Returns local seconds from the timed clip start.
(define (timed-clip-local-time clip time)
  (- time (timed-play-clip-start-time clip)))

; clip-contains? : (or/c play-clip? timed-play-clip? wait-clip?) real? -> boolean?
;;   Reports whether clip contains time in its half-open interval.
(define (clip-contains? clip time)
  (cond
    [(play-clip? clip)
     (time-in-interval? time
                        (play-clip-start-time clip)
                        (play-clip-duration clip))]
    [(timed-play-clip? clip)
     (time-in-interval? time
                        (timed-play-clip-start-time clip)
                        (timed-play-clip-duration clip))]
    [(wait-clip? clip)
     (time-in-interval? time
                        (wait-clip-start-time clip)
                        (wait-clip-duration clip))]
    [else
     #f]))

; time-in-interval? : real? real? real? -> boolean?
;;   Reports whether time lies in the half-open interval [start, start+duration).
(define (time-in-interval? time start duration)
  (and (<= start time)
       (< time (+ start duration))))


; scene-eased-progress : (-> real? real?) finite-real? -> real?
;;   Evaluates easing once and returns a finite value clamped to [0, 1].
(define (scene-eased-progress easing progress)
  (define clamped-progress
    (min 1 (max 0 progress)))
  (define value
    (easing clamped-progress))
  (unless (finite-real? value)
    (raise-arguments-error
     'animation-easing
     "an easing function must produce a finite real number"
     "result" value))
  (min 1 (max 0 value)))


;;;
;;; Scheduled Validation
;;;

; check-scheduled-component-conflicts : (listof visual-request-spec?) -> void?
;;   Rejects overlapping updates to the same target component. Touching local
;;   intervals are legal and permit deterministic succession boundaries.
(define (check-scheduled-component-conflicts specs)
  (let outer ([remaining specs])
    (when (pair? remaining)
      (define left
        (car remaining))
      (for ([right (in-list (cdr remaining))])
        (define left-request
          (visual-request-spec-request left))
        (define right-request
          (visual-request-spec-request right))
        (when (and
               (equal? (animation-request-component-target-id left-request)
                       (animation-request-component-target-id right-request))
               (intervals-overlap?
                (visual-request-spec-start left)
                (visual-request-spec-duration left)
                (visual-request-spec-start right)
                (visual-request-spec-duration right)))
          (define duplicate-component
            (for/first ([component
                         (in-list
                          (animation-request-components left-request))]
                        #:when
                        (memq component
                              (animation-request-components right-request)))
              component))
          (when duplicate-component
            (raise-arguments-error
             'scene-play
             "two overlapping scheduled animations target the same animation component"
             "target-id" (animation-request-component-target-id left-request)
             "component" duplicate-component
             "first-interval"
             (cons (visual-request-spec-start left)
                   (+ (visual-request-spec-start left)
                      (visual-request-spec-duration left)))
             "second-interval"
             (cons (visual-request-spec-start right)
                   (+ (visual-request-spec-start right)
                      (visual-request-spec-duration right)))))))
      (outer (cdr remaining)))))

; check-scheduled-removal-boundaries : (listof visual-request-spec?) -> void?
;;   Rejects an animation that remains active after the same target is removed.
;;   Reintroduction at the exact removal boundary remains legal.
(define (check-scheduled-removal-boundaries specs)
  (for ([removal (in-list specs)]
        #:when
        (removing-animation-request?
         (visual-request-spec-request removal)))
    (define removal-request
      (visual-request-spec-request removal))
    (define target-id
      (animation-request-target-id removal-request))
    (define removal-end
      (+ (visual-request-spec-start removal)
         (visual-request-spec-duration removal)))
    (for ([other (in-list specs)]
          #:unless (eq? removal other))
      (define other-request
        (visual-request-spec-request other))
      (when (and (equal? target-id
                         (animation-request-target-id other-request))
                 (< (visual-request-spec-start other) removal-end)
                 (> (+ (visual-request-spec-start other)
                       (visual-request-spec-duration other))
                    removal-end))
        (raise-arguments-error
         'scene-play
         "an animation cannot remain active after its target is removed"
         "target-id" target-id
         "removal-time" removal-end
         "animation-start" (visual-request-spec-start other)
         "animation-end" (+ (visual-request-spec-start other)
                             (visual-request-spec-duration other)))))))

; check-scheduled-camera-component-conflicts :
;   (listof visual-request-spec?) -> void?
;;   Rejects positive-measure overlap on center or world-width while permitting
;;   a pan/follow and zoom to run together. Touching intervals provide the
;;   normal deterministic handoff for camera successions.
(define (check-scheduled-camera-component-conflicts specs)
  (let outer ([remaining specs])
    (when (pair? remaining)
      (define left
        (car remaining))
      (for ([right (in-list (cdr remaining))])
        (when
            (intervals-overlap?
             (visual-request-spec-start left)
             (visual-request-spec-duration left)
             (visual-request-spec-start right)
             (visual-request-spec-duration right))
          (define left-components
            (camera-animation-request-components
             (visual-request-spec-request left)))
          (define right-components
            (camera-animation-request-components
             (visual-request-spec-request right)))
          (define duplicate-component
            (for/first ([component (in-list left-components)]
                        #:when (memq component right-components))
              component))
          (when duplicate-component
            (raise-arguments-error
             'scene-play
             "two overlapping scheduled camera animations target the same camera component"
             "component" duplicate-component
             "first-interval"
             (cons (visual-request-spec-start left)
                   (+ (visual-request-spec-start left)
                      (visual-request-spec-duration left)))
             "second-interval"
             (cons (visual-request-spec-start right)
                   (+ (visual-request-spec-start right)
                      (visual-request-spec-duration right))))))
      (outer (cdr remaining))))))

; removing-animation-request? : animation-request? -> boolean?
;;   Reports whether request removes its whole top-level target at completion.
(define (removing-animation-request? request)
  (or (fade-out-request? request)
      (uncreate-request? request)
      (reveal-out-request? request)
      (and (leave-request? request)
           (leave-request-remove-at-end? request))))

; intervals-overlap? : real? positive-real? real? positive-real? -> boolean?
;;   Reports positive-measure overlap; touching endpoints do not overlap.
(define (intervals-overlap? left-start left-duration right-start right-duration)
  (< (max left-start right-start)
     (min (+ left-start left-duration)
          (+ right-start right-duration))))


;;;
;;; General Validation
;;;

; supported-scene-play-request? : any/c -> boolean?
;;   Reports whether value can occur directly in scene-play.
(define (supported-scene-play-request? value)
  (or (animation-request? value)
      (timed-animation-request? value)
      (succession-animation-request? value)
      (animation-group-animation-request? value)
      (lagged-start-animation-request? value)
      (style-to-animation-request? value)
      (camera-animation-request? value)))

; visual-scene-play-request? : any/c -> boolean?
;;   Reports whether value contributes one or more Visual/scalar schedule leaves.
(define (visual-scene-play-request? value)
  (or (animation-request? value)
      (timed-animation-request? value)
      (succession-animation-request? value)
      (animation-group-animation-request? value)
      (lagged-start-animation-request? value)
      (style-to-animation-request? value)))

; scheduled-scene-play-request? : any/c -> boolean?
;;   Reports whether value requires the local scheduler rather than legacy play.
(define (scheduled-scene-play-request? value)
  (or (timed-animation-request? value)
      (succession-animation-request? value)
      (animation-group-animation-request? value)
      (lagged-start-animation-request? value)
      (style-to-animation-request? value)))

; timable-visual-request? : any/c -> boolean?
;;   Reports whether value may be wrapped by timed. Nested timed wrappers remain
;;   intentionally unsupported, while camera leaves share the ordinary local
;;   scheduling rules.
(define (timable-visual-request? value)
  (or (animation-request? value)
      (camera-animation-request? value)
      (succession-animation-request? value)
      (animation-group-animation-request? value)
      (lagged-start-animation-request? value)
      (style-to-animation-request? value)))

; composition-child-request? : any/c -> boolean?
;;   Reports whether value may occur directly inside a sequential/parallel/lagged
;;   composition. Timed Visual/camera composition wrappers and style transitions
;;   may nest like other composition leaves.
(define (composition-child-request? value)
  (or (timed-animation-request? value)
      (timable-visual-request? value)))

; check-composition-children : symbol? list? list? -> void?
;;   Validates a public composition constructor after optional single-list
;;   normalization. Composition values copy their child spine immutably.
(define (check-composition-children who animations requests)
  (when (null? requests)
    (raise-arguments-error
     who
     "at least one Visual or scalar animation is required"
     "animations" animations))
  (unless (andmap composition-child-request? requests)
    (raise-argument-error
     who
     "list of Visual/scalar or camera requests, timed compositions, style transitions, or sequential/parallel/lagged compositions"
     requests)))

; normalize-animation-requests : list? -> list?
;;   Unwraps the convenient single-list form accepted by play/composition APIs.
(define (normalize-animation-requests animations)
  (if (and (= (length animations) 1)
           (list? (car animations)))
      (car animations)
      animations))

; normalize-stagger-targets : any/c -> (listof any/c)
;; Copies the source collection's spine before construction.  A concrete list
;; makes source order explicit and prevents a mutable input vector from
;; changing the target collection during factory evaluation.
(define (normalize-stagger-targets targets [who 'stagger-map])
  (cond
    [(list? targets)
     (when (null? targets)
       (raise-arguments-error
        who
        "at least one target is required"
        "targets" targets))
     (for/list ([target (in-list targets)])
       target)]
    [(vector? targets)
     (when (zero? (vector-length targets))
       (raise-arguments-error
        who
        "at least one target is required"
        "targets" targets))
     (for/list ([target (in-vector targets)])
       target)]
    [else
     (raise-argument-error who "list? or vector?" targets)]))

; check-stagger-order : any/c -> void?
(define (check-stagger-order order [who 'stagger-map])
  (unless (or (memq order '(forward reverse))
              (animation-order? order))
    (raise-argument-error
     who
     "(or/c 'forward 'reverse animation-order?)"
     order)))

; call-stagger-factory : list? any/c -> (listof composition-child-request?)
;; Calls the factory exactly once per source target, in source order.  If it
;; accepts both one and two arguments, the two-argument form is deliberately
;; selected so callers receive the stable original source index.
(define (call-stagger-factory source-targets make-request [who 'stagger-map])
  (unless (procedure? make-request)
    (raise-argument-error who "procedure?" make-request))
  (define accepts-one?
    (procedure-arity-includes? make-request 1))
  (define accepts-two?
    (procedure-arity-includes? make-request 2))
  (unless (or accepts-one? accepts-two?)
    (raise-arguments-error
     who
     "request factory must accept one target argument or target and source-index arguments"
     "make-request" make-request))
  (for/list ([target (in-list source-targets)]
             [source-index (in-naturals)])
    (define request
      (with-handlers ([exn:fail?
                       (lambda (exception)
                         (raise-arguments-error
           who
                          "request factory raised an exception"
                          "source-index" source-index
                          "target" target
                          "exception-message" (exn-message exception)))])
        (if accepts-two?
            (make-request target source-index)
            (make-request target))))
    (unless (composition-child-request? request)
      (raise-arguments-error
       who
       "request factory must produce a valid composition child"
       "source-index" source-index
       "target" target
       "request" request))
    request))

; order-stagger-children : list? order-spec? -> list?
;; The input is already concrete and source-ordered. Reordering here cannot
;; affect factory evaluation or source indexes.
(define (order-stagger-children children order)
  (define plan
    (cond
      [(eq? order 'forward) (forward-order)]
      [(eq? order 'reverse) (reverse-order)]
      [else order]))
  (for/list ([index (in-vector
                     (resolve-animation-order plan (length children)))])
    (list-ref children index)))

; check-scene-sample-arguments : symbol? any/c any/c -> void?
;;   Validates a scene and a time in its closed timeline interval.
(define (check-scene-sample-arguments who scn time)
  (unless (scene? scn)
    (raise-argument-error who "scene?" scn))
  (unless (and (finite-real? time)
               (not (negative? time))
               (<= time (scene-duration scn)))
    (raise-arguments-error
     who
     "time must be a finite real in the closed scene interval"
     "time" time
     "scene-duration" (scene-duration scn))))

; check-nonnegative-time : symbol? any/c -> void?
;;   Raises an argument error unless time is nonnegative and finite.
(define (check-nonnegative-time who time)
  (unless (and (finite-real? time)
               (not (negative? time)))
    (raise-argument-error who "nonnegative finite real?" time)))

; check-positive-duration : symbol? any/c -> void?
;;   Raises an argument error unless duration is positive and finite.
(define (check-positive-duration who duration)
  (unless (and (finite-real? duration)
               (positive? duration))
    (raise-argument-error who "positive finite real?" duration)))

; check-easing : symbol? any/c -> void?
;;   Raises an argument error unless easing accepts one argument.
(define (check-easing who easing)
  (unless (and (procedure? easing)
               (procedure-arity-includes? easing 1))
    (raise-argument-error
     who
     "(procedure-arity-includes/c 1)"
     easing)))
