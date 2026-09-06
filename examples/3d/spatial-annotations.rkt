#lang racket/base

;;; SCENE-3D-S: Fixed-Structure Spatial Annotations

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (anchor id point color)
  (point3d origin3 #:id id
           #:style (point-style3d #:size 7 #:color color)
           #:transform (make-transform3 #:translation point)))

(define (make-world)
  (view3d
   (list
    (anchor 'A origin3 "midnightblue")
    (anchor 'B (vec3 0 0 2) "midnightblue")
    (anchor 'C (vec3 2 0 0) "midnightblue")
    (anchor 'D (vec3 0 2 0) "midnightblue")
    ;; The triangle sides follow the same named anchor points as the markers.
    (segment-between3d '(A) '(C) #:id 'ac #:color "steelblue" #:width 2)
    (segment-between3d '(A) '(D) #:id 'ad #:color "steelblue" #:width 2)
    (segment-between3d '(A) '(B) #:id 'ab #:color "steelblue" #:width 2)
    ;; Each item below is a fixed spatial relation with stable descendants.
    (distance-dimension3d '(A) '(B) #:id 'height
                          #:offset (vec3 1/3 0 0) #:color "darkgoldenrod")
    (angle-marker3d '(C) '(A) '(D) #:id 'base-angle #:radius 3/5
                    #:color "darkorange")
    (right-angle-marker3d '(C) '(A) '(D) #:id 'right-angle #:size 2/5
                          #:color "darkorange")
    (dihedral-angle3d '(A) '(B) '(C) '(D) #:id 'dihedral #:radius 2/3
                      #:color "purple")
    (normal-marker3d '(A) (vec3 -1/2 -1/2 1/2) #:id 'normal #:length 3/4
                     #:color "darkmagenta")
    (coordinate-tripod3d '(B) #:id 'axes #:length 2/3 #:width 2)
    )
   #:id 'world #:center (vec2 0 -1/3) #:width 6 #:height 9/2
   #:background "aliceblue" #:render-mode 'opaque
   #:camera (perspective-camera3d #:position (vec3 5 5 7)
                                  #:look-at (vec3 1/3 1/3 3/4)
                                  #:vertical-field-of-view (/ pi 5))))

(define (make-demo-scene)
  (scene-play
   (scene-add
    (make-scene) (make-world)
    (plain-text "SCENE-3D-S: fixed spatial annotations"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "Dimensions, planar and dihedral angles, a normal, and a coordinate tripod follow named points."
                #:id 'caption #:center (vec2 0 -31/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (animation-group
    (move3d-to '(world C) (vec3 2 3/4 0))
    (camera3d-orbit-by 'world #:center (vec3 1/3 1/3 3/4)
                       #:azimuth (/ pi 3) #:elevation (/ pi 18)))
   #:duration 4))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "spatial-annotations.rkt"
                #:args ([directory "frames"] [video #f])
                (set! output-directory directory)
                (set! output-video video))
  (render-frames! (make-demo-scene) output-directory #:fps 30)
  (when output-video (encode-mp4! output-directory output-video #:fps 30)))
