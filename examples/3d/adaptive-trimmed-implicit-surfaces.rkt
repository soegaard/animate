#lang racket/base

;;; SCENE-3D-Q: Adaptive, Trimmed, and Implicit Surface Gallery

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define adaptive
    (adaptive-parametric-surface3d
     (lambda (u v) (vec3 u v (* 1/3 (sin (* 3 u)) (cos (* 2 v)))))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'adaptive
     #:position-tolerance 1/80 #:maximum-depth 6
     #:material (material3d #:color "steelblue" #:shading 'smooth)
     #:transform (make-transform3 #:translation (vec3 -5/2 0 0))))
  (define trimmed
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0)) #:u-range '(-1 1) #:v-range '(-1 1) #:id 'trimmed
     #:trims (list (surface-trim (lambda (u v) (- 1 (+ (* u u) (* v v)))) #:id 'disk))
     #:material (material3d #:color "goldenrod" #:shading 'smooth)
     #:transform (make-transform3 #:translation (vec3 0 0 0))))
  (define implicit
    (implicit-surface3d
     (lambda (point)
       (- (+ (* (vec3-x point) (vec3-x point))
             (* (vec3-y point) (vec3-y point))
             (* (vec3-z point) (vec3-z point))) 9/16))
     #:id 'implicit #:resolution 18
     #:material (material3d #:color "mediumorchid" #:shading 'smooth)
     #:transform (make-transform3 #:translation (vec3 5/2 0 0))))
  (define world
    (view3d (list adaptive trimmed implicit) #:id 'world #:center (vec2 0 -1/4)
            #:width 9 #:height 9/2 #:background "aliceblue" #:render-mode 'opaque
            #:camera (perspective-camera3d #:position (vec3 6 4 9) #:look-at origin3
                                           #:vertical-field-of-view (/ pi 5))))
  (scene-play
   (scene-add (make-scene)
              world
              (plain-text "SCENE-3D-Q: adaptive, trimmed, and implicit surfaces"
                          #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                          #:font-family 'swiss #:font-weight 'bold #:color "navy")
              (plain-text "Each lowers to one immutable indexed surface mesh with provenance."
                          #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/4
                          #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (/ pi 3) #:elevation (/ pi 18)) #:duration 4))

(module+ main
  (define output-directory "frames") (define output-video #f)
  (command-line #:program "adaptive-trimmed-implicit-surfaces.rkt"
                #:args ([directory "frames"] [video #f])
                (set! output-directory directory) (set! output-video video))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
