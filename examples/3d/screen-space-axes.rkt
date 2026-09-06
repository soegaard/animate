#lang racket/base

;;; SCENE-3D-O: Constant-pixel mathematical marks

(require (only-in racket/math pi)
         animate
         animate/3d)

(provide make-demo-scene)

(define screen-style
  (stroke3d #:color "midnightblue" #:width 2 #:cap 'round #:join 'round))
(define world-style
  (stroke3d #:color "darkorange" #:width 1/12 #:width-mode 'world
            #:cap 'round #:join 'round))

(define (make-world)
  (view3d
   (list (axes3d #:id 'axes #:x-range (list -3 3) #:y-range (list -3 3)
                 #:z-range (list -3 3) #:stroke-style screen-style
                 #:arrow-style (arrow-style3d #:color "midnightblue" #:length 12))
         (polyline3d (list (vec3 -3 -2 0) (vec3 0 -1 0) (vec3 3 -2 0))
                     #:id 'screen-stroke #:style screen-style)
         (polyline3d (list (vec3 -3 -5/2 0) (vec3 0 -3/2 0) (vec3 3 -5/2 0))
                     #:id 'world-stroke #:style world-style))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 7 5 10) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-O: screen-space axes and arrowheads"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy")
    (plain-text "Blue strokes stay two pixels wide; the orange stroke is deliberately physical."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-dolly-by 'world 4)
   #:duration 5))
