#lang racket/base

;;;
;;; SCENE-3D-B Camera Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define (check-vec3= actual expected [tolerance 1e-9])
  (check-true (<= (abs (- (vec3-x actual) (vec3-x expected))) tolerance))
  (check-true (<= (abs (- (vec3-y actual) (vec3-y expected))) tolerance))
  (check-true (<= (abs (- (vec3-z actual) (vec3-z expected))) tolerance)))

(module+ test
  (define camera
    (perspective-camera3d #:position (vec3 0 0 8)
                          #:look-at origin3
                          #:near 1 #:far 20))
  (check-equal? (camera3d-project camera origin3 #:aspect 16/9) (vec2 0 0))
  (check-true (< (camera3d-view-depth camera (vec3 0 0 5))
                 (camera3d-view-depth camera origin3)))
  (check-false (camera3d-project camera (vec3 0 0 9) #:aspect 1))
  (check-false (camera3d-project camera (vec3 0 0 15) #:aspect 1))
  (define centre-ray
    (camera3d-pixel-ray camera 100 50 #:width 200 #:height 100))
  (check-vec3= (ray3-origin centre-ray) (vec3 0 0 8))
  (check-vec3= (ray3-direction centre-ray) (vec3 0 0 -1))
  (define orthographic
    (orthographic-camera3d #:position (vec3 0 0 8)
                           #:look-at origin3
                           #:near 1 #:far 20 #:vertical-size 4))
  (define near-left (camera3d-project orthographic (vec3 -1 0 4) #:aspect 2))
  (define far-left (camera3d-project orthographic (vec3 -1 0 0) #:aspect 2))
  (check-equal? near-left far-left)
  (define narrow (camera3d-project camera (vec3 1 0 0) #:aspect 1))
  (define wide (camera3d-project camera (vec3 1 0 0) #:aspect 2))
  (check-= (vec2-x wide) (/ (vec2-x narrow) 2) 1e-9)
  (check-equal? (vector-length (camera3d-frustum camera #:aspect 16/9)) 6))
