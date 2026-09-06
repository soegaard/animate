#lang racket/base

;;;
;;; SCENE-3D-B Spatial Path Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define cube
  (mesh3d #:id 'cube
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define world
  (view3d (list (group3d (list cube) #:id 'diagram)) #:id 'world))

(module+ test
  (check-true (spatial-path? '(world diagram cube)))
  (check-false (spatial-path? '(world 1)))
  (check-eq? (view3d-spatial-ref world '(world diagram cube)) cube)
  (check-true (view3d-spatial-has? world '(world diagram cube)))
  (check-false (view3d-spatial-has? world '(other diagram cube)))
  (define moved
    (view3d-spatial-update
     world '(world diagram cube)
     (lambda (object) (spatial-with-position object (vec3 2 0 0)))))
  (check-equal? (spatial-position (view3d-spatial-ref moved '(world diagram cube)))
                (vec3 2 0 0))
  (check-exn exn:fail?
             (lambda () (view3d-spatial-ref world '(world cube face))))
  (define state (scene-current-state (scene-add (make-scene) world)))
  (check-exn
   #rx"target is a spatial Visual inside view3d; use a 3D animation request"
   (lambda () (scene-state-ref state '(world diagram cube)))))
