#lang racket/base

;;; SCENE-3D-H Sweep Tests

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define profile (list (vec2 -1/10 -1/10) (vec2 1/10 -1/10)
                        (vec2 1/10 1/10) (vec2 -1/10 1/10)))
  (define path (polyline3d (list origin3 (vec3 1 0 0) (vec3 1 1 0)) #:id 'path))
  (define swept (sweep3d profile path #:id 'swept))
  (check-equal? (vector-length (mesh3d-vertices swept)) 12)
  (check-true (positive? (vector-length (mesh3d-triangles swept))))
  (check-not-false (mesh3d-normals swept)))
