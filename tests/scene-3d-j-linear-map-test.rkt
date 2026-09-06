#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define shear
    (linear3 1 0 1
             0 1 0
             0 0 1))
  (define diagram (linear-transformation-diagram3d #:id 'diagram #:vector (vec3 1 2 1)))
  (define world
    (view3d (list diagram) #:id 'world #:render-mode 'wireframe))
  (define scene
    (scene-play
     (scene-add (make-scene) world)
     (apply-linear3 '(world diagram) shear)
     #:duration 2))

  ;; The author-provided spatial subtree is retained exactly at clip start.
  (check-equal? (view3d-spatial-ref (scene-visual-at scene 'world 0) '(world diagram))
                diagram)

  ;; The wrapper leaves descendant paths visible and maps their full world
  ;; coordinates, not merely an independently rebuilt cube mesh.
  (define mapped-view (scene-visual-at scene 'world 2))
  (check-true (view3d-spatial-has? mapped-view '(world diagram basis i)))
  (define i-map
    (view3d-spatial-world-transform mapped-view '(world diagram basis i)))
  (check-equal? (affine3-apply-point i-map origin3) origin3)
  (check-equal? (affine3-apply-point i-map x-axis3) x-axis3)
  (define k-map
    (view3d-spatial-world-transform mapped-view '(world diagram basis k)))
  (check-equal? (affine3-apply-point k-map z-axis3) (vec3 1 0 1))

  ;; An affine request includes its translation and preserves the exact mapped
  ;; source identity at all nonzero samples.
  (define shifted
    (scene-play
     (scene-add (make-scene) world)
     (apply-affine3 '(world diagram)
                    (affine3 identity-linear3 (vec3 2 -1 0)))
     #:duration 1))
  (define shifted-map
    (view3d-spatial-world-transform
     (scene-visual-at shifted 'world 1) '(world diagram vector)))
  (check-equal? (affine3-apply-point shifted-map origin3) (vec3 2 -1 0)))
