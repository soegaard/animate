#lang racket/base

;;; SCENE-3D-O: vector arrow with a camera-sized arrowhead

(require animate
         animate/3d)

(provide make-demo-scene)

(define (make-world)
  (view3d
   (list
    (arrow3d (vec3 -3 -1 0) (vec3 3 2 0) #:id 'vector
             #:shaft-style (stroke3d #:color "tomato" #:width 3 #:cap 'round)
             #:tip-style (arrow-style3d #:color "tomato" #:length 16 #:width 11))
    (point3d (vec3 -3 -1 0) #:id 'start
             #:style (point-style3d #:size 10 #:color "midnightblue")))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 6 4 10) #:look-at origin3)
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-O: camera-sized arrowhead"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "The arrowhead remains readable during a large dolly."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-dolly-by 'world 5)
   #:duration 5))
