#lang racket/base

;;;
;;; SCENE-3D-B Spatial Tree Tests
;;;

(require rackunit
         "../3d.rkt")

(define triangle
  (mesh3d #:id 'triangle
          #:vertices (vector (vec3 0 0 0)
                             (vec3 2 0 0)
                             (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(module+ test
  (define shifted
    (spatial-with-position triangle (vec3 3 4 5)))
  (check-equal? (spatial-position shifted) (vec3 3 4 5))
  (check-equal? (spatial-rotation shifted) identity-rotation3)
  (check-equal? (spatial-scale shifted) (vec3 1 1 1))
  (define group
    (group3d (list shifted) #:id 'geometry
             #:transform (make-transform3 #:translation (vec3 1 0 0))))
  (check-true (spatial-container? group))
  (check-equal? (map spatial-child-id (spatial-child-entries group))
                '(triangle))
  (check-equal? (aabb3-minimum (spatial-local-bounds group)) (vec3 3 4 5))
  (check-equal? (aabb3-maximum (spatial-local-bounds group)) (vec3 5 5 5))
  (check-exn exn:fail?
             (lambda () (group3d (list triangle triangle) #:id 'bad)))
  (check-exn exn:fail?
             (lambda () (group3d (list triangle) #:id 'triangle))))
