#lang racket/base

;;;
;;; Preview Inspection Cameras
;;;

;; Represents a preview-only spatial camera.  Overrides are immutable values:
;; they can be applied to a sampled scene state for rendering but can never
;; alter its authored camera or source timeline.


;;;
;;; Imports and Exports
;;;

(require racket/match
         "../scene-state.rkt"
         "../geometry.rkt"
         "camera3d-animation.rkt"
         "camera3d.rkt"
         "projection3d.rkt"
         "rotation3.rkt"
         "vec3.rkt"
         "view3d-visual.rkt")

(provide (struct-out preview-camera3d-override)
         make-preview-camera3d-override
         preview-camera3d-override-orbit
         preview-camera3d-override-pan
         preview-camera3d-override-dolly
         preview-camera3d-override-apply
         preview-camera3d-override->datum
         datum->preview-camera3d-override)


;;;
;;; Immutable Override Value
;;;

(struct preview-camera3d-override (view-id camera target)
  #:transparent
  #:guard
  (lambda (view-id camera target who)
    (unless (symbol? view-id)
      (raise-argument-error who "symbol?" view-id))
    (unless (camera3d? camera)
      (raise-argument-error who "camera3d?" camera))
    (unless (vec3? target)
      (raise-argument-error who "vec3?" target))
    (values view-id camera target)))

;; preview-camera3d-override represents an inspection-only camera.
;;  - view-id  symbol?    top-level view3d identity whose authored camera it shadows.
;;  - camera   camera3d?  immutable inspection camera used only for preview rendering.
;;  - target   vec3?      stable world-space orbit/pan pivot for navigation.


;;;
;;; Construction and Navigation
;;;

; make-preview-camera3d-override : symbol? camera3d? [#:target vec3?]
;;                                  -> preview-camera3d-override?
;;   Creates an inspection override.  The default pivot is one camera-unit in
;; front of the authored camera, avoiding an unrecorded dependency on scene
;; geometry or previously rendered frames.
(define (make-preview-camera3d-override view-id camera
                                        #:target
                                        [target
                                         (vec3+ (camera3d-position camera)
                                                (camera3d-forward camera))])
  (preview-camera3d-override view-id camera target))

; preview-camera3d-override-orbit : preview-camera3d-override?
;;                                   finite-real? finite-real?
;;                                   -> preview-camera3d-override?
;;   Orbits the inspection camera around its immutable inspection target.
(define (preview-camera3d-override-orbit override azimuth elevation)
  (check-override 'preview-camera3d-override-orbit override)
  (check-finite-real 'preview-camera3d-override-orbit "azimuth" azimuth)
  (check-finite-real 'preview-camera3d-override-orbit "elevation" elevation)
  (struct-copy preview-camera3d-override override
               [camera
                (camera3d-orbit-sample
                 (preview-camera3d-override-camera override)
                 (preview-camera3d-override-target override)
                 azimuth elevation 1)]))

; preview-camera3d-override-pan : preview-camera3d-override? vec3?
;;                                 -> preview-camera3d-override?
;;   Moves both the inspection camera and pivot by an explicit world delta.
(define (preview-camera3d-override-pan override delta)
  (check-override 'preview-camera3d-override-pan override)
  (unless (vec3? delta)
    (raise-argument-error 'preview-camera3d-override-pan "vec3?" delta))
  (struct-copy preview-camera3d-override override
               [camera
                (camera3d-with-position
                 (preview-camera3d-override-camera override)
                 (vec3+ (camera3d-position
                         (preview-camera3d-override-camera override))
                        delta))]
               [target (vec3+ (preview-camera3d-override-target override)
                              delta)]))

; preview-camera3d-override-dolly : preview-camera3d-override? finite-real?
;;                                   -> preview-camera3d-override?
;;   Moves a perspective camera along its forward axis.  For an orthographic
;; inspection camera, positive distance zooms in by reducing visible height.
(define (preview-camera3d-override-dolly override distance)
  (check-override 'preview-camera3d-override-dolly override)
  (check-finite-real 'preview-camera3d-override-dolly "distance" distance)
  (define camera (preview-camera3d-override-camera override))
  (define adjusted
    (cond
      [(perspective-projection3d? (camera3d-projection camera))
       (camera3d-with-position
        camera
        (vec3+ (camera3d-position camera)
               (vec3-scale distance (camera3d-forward camera))))]
      [else
       (define projection (camera3d-projection camera))
       (camera3d-with-projection
        camera
        (orthographic-projection3d
         (max 1e-9
              (* (orthographic-projection3d-vertical-size projection)
                 (exp (- distance))))))]))
  (struct-copy preview-camera3d-override override [camera adjusted]))


;;;
;;; Scene-State Projection
;;;

; preview-camera3d-override-apply : scene-state? preview-camera3d-override?
;;                                    -> scene-state?
;;   Replaces only the sampled view3d camera used for one preview render.
(define (preview-camera3d-override-apply state override)
  (unless (scene-state? state)
    (raise-argument-error 'preview-camera3d-override-apply "scene-state?" state))
  (check-override 'preview-camera3d-override-apply override)
  (define view-id (preview-camera3d-override-view-id override))
  (define view (scene-state-ref state view-id))
  (unless (view3d? view)
    (raise-arguments-error
     'preview-camera3d-override-apply
     "a view3d named by the override"
     "view-id" view-id
     "visual" view))
  (scene-state-update
   state view-id
   (view3d-with-camera view (preview-camera3d-override-camera override))))


;;;
;;; Subprocess-safe Data
;;;

; preview-camera3d-override->datum : preview-camera3d-override? -> datum?
;;   Converts a preview override to a reader-safe protocol value.
(define (preview-camera3d-override->datum override)
  (check-override 'preview-camera3d-override->datum override)
  (list 'preview-camera3d-override
        (preview-camera3d-override-view-id override)
        (camera->datum (preview-camera3d-override-camera override))
        (vec3->datum (preview-camera3d-override-target override))))

; datum->preview-camera3d-override : datum? -> preview-camera3d-override?
;;   Reconstructs a validated inspection override from the worker protocol.
(define (datum->preview-camera3d-override datum)
  (match datum
    [(list 'preview-camera3d-override (? symbol? view-id) camera-datum target-datum)
     (make-preview-camera3d-override
      view-id
      (datum->camera camera-datum)
      #:target (datum->vec3 target-datum))]
    [_
     (raise-arguments-error
      'datum->preview-camera3d-override
      "a serialized preview camera override"
      "datum" datum)]))

(define (camera->datum camera)
  (list 'camera3d
        (vec3->datum (camera3d-position camera))
        (rotation->datum (camera3d-rotation camera))
        (camera3d-near camera)
        (camera3d-far camera)
        (projection->datum (camera3d-projection camera))))

(define (datum->camera datum)
  (match datum
    [(list 'camera3d position rotation near far projection)
     (define position-value (datum->vec3 position))
     (define rotation-value (datum->rotation rotation))
     (define projection-value (datum->projection projection))
     (cond
       [(perspective-projection3d? projection-value)
        (perspective-camera3d
         #:position position-value #:rotation rotation-value
         #:near near #:far far
         #:vertical-field-of-view
         (perspective-projection3d-vertical-field-of-view projection-value))]
       [else
        (orthographic-camera3d
         #:position position-value #:rotation rotation-value
         #:near near #:far far
         #:vertical-size (orthographic-projection3d-vertical-size projection-value))])]
    [_
     (raise-arguments-error 'datum->preview-camera3d-override
                            "a serialized camera3d"
                            "datum" datum)]))

(define (vec3->datum value)
  (list 'vec3 (vec3-x value) (vec3-y value) (vec3-z value)))

(define (datum->vec3 datum)
  (match datum
    [(list 'vec3 x y z) (vec3 x y z)]
    [_ (raise-arguments-error 'datum->preview-camera3d-override
                               "a serialized vec3" "datum" datum)]))

(define (rotation->datum value)
  (cons 'rotation3 (vector->list (rotation3-components value))))

(define (datum->rotation datum)
  (match datum
    [(list 'rotation3 w x y z)
     ;; The raw quaternion cannot be public construction API.  Reconstruct its
     ;; equivalent axis-angle orientation through the exposed conversion route.
     (define norm (sqrt (+ (* w w) (* x x) (* y y) (* z z))))
     (unless (and (finite-real? norm) (positive? norm))
       (raise-arguments-error 'datum->preview-camera3d-override
                              "a nonzero finite quaternion" "datum" datum))
     (define unit-w (/ w norm))
     (define unit-x (/ x norm))
     (define unit-y (/ y norm))
     (define unit-z (/ z norm))
     (define axis-length
       (sqrt (+ (* unit-x unit-x) (* unit-y unit-y) (* unit-z unit-z))))
     (define angle (* 2 (acos (max -1 (min 1 unit-w)))))
     (if (or (zero? angle) (zero? axis-length))
         identity-rotation3
         (axis-angle (vec3 (/ unit-x axis-length)
                           (/ unit-y axis-length)
                           (/ unit-z axis-length))
                     angle))]
    [_ (raise-arguments-error 'datum->preview-camera3d-override
                               "a serialized rotation3" "datum" datum)]))

(define (projection->datum projection)
  (cond
    [(perspective-projection3d? projection)
     (list 'perspective
           (perspective-projection3d-vertical-field-of-view projection))]
    [else
     (list 'orthographic (orthographic-projection3d-vertical-size projection))]))

(define (datum->projection datum)
  (match datum
    [(list 'perspective field-of-view) (perspective-projection3d field-of-view)]
    [(list 'orthographic height) (orthographic-projection3d height)]
    [_ (raise-arguments-error 'datum->preview-camera3d-override
                               "a serialized projection3d" "datum" datum)]))


;;;
;;; Validation
;;;

(define (check-override who value)
  (unless (preview-camera3d-override? value)
    (raise-argument-error who "preview-camera3d-override?" value)))

(define (check-finite-real who label value)
  (unless (finite-real? value)
    (raise-arguments-error who "a finite real value" label value)))
