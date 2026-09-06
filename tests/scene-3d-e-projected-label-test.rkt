#lang racket/base

;;;
;;; SCENE-3D-E Projected Label Tests
;;;

(require (only-in pict pict?)
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../private/3d/projected-anchor.rkt"
         "../private/3d/projected-label.rkt")

(define outer-camera
  (make-camera #:width 800 #:height 450 #:world-width 10))

(define point
  (mesh3d #:id 'A
          #:vertices (vector origin3)
          #:transform (make-transform3 #:translation (vec3 1 0 0))))
(define initial-camera
  (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3))
(define world
  (view3d (list point)
          #:id 'world
          #:center (vec2 1 2)
          #:width 8
          #:height 4
          #:camera initial-camera
          #:render-mode 'opaque))
(define label
  (follow-projected-spatial
   (plain-text "A" #:id 'a-label #:font-size 1/3)
   #:view 'world
   #:target '(A)
   #:offset (vec2 8 -8)))

(define (expected-label-position sampled-view position)
  (vec2+
   (project-spatial-point-to-view3d-world sampled-view position)
   (vec2 (/ 8 (camera-scale outer-camera))
         (/ -8 (camera-scale outer-camera)))))

(module+ test
  ;; A path target uses the exact transformed spatial origin, and a pixel
  ;; offset has constant screen size rather than perspective-distance scale.
  (define direct (resolve-projected-label label world outer-camera))
  (check-equal?
   (visual-position direct)
   (expected-label-position world (vec3 1 0 0)))
  (check-equal? (visual-scale direct) (vec2 1 1))

  ;; The same label follows both moving spatial geometry and the current camera
  ;; at one arbitrary middle frame. Nothing is cached from frame zero.
  (define animated
    (scene-play
     (scene-add (scene-add (make-scene) world) label)
     (animation-group
      (move3d-to '(world A) (vec3 2 1 0))
      (camera3d-move-to 'world (vec3 2 0 6)))
     #:duration 2))
  (define state (scene-sample animated 1))
  (define sampled-view (scene-state-resolved-ref state 'world))
  (define sampled-label
    (resolve-projected-label (scene-state-ref state 'a-label)
                             sampled-view outer-camera))
  (check-equal?
   (visual-position sampled-label)
   (expected-label-position sampled-view (vec3 3/2 1/2 0)))
  (check-equal? (visual-scale sampled-label) (vec2 1 1))

  ;; The scene adapter resolves this custom definition before ordinary Pict
  ;; dispatch, yielding a normal paintable 2D visual above the 3D viewport.
  (check-true (pict? (scene->pict animated 1 #:camera outer-camera)))

  ;; A literal anchor is accepted through the clear convenience spelling.
  (check-true
   (projected-label?
    (follow-projected-point
     (plain-text "O" #:id 'origin-label)
     #:view 'world
     #:point origin3))))
