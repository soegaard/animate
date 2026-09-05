#lang racket/base

;;;
;;; SCENE-EO Immutable Project Planning
;;;

;; A project declaration names every configuration concern without rendering.
;; `raco animate plan examples/project-planning.rkt sample-project` prints the
;; same pure path and target plan that preview and final rendering will use.

(require animate
         animate/project)

(provide sample-project)

(define dot
  (circle #:id 'dot #:center (vec2 -2 0) #:radius 1/2
          #:fill "tomato" #:stroke "firebrick"))

(define sample-scene
  (scene-play
   (scene-add (make-scene) dot)
   (move-to dot (vec2 2 0))
   #:duration 2))

(define sample-project
  (animate-project
   #:id 'project-planning
   #:source (scene-source sample-scene)
   #:render (render-spec #:fps 30 #:width 1280 #:height 720 #:workers 2)
   #:preview (preview-spec #:fps 30 #:pixel-scale 1/2 #:cache-megabytes 128)
   #:output (output-spec #:root "media" #:name "project-planning")
   #:encoder (encoder-spec #:codec 'h264 #:pixel-format 'yuv420p
                           #:options #hasheq((crf . "18")))
   #:cache (cache-spec #:root ".animate-cache" #:policy 'read-write)))
