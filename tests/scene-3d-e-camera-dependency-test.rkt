#lang racket/base

;;;
;;; SCENE-3D-E Camera Dependency Tests
;;;

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define camera-following-relation
  (spatial-relation
   (mesh3d #:id 'camera-marker #:vertices (vector origin3))
   #:depends-on (list (spatial-camera-dependency 'world))
   (lambda (context _template)
     (mesh3d #:id 'camera-marker
             #:vertices (vector origin3)
             #:transform
             (make-transform3
              #:translation
              (camera3d-position (spatial-relation-context-camera context)))))))

(define initial-camera
  (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3))
(define source-view
  (view3d (list camera-following-relation)
          #:id 'world
          #:camera initial-camera))

(define (resolved-marker scene time)
  (view3d-spatial-ref
   (scene-state-resolved-ref (scene-sample scene time) 'world)
   '(world camera-marker)))

(module+ test
  (define animated
    (scene-play
     (scene-add (make-scene) source-view)
     (camera3d-move-to 'world (vec3 2 1 8))
     #:duration 2))
  (check-equal? (spatial-position (resolved-marker animated 0)) (vec3 0 0 6))
  (check-equal? (spatial-position (resolved-marker animated 1)) (vec3 1 1/2 7))
  (check-equal? (spatial-position (resolved-marker animated 2)) (vec3 2 1 8))

  ;; Camera is never an ambient hidden input. A resolver which reads it without
  ;; declaring spatial-camera-dependency gets a precise semantic error.
  (define invalid
    (spatial-relation
     (mesh3d #:id 'invalid #:vertices (vector origin3))
     (lambda (context source)
       (spatial-relation-context-camera context)
       source)))
  (check-exn
   (lambda (failure)
     (and (exn:fail? failure)
          (regexp-match? #rx"spatial camera dependency" (exn-message failure))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-sample
       (scene-add (make-scene) (view3d (list invalid) #:id 'world))
       0)
      'world))))
