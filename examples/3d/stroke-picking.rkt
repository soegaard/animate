#lang racket/base

;;; SCENE-3D-O: screen-space stroke and marker picking preview target

(require animate
         animate/3d)

(provide make-demo-scene)

(define (make-world)
  (view3d
   (list
    (polyline3d (list (vec3 -3 -1 0) (vec3 0 2 0) (vec3 3 -1 0)) #:id 'picked-curve
                #:style (stroke3d #:color "royalblue" #:width 7 #:join 'round))
    (point3d (vec3 0 2 0) #:id 'vertex
             #:style (point-style3d #:size 12 #:color "darkorange"))
    (arrow3d (vec3 -3 -2 0) (vec3 3 -2 0) #:id 'picked-arrow
             #:shaft-style (stroke3d #:color "seagreen" #:width 4)
             #:tip-style (arrow-style3d #:color "seagreen" #:length 16)))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (orthographic-camera3d #:position (vec3 0 0 8) #:look-at origin3
                                  #:vertical-size 6)
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-add
   (make-scene) (make-world)
   (plain-text "SCENE-3D-O: click a stroke, point, or arrowhead"
               #:id 'title #:center (vec2 0 3)
               #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
   (plain-text "The preview reports a stable path, primitive kind, and source progress."
               #:id 'caption #:center (vec2 0 -3)
               #:font-size 1/4 #:font-family 'swiss #:color "darkslategray")))
