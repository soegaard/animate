#lang racket/base

;;;
;;; Spatial Animation Requests
;;;

;; Defines the pure request and compiled-value vocabulary for transformations
;; below a view3d.  Scene compilation owns path resolution; this module stays
;; independent of the ordinary 2D timeline and renderer layers.


;;;
;;; Imports and Exports
;;;

(require "spatial-path.rkt"
         "rotation3.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide move3d-to
         move3d-to-request?
         move3d-by
         move3d-by-request?
         rotate3d-to
         rotate3d-to-request?
         rotate3d-by
         rotate3d-by-request?
         scale3d-to
         scale3d-to-request?
         scale3d-by
         scale3d-by-request?
         transform3d-to
         transform3d-to-request?
         spatial-animation-request?
         (struct-out move3d-to-request)
         (struct-out move3d-by-request)
         (struct-out rotate3d-to-request)
         (struct-out rotate3d-by-request)
         (struct-out scale3d-to-request)
         (struct-out scale3d-by-request)
         (struct-out transform3d-to-request)
         (struct-out spatial-translation-animation)
         (struct-out spatial-rotation-animation)
         (struct-out spatial-scale-animation)
         (struct-out spatial-transform-animation)
         spatial-compiled-animation?)


;;;
;;; Requests
;;;

(struct move3d-to-request (target-path destination) #:transparent)
;; move3d-to-request records one absolute local spatial translation.
;;  - target-path  spatial-path?  rooted path beginning with a view3d identity.
;;  - destination  vec3?          requested final local translation.

(struct move3d-by-request (target-path delta) #:transparent)
;; move3d-by-request records one translation relative to the clip-start value.

(struct rotate3d-to-request (target-path rotation) #:transparent)
;; rotate3d-to-request records one absolute local orientation.

(struct rotate3d-by-request (target-path rotation) #:transparent)
;; rotate3d-by-request records an orientation composed after the clip-start
;; local orientation.  The rotation is normally made with axis-angle.

(struct scale3d-to-request (target-path scale) #:transparent)
;; scale3d-to-request records an absolute non-singular componentwise scale.

(struct scale3d-by-request (target-path factor) #:transparent)
;; scale3d-by-request records a componentwise scale factor applied at clip start.

(struct transform3d-to-request (target-path transform) #:transparent)
;; transform3d-to-request records a complete decomposed transform endpoint.


;;;
;;; Public Constructors
;;;

; move3d-to : spatial-path? vec3? -> move3d-to-request?
;;   Moves one spatial Visual to an absolute local position.
(define (move3d-to target-path destination)
  (check-target-path 'move3d-to target-path)
  (check-vec3 'move3d-to destination)
  (move3d-to-request target-path destination))

; move3d-by : spatial-path? vec3? -> move3d-by-request?
;;   Moves one spatial Visual by a local translation captured at clip start.
(define (move3d-by target-path delta)
  (check-target-path 'move3d-by target-path)
  (check-vec3 'move3d-by delta)
  (move3d-by-request target-path delta))

; rotate3d-to : spatial-path? rotation3? -> rotate3d-to-request?
;;   Rotates one spatial Visual to an absolute quaternion-backed orientation.
(define (rotate3d-to target-path rotation)
  (check-target-path 'rotate3d-to target-path)
  (unless (rotation3? rotation)
    (raise-argument-error 'rotate3d-to "rotation3?" rotation))
  (rotate3d-to-request target-path rotation))

; rotate3d-by : spatial-path? rotation3? -> rotate3d-by-request?
;;   Composes a local rotation after the clip-start orientation.  Use
;; (axis-angle axis radians) to author the delta explicitly.
(define (rotate3d-by target-path rotation)
  (check-target-path 'rotate3d-by target-path)
  (unless (rotation3? rotation)
    (raise-argument-error 'rotate3d-by "rotation3?" rotation))
  (rotate3d-by-request target-path rotation))

; scale3d-to : spatial-path? vec3? -> scale3d-to-request?
;;   Replaces one spatial Visual's componentwise scale without permitting zero.
(define (scale3d-to target-path scale)
  (check-target-path 'scale3d-to target-path)
  (check-nonsingular-scale 'scale3d-to scale)
  (scale3d-to-request target-path scale))

; scale3d-by : spatial-path? vec3? -> scale3d-by-request?
;;   Multiplies one spatial Visual's componentwise scale at clip start.
(define (scale3d-by target-path factor)
  (check-target-path 'scale3d-by target-path)
  (check-nonsingular-scale 'scale3d-by factor)
  (scale3d-by-request target-path factor))

; transform3d-to : spatial-path? transform3? -> transform3d-to-request?
;;   Replaces translation, rotation, and scale together at the clip endpoint.
(define (transform3d-to target-path transform)
  (check-target-path 'transform3d-to target-path)
  (unless (transform3? transform)
    (raise-argument-error 'transform3d-to "transform3?" transform))
  (transform3d-to-request target-path transform))


;;;
;;; Compiled Values
;;;

(struct spatial-translation-animation (target-path from to) #:transparent)
;; spatial-translation-animation stores exact local translation endpoints.

(struct spatial-rotation-animation (target-path from to) #:transparent)
;; spatial-rotation-animation stores quaternion-backed orientation endpoints.

(struct spatial-scale-animation (target-path from to) #:transparent)
;; spatial-scale-animation stores non-singular componentwise scale endpoints.

(struct spatial-transform-animation (target-path from to) #:transparent)
;; spatial-transform-animation stores complete decomposed transform endpoints.


;;;
;;; Predicates
;;;

; spatial-animation-request? : any/c -> boolean?
;;   Reports whether value is a SCENE-3D-D spatial transform request.
(define (spatial-animation-request? value)
  (or (move3d-to-request? value)
      (move3d-by-request? value)
      (rotate3d-to-request? value)
      (rotate3d-by-request? value)
      (scale3d-to-request? value)
      (scale3d-by-request? value)
      (transform3d-to-request? value)))

; spatial-compiled-animation? : any/c -> boolean?
;;   Reports whether value is one compiled SCENE-3D-D spatial update.
(define (spatial-compiled-animation? value)
  (or (spatial-translation-animation? value)
      (spatial-rotation-animation? value)
      (spatial-scale-animation? value)
      (spatial-transform-animation? value)))


;;;
;;; Validation
;;;

(define (check-target-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error
     who
     "nonempty spatial path rooted at a view3d, such as '(world cube)"
     value)))

(define (check-vec3 who value)
  (unless (vec3? value)
    (raise-argument-error who "vec3?" value)))

(define (check-nonsingular-scale who value)
  (check-vec3 who value)
  (unless (and (not (zero? (vec3-x value)))
               (not (zero? (vec3-y value)))
               (not (zero? (vec3-z value))))
    (raise-argument-error who "vec3 with nonzero scale components" value)))
