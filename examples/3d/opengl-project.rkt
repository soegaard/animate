#lang racket/base

;;; SCENE-3D-P: explicit OpenGL project configuration

;; This is the project form of the smaller `opengl-opaque-cube.rkt` demo.  It
;; keeps the normal scene/Pict composition but asks the 3D `view3d` renderer
;; for one retained OpenGL backend during final rendering.  Run the module with
;; Racket 9.3 GRacket; plain `racket` intentionally reports an actionable
;; configuration error instead of silently choosing software.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/3d/opengl
         animate/project
         animate/render)

(provide opengl-project
         opengl-project-scene)

(define (demo-view)
  (view3d
   (list
    (cube3d 2 #:id 'cube
            #:material (material3d #:color "tomato" #:shading 'smooth))
    (cube3d 5 #:id 'ground
            #:transform (make-transform3 #:translation (vec3 0 -2 0)
                                         #:scale (vec3 1 1/32 1))
            #:material (material3d #:color "slategray" #:shading 'flat
                                   #:double-sided? #t)))
   #:id 'world #:center (vec2 0 0) #:width 7 #:height 9/2
   #:camera (perspective-camera3d #:position (vec3 5 4 8) #:look-at origin3
                                 #:vertical-field-of-view (/ pi 5))
   #:lights (list (ambient-light3d #:intensity 1/4)
                  (directional-light3d (vec3 1 1 -1) #:intensity 3/4))
   #:background "aliceblue" #:render-mode 'opaque))

(define opengl-project-scene
  (scene-play
   (scene-add
    (make-scene)
    (demo-view)
    (plain-text "Project-selected Racket/OpenGL backend"
                #:id 'caption #:center (vec2 0 -16/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:azimuth (/ pi 2) #:elevation (/ pi 20))
   #:duration 2))

(define opengl-project
  (animate-project
   #:id 'opengl-project
   #:source (scene-source opengl-project-scene)
   #:render
   (render-spec #:fps 30 #:width 1280 #:height 720 #:workers 1
                #:renderer3d
                (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 128
                                        #:fallback 'error))
   #:preview (preview-spec #:fps 30 #:pixel-scale 1/2)
   #:output (output-spec #:root "media" #:name "opengl-project"
                          #:format 'png-sequence #:overwrite-policy 'replace)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root ".animate-cache" #:policy 'off)))

(module+ main
  (define requested-frame 0)
  (command-line
   #:program "opengl-project.rkt"
   #:args ([frame "0"])
   (set! requested-frame (string->number frame)))
  (unless (exact-nonnegative-integer? requested-frame)
    (raise-argument-error 'opengl-project.rkt "exact-nonnegative-integer?" requested-frame))
  (define report (render-project-frame! opengl-project requested-frame))
  (printf "Rendered OpenGL project frame ~a to ~a\n"
          requested-frame
          (hash-ref (project-execution-report-artifact-paths report) 'primary)))
