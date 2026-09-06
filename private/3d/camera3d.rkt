#lang racket/base

;;;
;;; Spatial Camera Model
;;;

;; Defines immutable 3D cameras.  Camera-local +x is screen-right, +y is
;; screen-up, and local -z is forward; this makes an identity camera at +z
;; looking toward the origin show world +x to the right and world +y upward.


;;;
;;; Imports and Exports
;;;

(require (only-in racket/math pi)
         "../geometry.rkt"
         "affine3.rkt"
         "projection3d.rkt"
         "ray-plane.rkt"
         "rotation3.rkt"
         "vec3.rkt")

(provide camera3d?
         perspective-camera3d
         orthographic-camera3d
         camera3d-position
         camera3d-rotation
         camera3d-near
         camera3d-far
         camera3d-projection
         camera3d-with-position
         camera3d-with-rotation
         camera3d-with-projection
         camera3d-forward
         camera3d-right
         camera3d-up
         camera3d-look-at
         camera3d-world->view
         camera3d-project
         camera3d-view-depth
         camera3d-pixel-ray
         camera3d-frustum
         camera3d-project-view)


;;;
;;; Camera Value
;;;

(struct camera3d-value (position rotation near far projection)
  #:transparent)

;; camera3d-value represents one immutable world-to-view camera.
;;  - position    vec3?         world position of the camera centre.
;;  - rotation    rotation3?    camera-local axes expressed in world coordinates.
;;  - near        positive-real? nearest visible positive forward depth.
;;  - far         positive-real? farthest visible forward depth, greater than near.
;;  - projection  projection3d? lens whose aspect is supplied by its viewport.

(define camera3d? camera3d-value?)
(define camera3d-position camera3d-value-position)
(define camera3d-rotation camera3d-value-rotation)
(define camera3d-near camera3d-value-near)
(define camera3d-far camera3d-value-far)
(define camera3d-projection camera3d-value-projection)


;;;
;;; Construction
;;;

; perspective-camera3d : [#:position vec3?] [#:look-at vec3?]
;                         [#:up vec3?] [#:rotation (or/c #f rotation3?)]
;                         [#:near positive-real?] [#:far positive-real?]
;                         [#:vertical-field-of-view finite-real?]
;                         -> camera3d?
;;   Creates a perspective camera looking from position toward look-at unless
;;   an explicit camera-local rotation is supplied.
(define (perspective-camera3d
         #:position [position (vec3 0 0 8)]
         #:look-at [look-at origin3]
         #:up [up y-axis3]
         #:rotation [rotation #f]
         #:near [near 1/10]
         #:far [far 100]
         #:vertical-field-of-view [vertical-field-of-view (/ pi 4)])
  (make-camera3d
   'perspective-camera3d position look-at up rotation near far
   (perspective-projection3d vertical-field-of-view)))

; orthographic-camera3d : [#:position vec3?] [#:look-at vec3?]
;                          [#:up vec3?] [#:rotation (or/c #f rotation3?)]
;                          [#:near positive-real?] [#:far positive-real?]
;                          [#:vertical-size positive-real?] -> camera3d?
;;   Creates a parallel orthographic camera with the requested visible height.
(define (orthographic-camera3d
         #:position [position (vec3 0 0 8)]
         #:look-at [look-at origin3]
         #:up [up y-axis3]
         #:rotation [rotation #f]
         #:near [near 1/10]
         #:far [far 100]
         #:vertical-size [vertical-size 6])
  (make-camera3d
   'orthographic-camera3d position look-at up rotation near far
   (orthographic-projection3d vertical-size)))

(define (make-camera3d who position look-at up rotation near far projection)
  (unless (vec3? position)
    (raise-argument-error who "vec3?" position))
  (unless (vec3? look-at)
    (raise-argument-error who "vec3?" look-at))
  (unless (vec3? up)
    (raise-argument-error who "vec3?" up))
  (unless (or (not rotation) (rotation3? rotation))
    (raise-argument-error who "(or/c #f rotation3?)" rotation))
  (check-near-far who near far)
  (define resolved-rotation
    (or rotation (look-rotation who position look-at up)))
  (camera3d-value position resolved-rotation near far projection))


;;;
;;; Immutable Camera Updates
;;;

; camera3d-with-position : camera3d? vec3? -> camera3d?
;;   Returns camera with its world-space position replaced exactly.
(define (camera3d-with-position camera position)
  (check-camera 'camera3d-with-position camera)
  (unless (vec3? position)
    (raise-argument-error 'camera3d-with-position "vec3?" position))
  (camera3d-value position
                  (camera3d-rotation camera)
                  (camera3d-near camera)
                  (camera3d-far camera)
                  (camera3d-projection camera)))

; camera3d-with-rotation : camera3d? rotation3? -> camera3d?
;;   Returns camera with its complete world orientation replaced exactly.
(define (camera3d-with-rotation camera rotation)
  (check-camera 'camera3d-with-rotation camera)
  (unless (rotation3? rotation)
    (raise-argument-error 'camera3d-with-rotation "rotation3?" rotation))
  (camera3d-value (camera3d-position camera)
                  rotation
                  (camera3d-near camera)
                  (camera3d-far camera)
                  (camera3d-projection camera)))

; camera3d-with-projection : camera3d? projection3d? -> camera3d?
;;   Returns camera with the same pose and clipping range but a new projection.
(define (camera3d-with-projection camera projection)
  (check-camera 'camera3d-with-projection camera)
  (unless (or (perspective-projection3d? projection)
              (orthographic-projection3d? projection))
    (raise-argument-error
     'camera3d-with-projection
     "(or/c perspective-projection3d? orthographic-projection3d?)"
     projection))
  (camera3d-value (camera3d-position camera)
                  (camera3d-rotation camera)
                  (camera3d-near camera)
                  (camera3d-far camera)
                  projection))


;;;
;;; Camera Axes and Look-at Updates
;;;

; camera3d-forward : camera3d? -> vec3?
;;   Returns the camera's world-space forward direction, corresponding to local -z.
(define (camera3d-forward camera)
  (check-camera 'camera3d-forward camera)
  (rotation3-apply (camera3d-rotation camera) (vec3 0 0 -1)))

; camera3d-right : camera3d? -> vec3?
;;   Returns the camera's world-space screen-right direction.
(define (camera3d-right camera)
  (check-camera 'camera3d-right camera)
  (rotation3-apply (camera3d-rotation camera) x-axis3))

; camera3d-up : camera3d? -> vec3?
;;   Returns the camera's world-space screen-up direction.
(define (camera3d-up camera)
  (check-camera 'camera3d-up camera)
  (rotation3-apply (camera3d-rotation camera) y-axis3))

; camera3d-look-at : camera3d? vec3? [#:up vec3?] -> camera3d?
;;   Returns camera reoriented toward target while retaining its projection range.
(define (camera3d-look-at camera target #:up [up y-axis3])
  (check-camera 'camera3d-look-at camera)
  (unless (vec3? target)
    (raise-argument-error 'camera3d-look-at "vec3?" target))
  (unless (vec3? up)
    (raise-argument-error 'camera3d-look-at "vec3?" up))
  (camera3d-value
   (camera3d-position camera)
   (look-rotation 'camera3d-look-at (camera3d-position camera) target up)
   (camera3d-near camera)
   (camera3d-far camera)
   (camera3d-projection camera)))


;;;
;;; Coordinate Conversion and Projection
;;;

; camera3d-world->view : camera3d? vec3? -> vec3?
;;   Converts a world point to camera-local coordinates; points ahead have z < 0.
(define (camera3d-world->view camera point)
  (check-camera 'camera3d-world->view camera)
  (unless (vec3? point)
    (raise-argument-error 'camera3d-world->view "vec3?" point))
  (rotation3-apply
   (rotation3-invert (camera3d-rotation camera))
   (vec3- point (camera3d-position camera))))

; camera3d-view-depth : camera3d? vec3? -> finite-real?
;;   Returns positive distance along the camera's forward (-z) axis.
(define (camera3d-view-depth camera point)
  (check-camera 'camera3d-view-depth camera)
  (- (vec3-z (camera3d-world->view camera point))))

; camera3d-project : camera3d? vec3? #:aspect positive-real? -> (or/c #f vec2?)
;;   Projects a world point to normalized viewport coordinates, or #f when it
;; is behind the camera or outside the inclusive near/far depth interval.
(define (camera3d-project camera point #:aspect [aspect 1])
  (check-camera 'camera3d-project camera)
  (check-aspect 'camera3d-project aspect)
  (define view-point (camera3d-world->view camera point))
  (camera3d-project-view camera view-point #:aspect aspect))

; camera3d-project-view : camera3d? vec3? #:aspect positive-real? -> (or/c #f vec2?)
;;   Projects an already camera-local point when its forward depth is visible.
(define (camera3d-project-view camera view-point #:aspect [aspect 1])
  (check-camera 'camera3d-project-view camera)
  (unless (vec3? view-point)
    (raise-argument-error 'camera3d-project-view "vec3?" view-point))
  (check-aspect 'camera3d-project-view aspect)
  (define depth (- (vec3-z view-point)))
  (and (<= (camera3d-near camera) depth (camera3d-far camera))
       (projection3d-project-view (camera3d-projection camera) view-point aspect)))

; camera3d-pixel-ray : camera3d? finite-real? finite-real?
;                      #:width exact-positive-integer? #:height exact-positive-integer?
;                      -> ray3?
;;   Returns the world ray through a pixel whose origin is at the top left.
(define (camera3d-pixel-ray camera pixel-x pixel-y #:width width #:height height)
  (check-camera 'camera3d-pixel-ray camera)
  (unless (finite-real? pixel-x)
    (raise-argument-error 'camera3d-pixel-ray "finite real?" pixel-x))
  (unless (finite-real? pixel-y)
    (raise-argument-error 'camera3d-pixel-ray "finite real?" pixel-y))
  (unless (exact-positive-integer? width)
    (raise-argument-error 'camera3d-pixel-ray "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'camera3d-pixel-ray "exact-positive-integer?" height))
  (define aspect (/ width height))
  (define normalized-x (- (* 2 (/ pixel-x width)) 1))
  (define normalized-y (- 1 (* 2 (/ pixel-y height))))
  (define projection (camera3d-projection camera))
  (define direction-local
    (cond [(perspective-projection3d? projection)
           (define half-height
             (projection3d-half-height projection 1))
           (vec3 (* normalized-x aspect half-height)
                 (* normalized-y half-height)
                 -1)]
          [else (vec3 0 0 -1)]))
  (define origin-local
    (cond [(perspective-projection3d? projection) origin3]
          [else
           (define half-height
             (projection3d-half-height projection (camera3d-near camera)))
           (vec3 (* normalized-x aspect half-height)
                 (* normalized-y half-height)
                 (- (camera3d-near camera)))]))
  (ray3
   (vec3+ (camera3d-position camera)
          (rotation3-apply (camera3d-rotation camera) origin-local))
   (rotation3-apply (camera3d-rotation camera)
                    (vec3-normalize direction-local))))

; camera3d-frustum : camera3d? #:aspect positive-real? -> (vectorof plane3?)
;;   Returns inward-facing near, far, left, right, bottom, and top clipping planes.
(define (camera3d-frustum camera #:aspect [aspect 1])
  (check-camera 'camera3d-frustum camera)
  (check-aspect 'camera3d-frustum aspect)
  (define projection (camera3d-projection camera))
  (define local-planes
    (append
     (list (cons (vec3 0 0 (- (camera3d-near camera))) (vec3 0 0 -1))
           (cons (vec3 0 0 (- (camera3d-far camera))) (vec3 0 0 1)))
     (if (perspective-projection3d? projection)
         (let ([half-height (projection3d-half-height projection 1)])
           (list (cons origin3 (vec3 1 0 (- (* aspect half-height))))
                 (cons origin3 (vec3 -1 0 (- (* aspect half-height))))
                 (cons origin3 (vec3 0 1 (- half-height)))
                 (cons origin3 (vec3 0 -1 (- half-height)))))
         (let* ([half-height (projection3d-half-height projection 1)]
                [half-width (* aspect half-height)])
           (list (cons (vec3 (- half-width) 0 0) x-axis3)
                 (cons (vec3 half-width 0 0) (vec3 -1 0 0))
                 (cons (vec3 0 (- half-height) 0) y-axis3)
                 (cons (vec3 0 half-height 0) (vec3 0 -1 0)))))))
  (vector->immutable-vector
   (for/vector ([local-plane (in-list local-planes)])
     (define local-point (car local-plane))
     (define local-normal (cdr local-plane))
     (plane3
      (vec3+ (camera3d-position camera)
             (rotation3-apply (camera3d-rotation camera) local-point))
      (rotation3-apply (camera3d-rotation camera) local-normal)))))


;;;
;;; Validation and Orientation
;;;

(define (look-rotation who position target up)
  (define forward (vec3- target position))
  (when (zero? (vec3-length forward))
    (raise-arguments-error who
                           "a look-at target distinct from camera position"
                           "position" position
                           "look-at" target))
  ;; rotation3-look-at maps local +z, while a camera sees along local -z.
  (rotation3-look-at (vec3-scale -1 forward) #:up up))

(define (check-camera who value)
  (unless (camera3d? value)
    (raise-argument-error who "camera3d?" value)))

(define (check-near-far who near far)
  (unless (and (finite-real? near) (positive? near))
    (raise-argument-error who "positive finite near distance" near))
  (unless (and (finite-real? far) (> far near))
    (raise-argument-error who "finite far distance greater than near" far)))

(define (check-aspect who aspect)
  (unless (and (finite-real? aspect) (positive? aspect))
    (raise-argument-error who "positive finite viewport aspect" aspect)))
