#lang racket/base

;;; SCENE-3D-H Extrusion Tests

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  (define square (list (vec2 -1 -1) (vec2 1 -1) (vec2 1 1) (vec2 -1 1)))
  (define solid (extrude3d square #:id 'solid #:vector (vec3 0 0 2)))
  (check-equal? (vector-length (mesh3d-vertices solid)) 8)
  (check-equal? (vector-length (mesh3d-triangles solid)) 12)
  (check-equal? (vector-length (mesh3d-boundary-edges solid)) 0)
  (check-exn exn:fail? (lambda () (extrude3d square #:id 'flat #:vector x-axis3)))
  (check-exn exn:fail? (lambda () (extrude3d (list (vec2 0 0) (vec2 1 1) (vec2 0 1) (vec2 1 0)) #:id 'bow))))
