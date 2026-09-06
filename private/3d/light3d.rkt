#lang racket/base

;;; Renderer-independent 3D Lights

(require "../color-style.rkt"
         "../geometry.rkt"
         "vec3.rkt")

(provide ambient-light3d
         ambient-light3d?
         ambient-light3d-intensity
         ambient-light3d-color
         directional-light3d
         directional-light3d?
         directional-light3d-direction
         directional-light3d-intensity
         directional-light3d-color
         light3d?
         default-lights3d)

(struct ambient-light3d-value (intensity color) #:transparent)
(struct directional-light3d-value (direction intensity color) #:transparent)

(define ambient-light3d? ambient-light3d-value?)
(define ambient-light3d-intensity ambient-light3d-value-intensity)
(define ambient-light3d-color ambient-light3d-value-color)
(define directional-light3d? directional-light3d-value?)
(define directional-light3d-direction directional-light3d-value-direction)
(define directional-light3d-intensity directional-light3d-value-intensity)
(define directional-light3d-color directional-light3d-value-color)
(define (light3d? value)
  (or (ambient-light3d? value) (directional-light3d? value)))

; ambient-light3d : [#:intensity nonnegative-finite-real?]
;                   [#:color color-spec?] -> ambient-light3d?
(define (ambient-light3d #:intensity [intensity 1] #:color [color "white"])
  (check-intensity 'ambient-light3d intensity)
  (ambient-light3d-value intensity (opaque-color 'ambient-light3d color)))

; directional-light3d : vec3? [#:intensity nonnegative-finite-real?]
;                       [#:color color-spec?] -> directional-light3d?
;; Direction is the direction in which illumination travels.  A surface facing
;; `-direction` receives the diffuse contribution.
(define (directional-light3d direction
                             #:intensity [intensity 1]
                             #:color [color "white"])
  (unless (vec3? direction)
    (raise-argument-error 'directional-light3d "vec3?" direction))
  (when (zero? (vec3-length direction))
    (raise-argument-error 'directional-light3d "nonzero vec3?" direction))
  (check-intensity 'directional-light3d intensity)
  (directional-light3d-value (vec3-normalize direction)
                              intensity
                              (opaque-color 'directional-light3d color)))

(define (check-intensity who value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-argument-error who "nonnegative finite real?" value)))

(define (opaque-color who value)
  (unless (color-spec? value)
    (raise-argument-error who "color-spec?" value))
  (define resolved (color-spec->rgba-color value who))
  (unless (= (rgba-color-alpha resolved) 1)
    (raise-arguments-error who "an opaque light color" "color" value))
  resolved)

;; A quiet ambient fill plus a light travelling down and into the scene from
;; the viewer's upper left.  Empty `#:lights` lists use this deterministic set.
(define default-lights3d
  (list (ambient-light3d #:intensity 1/4)
        (directional-light3d (vec3 1 1 -1) #:intensity 3/4)))
