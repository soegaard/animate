#lang racket/base

;;; SCENE-3D-N: Camera-independent mesh compilation

;; The left sphere makes a dense, closed surface readable throughout an orbit.
;; The two gold cubes deliberately have independent spatial IDs and transforms
;; but exactly equal local geometry, so one compiled geometry resource serves
;; two moving instances.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene
         mesh-diagnostics-summary)

(define surface-material
  (material3d #:color "cornflowerblue" #:shading 'smooth #:ambient 1/2 #:diffuse 1/2))
(define instance-material
  (material3d #:color "goldenrod" #:shading 'flat #:ambient 1/2 #:diffuse 1/2))

(define (make-world)
  (define high-surface
    (sphere3d 3/2 #:id 'surface #:latitude-segments 32 #:longitude-segments 64
              #:transform (make-transform3 #:translation (vec3 -11/5 0 0))
              #:material surface-material))
  (define first-instance
    (cube3d 6/5 #:id 'first-instance
            #:transform (make-transform3 #:translation (vec3 9/5 -2/5 0))
            #:material instance-material))
  (define second-instance
    (cube3d 6/5 #:id 'second-instance
            #:transform (make-transform3 #:translation (vec3 18/5 2/5 0))
            #:material instance-material))
  (view3d
   (list high-surface first-instance second-instance)
   #:id 'world #:center origin #:width 9 #:height 5
   #:camera (perspective-camera3d #:position (vec3 7 5 10) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1/2)
                  (directional-light3d (vec3 1 1 -1) #:intensity 1/2))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (define world (make-world))
  (define title
    (plain-text "SCENE-3D-N: compiled mesh geometry"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "Orbiting camera and moving instances reuse camera-independent mesh resources."
                #:id 'caption #:center (vec2 0 -16/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title caption)
   (camera3d-orbit-by 'world #:azimuth (* 3/2 pi) #:elevation (/ pi 16))
   (move3d-to '(world second-instance) (vec3 18/5 -2/5 1/2))
   #:duration 5))

;; This headless query is useful at a REPL. The report lists the same immutable
;; topology facts seen by a renderer, without opening a window or rasterizing.
(define (mesh-diagnostics-summary)
  (define world (make-world))
  (define surface
    (view3d-spatial-ref world '(world surface)))
  (define analysis (analyze-mesh3d surface))
  (hasheq 'vertices (mesh3d-analysis-vertex-count analysis)
          'triangles (mesh3d-analysis-triangle-count analysis)
          'watertight? (mesh3d-analysis-watertight? analysis)
          'boundary-edges (vector-length (mesh3d-analysis-boundary-edges analysis))))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "mesh-diagnostics.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
