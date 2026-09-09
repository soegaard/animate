#lang racket/base

;;;
;;; 3D Semantic Color Interpolation Tests
;;;

;; Exercises pure 3D authoring operations only. Rendering preparation remains
;; responsible for resolving the expressions against an explicit theme.

(require rackunit
         "../3d.rkt"
         "../colors.rkt")

(module+ test
  (define material
    (material3d #:color aqua-c #:specular-color theme-accent #:emission red-c))
  (check-eq? (material3d-color material) aqua-c)
  (check-eq? (material3d-specular-color material) theme-accent)
  (check-eq? (material3d-emission material) red-c)
  (check-eq? (ambient-light3d-color (ambient-light3d #:color theme-accent))
             theme-accent)

  ;; A clipped edge retains a mix of authored tokens rather than resolving the
  ;; selected palette during topology processing.
  (define source
    (mesh3d #:id 'token-triangle
            #:vertices (vector (vec3 -1 0 0) (vec3 1 0 0) (vec3 1 1 0))
            #:triangles (vector (vector 0 1 2))
            #:colors (vector aqua-c red-c blue-c)))
  (define sliced
    (slice-mesh3d source (plane3 origin3 x-axis3) #:keep 'positive))
  (check-true
   (for/or ([color (in-vector (mesh3d-colors sliced))])
     (color-expression? color)))
  (check-not-exn
   (lambda ()
     (for ([color (in-vector (mesh3d-colors sliced))])
       (when (color-expression? color)
         (resolve-color color animate-dark-theme))))))
