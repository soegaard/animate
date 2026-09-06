#lang racket/base

;;; SCENE-3D-P: one retained renderer, two independently composed viewports

(require (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define shared-cube
  (cube3d 2 #:id 'cube
          #:material (material3d #:color "cornflowerblue" #:shading 'smooth)))

(define (make-viewport id centre camera)
  (view3d (list shared-cube)
          #:id id #:center centre #:width 11/2 #:height 15/4
          #:camera camera
          #:lights (list (ambient-light3d #:intensity 1/4)
                         (directional-light3d (vec3 1 1 -1) #:intensity 3/4))
          #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (define left
    (make-viewport
     'left-world (vec2 -3 0)
     (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                           #:vertical-field-of-view (/ pi 5))))
  (define right
    (make-viewport
     'right-world (vec2 3 0)
     (orthographic-camera3d #:position (vec3 4 3 7) #:look-at origin3
                            #:vertical-size 4)))
  (scene-wait
   (scene-add
    (make-scene)
    left right
    (plain-text "Two view3d values, one ordinary 2D frame"
                #:id 'title #:center (vec2 0 13/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy")
    (plain-text "perspective" #:id 'left-label #:center (vec2 -3 -12/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray")
    (plain-text "orthographic" #:id 'right-label #:center (vec2 3 -12/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   1))

(module+ main
  (render-frames! (make-demo-scene) "frames" #:fps 30))
