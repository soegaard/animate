#lang racket/base

;;;
;;; Camera Animation Model
;;;

;; Defines immutable camera pan, zoom, fit, and follow requests with
;; deterministic sampling.
;;
;; Camera animations change only the camera center and visible world width.
;; Pixel dimensions and background remain fixed throughout a play clip.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "camera.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "scene-state.rkt"
         "visual-model.rkt")

;; Exports
(provide camera-pan-to
         camera-pan-to-request?
         camera-pan-by
         camera-pan-by-request?
         camera-zoom-to
         camera-zoom-to-request?
         camera-zoom-by
         camera-zoom-by-request?
         camera-follow
         camera-follow-request?
         camera-fit-request?
         make-camera-fit-request
         camera-animation-request?
         camera-animation-request-components
         compiled-camera-animation-components
         compile-camera-animation-requests
         apply-compiled-camera-animations
         complete-compiled-camera-animations
         compiled-camera-animations-require-scene-state?)


;;;
;;; Request Data
;;;

(struct camera-pan-to-request (center)
  #:transparent)

;; camera-pan-to-request represents an absolute camera-center request.
;;  - center  vec2?  requested world point at the frame center.

(struct camera-pan-by-request (delta)
  #:transparent)

;; camera-pan-by-request represents a relative camera-center request.
;;  - delta  vec2?  world displacement added to the clip-start center.

(struct camera-zoom-to-request (world-width)
  #:transparent)

;; camera-zoom-to-request represents an absolute visible-width request.
;;  - world-width  positive finite real?  requested visible world width.

(struct camera-zoom-by-request (factor)
  #:transparent)

;; camera-zoom-by-request represents a relative magnification request.
;;  - factor  positive finite real?  magnification applied at clip start.
;;                                  Values above one zoom in.

(struct camera-follow-request (target-id)
  #:transparent)

;; camera-follow-request represents clip-scoped camera tracking.
;;  - target-id  symbol?  top-level Visual whose clip motion is followed.

(struct camera-fit-request (center world-width)
  #:transparent
  #:constructor-name make-camera-fit-request/raw)

;; camera-fit-request represents one concrete fitted camera endpoint.
;;  - center       vec2?                  fitted frame center.
;;  - world-width  positive finite real?  fitted visible world width.


;;;
;;; Compiled Animation Data
;;;

(struct camera-center-animation (from to)
  #:transparent)

;; camera-center-animation represents one compiled camera-center transition.
;;  - from  vec2?  center at clip start.
;;  - to    vec2?  center at clip end.

(struct camera-world-width-animation (from to)
  #:transparent)

;; camera-world-width-animation represents one compiled visible-width change.
;;  - from  positive finite real?  visible width at clip start.
;;  - to    positive finite real?  visible width at clip end.

(struct camera-follow-animation
  (target-id target-from target-to x-frame-offset y-frame-offset)
  #:transparent)

;; camera-follow-animation represents one compiled target-follow transition.
;;  - target-id       symbol?       followed top-level Visual identity.
;;  - target-from     vec2?         target position at clip start.
;;  - target-to       vec2?         target position at motion endpoint.
;;  - x-frame-offset  finite-real?  initial target offset / visible width.
;;  - y-frame-offset  finite-real?  initial target offset / visible height.

(struct camera-fit-animation
  (center-from center-to world-width-from world-width-to)
  #:transparent)

;; camera-fit-animation represents simultaneous fitted center and width changes.
;;  - center-from       vec2?                  center at clip start.
;;  - center-to         vec2?                  fitted endpoint center.
;;  - world-width-from  positive finite real?  width at clip start.
;;  - world-width-to    positive finite real?  fitted endpoint width.


;;;
;;; Public Requests
;;;

; camera-pan-to : vec2? -> camera-pan-to-request?
;;   Creates a request to place center at the middle of the camera frame.
(define (camera-pan-to center)
  (unless (vec2? center)
    (raise-argument-error 'camera-pan-to "vec2?" center))
  (camera-pan-to-request center))

; camera-pan-by : vec2? -> camera-pan-by-request?
;;   Creates a request to add delta to the camera center at clip start.
(define (camera-pan-by delta)
  (unless (vec2? delta)
    (raise-argument-error 'camera-pan-by "vec2?" delta))
  (camera-pan-by-request delta))

; camera-zoom-to : positive-real? -> camera-zoom-to-request?
;;   Creates a request for an absolute visible world width.
(define (camera-zoom-to world-width)
  (check-positive-finite-real 'camera-zoom-to world-width)
  (camera-zoom-to-request world-width))

; camera-zoom-by : positive-real? -> camera-zoom-by-request?
;;   Creates a relative magnification request; values above one zoom in.
(define (camera-zoom-by factor)
  (check-positive-finite-real 'camera-zoom-by factor)
  (camera-zoom-by-request factor))

; camera-follow : (or/c visual? symbol?) -> camera-follow-request?
;;   Creates a request that keeps target at its clip-start frame position.
(define (camera-follow target)
  (camera-follow-request
   (visual-target-id target 'camera-follow)))

; make-camera-fit-request : vec2? positive-real? -> camera-fit-request?
;;   Creates one internal concrete fit request for center and visible width.
(define (make-camera-fit-request center world-width)
  (unless (vec2? center)
    (raise-argument-error 'make-camera-fit-request "vec2?" center))
  (check-positive-finite-real 'make-camera-fit-request world-width)
  (make-camera-fit-request/raw center world-width))


;;;
;;; Compilation
;;;

; camera-animation-request? : any/c -> boolean?
;;   Reports whether value is a supported uncompiled camera request.
(define (camera-animation-request? value)
  (or (camera-pan-to-request? value)
      (camera-pan-by-request? value)
      (camera-zoom-to-request? value)
      (camera-zoom-by-request? value)
      (camera-follow-request? value)
      (camera-fit-request? value)))

; compile-camera-animation-requests : camera?
;                                     scene-state?
;                                     scene-state?
;                                     (listof camera-animation-request?)
;                                     -> (listof compiled-camera-animation?)
;;   Compiles requests against shared clip-start and motion-end states.
(define (compile-camera-animation-requests camera
                                           start-state
                                           motion-end-state
                                           requests)
  (unless (camera? camera)
    (raise-argument-error
     'compile-camera-animation-requests
     "camera?"
     camera))
  (unless (scene-state? start-state)
    (raise-argument-error
     'compile-camera-animation-requests
     "scene-state?"
     start-state))
  (unless (scene-state? motion-end-state)
    (raise-argument-error
     'compile-camera-animation-requests
     "scene-state?"
     motion-end-state))
  (unless (and (list? requests)
               (andmap camera-animation-request? requests))
    (raise-argument-error
     'compile-camera-animation-requests
     "list of camera animation requests"
     requests))
  (check-camera-request-component-conflicts requests)
  (for/list ([request (in-list requests)])
    (compile-camera-animation-request camera
                                      start-state
                                      motion-end-state
                                      request)))

; compile-camera-animation-request : camera?
;                                    scene-state?
;                                    scene-state?
;                                    camera-animation-request?
;                                    -> compiled-camera-animation?
;;   Compiles one request against the shared clip values.
(define (compile-camera-animation-request camera
                                          start-state
                                          motion-end-state
                                          request)
  (cond
    [(camera-pan-to-request? request)
     (camera-center-animation
      (camera-center camera)
      (camera-pan-to-request-center request))]
    [(camera-pan-by-request? request)
     (camera-center-animation
      (camera-center camera)
      (vec2+ (camera-center camera)
             (camera-pan-by-request-delta request)))]
    [(camera-zoom-to-request? request)
     (camera-world-width-animation
      (camera-world-width camera)
      (camera-zoom-to-request-world-width request))]
    [(camera-zoom-by-request? request)
     (define destination
       (/ (camera-world-width camera)
          (camera-zoom-by-request-factor request)))
     (unless (and (finite-real? destination)
                  (positive? destination))
       (raise-arguments-error
        'scene-play
        "relative camera zoom must produce a positive finite world width"
        "camera-world-width" (camera-world-width camera)
        "factor" (camera-zoom-by-request-factor request)
        "result" destination))
     (camera-world-width-animation
      (camera-world-width camera)
      destination)]
    [(camera-follow-request? request)
     (compile-camera-follow-request camera
                                    start-state
                                    motion-end-state
                                    request)]
    [(camera-fit-request? request)
     (camera-fit-animation
      (camera-center camera)
      (camera-fit-request-center request)
      (camera-world-width camera)
      (camera-fit-request-world-width request))]
    [else
     (raise-argument-error
      'compile-camera-animation-request
      "camera animation request"
      request)]))

; compile-camera-follow-request : camera?
;                                 scene-state?
;                                 scene-state?
;                                 camera-follow-request?
;                                 -> camera-follow-animation?
;;   Compiles target motion and its initial normalized frame position.
(define (compile-camera-follow-request camera
                                       start-state
                                       motion-end-state
                                       request)
  (define target-id
    (camera-follow-request-target-id request))
  (define target-from
    (camera-follow-target-position start-state target-id))
  (define target-to
    (camera-follow-target-position motion-end-state target-id))
  (define world-width
    (camera-world-width camera))
  (define world-height
    (camera-world-height camera))
  (define displacement
    (vec2- target-from
           (camera-center camera)))
  (camera-follow-animation
   target-id
   target-from
   target-to
   (/ (vec2-x displacement) world-width)
   (/ (vec2-y displacement) world-height)))

; camera-follow-target-position : scene-state? symbol? -> vec2?
;;   Returns a checked top-level target position for follow compilation.
(define (camera-follow-target-position state target-id)
  (unless (scene-state-has? state target-id)
    (raise-arguments-error
     'scene-play
     "camera-follow requires a top-level Visual in the clip motion states"
     "visual-id" target-id))
  (define visual
    (scene-state-resolved-ref state target-id))
  (when (frame-space-visual? visual)
    (raise-arguments-error
     'scene-play
     "camera-follow requires a world-space top-level Visual"
     "visual-id" target-id))
  (define position
    (visual-position visual))
  (unless (vec2? position)
    (raise-arguments-error
     'scene-play
     "camera-follow requires visual-position to return a vec2"
     "visual-id" target-id
     "visual-position" position))
  position)

; check-camera-request-component-conflicts :
;   (listof camera-animation-request?) -> void?
;;   Rejects duplicate updates to one camera component in a play clip.
(define (check-camera-request-component-conflicts requests)
  (define components
    (for*/list ([request (in-list requests)]
                [component
                 (in-list
                  (camera-animation-request-components request))])
      component))
  (define duplicate
    (find-duplicate components))
  (when duplicate
    (raise-arguments-error
     'scene-play
     "two simultaneous camera animations target the same camera component"
     "component" duplicate)))

; camera-animation-request-components : camera-animation-request?
;                                       -> (listof symbol?)
;;   Returns every camera component changed by request.
(define (camera-animation-request-components request)
  (cond
    [(or (camera-pan-to-request? request)
         (camera-pan-by-request? request)
         (camera-follow-request? request))
     '(center)]
    [(or (camera-zoom-to-request? request)
         (camera-zoom-by-request? request))
     '(world-width)]
    [(camera-fit-request? request)
     '(center world-width)]
    [else
     (raise-argument-error
      'camera-animation-request-components
      "camera animation request"
      request)]))

; find-duplicate : list? -> any/c
;;   Returns the first duplicate value, or #f when all values are distinct.
(define (find-duplicate values)
  (let loop ([remaining values]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))


;;;
;;; Sampling
;;;

; compiled-camera-animations-require-scene-state? :
;   (listof compiled-camera-animation?) -> boolean?
;;   Reports whether exact camera sampling needs the sampled Visual state.
(define (compiled-camera-animations-require-scene-state? animations)
  (unless (and (list? animations)
               (andmap compiled-camera-animation? animations))
    (raise-argument-error
     'compiled-camera-animations-require-scene-state?
     "list of compiled camera animations"
     animations))
  (for/or ([animation (in-list animations)])
    (camera-follow-animation? animation)))

; apply-compiled-camera-animations : camera?
;                                    (listof compiled-camera-animation?)
;                                    finite-real?
;                                    (-> finite-real? finite-real?)
;                                    [(or/c scene-state? false/c)]
;                                    -> camera?
;;   Samples camera animations, optionally following the sampled Visual state.
(define (apply-compiled-camera-animations camera animations progress easing
                                          [sampled-state #f])
  (unless (camera? camera)
    (raise-argument-error
     'apply-compiled-camera-animations
     "camera?"
     camera))
  (unless (and (list? animations)
               (andmap compiled-camera-animation? animations))
    (raise-argument-error
     'apply-compiled-camera-animations
     "list of compiled camera animations"
     animations))
  (unless (finite-real? progress)
    (raise-argument-error
     'apply-compiled-camera-animations
     "finite real?"
     progress))
  (unless (and (procedure? easing)
               (procedure-arity-includes? easing 1))
    (raise-argument-error
     'apply-compiled-camera-animations
     "(procedure-arity-includes/c 1)"
     easing))
  (unless (or (not sampled-state)
              (scene-state? sampled-state))
    (raise-argument-error
     'apply-compiled-camera-animations
     "(or/c scene-state? false/c)"
     sampled-state))
  (check-compiled-camera-component-conflicts animations)
  (define eased-progress
    (clamp-unit (easing (clamp-unit progress))))
  (define width-animation
    (find-compiled-camera-animation animations 'world-width))
  (define sampled-world-width
    (if width-animation
        (sample-camera-world-width width-animation eased-progress)
        (camera-world-width camera)))
  (define center-animation
    (find-compiled-camera-animation animations 'center))
  (define sampled-center
    (if center-animation
        (sample-camera-center camera
                              center-animation
                              sampled-world-width
                              eased-progress
                              sampled-state)
        (camera-center camera)))
  (camera-with-view camera
                    sampled-center
                    sampled-world-width))

; complete-compiled-camera-animations : camera?
;                                       (listof compiled-camera-animation?)
;                                       (-> finite-real? finite-real?)
;                                       [(or/c scene-state? false/c)]
;                                       -> camera?
;;   Produces the camera endpoint after all animations complete.
(define (complete-compiled-camera-animations camera animations easing
                                             [sampled-state #f])
  (apply-compiled-camera-animations
   camera animations 1 easing sampled-state))

; compiled-camera-animation? : any/c -> boolean?
;;   Reports whether value is a supported compiled camera animation.
(define (compiled-camera-animation? value)
  (or (camera-center-animation? value)
      (camera-world-width-animation? value)
      (camera-follow-animation? value)
      (camera-fit-animation? value)))

; compiled-camera-animation-components : compiled-camera-animation?
;                                        -> (listof symbol?)
;;   Returns every camera component changed by animation.
(define (compiled-camera-animation-components animation)
  (cond
    [(or (camera-center-animation? animation)
         (camera-follow-animation? animation))
     '(center)]
    [(camera-world-width-animation? animation)
     '(world-width)]
    [(camera-fit-animation? animation)
     '(center world-width)]
    [else
     (raise-argument-error
      'compiled-camera-animation-components
      "compiled camera animation"
      animation)]))

; check-compiled-camera-component-conflicts :
;   (listof compiled-camera-animation?) -> void?
;;   Rejects malformed compiled lists containing duplicate components.
(define (check-compiled-camera-component-conflicts animations)
  (define components
    (for*/list ([animation (in-list animations)]
                [component
                 (in-list
                  (compiled-camera-animation-components animation))])
      component))
  (define duplicate
    (find-duplicate components))
  (when duplicate
    (raise-arguments-error
     'apply-compiled-camera-animations
     "compiled camera animations contain duplicate components"
     "component" duplicate)))

; find-compiled-camera-animation : (listof compiled-camera-animation?) symbol?
;                                  -> (or/c compiled-camera-animation? false/c)
;;   Returns the animation that changes component, or false when absent.
(define (find-compiled-camera-animation animations component)
  (for/first ([animation (in-list animations)]
              #:when
              (memq component
                    (compiled-camera-animation-components animation)))
    animation))

; sample-camera-world-width : compiled-camera-animation? finite-real?
;                             -> positive-real?
;;   Returns the visible world width supplied by animation at progress.
(define (sample-camera-world-width animation progress)
  (cond
    [(camera-world-width-animation? animation)
     (real-lerp (camera-world-width-animation-from animation)
                (camera-world-width-animation-to animation)
                progress)]
    [(camera-fit-animation? animation)
     (real-lerp (camera-fit-animation-world-width-from animation)
                (camera-fit-animation-world-width-to animation)
                progress)]
    [else
     (raise-argument-error
      'sample-camera-world-width
      "compiled camera world-width animation"
      animation)]))

; sample-camera-center : camera?
;                        compiled-camera-animation?
;                        positive-real?
;                        finite-real?
;                        (or/c scene-state? false/c)
;                        -> vec2?
;;   Returns the camera center supplied by animation at progress.
(define (sample-camera-center camera animation world-width progress sampled-state)
  (cond
    [(camera-center-animation? animation)
     (vec2-lerp (camera-center-animation-from animation)
                (camera-center-animation-to animation)
                progress)]
    [(camera-follow-animation? animation)
     (sample-camera-follow-center camera
                                  animation
                                  world-width
                                  progress
                                  sampled-state)]
    [(camera-fit-animation? animation)
     (vec2-lerp (camera-fit-animation-center-from animation)
                (camera-fit-animation-center-to animation)
                progress)]
    [else
     (raise-argument-error
      'sample-camera-center
      "compiled camera-center animation"
      animation)]))

; sample-camera-follow-center : camera?
;                               camera-follow-animation?
;                               positive-real?
;                               finite-real?
;                               (or/c scene-state? false/c)
;                               -> vec2?
;;   Keeps the sampled followed target at its clip-start normalized position.
(define (sample-camera-follow-center camera
                                     animation
                                     world-width
                                     progress
                                     sampled-state)
  (define target-position
    (if sampled-state
        (camera-follow-target-position
         sampled-state
         (camera-follow-animation-target-id animation))
        (vec2-lerp (camera-follow-animation-target-from animation)
                   (camera-follow-animation-target-to animation)
                   progress)))
  (define world-height
    (* world-width
       (/ (camera-height camera)
          (camera-width camera))))
  (vec2-
   target-position
   (vec2 (* (camera-follow-animation-x-frame-offset animation)
            world-width)
         (* (camera-follow-animation-y-frame-offset animation)
            world-height))))

; camera-with-view : camera? vec2? positive-real? -> camera?
;;   Replaces camera center and visible width while preserving frame settings.
(define (camera-with-view camera center world-width)
  (make-camera #:width (camera-width camera)
               #:height (camera-height camera)
               #:world-width world-width
               #:center center
               #:background (camera-background camera)))

; clamp-unit : any/c -> real?
;;   Validates value and clamps it to the closed unit interval.
(define (clamp-unit value)
  (unless (finite-real? value)
    (raise-arguments-error
     'animation-easing
     "an easing function must produce a finite real number"
     "result" value))
  (min 1 (max 0 value)))


;;;
;;; Validation
;;;

; check-positive-finite-real : symbol? any/c -> void?
;;   Raises an argument error unless value is positive and finite.
(define (check-positive-finite-real who value)
  (unless (and (finite-real? value)
               (positive? value))
    (raise-argument-error who "positive finite real?" value)))
