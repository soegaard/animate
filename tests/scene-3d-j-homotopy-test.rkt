#lang racket/base

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define source
    (mesh3d #:id 'triangle
            #:vertices (vector (vec3 0 0 0) (vec3 1 0 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))))
  (define world (view3d (list source) #:id 'world #:render-mode 'wireframe))
  (define scene
    (scene-play
     (scene-add (make-scene) world)
     (apply-homotopy3
      '(world triangle)
      (lambda (point alpha)
        ;; alpha squared distinguishes direct H(p, alpha) sampling from an
        ;; interpolation between two endpoint meshes.
        (vec3 (vec3-x point) (vec3-y point) (* alpha alpha (vec3-x point)))))
     #:duration 2))

  (check-eq? (view3d-spatial-ref (scene-visual-at scene 'world 0) '(world triangle)) source)
  (define midpoint
    (view3d-spatial-ref (scene-visual-at scene 'world 1) '(world triangle)))
  (check-equal? (vector-ref (mesh3d-vertices midpoint) 1) (vec3 1 0 1/4))
  (define endpoint
    (view3d-spatial-ref (scene-visual-at scene 'world 2) '(world triangle)))
  (check-equal? (vector-ref (mesh3d-vertices endpoint) 1) (vec3 1 0 1)))
