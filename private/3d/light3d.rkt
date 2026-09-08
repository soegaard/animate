#lang racket/base

;;;
;;; Renderer-independent immutable 3D lights
;;;

(require (only-in racket/math pi)
         "../color-style.rkt"
         "../geometry.rkt"
         "light-attenuation3d.rkt"
         "shadow3d.rkt"
         "vec3.rkt")

(provide ambient-light3d ambient-light3d? ambient-light3d-id
         ambient-light3d-intensity ambient-light3d-color ambient-light3d-shadow
         directional-light3d directional-light3d? directional-light3d-id
         directional-light3d-direction directional-light3d-intensity
         directional-light3d-color directional-light3d-shadow
         point-light3d point-light3d? point-light3d-id point-light3d-position
         point-light3d-intensity point-light3d-color point-light3d-attenuation
         point-light3d-range point-light3d-shadow
         spot-light3d spot-light3d? spot-light3d-id spot-light3d-position
         spot-light3d-direction spot-light3d-intensity spot-light3d-color
         spot-light3d-inner-angle spot-light3d-outer-angle
         spot-light3d-attenuation spot-light3d-range spot-light3d-shadow
         light3d? light3d-id light3d-color light3d-intensity light3d-shadow light3d-kind
         default-lights3d)

;; Shadow descriptors arrive in V6. Reserving an explicit #f-only field now
;; makes later policy durable without accepting an untyped placeholder.
(struct ambient-light3d-value (id intensity color shadow) #:transparent)
(struct directional-light3d-value (id direction intensity color shadow) #:transparent)
(struct point-light3d-value (id position intensity color attenuation range shadow) #:transparent)
(struct spot-light3d-value
  (id position direction intensity color inner-angle outer-angle attenuation range shadow)
  #:transparent)

(define ambient-light3d? ambient-light3d-value?)
(define ambient-light3d-id ambient-light3d-value-id)
(define ambient-light3d-intensity ambient-light3d-value-intensity)
(define ambient-light3d-color ambient-light3d-value-color)
(define ambient-light3d-shadow ambient-light3d-value-shadow)
(define directional-light3d? directional-light3d-value?)
(define directional-light3d-id directional-light3d-value-id)
(define directional-light3d-direction directional-light3d-value-direction)
(define directional-light3d-intensity directional-light3d-value-intensity)
(define directional-light3d-color directional-light3d-value-color)
(define directional-light3d-shadow directional-light3d-value-shadow)
(define point-light3d? point-light3d-value?)
(define point-light3d-id point-light3d-value-id)
(define point-light3d-position point-light3d-value-position)
(define point-light3d-intensity point-light3d-value-intensity)
(define point-light3d-color point-light3d-value-color)
(define point-light3d-attenuation point-light3d-value-attenuation)
(define point-light3d-range point-light3d-value-range)
(define point-light3d-shadow point-light3d-value-shadow)
(define spot-light3d? spot-light3d-value?)
(define spot-light3d-id spot-light3d-value-id)
(define spot-light3d-position spot-light3d-value-position)
(define spot-light3d-direction spot-light3d-value-direction)
(define spot-light3d-intensity spot-light3d-value-intensity)
(define spot-light3d-color spot-light3d-value-color)
(define spot-light3d-inner-angle spot-light3d-value-inner-angle)
(define spot-light3d-outer-angle spot-light3d-value-outer-angle)
(define spot-light3d-attenuation spot-light3d-value-attenuation)
(define spot-light3d-range spot-light3d-value-range)
(define spot-light3d-shadow spot-light3d-value-shadow)

(define (light3d? value)
  (or (ambient-light3d? value) (directional-light3d? value)
      (point-light3d? value) (spot-light3d? value)))

(define (light3d-kind light)
  (cond [(ambient-light3d? light) 'ambient]
        [(directional-light3d? light) 'directional]
        [(point-light3d? light) 'point]
        [(spot-light3d? light) 'spot]
        [else (raise-argument-error 'light3d-kind "light3d?" light)]))

(define (light3d-id light)
  (case (light3d-kind light)
    [(ambient) (ambient-light3d-id light)] [(directional) (directional-light3d-id light)]
    [(point) (point-light3d-id light)] [(spot) (spot-light3d-id light)]))
(define (light3d-color light)
  (case (light3d-kind light)
    [(ambient) (ambient-light3d-color light)] [(directional) (directional-light3d-color light)]
    [(point) (point-light3d-color light)] [(spot) (spot-light3d-color light)]))
(define (light3d-intensity light)
  (case (light3d-kind light)
    [(ambient) (ambient-light3d-intensity light)] [(directional) (directional-light3d-intensity light)]
    [(point) (point-light3d-intensity light)] [(spot) (spot-light3d-intensity light)]))
(define (light3d-shadow light)
  (case (light3d-kind light)
    [(ambient) (ambient-light3d-shadow light)] [(directional) (directional-light3d-shadow light)]
    [(point) (point-light3d-shadow light)] [(spot) (spot-light3d-shadow light)]))

; ambient-light3d : [#:id symbol?] [#:intensity nonnegative-finite-real?]
;                   [#:color color-spec?] [#:shadow #f] -> ambient-light3d?
(define (ambient-light3d #:id [id 'ambient] #:intensity [intensity 1]
                         #:color [color "white"] #:shadow [shadow #f])
  (check-id 'ambient-light3d id) (check-intensity 'ambient-light3d intensity)
  (check-shadow 'ambient-light3d 'ambient shadow)
  (ambient-light3d-value id intensity (opaque-color 'ambient-light3d color) shadow))

; Direction travels away from the source. A surface facing `-direction` is lit.
(define (directional-light3d direction #:id [id 'key] #:intensity [intensity 1]
                             #:color [color "white"] #:shadow [shadow #f])
  (check-id 'directional-light3d id) (check-direction 'directional-light3d direction)
  (check-intensity 'directional-light3d intensity)
  (check-shadow 'directional-light3d 'directional shadow)
  (directional-light3d-value id (vec3-normalize direction) intensity
                              (opaque-color 'directional-light3d color) shadow))

(define (point-light3d position #:id [id 'point] #:intensity [intensity 1]
                       #:color [color "white"]
                       #:attenuation [attenuation (inverse-square-attenuation3d)]
                       #:range [range #f] #:shadow [shadow #f])
  (check-id 'point-light3d id) (check-position 'point-light3d position)
  (check-intensity 'point-light3d intensity) (check-attenuation 'point-light3d attenuation)
  (check-range 'point-light3d range) (check-shadow 'point-light3d 'point shadow)
  (point-light3d-value id position intensity (opaque-color 'point-light3d color)
                       attenuation range shadow))

(define (spot-light3d position direction #:id [id 'spot] #:intensity [intensity 1]
                      #:color [color "white"] #:inner-angle [inner-angle 0]
                      #:outer-angle [outer-angle (/ pi 4)]
                      #:attenuation [attenuation (inverse-square-attenuation3d)]
                      #:range [range #f] #:shadow [shadow #f])
  (check-id 'spot-light3d id) (check-position 'spot-light3d position)
  (check-direction 'spot-light3d direction) (check-intensity 'spot-light3d intensity)
  (check-cone-angles 'spot-light3d inner-angle outer-angle)
  (check-attenuation 'spot-light3d attenuation) (check-range 'spot-light3d range)
  (check-shadow 'spot-light3d 'spot shadow)
  (spot-light3d-value id position (vec3-normalize direction) intensity
                      (opaque-color 'spot-light3d color) inner-angle outer-angle
                      attenuation range shadow))

(define (check-id who value)
  (unless (symbol? value) (raise-argument-error who "symbol? as #:id" value)))
(define (check-position who value)
  (unless (vec3? value) (raise-argument-error who "vec3? position" value)))
(define (check-direction who value)
  (unless (vec3? value) (raise-argument-error who "vec3? direction" value))
  (when (zero? (vec3-length value))
    (raise-argument-error who "nonzero vec3? direction" value)))
(define (check-intensity who value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-argument-error who "nonnegative finite real?" value)))
(define (check-attenuation who value)
  (unless (light-attenuation3d? value)
    (raise-argument-error who "light-attenuation3d?" value)))
(define (check-range who value)
  (unless (or (not value) (and (finite-real? value) (positive? value)))
    (raise-argument-error who "#f or positive finite real? as #:range" value)))
(define (check-shadow who kind value)
  (cond [(not value) (void)]
        [(and (eq? kind 'directional) (directional-shadow3d? value)) (void)]
        [(and (eq? kind 'spot) (spot-shadow3d? value)) (void)]
        [(eq? kind 'ambient)
         (raise-arguments-error who "#f: ambient light has no directional shadow map"
                                "shadow" value)]
        [(eq? kind 'point)
         (raise-arguments-error who "#f: point-light cube shadows are deferred"
                                "shadow" value)]
        [else
         (raise-arguments-error
          who
          (case kind
            [(directional) "#f or directional-shadow3d? as #:shadow"]
            [(spot) "#f or spot-shadow3d? as #:shadow"])
          "shadow" value)]))
(define (check-cone-angles who inner-angle outer-angle)
  ;; Delegate the shared validation to the cone-factor implementation.
  (void (spot-cone-factor3d inner-angle outer-angle 0)))
(define (opaque-color who value)
  (unless (color-spec? value) (raise-argument-error who "color-spec?" value))
  (define resolved (color-spec->rgba-color value who))
  (unless (= (rgba-color-alpha resolved) 1)
    (raise-arguments-error who "an opaque light color" "color" value))
  resolved)

;; Empty `#:lights` uses these stable, distinct identities.
(define default-lights3d
  (list (ambient-light3d #:id 'ambient #:intensity 1/4)
        (directional-light3d (vec3 1 1 -1) #:id 'key #:intensity 3/4)))
