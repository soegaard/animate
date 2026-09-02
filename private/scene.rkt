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
         "camera-animation.rkt"
         "camera.rkt"
         "geometry.rkt"
         "parameter.rkt"
         "scene-state.rkt")

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
         scene-clip-count)


;;;
;;; Data Representation
;;;

(struct timed-animation-request (request start duration easing)
  #:transparent)

;; timed-animation-request wraps one Visual leaf or composition with local timing.
;;  - request   timable-visual-request?          Visual request/composition to schedule.
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
;; expansion and explicit timed-child scaling. Camera requests
;; deliberately remain full-clip requests, while camera-follow samples the
;; actual locally scheduled Visual state.

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

; timed : timable-visual-request?
;         [#:start nonnegative-real?]
;         [#:duration positive-real?]
;         [#:easing (or/c false/c (-> real? real?))]
;         -> timed-animation-request?
;;   Adds local timing to one Visual leaf or composition. A false easing inherits
;;   the enclosing timing context. Camera requests and another
;;   timed wrapper are not accepted, but style and sequential/parallel/lagged
;;   compositions may be wrapped directly.
(define (timed request
               #:start [start 0]
               #:duration [duration 1]
               #:easing [easing #f])
  (unless (timable-visual-request? request)
    (raise-argument-error
     'timed
     "Visual/scalar animation request, style transition, or sequential/parallel/lagged composition"
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
  (define visual-specs
    (append-map
     (lambda (request)
       (request->visual-specs request duration easing))
     (filter visual-scene-play-request? requests)))
  (define camera-requests
    (filter camera-animation-request? requests))
  (check-scheduled-component-conflicts visual-specs)
  (check-scheduled-removal-boundaries visual-specs)
  (define start-state
    (scene-current-state scn))
  (define visual-batches
    (compile-scheduled-visual-batches start-state visual-specs))
  (define end-state
    (sample-scheduled-visual-state start-state visual-batches duration))
  (define start-camera
    (scene-current-camera scn))
  (define camera-start-state
    (if (ormap camera-follow-request? camera-requests)
        (sample-scheduled-visual-state start-state visual-batches 0)
        start-state))
  (define compiled-camera-animations
    (compile-camera-animation-requests start-camera
                                       camera-start-state
                                       end-state
                                       camera-requests))
  (define clip
    (timed-play-clip (scene-duration scn)
                     duration
                     start-state
                     start-camera
                     visual-batches
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
     end-state))
  (define end-camera
    (complete-compiled-camera-animations start-camera
                                         compiled-camera-animations
                                         endpoint-easing
                                         endpoint-motion-state))
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
;                                 timed-animation-request?
;                                 succession-animation-request?
;                                 animation-group-animation-request?
;                                 lagged-start-animation-request?)
;                         positive-real? easing?
;                         -> (listof visual-request-spec?)
;;   Resolves one top-level Visual request into concrete local schedule leaves.
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
    [(animation-request? request)
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
      "Visual/scalar, timed composition, style transition, or composition animation request"
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
    [(animation-request? request)
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
      "Visual/scalar, timed composition, style transition, or sequential/parallel/lagged composition"
      request)]))

; expand-timed-content : timable-visual-request? nonnegative-real? positive-real?
;                        easing? -> (listof visual-request-spec?)
;;   Places the active content of a timed wrapper in one concrete interval.
(define (expand-timed-content request start duration easing)
  (cond
    [(animation-request? request)
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
      "Visual/scalar animation request, style transition, or sequential/parallel/lagged composition"
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
(define (sample-scheduled-visual-state start-state batches local-time)
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
            (<= (active-scheduled-end entry) event-time))
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
            (> (active-scheduled-end entry) event-time))
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
      (scene-clip-at 'scene-sample scn time)
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
      (scene-clip-at 'scene-camera-at scn time)
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
      (scene-clip-at 'scene-sample-with-camera scn time)
      time)]))

; scene-endpoint-time? : scene? nonnegative-real? -> boolean?
;;   Reports whether time selects the scene's stored endpoint values.
(define (scene-endpoint-time? scn time)
  (or (null? (scene-clips scn))
      (= time (scene-duration scn))))

; scene-clip-at : symbol? scene? nonnegative-real?
;                 -> (or/c play-clip? timed-play-clip? wait-clip?)
;;   Returns the timeline clip at time or raises an error for a broken timeline.
(define (scene-clip-at who scn time)
  (define clip
    (find-clip-at scn time))
  (unless clip
    (raise-arguments-error
     who
     "no timeline clip covers the requested time"
     "time" time))
  clip)

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
     (define camera-animations
       (timed-play-clip-camera-animations clip))
     (cond
       [(null? camera-animations)
        (timed-play-clip-start-camera clip)]
       [(compiled-camera-animations-require-scene-state?
         camera-animations)
        (define-values (_sampled-state sampled-camera)
          (clip->scene-values-at clip time))
        sampled-camera]
       [else
        (apply-compiled-camera-animations
         (timed-play-clip-start-camera clip)
         camera-animations
         (timed-clip-progress clip time)
         (timed-play-clip-easing clip))])]
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
     (define eased-camera-progress
       (scene-eased-progress
        (timed-play-clip-easing clip)
        (timed-clip-progress clip time)))
     (values
      sampled-state
      (apply-compiled-camera-animations
       (timed-play-clip-start-camera clip)
       (timed-play-clip-camera-animations clip)
       eased-camera-progress
       linear
       sampled-state))]
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

; timed-clip-progress : timed-play-clip? real? -> real?
;;   Returns normalized full-clip progress for camera requests.
(define (timed-clip-progress clip time)
  (/ (timed-clip-local-time clip time)
     (timed-play-clip-duration clip)))

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
               (equal? (animation-request-target-id left-request)
                       (animation-request-target-id right-request))
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
             "target-id" (animation-request-target-id left-request)
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

; removing-animation-request? : animation-request? -> boolean?
;;   Reports whether request removes its whole top-level target at completion.
(define (removing-animation-request? request)
  (or (fade-out-request? request)
      (uncreate-request? request)))

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
;;   Reports whether value may be wrapped by timed. Nested timed wrappers and
;;   camera requests remain intentionally unsupported inside timed wrappers.
(define (timable-visual-request? value)
  (or (animation-request? value)
      (succession-animation-request? value)
      (animation-group-animation-request? value)
      (lagged-start-animation-request? value)
      (style-to-animation-request? value)))

; composition-child-request? : any/c -> boolean?
;;   Reports whether value may occur directly inside a sequential/parallel/lagged
;;   composition. Timed Visual/composition wrappers and style
;;   transitions may nest like other Visual compositions; camera requests remain
;;   top-level.
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
     "list of Visual/scalar, timed composition, style transitions, or sequential/parallel/lagged compositions"
     requests)))

; normalize-animation-requests : list? -> list?
;;   Unwraps the convenient single-list form accepted by play/composition APIs.
(define (normalize-animation-requests animations)
  (if (and (= (length animations) 1)
           (list? (car animations)))
      (car animations)
      animations))

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
