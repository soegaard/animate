#lang racket/base

;;;
;;; Immutable finite-light animation values
;;;

;; Requests are intentionally scene-independent.  `animation.rkt` resolves the
;; `(view-id light-id)` target and captures its source fields at the exact clip
;; start.  The samplers below then work from those immutable endpoints for
;; forward playback, reverse playback, and arbitrary frame lookup alike.

(require "../color-style.rkt"
         "../geometry.rkt"
         "light-attenuation3d.rkt"
         "light3d.rkt"
         "rotation3.rkt"
         "vec3.rkt")

(provide light3d-intensity-to
         light3d-intensity-to-request?
         light3d-color-to
         light3d-color-to-request?
         point-light3d-move-to
         point-light3d-move-to-request?
         point-light3d-move-by
         point-light3d-move-by-request?
         spot-light3d-move-to
         spot-light3d-move-to-request?
         spot-light3d-aim-at
         spot-light3d-aim-at-request?
         spot-light3d-cone-to
         spot-light3d-cone-to-request?
         light3d-animation-request?
         (struct-out light3d-intensity-to-request)
         (struct-out light3d-color-to-request)
         (struct-out point-light3d-move-to-request)
         (struct-out point-light3d-move-by-request)
         (struct-out spot-light3d-move-to-request)
         (struct-out spot-light3d-aim-at-request)
         (struct-out spot-light3d-cone-to-request)
         (struct-out light3d-intensity-animation)
         (struct-out light3d-color-animation)
         (struct-out point-light3d-position-animation)
         (struct-out spot-light3d-position-animation)
         (struct-out spot-light3d-direction-animation)
         (struct-out spot-light3d-cone-animation)
         light3d-compiled-animation?
         light3d-color-sample
         light3d-direction-sample)

;;;
;;; Requests
;;;

(struct light3d-intensity-to-request (view-id light-id destination) #:transparent)
(struct light3d-color-to-request (view-id light-id destination) #:transparent)
(struct point-light3d-move-to-request (view-id light-id destination) #:transparent)
(struct point-light3d-move-by-request (view-id light-id delta) #:transparent)
(struct spot-light3d-move-to-request (view-id light-id destination) #:transparent)
(struct spot-light3d-aim-at-request (view-id light-id target) #:transparent)
(struct spot-light3d-cone-to-request (view-id light-id inner-angle outer-angle) #:transparent)

; light3d-intensity-to : symbol? symbol? nonnegative-finite-real? -> request?
(define (light3d-intensity-to view-id light-id destination)
  (check-target 'light3d-intensity-to view-id light-id)
  (check-intensity 'light3d-intensity-to destination)
  (light3d-intensity-to-request view-id light-id destination))

; light3d-color-to : symbol? symbol? color-spec? -> request?
(define (light3d-color-to view-id light-id destination)
  (check-target 'light3d-color-to view-id light-id)
  (light3d-color-to-request view-id light-id
                            (opaque-color 'light3d-color-to destination)))

; point-light3d-move-to : symbol? symbol? vec3? -> request?
(define (point-light3d-move-to view-id light-id destination)
  (check-target 'point-light3d-move-to view-id light-id)
  (check-vec3 'point-light3d-move-to destination)
  (point-light3d-move-to-request view-id light-id destination))

; point-light3d-move-by : symbol? symbol? vec3? -> request?
(define (point-light3d-move-by view-id light-id delta)
  (check-target 'point-light3d-move-by view-id light-id)
  (check-vec3 'point-light3d-move-by delta)
  (point-light3d-move-by-request view-id light-id delta))

; spot-light3d-move-to : symbol? symbol? vec3? -> request?
(define (spot-light3d-move-to view-id light-id destination)
  (check-target 'spot-light3d-move-to view-id light-id)
  (check-vec3 'spot-light3d-move-to destination)
  (spot-light3d-move-to-request view-id light-id destination))

; spot-light3d-aim-at : symbol? symbol? vec3? -> request?
(define (spot-light3d-aim-at view-id light-id target)
  (check-target 'spot-light3d-aim-at view-id light-id)
  (check-vec3 'spot-light3d-aim-at target)
  (spot-light3d-aim-at-request view-id light-id target))

; spot-light3d-cone-to : symbol? symbol? nonnegative-finite-real?
;                        positive-finite-real? -> request?
(define (spot-light3d-cone-to view-id light-id inner-angle outer-angle)
  (check-target 'spot-light3d-cone-to view-id light-id)
  ;; This shared evaluator owns the exact `0 <= inner <= outer <= pi` rule.
  (spot-cone-factor3d inner-angle outer-angle 0)
  (spot-light3d-cone-to-request view-id light-id inner-angle outer-angle))

(define (light3d-animation-request? value)
  (or (light3d-intensity-to-request? value)
      (light3d-color-to-request? value)
      (point-light3d-move-to-request? value)
      (point-light3d-move-by-request? value)
      (spot-light3d-move-to-request? value)
      (spot-light3d-aim-at-request? value)
      (spot-light3d-cone-to-request? value)))

;;;
;;; Clip-start compiled values
;;;

;; Every record preserves both target symbols, rather than treating a light as
;; a fake spatial child.  `from` is read once at compilation and is never
;; overwritten by a prior sampled frame.
(struct light3d-intensity-animation (view-id light-id from to) #:transparent)
(struct light3d-color-animation (view-id light-id from to) #:transparent)
(struct point-light3d-position-animation (view-id light-id from to) #:transparent)
(struct spot-light3d-position-animation (view-id light-id from to) #:transparent)
(struct spot-light3d-direction-animation (view-id light-id from to) #:transparent)
(struct spot-light3d-cone-animation
  (view-id light-id from-inner from-outer to-inner to-outer)
  #:transparent)

(define (light3d-compiled-animation? value)
  (or (light3d-intensity-animation? value)
      (light3d-color-animation? value)
      (point-light3d-position-animation? value)
      (spot-light3d-position-animation? value)
      (spot-light3d-direction-animation? value)
      (spot-light3d-cone-animation? value)))

;;;
;;; Pure samplers
;;;

;; Light colors retain their authored semantic specifications through an
;; animation.  `color-mix` declares the existing linear-light policy without
;; forcing a theme lookup while a scene is sampled.
(define (light3d-color-sample from to progress)
  (unless (color-spec? from)
    (raise-argument-error 'light3d-color-sample "color-spec?" from))
  (unless (color-spec? to)
    (raise-argument-error 'light3d-color-sample "color-spec?" to))
  (check-unit 'light3d-color-sample progress)
  (color-mix from to progress))

;; A normalized vector lerp is smooth and inexpensive away from a half-turn.
;; Near opposite directions it becomes numerically ill-conditioned, so sample
;; the deterministic quaternion rotation instead. `rotation3-from-to` supplies
;; a stable perpendicular axis for the exact antipodal case.
(define (light3d-direction-sample from to progress)
  (check-direction 'light3d-direction-sample from)
  (check-direction 'light3d-direction-sample to)
  (check-unit 'light3d-direction-sample progress)
  (cond [(zero? progress) from]
        [(= progress 1) to]
        [else
         (define unit-from (vec3-normalize from))
         (define unit-to (vec3-normalize to))
         (if (< (vec3-dot unit-from unit-to) -0.999)
             (rotation3-apply
              (rotation3-slerp identity-rotation3
                               (rotation3-from-to unit-from unit-to)
                               progress)
              unit-from)
             (vec3-normalize (vec3-lerp unit-from unit-to progress)))]))

;;;
;;; Validation
;;;

(define (check-target who view-id light-id)
  (unless (symbol? view-id)
    (raise-argument-error who "symbol? view ID" view-id))
  (unless (symbol? light-id)
    (raise-argument-error who "symbol? light ID" light-id)))

(define (check-intensity who value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-argument-error who "nonnegative finite real?" value)))

(define (check-vec3 who value)
  (unless (vec3? value)
    (raise-argument-error who "vec3?" value)))

(define (check-direction who value)
  (check-vec3 who value)
  (when (zero? (vec3-length value))
    (raise-argument-error who "nonzero vec3? direction" value)))

(define (check-unit who progress)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error who "finite real in [0, 1]" progress)))

(define (opaque-color who value)
  (unless (color-spec? value)
    (raise-argument-error who "color-spec?" value))
  (define normalized (normalize-color-spec value who))
  (when (and (rgba-color? normalized)
             (not (= (rgba-color-alpha normalized) 1)))
    (raise-argument-error who "opaque literal color-spec?" value))
  normalized)

(define (check-opaque-rgba who value)
  (unless (and (rgba-color? value) (= (rgba-color-alpha value) 1))
    (raise-argument-error who "opaque rgba-color?" value)))
