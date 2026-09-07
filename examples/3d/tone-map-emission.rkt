#lang racket/base

;;; SCENE-3D-V2: Linear-light emission and final tone mapping

;; Two equal scenes differ only in their immutable final output policy.  The
;; deliberately strong emission is retained in linear light; clamp reaches the
;; display ceiling while Reinhard keeps a visible highlight gradient.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define (glowing-sphere id)
  (sphere3d 3/2 #:id id
            #:material
            (material3d #:color "mediumpurple" #:shading 'smooth
                        #:lighting 'blinn-phong
                        #:ambient 1/5 #:diffuse 4/5
                        #:specular 2 #:specular-color "white" #:roughness 1/4
                        #:emission "gold" #:emission-strength 2)))

(define (demo-camera)
  (perspective-camera3d #:position (vec3 4 2 7) #:look-at origin3
                        #:vertical-field-of-view (/ pi 5)))

(define (tone-view id center policy)
  (view3d (list (glowing-sphere 'sphere))
          #:id id #:center center #:width 11/2 #:height 15/4
          #:camera (demo-camera)
          #:lights (list (ambient-light3d #:intensity 1/5)
                         (directional-light3d (vec3 1 1 -1) #:intensity 4/5))
          #:background "#101827" #:tone-map policy #:render-mode 'opaque))

(define (make-demo-scene)
  (define clamp-view (tone-view 'clamp (vec2 -3 0) (tone-map3d 'clamp 1 1)))
  (define reinhard-view (tone-view 'reinhard (vec2 3 0) (tone-map3d 'reinhard 1 1)))
  (define title
    (plain-text "SCENE-3D-V2: linear light and tone mapping"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define clamp-caption
    (plain-text "clamp (default)" #:id 'clamp-caption #:center (vec2 -3 -5/2)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (define reinhard-caption
    (plain-text "Reinhard: preserves bright detail" #:id 'reinhard-caption
                #:center (vec2 3 -5/2)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) clamp-view reinhard-view title clamp-caption reinhard-caption)
   (camera3d-orbit-by 'clamp #:azimuth (/ pi 3))
   (camera3d-orbit-by 'reinhard #:azimuth (/ pi 3))
   #:duration 3))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "tone-map-emission.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
