#lang racket/base

;;; SCENE-3D-C: Opaque, Depth-tested Cube

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide cube-vertices
         cube-triangles
         make-opaque-cube
         make-demo-scene)

(define cube-vertices
  (vector (vec3 -1 -1 -1) (vec3 1 -1 -1)
          (vec3 1 1 -1) (vec3 -1 1 -1)
          (vec3 -1 -1 1) (vec3 1 -1 1)
          (vec3 1 1 1) (vec3 -1 1 1)))

;; Every exterior face is CCW when seen from outside the cube.
(define cube-triangles
  (vector (vector 4 5 6) (vector 4 6 7) ; front (+z)
          (vector 0 2 1) (vector 0 3 2) ; back (-z)
          (vector 0 4 7) (vector 0 7 3) ; left (-x)
          (vector 1 2 6) (vector 1 6 5) ; right (+x)
          (vector 3 7 6) (vector 3 6 2) ; top (+y)
          (vector 0 1 5) (vector 0 5 4))) ; bottom (-y)

(define (make-opaque-cube id
                          #:transform [transform identity-transform3]
                          #:color [color "cornflowerblue"])
  (mesh3d #:id id
          #:vertices cube-vertices
          #:triangles cube-triangles
          #:transform transform
          #:material (material3d #:color color #:shading 'flat)))

(define (make-demo-scene)
  (define camera
    (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3
                          #:vertical-field-of-view (/ pi 5)
                          #:near 1/10 #:far 30))
  (define cube
    (make-opaque-cube
     'cube
     #:transform
     (make-transform3 #:rotation (axis-angle (vec3 1 1 0) (/ pi 9)))))
  (define world
    (view3d (list cube)
            #:id 'world
            #:center (vec2 0 -1/4)
            #:width 6 #:height 4
            #:camera camera
            #:background "aliceblue"
            #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-C: opaque depth-tested triangle mesh"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "Flat light, frustum clipping, back-face culling, and a z-buffer"
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-wait (scene-add (make-scene) world title caption) 4))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "opaque-cube.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
