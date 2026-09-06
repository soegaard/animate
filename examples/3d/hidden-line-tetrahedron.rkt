#lang racket/base

;;; SCENE-3D-O: Depth-aware mathematical mesh outlines

(require (only-in racket/math pi)
         animate
         animate/3d)

(provide make-demo-scene)

(define visible-edge
  (stroke3d #:color "midnightblue" #:width 2 #:cap 'round #:join 'round
            #:depth-mode 'test #:depth-bias 1e-4))
(define hidden-edge
  (stroke3d #:color "slategray" #:width 1 #:dash '(4 4) #:cap 'butt
            #:depth-mode 'hidden #:depth-bias 1e-4))

(define (make-world)
  (define tetrahedron
    (tetrahedron3d 2 #:id 'tetrahedron
                   #:color "aliceblue"
                   #:material (material3d #:color "aliceblue" #:shading 'flat
                                          #:ambient 3/4 #:diffuse 1/4)))
  (view3d
   (list (with-edges3d tetrahedron
                       #:edges 'feature
                       #:visible visible-edge
                       #:hidden hidden-edge
                       #:surface 'visible))
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 6 4 8) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 3/4)
                  (directional-light3d (vec3 -1 1 -1) #:intensity 1/4))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene)
    (make-world)
    (plain-text "SCENE-3D-O: visible and hidden tetrahedron edges"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy")
    (plain-text "Solid edges stay crisp; occluded edges are dashed from the opaque depth buffer."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (* 3/2 pi) #:elevation (/ pi 12))
   #:duration 5))
