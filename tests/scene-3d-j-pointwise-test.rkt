#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt"
         "../private/3d/spatial-map3d.rkt")

(module+ test
  (define source
    (mesh3d #:id 'triangle
            #:vertices (vector (vec3 0 0 0) (vec3 1 0 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))))
  (define world (view3d (list source) #:id 'world #:render-mode 'wireframe))
  (define scene
    (scene-play
     (scene-add (make-scene) world)
     (apply-pointwise3 '(world triangle)
                       (lambda (point)
                         (vec3 (+ 1 (* 2 (vec3-x point)))
                               (vec3-y point)
                               (vec3-z point))))
     #:duration 2))

  (check-eq? (view3d-spatial-ref (scene-visual-at scene 'world 0) '(world triangle)) source)
  ;; apply-pointwise3 blends from identity to F over its clip; its endpoint is
  ;; a transformed mesh with recomputed normals, not a pre-rendered image.
  (define midpoint
    (view3d-spatial-ref (scene-visual-at scene 'world 1) '(world triangle)))
  (check-equal? (vector-ref (mesh3d-vertices midpoint) 1) (vec3 2 0 0))
  (check-true (vector? (mesh3d-normals midpoint)))
  (define endpoint
    (view3d-spatial-ref (scene-visual-at scene 'world 2) '(world triangle)))
  (check-equal? (vector-ref (mesh3d-vertices endpoint) 1) (vec3 3 0 0))

  ;; The explicit drop policy removes each incident triangle, while the default
  ;; reports the invalid result rather than silently changing topology.
  (define two-triangles
    (mesh3d #:id 'two
            #:vertices (vector (vec3 0 0 0) (vec3 1 0 0)
                               (vec3 0 1 0) (vec3 1 1 0))
            #:triangles (vector (vector 0 1 2) (vector 1 3 2))))
  (define dropped
    (pointwise-map-mesh3d
     two-triangles identity-affine3 identity-affine3
     (lambda (point) (and (zero? (vec3-x point)) point))
     #:on-failure 'drop-triangle))
  (check-equal? (vector-length (mesh3d-triangles dropped)) 0)
  (check-exn exn:fail?
             (lambda ()
               (pointwise-map-mesh3d
                two-triangles identity-affine3 identity-affine3
                (lambda (_point) #f)))))
