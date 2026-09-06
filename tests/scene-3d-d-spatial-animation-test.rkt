#lang racket/base

;;;
;;; SCENE-3D-D Spatial Animation Tests
;;;

(require (only-in racket/math pi)
         rackunit
         "../3d.rkt"
         "../main.rkt")

(define face
  (mesh3d #:id 'cube
          #:vertices (vector (vec3 -1 -1 0)
                             (vec3 1 -1 0)
                             (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define rig
  (group3d (list face) #:id 'rig))

(define initial-view
  (view3d (list rig)
          #:id 'world
          #:camera (perspective-camera3d #:position (vec3 0 0 6)
                                         #:look-at origin3)
          #:render-mode 'opaque))

(define initial-scene
  (scene-add (make-scene) initial-view))

(define (spatial-at scene time path)
  (view3d-spatial-ref (scene-state-ref (scene-sample scene time) 'world) path))

(module+ test
  (define destination-position (vec3 2 0 1))
  (define destination-rotation (axis-angle z-axis3 (/ pi 2)))
  (define destination-scale (vec3 2 3 4))
  (define animated
    (scene-play initial-scene
                (move3d-to '(world rig cube) destination-position)
                (rotate3d-to '(world rig cube) destination-rotation)
                (scale3d-to '(world rig cube) destination-scale)
                #:duration 2))

  ;; Exact clip endpoints preserve the source/destination representations.
  (define source (spatial-at animated 0 '(world rig cube)))
  (define endpoint (spatial-at animated 2 '(world rig cube)))
  (check-equal? (spatial-transform source) identity-transform3)
  (check-equal? (transform3-translation (spatial-transform endpoint))
                destination-position)
  (check-equal? (transform3-rotation (spatial-transform endpoint))
                destination-rotation)
  (check-equal? (transform3-scale (spatial-transform endpoint))
                destination-scale)

  (define midpoint (spatial-at animated 1 '(world rig cube)))
  (check-equal? (transform3-translation (spatial-transform midpoint))
                (vec3 1 0 1/2))
  (check-equal? (transform3-scale (spatial-transform midpoint))
                (vec3 3/2 2 5/2))
  (check-equal?
   (rotation3-apply (transform3-rotation (spatial-transform midpoint)) x-axis3)
   (rotation3-apply (axis-angle z-axis3 (/ pi 4)) x-axis3))

  ;; Relative and complete-transform forms use the actual clip-start value.
  (define relative
    (scene-play
     (scene-add
      (make-scene)
      (view3d
       (list (group3d
              (list (mesh3d #:id 'cube
                             #:vertices (vector (vec3 0 0 0))
                             #:transform (make-transform3 #:translation (vec3 1 2 3))))
              #:id 'rig))
       #:id 'world))
     (move3d-by '(world rig cube) (vec3 -1 1 2))
     (scale3d-by '(world rig cube) (vec3 2 3 4))
     #:duration 1))
  (define relative-end (spatial-at relative 1 '(world rig cube)))
  (check-equal? (transform3-translation (spatial-transform relative-end))
                (vec3 0 3 5))
  (check-equal? (transform3-scale (spatial-transform relative-end))
                (vec3 2 3 4))

  (define full-transform
    (make-transform3 #:translation (vec3 -2 1 0)
                     #:rotation (axis-angle x-axis3 (/ pi 3))
                     #:scale (vec3 2 2 2)))
  (define transformed
    (scene-play initial-scene
                (transform3d-to '(world rig cube) full-transform)
                #:duration 1))
  (check-equal? (spatial-transform (spatial-at transformed 1 '(world rig cube)))
                full-transform)

  ;; Singular scale interpolation is rejected while compiling, before sampling.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play initial-scene
                           (scale3d-to '(world rig cube) (vec3 -1 1 1))
                           #:duration 1))))
