#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define triangle
    (mesh3d #:id 'triangle
            #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
            #:triangles (vector (vector 0 1 2))))
  (define nested
    (group3d (list triangle) #:id 'inner
             #:transform (make-transform3 #:translation (vec3 1 0 0))))
  (define world
    (view3d (list nested) #:id 'world #:width 6 #:height 4
            #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 0 0 6)
                                           #:look-at origin3)))
  (define inspections (view3d-spatial-inspections world))
  (check-equal? (map spatial-inspection-path inspections)
                '((world inner) (world inner triangle)))
  (define leaf (list-ref inspections 1))
  (check-eq? (spatial-inspection-kind leaf) 'mesh)
  (check-equal? (spatial-inspection-triangle-count leaf) 1)
  (check-equal? (spatial-inspection-vertex-count leaf) 3)
  (check-equal? (affine3-apply-point (spatial-inspection-world-transform leaf) origin3)
                (vec3 1 0 0))
  (check-true (aabb3-contains? (spatial-inspection-world-bounds leaf) (vec3 1 0 0)))
  (check-equal? (spatial-inspection-camera-position leaf) (vec3 0 0 6))
  (check-true (vec3? (spatial-inspection-view-position leaf)))
  (check-not-false (spatial-inspection-projected-position leaf))
  (check-true (positive? (spatial-inspection-view-depth leaf)))
  (check-eq? (spatial-inspection-kind (car inspections)) 'group)
  (check-equal? (view3d-spatial-inspection-at world '(world inner triangle)) leaf))
