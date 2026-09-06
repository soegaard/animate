#lang racket/base

;;; SCENE-3D-M: retained backend conformance probe

;; The visible animation uses the normal `view3d` boundary.  Its renderer is
;; selected dynamically by `animate/3d/render`, so the author never puts a
;; backend object, native resource, or cache key into this immutable Scene.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/3d/render
         animate/render)

(provide make-demo-scene
         retained-renderer-summary)

(define (make-world)
  (view3d
   (list
    (cube3d 6/5 #:id 'blue
            #:transform (make-transform3 #:translation (vec3 -7/5 0 0))
            #:material (material3d #:color "cornflowerblue" #:shading 'smooth
                                   #:specular 1/5))
    (cube3d 6/5 #:id 'gold
            #:transform (make-transform3 #:translation (vec3 7/5 1/5 -2/5))
            #:material (material3d #:color "goldenrod" #:shading 'smooth
                                   #:specular 1/5))
    (torus3d 1 1/3 #:id 'ring
             #:transform (make-transform3 #:translation (vec3 0 -1/2 1/2)
                                          #:rotation (axis-angle x-axis3 (/ pi 2)))
             #:material (material3d #:color "tomato" #:shading 'smooth
                                    #:specular 1/3)))
   #:id 'world #:center (vec2 1/2 0) #:width 7 #:height 4
   #:camera (perspective-camera3d #:position (vec3 5 3 7) #:look-at origin3
                                  #:vertical-field-of-view (/ pi 5))
   ;; This is a renderer-protocol probe, not a dramatic lighting study. A
   ;; broad ambient fill preserves each object's colour through the orbit so
   ;; the depth-tested face ordering remains easy to inspect.
   #:lights (list (ambient-light3d #:intensity 2/3)
                  (directional-light3d (vec3 1 1 -1) #:intensity 1/2))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (define world (make-world))
  (define title
    (plain-text "SCENE-3D-M: retained renderer protocol"
                #:id 'title #:center (vec2 0 14/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "Immutable scene → cached preparation → fresh depth-tested frame"
                #:id 'caption #:center (vec2 0 -12/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) world title caption)
   (camera3d-orbit-by 'world #:azimuth (* 3/2 pi) #:elevation (/ pi 14))
   #:duration 5))

;; A small, direct probe for a REPL or test.  Repeating an identical request
;; reuses only the renderer-owned preparation; its returned bytes are still a
;; new immutable frame result.  The scene value itself never changes.
(define (retained-renderer-summary)
  (define renderer (retained-software-renderer3d #:capacity 2))
  (define request (view3d->render3d-request (make-world) 320 180))
  (define first (renderer3d-prepare renderer request))
  (define second (renderer3d-prepare renderer request))
  (define result (renderer3d-render renderer second request))
  (hasheq 'renderer (renderer3d-id renderer)
          'same-preparation? (eq? first second)
          'cache-hits (retained-software-renderer3d-cache-hits renderer)
          'cache-misses (retained-software-renderer3d-cache-misses renderer)
          'width (renderer3d-render-result-width result)
          'height (renderer3d-render-result-height result)))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "retained-renderer.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
