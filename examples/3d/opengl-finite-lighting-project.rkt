#lang racket/base

;;; SCENE-3D-V6: explicit OpenGL point and spot lighting project

;; This selects the retained GPU backend for the V5 finite-light animation.
;; Use Racket 9.3 GRacket, for example:
;;   gracket preview-cli.rkt preview examples/3d/opengl-finite-lighting-project.rkt
;;     opengl-finite-lighting-project

(require racket/cmdline
         animate/3d/opengl
         animate/project
         animate/render
         "finite-lighting.rkt")

(provide opengl-finite-lighting-project)

(define opengl-finite-lighting-project
  (animate-project
   #:id 'opengl-finite-lighting
   #:source (scene-source (make-demo-scene))
   #:render
   (render-spec #:fps 30 #:width 1280 #:height 720 #:workers 1
                #:renderer3d
                (opengl-renderer3d-spec #:samples 4 #:cache-megabytes 128
                                        #:fallback 'error))
   #:preview (preview-spec #:fps 30 #:pixel-scale 1/2)
   #:output (output-spec #:root "media" #:name "opengl-finite-lighting"
                          #:format 'png-sequence #:overwrite-policy 'replace)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root ".animate-cache" #:policy 'off)))

(module+ main
  (define requested-frame 0)
  (command-line
   #:program "opengl-finite-lighting-project.rkt"
   #:args ([frame "0"])
   (set! requested-frame (string->number frame)))
  (unless (exact-nonnegative-integer? requested-frame)
    (raise-argument-error 'opengl-finite-lighting-project.rkt
                          "exact-nonnegative-integer?" requested-frame))
  (define report (render-project-frame! opengl-finite-lighting-project requested-frame))
  (printf "Rendered OpenGL finite-light project frame ~a to ~a\n"
          requested-frame
          (hash-ref (project-execution-report-artifact-paths report) 'primary)))
