#lang racket/base

;;; SCENE-3D-H: Solid of Revolution

(require racket/cmdline
         racket/math
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define profile
  ;; The closed region below y = x on [0, 2], represented as (axis, radius).
  (list (vec2 0 0) (vec2 2 2) (vec2 2 0)))

(define (make-demo-scene)
  (define solid
    (revolve3d profile #:id 'volume #:axis 'x #:segments 64
               #:color "cornflowerblue"))
  (define world
    (view3d (list solid) #:id 'world #:center (vec2 0 -1/3) #:width 7 #:height 4
            #:background "aliceblue" #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 6 5 7)
                                           #:look-at (vec3 1 0 0)
                                           #:vertical-field-of-view (/ pi 5))))
  (define title
    (plain-text "SCENE-3D-H: solid of revolution" #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define integral
    (plain-text "V = π ∫₀² x² dx" #:id 'integral #:center (vec2 -4 -1/3)
                #:font-size 2/5 #:font-family 'roman #:color "midnightblue"))
  (define caption
    (plain-text "A fixed profile is revolved around the x-axis; the formula remains a crisp 2D Visual."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (scene-play (scene-add (make-scene) world title integral caption)
              (camera3d-orbit-by 'world #:center (vec3 1 0 0) #:azimuth (* 2 pi) #:elevation (/ pi 12))
              #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "solid-of-revolution.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory) (set! output-video mp4-file))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
