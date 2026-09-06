#lang racket/base

;;;
;;; Spatial Camera Animation
;;;

;; Defines immutable camera requests and the pure pose/lens samplers used by
;; SCENE-3D-D.  It does not depend on scenes, preview workers, or rendering.


;;;
;;; Imports and Exports
;;;

(require "../geometry.rkt"
         "camera3d.rkt"
         "projection3d.rkt"
         "rotation3.rkt"
         "spatial-path.rkt"
         "vec3.rkt")

(provide camera3d-move-to
         camera3d-move-to-request?
         camera3d-look-at-to
         camera3d-look-at-to-request?
         camera3d-orbit-by
         camera3d-orbit-by-request?
         camera3d-roll-to
         camera3d-roll-to-request?
         camera3d-field-of-view-to
         camera3d-field-of-view-to-request?
         camera3d-orthographic-height-to
         camera3d-orthographic-height-to-request?
         camera3d-dolly-by
         camera3d-dolly-by-request?
         camera3d-fit
         camera3d-fit-request?
         camera3d-follow
         camera3d-follow-request?
         camera3d-animation-request?
         (struct-out camera3d-move-to-request)
         (struct-out camera3d-look-at-to-request)
         (struct-out camera3d-orbit-by-request)
         (struct-out camera3d-roll-to-request)
         (struct-out camera3d-field-of-view-to-request)
         (struct-out camera3d-orthographic-height-to-request)
         (struct-out camera3d-dolly-by-request)
         (struct-out camera3d-fit-request)
         (struct-out camera3d-follow-request)
         (struct-out camera3d-pose-animation)
         (struct-out camera3d-orbit-animation)
         (struct-out camera3d-field-of-view-animation)
         (struct-out camera3d-orthographic-height-animation)
         (struct-out camera3d-follow-animation)
         camera3d-compiled-animation?
         camera3d-pose-lerp
         camera3d-orbit-sample
         camera3d-roll-camera
         camera3d-field-of-view-sample
         camera3d-orthographic-height-sample)


;;;
;;; Request Values
;;;

(struct camera3d-move-to-request (view-id destination) #:transparent)
;; camera3d-move-to-request records an absolute camera position endpoint.

(struct camera3d-look-at-to-request (view-id target up) #:transparent)
;; camera3d-look-at-to-request records a world point and an explicit up hint.

(struct camera3d-orbit-by-request (view-id center azimuth elevation)
  #:transparent)
;; camera3d-orbit-by-request records a finite orbit about one world-space centre.

(struct camera3d-roll-to-request (view-id angle) #:transparent)
;; camera3d-roll-to-request records an absolute roll about the forward axis.

(struct camera3d-field-of-view-to-request (view-id field-of-view) #:transparent)
;; camera3d-field-of-view-to-request changes only a perspective camera lens.

(struct camera3d-orthographic-height-to-request (view-id height) #:transparent)
;; camera3d-orthographic-height-to-request changes only an orthographic lens.

(struct camera3d-dolly-by-request (view-id distance) #:transparent)
;; camera3d-dolly-by-request moves along the camera's clip-start forward axis.

(struct camera3d-fit-request (view-id padding) #:transparent)
;; camera3d-fit-request frames the full spatial bounds in one viewport.

(struct camera3d-follow-request (view-id target-path) #:transparent)
;; camera3d-follow-request keeps the clip-start camera offset from one spatial
;; target.  The target path is rooted at the same view3d identity.


;;;
;;; Public Constructors
;;;

; camera3d-move-to : symbol? vec3? -> camera3d-move-to-request?
;;   Moves one view3d's camera to an absolute world-space position.
(define (camera3d-move-to view-id destination)
  (check-view-id 'camera3d-move-to view-id)
  (check-vec3 'camera3d-move-to destination)
  (camera3d-move-to-request view-id destination))

; camera3d-look-at-to : symbol? vec3? [#:up vec3?] -> camera3d-look-at-to-request?
;;   Orients one view3d's camera toward target while retaining its position.
(define (camera3d-look-at-to view-id target #:up [up y-axis3])
  (check-view-id 'camera3d-look-at-to view-id)
  (check-vec3 'camera3d-look-at-to target)
  (check-vec3 'camera3d-look-at-to up)
  (camera3d-look-at-to-request view-id target up))

; camera3d-orbit-by : symbol? [#:center vec3?] [#:azimuth finite-real?]
;;                    [#:elevation finite-real?] -> camera3d-orbit-by-request?
;;   Orbits around center, using world up for azimuth and the yawed camera-right
;; axis for elevation.  With no centre supplied, the world origin is used.
(define (camera3d-orbit-by view-id
                           #:center [center origin3]
                           #:azimuth [azimuth 0]
                           #:elevation [elevation 0])
  (check-view-id 'camera3d-orbit-by view-id)
  (check-vec3 'camera3d-orbit-by center)
  (check-finite-real 'camera3d-orbit-by "azimuth" azimuth)
  (check-finite-real 'camera3d-orbit-by "elevation" elevation)
  (camera3d-orbit-by-request view-id center azimuth elevation))

; camera3d-roll-to : symbol? finite-real? -> camera3d-roll-to-request?
;;   Sets the camera's absolute roll in radians relative to an upright look-at
;; orientation for its current forward direction.
(define (camera3d-roll-to view-id angle)
  (check-view-id 'camera3d-roll-to view-id)
  (check-finite-real 'camera3d-roll-to "angle" angle)
  (camera3d-roll-to-request view-id angle))

; camera3d-field-of-view-to : symbol? finite-real?
;;                             -> camera3d-field-of-view-to-request?
;;   Changes the vertical field of view of a perspective camera.
(define (camera3d-field-of-view-to view-id field-of-view)
  (check-view-id 'camera3d-field-of-view-to view-id)
  ;; The lens structure provides the authoritative strict range check.
  (perspective-projection3d field-of-view)
  (camera3d-field-of-view-to-request view-id field-of-view))

; camera3d-orthographic-height-to : symbol? positive-real?
;;                                   -> camera3d-orthographic-height-to-request?
;;   Changes the visible vertical height of an orthographic camera.
(define (camera3d-orthographic-height-to view-id height)
  (check-view-id 'camera3d-orthographic-height-to view-id)
  (orthographic-projection3d height)
  (camera3d-orthographic-height-to-request view-id height))

; camera3d-dolly-by : symbol? finite-real? -> camera3d-dolly-by-request?
;;   Moves the camera along its clip-start forward axis; positive is forward.
(define (camera3d-dolly-by view-id distance)
  (check-view-id 'camera3d-dolly-by view-id)
  (check-finite-real 'camera3d-dolly-by "distance" distance)
  (camera3d-dolly-by-request view-id distance))

; camera3d-fit : symbol? [#:padding positive-real?] -> camera3d-fit-request?
;;   Fits the spatial contents of one view3d using a conservative padding factor.
(define (camera3d-fit view-id #:padding [padding 11/10])
  (check-view-id 'camera3d-fit view-id)
  (unless (and (finite-real? padding) (positive? padding))
    (raise-argument-error 'camera3d-fit "positive finite real?" padding))
  (camera3d-fit-request view-id padding))

; camera3d-follow : symbol? spatial-path? -> camera3d-follow-request?
;;   Causes the camera to retain its clip-start offset from a spatial target.
(define (camera3d-follow view-id target-path)
  (check-view-id 'camera3d-follow view-id)
  (unless (and (spatial-path? target-path)
               (pair? (cdr target-path))
               (eq? view-id (car target-path)))
    (raise-argument-error
     'camera3d-follow
     "spatial path rooted at the requested view3d"
     target-path))
  (camera3d-follow-request view-id target-path))


;;;
;;; Compiled Values
;;;

(struct camera3d-pose-animation (view-id from to) #:transparent)
;; camera3d-pose-animation interpolates position and quaternion orientation.

(struct camera3d-orbit-animation (view-id from center azimuth elevation to)
  #:transparent)
;; camera3d-orbit-animation retains the exact orbit parameters and endpoints.

(struct camera3d-field-of-view-animation (view-id from to) #:transparent)
;; camera3d-field-of-view-animation retains perspective lens endpoints.

(struct camera3d-orthographic-height-animation (view-id from to) #:transparent)
;; camera3d-orthographic-height-animation retains orthographic lens endpoints.

(struct camera3d-follow-animation (view-id target-path offset source) #:transparent)
;; camera3d-follow-animation carries the exact clip-start camera and offset.


;;;
;;; Predicates
;;;

; camera3d-animation-request? : any/c -> boolean?
;;   Reports whether value is a SCENE-3D-D camera request.
(define (camera3d-animation-request? value)
  (or (camera3d-move-to-request? value)
      (camera3d-look-at-to-request? value)
      (camera3d-orbit-by-request? value)
      (camera3d-roll-to-request? value)
      (camera3d-field-of-view-to-request? value)
      (camera3d-orthographic-height-to-request? value)
      (camera3d-dolly-by-request? value)
      (camera3d-fit-request? value)
      (camera3d-follow-request? value)))

; camera3d-compiled-animation? : any/c -> boolean?
;;   Reports whether value is a compiled SCENE-3D-D camera animation.
(define (camera3d-compiled-animation? value)
  (or (camera3d-pose-animation? value)
      (camera3d-orbit-animation? value)
      (camera3d-field-of-view-animation? value)
      (camera3d-orthographic-height-animation? value)
      (camera3d-follow-animation? value)))


;;;
;;; Pure Camera Sampling
;;;

; camera3d-pose-lerp : camera3d? camera3d? unit-real? -> camera3d?
;;   Interpolates a same-kind camera pose with exact endpoints.
(define (camera3d-pose-lerp from to progress)
  (check-camera 'camera3d-pose-lerp from)
  (check-camera 'camera3d-pose-lerp to)
  (check-unit 'camera3d-pose-lerp progress)
  (unless (same-projection-kind? from to)
    (raise-arguments-error 'camera3d-pose-lerp
                           "cameras with the same projection kind"
                           "from" from "to" to))
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [else
         (camera3d-with-rotation
          (camera3d-with-position from
                                  (vec3-lerp (camera3d-position from)
                                             (camera3d-position to)
                                             progress))
          (rotation3-slerp (camera3d-rotation from)
                           (camera3d-rotation to)
                           progress))]))

; camera3d-orbit-sample : camera3d? vec3? finite-real? finite-real? unit-real?
;;                         -> camera3d?
;;   Samples an orbit without accumulating state between frames.
(define (camera3d-orbit-sample from center azimuth elevation progress)
  (check-camera 'camera3d-orbit-sample from)
  (check-vec3 'camera3d-orbit-sample center)
  (check-finite-real 'camera3d-orbit-sample "azimuth" azimuth)
  (check-finite-real 'camera3d-orbit-sample "elevation" elevation)
  (check-unit 'camera3d-orbit-sample progress)
  (define destination
    (camera3d-orbit-endpoint from center azimuth elevation))
  (cond [(zero? progress) from]
        [(= progress 1) destination]
        [else
         (define position
           (orbit-position from center (* azimuth progress) (* elevation progress)))
         ;; The orbit's pose is constrained by its geometric target at every
         ;; sampled position.  Slerping only the endpoint quaternions can
         ;; briefly aim away from the centre (especially across a half-turn),
         ;; even though the position is on the correct orbit.  `camera3d-look-at`
         ;; still produces the immutable quaternion representation; it simply
         ;; derives that quaternion from the current point on the orbit.
         (camera3d-look-at (camera3d-with-position from position) center)]))

; camera3d-roll-camera : camera3d? finite-real? -> camera3d?
;;   Returns the absolute-roll endpoint for one camera's current forward axis.
(define (camera3d-roll-camera camera angle)
  (check-camera 'camera3d-roll-camera camera)
  (check-finite-real 'camera3d-roll-camera "angle" angle)
  (define forward (camera3d-forward camera))
  (define upright
    (with-handlers ([exn:fail?
                     (lambda (_failure)
                       (rotation3-look-at
                        (vec3-scale -1 forward)
                        #:up (camera3d-up camera)))])
      (rotation3-look-at (vec3-scale -1 forward) #:up y-axis3)))
  (camera3d-with-rotation
   camera
   (rotation3-compose upright (axis-angle (vec3 0 0 -1) angle))))

; camera3d-field-of-view-sample : camera3d? finite-real? unit-real? -> camera3d?
;;   Samples a perspective field of view while preserving exact endpoints.
(define (camera3d-field-of-view-sample camera destination progress)
  (check-camera 'camera3d-field-of-view-sample camera)
  (check-unit 'camera3d-field-of-view-sample progress)
  (define projection (camera3d-projection camera))
  (unless (perspective-projection3d? projection)
    (raise-arguments-error 'camera3d-field-of-view-sample
                           "a perspective camera"
                           "camera" camera))
  (define endpoint (perspective-projection3d destination))
  (cond [(zero? progress) camera]
        [(= progress 1)
         (camera3d-with-projection camera endpoint)]
        [else
         (camera3d-with-projection
          camera
          (perspective-projection3d
           (real-lerp (perspective-projection3d-vertical-field-of-view projection)
                      destination
                      progress)))]))

; camera3d-orthographic-height-sample : camera3d? positive-real? unit-real?
;;                                       -> camera3d?
;;   Samples an orthographic visible height while preserving exact endpoints.
(define (camera3d-orthographic-height-sample camera destination progress)
  (check-camera 'camera3d-orthographic-height-sample camera)
  (check-unit 'camera3d-orthographic-height-sample progress)
  (define projection (camera3d-projection camera))
  (unless (orthographic-projection3d? projection)
    (raise-arguments-error 'camera3d-orthographic-height-sample
                           "an orthographic camera"
                           "camera" camera))
  (define endpoint (orthographic-projection3d destination))
  (cond [(zero? progress) camera]
        [(= progress 1) (camera3d-with-projection camera endpoint)]
        [else
         (camera3d-with-projection
          camera
          (orthographic-projection3d
           (real-lerp (orthographic-projection3d-vertical-size projection)
                      destination
                      progress)))]))


;;;
;;; Local Helpers
;;;

(define (camera3d-orbit-endpoint camera center azimuth elevation)
  (define position (orbit-position camera center azimuth elevation))
  (camera3d-look-at (camera3d-with-position camera position) center))

(define (orbit-position camera center azimuth elevation)
  (define offset (vec3- (camera3d-position camera) center))
  (when (zero? (vec3-length offset))
    (raise-arguments-error 'camera3d-orbit-by
                           "a camera position distinct from its orbit centre"
                           "camera-position" (camera3d-position camera)
                           "center" center))
  (define yaw (axis-angle y-axis3 azimuth))
  (define elevated-axis
    (rotation3-apply yaw x-axis3))
  (define elevation-rotation (axis-angle elevated-axis elevation))
  (vec3+ center
         (rotation3-apply elevation-rotation
                          (rotation3-apply yaw offset))))

(define (same-projection-kind? first second)
  (or (and (perspective-projection3d? (camera3d-projection first))
           (perspective-projection3d? (camera3d-projection second)))
      (and (orthographic-projection3d? (camera3d-projection first))
           (orthographic-projection3d? (camera3d-projection second)))))

(define (check-view-id who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-camera who value)
  (unless (camera3d? value)
    (raise-argument-error who "camera3d?" value)))

(define (check-vec3 who value)
  (unless (vec3? value)
    (raise-argument-error who "vec3?" value)))

(define (check-finite-real who label value)
  (unless (finite-real? value)
    (raise-arguments-error who "a finite real value" label value)))

(define (check-unit who value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-argument-error who "finite real in [0, 1]" value)))
