#lang racket/base

;;; SCENE-3D-O: cap, join, and dash gallery

(require animate
         animate/3d)

(provide make-demo-scene)

(define (mark id points style)
  (polyline3d points #:id id #:style style))

(define (make-world)
  (view3d
   (list
    (mark 'round
          (list (vec3 -4 2 0) (vec3 -3 5/2 0) (vec3 -2 2 0))
          (stroke3d #:color "royalblue" #:width 8 #:cap 'round #:join 'round))
    (mark 'bevel
          (list (vec3 -1 2 0) origin3 (vec3 1 2 0))
          (stroke3d #:color "tomato" #:width 8 #:cap 'square #:join 'bevel))
    (mark 'miter
          (list (vec3 2 2 0) (vec3 3 5/2 0) (vec3 4 2 0))
          (stroke3d #:color "darkorange" #:width 8 #:cap 'butt #:join 'miter))
    (mark 'dashed
          (list (vec3 -4 -2 0) (vec3 4 -2 0))
          (stroke3d #:color "seagreen" #:width 5 #:dash '(12 6)
                    #:cap 'round #:dash-offset 3)))
   #:id 'world #:center origin #:width 10 #:height 5
   #:camera (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                                  #:vertical-size 6)
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-add
   (make-scene) (make-world)
   (plain-text "SCENE-3D-O: caps, joins, and dashes"
               #:id 'title #:center (vec2 0 3)
               #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
   (plain-text "Stroke details are resolved in pixels after projection."
               #:id 'caption #:center (vec2 0 -3)
               #:font-size 1/4 #:font-family 'swiss #:color "darkslategray")))
