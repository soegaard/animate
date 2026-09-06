#lang racket/base

;;; SCENE-3D-O: constant-pixel stroke against an explicit physical width

(require (only-in racket/math pi)
         animate
         animate/3d)

(provide make-demo-scene)

(define (make-world)
  (view3d
   (list
    (line3d (vec3 -3 1 0) (vec3 3 1 0) #:id 'screen
            #:style (stroke3d #:color "royalblue" #:width 5 #:cap 'round))
    (line3d (vec3 -3 -1 0) (vec3 3 -1 0) #:id 'world-stroke
            #:style (stroke3d #:color "darkorange" #:width 1/6 #:width-mode 'world
                              #:cap 'round)))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 6 4 10) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-O: screen versus world stroke width"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "Blue remains five pixels; orange measures a physical diameter."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-dolly-by 'world 5)
   #:duration 5))
