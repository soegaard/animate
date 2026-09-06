#lang racket/base

;;; SCENE-3D-S: Stable Vertex Anchors with Crisp Projected Labels

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define tetra (tetrahedron3d 2 #:id 'tetra #:color "steelblue"))
  (define world
    (view3d (list tetra) #:id 'world #:center (vec2 0 -1/4) #:width 6 #:height 9/2
            #:background "aliceblue" #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                                           #:vertical-field-of-view (/ pi 5))))
  (define placement (label-placement3d '(north-east east north) 14 3 #t #t '() 1 10))
  (define label
    (label3d (plain-text "vertex 0" #:id 'vertex-label #:font-size 1/4
                         #:font-family 'swiss #:color "firebrick")
             #:view 'world #:anchor (vertex-anchor3d '(world tetra) 0)
             #:placement placement #:offset (vec2 14 14) #:occlusion 'fade))
  (scene-play
   (scene-add (make-scene) world label
              (plain-text "SCENE-3D-S: resolved anchors and label policy"
                          #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                          #:font-family 'swiss #:font-weight 'bold #:color "navy")
              (plain-text "The label remains ordinary 2D text; its target is an immutable vertex anchor."
                          #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/4
                          #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (/ pi 2) #:elevation (/ pi 16)) #:duration 4))

(module+ main
  (define output-directory "frames") (define output-video #f)
  (command-line #:program "anchor-aware-labels.rkt" #:args ([directory "frames"] [video #f])
                (set! output-directory directory) (set! output-video video))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
