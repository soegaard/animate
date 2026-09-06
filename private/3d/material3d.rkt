#lang racket/base

;;; 3D Materials

(require "../color-style.rkt"
         "../geometry.rkt")

(provide material3d
         material3d?
         material3d-color
         material3d-shading
         material3d-ambient
         material3d-diffuse
         material3d-specular
         material3d-roughness
         material3d-double-sided?
         material3d-wireframe?
         default-material3d)

;; Material values are deliberately renderer independent.  Alpha belongs to
;; the resolved material colour; SCENE-3D-I's renderer decides how translucent
;; triangles are sorted and composited rather than baking a backend policy
;; into the model.
(struct material3d-value
  (color shading ambient diffuse specular roughness double-sided? wireframe?)
  #:transparent)

(define material3d? material3d-value?)
(define material3d-color material3d-value-color)
(define material3d-shading material3d-value-shading)
(define material3d-ambient material3d-value-ambient)
(define material3d-diffuse material3d-value-diffuse)
(define material3d-specular material3d-value-specular)
(define material3d-roughness material3d-value-roughness)
(define material3d-double-sided? material3d-value-double-sided?)
(define material3d-wireframe? material3d-value-wireframe?)

; material3d : [#:color color-spec?] [#:shading (or/c 'unlit 'flat 'smooth)]
;              [#:ambient nonnegative-finite-real?]
;              [#:diffuse nonnegative-finite-real?]
;              [#:specular nonnegative-finite-real?]
;              [#:roughness positive-finite-real?]
;              [#:double-sided? boolean?] [#:wireframe? boolean?]
;              -> material3d?
;; Creates one surface material.  Specular values are retained as stable model
;; data but not yet rendered by the reference renderer.
(define (material3d #:color [color "cornflowerblue"]
                    #:shading [shading 'flat]
                    #:ambient [ambient 1]
                    #:diffuse [diffuse 1]
                    #:specular [specular 0]
                    #:roughness [roughness 1]
                    #:double-sided? [double-sided? #f]
                    #:wireframe? [wireframe? #f])
  (unless (color-spec? color)
    (raise-argument-error 'material3d "color-spec?" color))
  (define resolved-color (color-spec->rgba-color color 'material3d))
  (unless (memq shading '(unlit flat smooth))
    (raise-argument-error 'material3d "(or/c 'unlit 'flat 'smooth)" shading))
  (for ([value (in-list (list ambient diffuse specular))]
        [name (in-list '(ambient diffuse specular))])
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error 'material3d "nonnegative finite coefficients"
                             "coefficient" name "value" value)))
  (unless (and (finite-real? roughness) (positive? roughness))
    (raise-argument-error 'material3d "positive finite roughness" roughness))
  (unless (boolean? double-sided?)
    (raise-argument-error 'material3d "boolean?" double-sided?))
  (unless (boolean? wireframe?)
    (raise-argument-error 'material3d "boolean?" wireframe?))
  (material3d-value resolved-color shading ambient diffuse specular roughness
                    double-sided? wireframe?))

(define default-material3d (material3d))
