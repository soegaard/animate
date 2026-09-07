#lang racket/base

;;; SCENE-3D-V5: software point and spot lighting

;; This deliberately uses the ordinary software render path. The warm point
;; source moves across the sphere while the cool spot tightens toward it, so
;; attenuation, cone falloff, and the V4 named-light timeline requests are all
;; visible without requiring an OpenGL backend.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define orb-material
    (material3d #:color "slateblue" #:shading 'smooth #:lighting 'blinn-phong
                #:ambient 1/8 #:diffuse 1 #:specular 2/5 #:specular-color "white"
                #:roughness 2/5))
  (define floor-material
    (material3d #:color "midnightblue" #:shading 'flat #:lighting 'lambert
                #:ambient 1/8 #:diffuse 3/4 #:double-sided? #t))
  (define world
    (view3d
     (list (sphere3d 3/2 #:id 'orb #:material orb-material)
           (box3d 9 1/10 7 #:id 'floor
                  #:transform (make-transform3 #:translation (vec3 0 -8/5 0))
                  #:material floor-material))
     #:id 'world #:center origin #:width 8 #:height 9/2
     #:camera (perspective-camera3d #:position (vec3 5 3 8) #:look-at origin3
                                    #:vertical-field-of-view (/ pi 5))
     #:lights
     (list (ambient-light3d #:id 'fill #:intensity 1/6 #:color "white")
           (point-light3d (vec3 -3 3 4) #:id 'warm #:intensity 9/4 #:color "gold"
                          #:attenuation (inverse-square-attenuation3d
                                         #:reference-distance 2)
                          #:range 10)
           (spot-light3d (vec3 2 4 3) (vec3 -2 -4 -3)
                         #:id 'cool #:intensity 7/4 #:color "lightskyblue"
                         #:inner-angle (/ pi 12) #:outer-angle (/ pi 4)
                         #:attenuation (inverse-square-attenuation3d
                                        #:reference-distance 2)
                         #:range 10))
     #:background "aliceblue" #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-V5: point and spot lighting"
                #:id 'title #:center (vec2 0 3)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "The warm point source moves; the cool spot narrows toward the sphere."
                #:id 'caption #:center (vec2 0 -3)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title caption)
   (animation-group
    (point-light3d-move-to 'world 'warm (vec3 3 3 4))
    (light3d-color-to 'world 'warm "tomato")
    (spot-light3d-aim-at 'world 'cool (vec3 -1/2 0 0))
    (spot-light3d-cone-to 'world 'cool (/ pi 18) (/ pi 6)))
   #:duration 3))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "finite-lighting.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
