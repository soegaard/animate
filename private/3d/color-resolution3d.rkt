#lang racket/base

;;;
;;; 3D Render-Time Colour Resolution
;;;

;; 3D authoring values retain immutable colour specifications.  This module is
;; the deliberately small boundary that turns those specifications into RGBA
;; values for one already-captured render colour context.  Keeping it outside
;; material3d.rkt and light3d.rkt prevents a selected theme from becoming
;; mutable state in the spatial model.

(require "../color-style.rkt"
         "../render-color-context.rkt"
         "light3d.rkt"
         "material3d.rkt")

(provide resolve-color3d
         resolve-color3d/opacity
         resolve-material3d
         resolve-light3d
         resolve-lights3d)

(define (resolve-color3d color context)
  (resolve-color-in-context color context))

(define (resolve-color3d/opacity color opacity context)
  (unless (and (real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'resolve-color3d/opacity "real in [0, 1]" opacity))
  (define resolved (resolve-color3d color context))
  (rgba-color (rgba-color-red resolved)
              (rgba-color-green resolved)
              (rgba-color-blue resolved)
              (* opacity (rgba-color-alpha resolved))))

;; resolve-material3d : material3d? render-color-context? -> material3d?
;; Produces a renderer-private material whose colour fields are all concrete
;; RGBA values.  The result deliberately reuses every non-colour authoring
;; coefficient exactly, so a theme never changes the lighting equation.
(define (resolve-material3d material context)
  (unless (material3d? material)
    (raise-argument-error 'resolve-material3d "material3d?" material))
  (material3d #:color (resolve-color3d (material3d-color material) context)
              #:shading (material3d-shading material)
              #:lighting (material3d-lighting material)
              #:ambient (material3d-ambient material)
              #:diffuse (material3d-diffuse material)
              #:specular (material3d-specular material)
              #:specular-color
              (resolve-color3d (material3d-specular-color material) context)
              #:roughness (material3d-roughness material)
              #:emission (resolve-color3d (material3d-emission material) context)
              #:emission-strength (material3d-emission-strength material)
              #:double-sided? (material3d-double-sided? material)
              #:casts-shadow? (material3d-casts-shadow? material)
              #:receives-shadow? (material3d-receives-shadow? material)
              #:wireframe? (material3d-wireframe? material)))

;; A light has always required opaque colour.  Literal values are rejected by
;; its constructor; a token or expression can only be checked after its theme
;; resolves, immediately before a renderer uses it.
(define (resolved-light-color who light context)
  (define color (resolve-color3d (light3d-color light) context))
  (unless (= (rgba-color-alpha color) 1)
    (raise-arguments-error
     who
     "a light whose resolved color is opaque"
     "light-id" (light3d-id light)
     "color" color))
  color)

;; resolve-light3d : light3d? render-color-context? -> light3d?
(define (resolve-light3d light context)
  (unless (light3d? light)
    (raise-argument-error 'resolve-light3d "light3d?" light))
  (define color (resolved-light-color 'resolve-light3d light context))
  (cond
    [(ambient-light3d? light)
     (ambient-light3d #:id (ambient-light3d-id light)
                      #:intensity (ambient-light3d-intensity light)
                      #:color color #:shadow (ambient-light3d-shadow light))]
    [(directional-light3d? light)
     (directional-light3d (directional-light3d-direction light)
                          #:id (directional-light3d-id light)
                          #:intensity (directional-light3d-intensity light)
                          #:color color #:shadow (directional-light3d-shadow light))]
    [(point-light3d? light)
     (point-light3d (point-light3d-position light)
                    #:id (point-light3d-id light)
                    #:intensity (point-light3d-intensity light)
                    #:color color
                    #:attenuation (point-light3d-attenuation light)
                    #:range (point-light3d-range light)
                    #:shadow (point-light3d-shadow light))]
    [else
     (spot-light3d (spot-light3d-position light) (spot-light3d-direction light)
                   #:id (spot-light3d-id light)
                   #:intensity (spot-light3d-intensity light)
                   #:color color
                   #:inner-angle (spot-light3d-inner-angle light)
                   #:outer-angle (spot-light3d-outer-angle light)
                   #:attenuation (spot-light3d-attenuation light)
                   #:range (spot-light3d-range light)
                   #:shadow (spot-light3d-shadow light))]))

(define (resolve-lights3d lights context)
  (unless (and (list? lights) (andmap light3d? lights))
    (raise-argument-error 'resolve-lights3d "(listof light3d?)" lights))
  (for/list ([light (in-list lights)])
    (resolve-light3d light context)))
