#lang racket/base

;;; Themeable sampled surface fields retain their geometry

(require rackunit
         "../3d.rkt"
         "../colors.rkt")

(module+ test
  (define surface
    (parametric-surface3d
     (lambda (u v) (vec3 u v (+ (* u u) (* 1/4 v))))
     #:id 'themed-surface #:resolution '(5 4)))
  (define coloured
    (surface-color-by-scalar surface vec3-z #:low aqua-c #:high theme-accent))
  ;; Colouring a retained field consumes its samples once. It does not rerun
  ;; the parameterization or alter the fixed topology when a theme is chosen.
  (check-equal? (surface3d-points coloured) (surface3d-points surface))
  (check-equal? (surface3d-resolution coloured) (surface3d-resolution surface))
  (check-true
   (for/and ([color (in-vector (surface3d-colors coloured))])
     (color-spec? color)))
  (check-true
   (for/or ([color (in-vector (surface3d-colors coloured))])
     (color-expression? color)))
  (define source-mesh (surface3d->mesh3d surface))
  (define coloured-mesh (surface3d->mesh3d coloured))
  (check-equal? (mesh3d-vertices coloured-mesh) (mesh3d-vertices source-mesh))
  (check-equal? (mesh3d-triangles coloured-mesh) (mesh3d-triangles source-mesh)))
