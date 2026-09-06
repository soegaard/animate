#lang racket/base

;;; SCENE-3D-R: Semantic Two-Sided Cube Cut and Separate Caps

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define cube (cube3d 3 #:id 'source #:color "cornflowerblue"))
  (define cut (cut-mesh3d cube (plane3 origin3 x-axis3) #:cap default-cap-style3d))
  (define left (mesh-cut3d-result-negative cut))
  (define right (mesh-cut3d-result-positive cut))
  (define left-cap (mesh-cut3d-result-negative-cap cut))
  (define right-cap (mesh-cut3d-result-positive-cap cut))
  (define assembly
    (group3d
     (list (spatial-with-transform left (make-transform3 #:translation (vec3 -1/2 0 0)))
           (spatial-with-transform right (make-transform3 #:translation (vec3 1/2 0 0)))
           (spatial-with-transform left-cap (make-transform3 #:translation (vec3 -1/2 0 0)))
           (spatial-with-transform right-cap (make-transform3 #:translation (vec3 1/2 0 0)))
           (section-curve3d cube (plane3 origin3 x-axis3) #:id 'section
                            #:style (tube-style3d #:radius 1/32 #:color "firebrick")))
     #:id 'cutaway))
  (define world
    (view3d (list assembly) #:id 'world #:center (vec2 0 -1/4) #:width 7 #:height 9/2
            #:background "aliceblue" #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 6 4 8) #:look-at origin3
                                           #:vertical-field-of-view (/ pi 5))))
  (scene-play
   (scene-add (make-scene) world
              (plain-text "SCENE-3D-R: explicit cut sides, caps, and section"
                          #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                          #:font-family 'swiss #:font-weight 'bold #:color "navy")
              (plain-text "The cap meshes remain separately addressable from the clipped faces."
                          #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/4
                          #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (/ pi 2) #:elevation (/ pi 20)) #:duration 4))

(module+ main
  (define output-directory "frames") (define output-video #f)
  (command-line #:program "capped-cube-cutaway.rkt" #:args ([directory "frames"] [video #f])
                (set! output-directory directory) (set! output-video video))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
