#lang racket/base

;;; SCENE-3D-P: project OpenGL integration, intentionally dedicated to GRacket

(require rackunit
         racket/file
         racket/runtime-path
         "../3d.rkt"
         "../main.rkt"
         "../project.rkt"
         "../render.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define (project-view)
  (view3d
   (list (cube3d 2 #:id 'cube #:color "tomato"))
   #:id 'world #:width 4 #:height 3 #:render-mode 'opaque
   #:camera (perspective-camera3d #:position (vec3 4 3 7) #:look-at origin3)))

(module+ test
  ;; The normal headless suite reaches this file but never loads the optional
  ;; GL backend. The dedicated CI lane must set this flag and runs GRacket (or
  ;; Xvfb/GRacket), so a context-creation failure is never silently software-
  ;; fallback behavior.
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define temporary-root (make-temporary-file "animate-3d-p-project-~a" 'directory))
    (dynamic-wind
     void
     (lambda ()
       (define project
         (animate-project
          #:id 'scene-3d-p-project-smoke
          #:source (scene-source (scene-wait (scene-add (make-scene) (project-view)) 1))
          #:render
          (render-spec #:fps 1 #:width 128 #:height 96 #:workers 1
                       #:renderer3d
                       ((dynamic-require opengl-module-path 'opengl-renderer3d-spec)
                        #:samples 1 #:cache-megabytes 16 #:fallback 'error))
          #:output (output-spec #:root (build-path temporary-root "output")
                                 #:name "frame" #:format 'png-sequence
                                 #:overwrite-policy 'replace)
          #:encoder (encoder-spec #:codec 'none)
          #:cache (cache-spec #:root (build-path temporary-root "cache") #:policy 'off)))
       (check-true (project-check-report-ok? (check-project! (plan-project project))))
       (define report (render-project-frame! project 0))
       (define output-directory (hash-ref (project-execution-report-artifact-paths report) 'primary))
       (check-true (file-exists? (build-path output-directory "frame-000000.png"))))
     (lambda () (delete-directory/files temporary-root)))))
