#lang racket/base

;;; SCENE-3D-O: a stroke crosses the near plane without a projection singularity

(require animate
         animate/3d)

(provide make-demo-scene)

(define (make-world)
  (view3d
   (list
    (line3d (vec3 -2 0 7/2) (vec3 2 0 -3) #:id 'crossing
            #:style (stroke3d #:color "darkorchid" #:width 5 #:cap 'round))
    (point3d (vec3 2 0 -3) #:id 'anchor
             #:style (point-style3d #:size 10 #:color "goldenrod")))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 0 0 4) #:look-at origin3
                                 #:near 1 #:far 16)
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-add
   (make-scene) (make-world)
   (plain-text "SCENE-3D-O: near-plane stroke clipping"
               #:id 'title #:center (vec2 0 3)
               #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
   (plain-text "The finite surviving centreline keeps its authored dash and pick progress."
               #:id 'caption #:center (vec2 0 -3)
               #:font-size 1/4 #:font-family 'swiss #:color "darkslategray")))
