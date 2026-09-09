#lang racket/base

;;;
;;; Software preview worker-pool demonstration
;;;

;; This project deliberately names its Scene through `module-binding-source`.
;; That lets the project preview use its ten isolated software renderer
;; processes.  Direct `scene-source` projects keep one in-process renderer,
;; because arbitrary Scene-building code need not be process-safe.

(require racket/runtime-path
         animate
         animate/project
         animate/preview)

(provide software-preview-scene
         software-preview-project)

(define dot
  (circle #:id 'dot
          #:center (vec2 -4 0)
          #:radius 1/2
          #:fill "tomato"
          #:stroke "firebrick"))

(define software-preview-scene
  (scene-play
   (scene-add (make-scene) dot)
   (move-to dot (vec2 4 0))
   #:duration 4))

(define-runtime-path source-path "software-preview-parallel.rkt")

(define software-preview-project
  (animate-project
   #:id 'software-preview-parallel
   #:source (module-binding-source source-path 'software-preview-scene)
   #:render (render-spec #:fps 30 #:width 1280 #:height 720)
   #:preview (preview-spec #:fps 30 #:pixel-scale 1 #:prefetch 6)
   ;; Preview does not write final output, but a complete project declaration
   ;; makes the same source usable with `raco animate` later if wanted.
   #:output (output-spec #:root "tmp-preview-test"
                          #:name "software-preview-parallel"
                          #:format 'png-sequence)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root ".animate-cache" #:policy 'off)))

(module+ main
  (void
   (open-project-preview
    software-preview-project
    #:title "Animate: parallel software preview")))
