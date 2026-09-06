#lang racket/base

;;; SCENE-3D-H Revolution Tests

(require rackunit
         "../main.rkt"
         "../3d.rkt")

(module+ test
  ;; The closed region under y = x from 0 to 1 rotates about the x axis.
  (define cone-region (list (vec2 0 0) (vec2 1 1) (vec2 1 0)))
  (define solid (revolve3d cone-region #:id 'revolution #:axis 'x #:segments 12))
  (check-true (positive? (vector-length (mesh3d-vertices solid))))
  (check-true (positive? (vector-length (mesh3d-triangles solid))))
  (check-exn exn:fail? (lambda () (revolve3d cone-region #:id 'bad #:axis 'q)))
  (check-exn exn:fail? (lambda () (revolve3d (list (vec2 0 -1) (vec2 1 0) (vec2 0 0)) #:id 'negative))))
