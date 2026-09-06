#lang racket/base

;;; SCENE-3D-O: all, feature, and silhouette edge selections side by side

(require (only-in racket/math pi)
         animate
         animate/3d)

(provide make-demo-scene)

(define (outlined-cube id position edges color)
  (spatial-with-position
   (with-edges3d
    (cube3d 2 #:id id #:color color)
    #:edges edges
    #:visible (stroke3d #:color "midnightblue" #:width 2 #:depth-mode 'test)
    #:hidden (stroke3d #:color "slategray" #:width 1 #:dash '(3 3)
                       #:depth-mode 'hidden)
    #:surface 'visible)
   position))

(define (make-world)
  (view3d
   (list (outlined-cube 'all (vec3 -3 0 0) 'all "aliceblue")
         (outlined-cube 'feature origin3 'feature "honeydew")
         (outlined-cube 'silhouette (vec3 3 0 0) 'silhouette "lavender"))
   #:id 'world #:center origin #:width 10 #:height 5
   #:camera (perspective-camera3d #:position (vec3 8 5 10) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-O: all, feature, and silhouette edges"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "The selected edge set is prepared for the active camera."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth pi)
   #:duration 5))
