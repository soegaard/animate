#lang racket/base

;;;
;;; Surface Colour Fields
;;;

;; Declares deterministic per-vertex colour fields over a fixed surface grid.
;; Colours are semantic RGBA values; the opaque renderer rejects transparency
;; before rasterization just as it does for materials.


;;;
;;; Imports and Exports
;;;

(require "../color-style.rkt"
         "../geometry.rkt"
         "material3d.rkt"
         "parametric-surface3d.rkt"
         "surface-grid.rkt"
         "vec3.rkt")

(provide surface-color
         surface-color-by-height
         surface-color-by-scalar
         surface-checkerboard
         surface-wireframe)


;;;
;;; Uniform and Scalar Colouring
;;;

; surface-color : surface3d? color-spec? -> surface3d?
;;   Replaces the surface material's base colour without changing its topology.
(define (surface-color surface color)
  (unless (surface3d? surface) (raise-argument-error 'surface-color "surface3d?" surface))
  (unless (color-spec? color) (raise-argument-error 'surface-color "color-spec?" color))
  (surface3d-with-material surface
                           (material-with-color (surface3d-material surface) color)))

; surface-color-by-height : surface3d? [#:low color-spec?] [#:high color-spec?]
;                           -> surface3d?
;;   Interpolates per-vertex colour from the sampled local z coordinate.
(define (surface-color-by-height surface #:low [low "midnightblue"]
                                 #:high [high "gold"])
  (surface-color-by-scalar surface vec3-z #:low low #:high high))

; surface-color-by-scalar : surface3d? (vec3? -> finite-real?)
;                           [#:low color-spec?] [#:high color-spec?] -> surface3d?
;;   Maps a deterministic scalar value at each existing sample to a colour ramp.
(define (surface-color-by-scalar surface scalar
                                 #:low [low "midnightblue"]
                                 #:high [high "gold"])
  (unless (surface3d? surface) (raise-argument-error 'surface-color-by-scalar "surface3d?" surface))
  (unless (procedure? scalar) (raise-argument-error 'surface-color-by-scalar "procedure?" scalar))
  (define low-color (resolved-color 'surface-color-by-scalar low))
  (define high-color (resolved-color 'surface-color-by-scalar high))
  (define values
    (for/vector ([point (in-vector (surface3d-points surface))])
      (define value (scalar point))
      (unless (finite-real? value)
        (raise-arguments-error 'surface-color-by-scalar "a finite scalar result"
                               "point" point "result" value))
      value))
  (define minimum (for/fold ([minimum +inf.0]) ([value (in-vector values)]) (min minimum value)))
  (define maximum (for/fold ([maximum -inf.0]) ([value (in-vector values)]) (max maximum value)))
  (surface3d-with-colors
   surface
   (for/vector ([value (in-vector values)])
     (rgba-color-lerp low-color high-color
                      (if (= minimum maximum) 1/2 (/ (- value minimum) (- maximum minimum)))))))


;;;
;;; Structured Fields
;;;

; surface-checkerboard : surface3d? [#:u-cells exact-positive-integer?]
;                        [#:v-cells exact-positive-integer?] ... -> surface3d?
;;   Colours samples by a deterministic parameter-space checkerboard field.
(define (surface-checkerboard surface
                              #:u-cells [u-cells 8]
                              #:v-cells [v-cells 8]
                              #:first [first "lightsteelblue"]
                              #:second [second "white"])
  (unless (surface3d? surface) (raise-argument-error 'surface-checkerboard "surface3d?" surface))
  (unless (and (exact-positive-integer? u-cells) (exact-positive-integer? v-cells))
    (raise-argument-error 'surface-checkerboard "positive exact cell counts" (list u-cells v-cells)))
  (define first-color (resolved-color 'surface-checkerboard first))
  (define second-color (resolved-color 'surface-checkerboard second))
  (define u-range (surface3d-u-range surface))
  (define v-range (surface3d-v-range surface))
  (define grid (surface3d-grid surface))
  (surface3d-with-colors
   surface
   (for*/vector ([u (in-vector (surface-grid-u-values grid))]
                 [v (in-vector (surface-grid-v-values grid))])
     (define u-cell (min (sub1 u-cells)
                         (inexact->exact (floor (* u-cells (/ (- u (first u-range))
                                                               (- (second u-range) (first u-range))))))))
     (define v-cell (min (sub1 v-cells)
                         (inexact->exact (floor (* v-cells (/ (- v (first v-range))
                                                               (- (second v-range) (first v-range))))))))
     (if (even? (+ u-cell v-cell)) first-color second-color))))

; surface-wireframe : surface3d? -> surface3d?
;;   Marks a surface material for declaration as a wireframe intent.  Rendering
;; that intent is available in a `view3d` using global `'wireframe` mode; an
;; opaque wireframe overlay awaits the later transparency/overlay stage.
(define (surface-wireframe surface)
  (unless (surface3d? surface) (raise-argument-error 'surface-wireframe "surface3d?" surface))
  (define material (surface3d-material surface))
  (surface3d-with-material
   surface
   (material3d #:color (material3d-color material)
               #:shading (material3d-shading material)
               #:ambient (material3d-ambient material)
               #:diffuse (material3d-diffuse material)
               #:specular (material3d-specular material)
               #:roughness (material3d-roughness material)
               #:double-sided? (material3d-double-sided? material)
               #:wireframe? #t)))


;;;
;;; Local Helpers
;;;

(define (resolved-color who color)
  (color-spec->rgba-color color who))

(define (material-with-color material color)
  (material3d #:color color
              #:shading (material3d-shading material)
              #:ambient (material3d-ambient material)
              #:diffuse (material3d-diffuse material)
              #:specular (material3d-specular material)
              #:roughness (material3d-roughness material)
              #:double-sided? (material3d-double-sided? material)
              #:wireframe? (material3d-wireframe? material)))
