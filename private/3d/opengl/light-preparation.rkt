#lang racket/base

;;;
;;; OpenGL Numerical Light Preparation
;;;

;; Converts already-resolved immutable lights into the compact numerical stream
;; consumed by the GLSL upload adapter. This module deliberately has no GL or
;; GUI dependency, so themed-light validation is testable headlessly.

(require "../../color-style.rkt"
         "../color-space3d.rkt"
         "../light-attenuation3d.rkt"
         "../light3d.rkt"
         "../vec3.rkt")

(provide (struct-out gl-light-record)
         pack-opengl-lights
         opengl-light-packing-datum)

;; gl-light-record is one already-resolved non-ambient shader record. Its
;; ordering is the authored light ordering with ambient entries omitted.
(struct gl-light-record
  (id kind direction position color intensity attenuation-mode attenuation-a attenuation-b attenuation-c
      attenuation-cutoff range inner-angle outer-angle)
  #:transparent)

;; pack-opengl-lights : (listof light3d?) -> real? real? real? (listof gl-light-record?)
;; Produces linear ambient totals and concrete non-ambient upload records.
(define (pack-opengl-lights lights)
  (check-resolved-opengl-lights lights)
  (define-values (ambient-red ambient-green ambient-blue records)
    (for/fold ([red 0.0] [green 0.0] [blue 0.0] [reversed-records '()])
              ([light (in-list lights)])
      (cond
        [(ambient-light3d? light)
         (define linear (rgba-srgb->linear (ambient-light3d-color light)))
         (values (+ red (* (ambient-light3d-intensity light) (linear-rgba3d-red linear)))
                 (+ green (* (ambient-light3d-intensity light) (linear-rgba3d-green linear)))
                 (+ blue (* (ambient-light3d-intensity light) (linear-rgba3d-blue linear)))
                 reversed-records)]
        [(directional-light3d? light)
         (values red green blue
                 (cons (gl-light-record
                        (directional-light3d-id light)
                        0 (directional-light3d-direction light) origin3
                        (directional-light3d-color light) (directional-light3d-intensity light)
                        0 1 0 0 -1 -1 0 0)
                       reversed-records))]
        [(point-light3d? light)
         (values red green blue
                 (cons (finite-light->gl-record
                        (point-light3d-id light)
                        1 (point-light3d-position light) origin3
                        (point-light3d-color light) (point-light3d-intensity light)
                        (point-light3d-attenuation light) (point-light3d-range light) 0 0)
                       reversed-records))]
        [(spot-light3d? light)
         (values red green blue
                 (cons (finite-light->gl-record
                        (spot-light3d-id light)
                        2 (spot-light3d-position light) (spot-light3d-direction light)
                        (spot-light3d-color light) (spot-light3d-intensity light)
                        (spot-light3d-attenuation light) (spot-light3d-range light)
                        (spot-light3d-inner-angle light) (spot-light3d-outer-angle light))
                       reversed-records))]
        [else
         (raise-argument-error 'pack-opengl-lights "light3d?" light)])))
  (values ambient-red ambient-green ambient-blue (reverse records)))

;; opengl-light-packing-datum : (listof light3d?) -> immutable-hash?
;; Returns a headless test/diagnostic summary of the exact numerical boundary.
(define (opengl-light-packing-datum lights)
  (define-values (ambient-red ambient-green ambient-blue records)
    (pack-opengl-lights lights))
  (hasheq 'ambient-linear (list ambient-red ambient-green ambient-blue)
          'non-ambient
          (for/list ([record (in-list records)])
            (hasheq 'id (gl-light-record-id record)
                    'kind (gl-light-record-kind record)
                    'color (gl-light-record-color record)
                    'intensity (gl-light-record-intensity record)))))

(define (check-resolved-opengl-lights lights)
  (unless (and (list? lights) (andmap light3d? lights))
    (raise-argument-error 'pack-opengl-lights "(listof light3d?)" lights))
  (for ([light (in-list lights)])
    (unless (rgba-color? (light3d-color light))
      (raise-arguments-error
       'pack-opengl-lights
       "lights resolved to RGBA before OpenGL numerical packing"
       "light-id" (light3d-id light)
       "color" (light3d-color light)))))

(define (finite-light->gl-record id kind position direction color intensity attenuation range inner outer)
  (define parameters (light-attenuation3d-parameters attenuation))
  (define-values (mode a b c cutoff)
    (case (light-attenuation3d-mode attenuation)
      [(constant)
       (values 0 (hash-ref parameters 'factor) 0 0 -1)]
      [(inverse-square)
       (values 1 0 0 (hash-ref parameters 'reference-distance)
               (or (hash-ref parameters 'cutoff) -1))]
      [(polynomial)
       (values 2 (hash-ref parameters 'constant) (hash-ref parameters 'linear)
               (hash-ref parameters 'quadratic) (or (hash-ref parameters 'cutoff) -1))]))
  (gl-light-record id kind direction position color intensity mode a b c cutoff
                   (or range -1) inner outer))
