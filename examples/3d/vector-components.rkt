#lang racket/base

;;; SCENE-3D-F: Spatial Vector Components

;; The red, green, and blue arrows are the orthogonal components of
;; v = (2, 1, 3); the gold arrow is their resultant.  Curves, tips, axes, and
;; grid lines are camera-aware screen-space marks, while x/y/z stay crisp 2D
;; projected labels tied to the stable spatial label-anchor paths.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define vector-v (vec3 2 1 3))

(define (make-world)
  (view3d
   (list
    (coordinate-plane3d 'xy #:id 'xy-plane #:u-range (list -3 4) #:v-range (list -2 3)
                        #:color "aliceblue")
    (grid-plane3d 'xy #:id 'xy-grid #:u-range (list -3 4) #:v-range (list -2 3)
                  #:step 1 #:style (stroke3d #:width 1 #:color "lightsteelblue"))
    (axes3d #:id 'axes #:x-range (list -3 4) #:y-range (list -2 3) #:z-range (list -2 4)
            #:stroke-style (stroke3d #:width 2 #:color "midnightblue")
            #:arrow-style (arrow-style3d #:color "midnightblue"))
    (vector-components3d vector-v #:id 'components)
    (point3d vector-v #:id 'v-tip #:style (point-style3d #:size 10 #:color "gold")))
   #:id 'world #:center (vec2 0 -1/4) #:width 7 #:height 9/2
   #:camera (perspective-camera3d #:position (vec3 7 5 9) #:look-at (vec3 1 1/2 1)
                                 #:vertical-field-of-view (/ pi 5))
   #:background "white" #:render-mode 'opaque))

(define (axis-label id text target offset)
  (follow-projected-spatial
   (plain-text text #:id id #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
               #:color "midnightblue")
   #:view 'world #:target target #:offset offset))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-3D-F: vector components in space"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "v = (2, 1, 3): screen-space marks orbit with the camera; x, y, z remain projected labels."
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene)
              (make-world) title caption
              (axis-label 'x-label "x" '(axes labels x) (vec2 9 -5))
              (axis-label 'y-label "y" '(axes labels y) (vec2 8 6))
              (axis-label 'z-label "z" '(axes labels z) (vec2 -10 7)))
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 16))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "vector-components.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
