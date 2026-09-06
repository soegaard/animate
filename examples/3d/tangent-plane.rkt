#lang racket/base

;;; SCENE-3D-G: Saddle Surface and Tangent Plane

;; A fixed-grid graph z=x²-y² is rendered with a height colour field.  The
;; point, coordinate curves, two tangent vectors, normal, and tangent plane are
;; all ordinary immutable spatial Visuals; the explanatory formula remains a
;; crisp fixed 2D Visual above the viewport.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define saddle
  (surface-color-by-height
   (function-surface3d
    (lambda (x y) (- (* x x) (* y y)))
    #:x-range (list -3/2 3/2) #:y-range (list -3/2 3/2)
    #:resolution (list 41 41) #:id 'saddle
    #:derivative-x (lambda (x _y) (* 2 x))
    #:derivative-y (lambda (_x y) (* -2 y))
    #:material (material3d #:color "steelblue" #:shading 'smooth #:ambient 1
                           #:diffuse 1 #:double-sided? #t))
   #:low "royalblue" #:high "gold"))

(define calculus-u 1/2)
(define calculus-v -1/3)

(define (make-world)
  (define curve-u
    (surface-coordinate-curve saddle #:u calculus-u #:id 'u-curve
                              #:samples 65 #:radius 1/42 #:color "tomato"))
  (define curve-v
    (surface-coordinate-curve saddle #:v calculus-v #:id 'v-curve
                              #:samples 65 #:radius 1/42 #:color "forestgreen"))
  (view3d
   (list
    (grid-plane3d 'xy #:id 'ground #:u-range (list -3/2 3/2) #:v-range (list -3/2 3/2)
                  #:step 1 #:radius 1/110 #:color "lightsteelblue")
    (axes3d #:id 'axes #:x-range (list -3/2 3/2) #:y-range (list -3/2 3/2) #:z-range (list -2 2)
            #:radius 1/48 #:color "midnightblue")
    saddle
    (surface-tangent-plane saddle calculus-u calculus-v #:id 'tangent-plane
                           #:size 2/3 #:color "lavender")
    curve-u curve-v
    (surface-point saddle calculus-u calculus-v #:id 'contact #:radius 1/10 #:color "gold")
    (surface-tangent-u saddle calculus-u calculus-v #:id 'tangent-u #:length 4/5 #:color "tomato")
    (surface-tangent-v saddle calculus-u calculus-v #:id 'tangent-v #:length 4/5 #:color "forestgreen")
    (surface-normal saddle calculus-u calculus-v #:id 'normal #:length 1 #:color "midnightblue")
    (surface-point saddle -3/2 calculus-v #:id 'traveller #:radius 1/12 #:color "white"))
   #:id 'world #:center (vec2 0 -1/4) #:width 7 #:height 9/2
   #:camera (perspective-camera3d #:position (vec3 7 6 10)
                                 #:look-at (vec3 0 0 0)
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1))
   #:background "white" #:render-mode 'opaque))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-3D-G: tangent plane on z = x² - y²"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "Fixed samples give stable normals, curves, and a direct-time surface reveal."
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) (make-world) title caption)
   (timed (reveal-surface-u '(world saddle)) #:duration 2)
   (timed (move-along-curve3d '(world traveller) '(world u-curve)) #:duration 5)
   (timed (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 20)) #:duration 5)
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "tangent-plane.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
