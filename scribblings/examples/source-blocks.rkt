#lang racket/base
(require animate animate/authoring)
(provide hot-reload-demo animation)

;; doc: blocks begin
(define-scene-program hot-reload-demo
  #:initial (make-scene)
  (scene-block setup (scene)
    (scene-wait
     (scene-add scene
                (circle #:id 'dot #:center (vec2 -3 0) #:radius 1/2
                        #:fill "tomato" #:stroke "firebrick"))
     1))
  (scene-block move-dot (scene)
    (scene-play scene (move-to 'dot (vec2 3 0)) #:duration 2))
  (scene-block hold (scene)
    (scene-wait scene 1)))
;; doc: blocks end

;; Headless compilation for the manual's frame renderer and tests. This does
;; not open a preview, draw frames, or encode a movie.
(define animation
  (compiled-scene-program-scene (compile-scene-program hot-reload-demo)))
