#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define near
    (mesh3d #:id 'near
            #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))))
  (define far
    (mesh3d #:id 'far
            #:vertices (vector (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 0 1 -1))
            #:triangles (vector (vector 0 1 2))))
  (define world
    (view3d (list far near) #:id 'world #:width 4 #:height 4 #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 4) #:look-at origin3)))
  (define hit (view3d-pixel-pick world 100 100 #:width 200 #:height 200))
  (check-true (spatial-pick? hit))
  (check-equal? (spatial-pick-path hit) '(world near))
  (check-equal? (spatial-pick-triangle-index hit) 0)
  (check-= (vec3-z (spatial-pick-point hit)) 0 1e-12)
  (check-= (spatial-pick-distance hit) 4 1e-12)
  (check-eq? (spatial-inspection-kind (spatial-pick-inspection hit)) 'mesh)
  (check-equal? (length (hash-ref (spatial-pick-metadata hit) 'world-triangle)) 3)
  (check-true
   (andmap vec3? (hash-ref (spatial-pick-metadata hit) 'world-triangle)))
  (check-false (view3d-pixel-pick world 0 0 #:width 200 #:height 200)))
