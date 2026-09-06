#lang racket/base

;;; SCENE-3D-P: explicit retained OpenGL cube

;; Run this with Racket 9.3 GRacket.  The ordinary 2D scene pipeline stays
;; intact: only the view3d visual selects the explicit OpenGL renderer through
;; the dynamic backend boundary while its pixels are composed back into the
;; standard frame.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/3d/opengl
         animate/3d/render
         animate/render)

(provide make-demo-scene
         opengl-cube-summary)

(define (make-world)
  (view3d
   (list
    (cube3d 2 #:id 'cube
            #:material (material3d #:color "tomato" #:shading 'smooth))
    (cube3d 4 #:id 'floor
            #:transform (make-transform3 #:translation (vec3 0 -2 0)
                                         #:scale (vec3 1 1/20 1))
            #:material (material3d #:color "slategray" #:shading 'flat
                                   #:double-sided? #t)))
   #:id 'world #:center (vec2 0 -1/4) #:width 7 #:height 9/2
   #:camera (perspective-camera3d #:position (vec3 5 4 8) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1/4)
                  (directional-light3d (vec3 1 1 -1) #:intensity 3/4))
   #:background "aliceblue" #:render-mode 'opaque))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-3D-P: retained Racket/OpenGL renderer"
                #:id 'title #:center (vec2 0 15/4)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define caption
    (plain-text "VBO/VAO geometry · offscreen FBO · standard ARGB frame composition"
                #:id 'caption #:center (vec2 0 -29/10)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (make-scene) (make-world) title caption)
   (camera3d-orbit-by 'world #:azimuth (* 2 pi) #:elevation (/ pi 16))
   #:duration 5))

;; A direct probe suitable for a REPL.  Render twice to demonstrate that a
;; warm camera-identical frame reads the retained GPU geometry rather than
;; uploading it again.
(define (opengl-cube-summary)
  (define renderer
    (opengl-renderer3d (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 64)))
  (dynamic-wind
   void
   (lambda ()
     (define request (view3d->render3d-request (make-world) 640 360))
     (define preparation (renderer3d-prepare renderer request))
     (define first (renderer3d-render renderer preparation request))
     (define second (renderer3d-render renderer preparation request))
     (hasheq 'renderer (renderer3d-id renderer)
             'first-byte-count (bytes-length (renderer3d-render-result-argb-bytes first))
             'same-pixels? (bytes=? (renderer3d-render-result-argb-bytes first)
                                    (renderer3d-render-result-argb-bytes second))
             'statistics (opengl-renderer3d-statistics renderer)))
   (lambda () (opengl-renderer3d-release! renderer))))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "opengl-opaque-cube.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define renderer
    (opengl-renderer3d (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 64)))
  (dynamic-wind
   void
   (lambda ()
     (define paths
       (parameterize ([current-view3d-renderer3d renderer])
         (render-frames! (make-demo-scene) output-directory #:fps 30)))
     (printf "Rendered ~a OpenGL frames to ~a\n" (length paths) output-directory)
     (when output-video
       (encode-mp4! output-directory output-video #:fps 30)
       (printf "Encoded ~a\n" output-video)))
   (lambda () (opengl-renderer3d-release! renderer))))
