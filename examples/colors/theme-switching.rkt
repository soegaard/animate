#lang racket/base

;; Render this unchanged scene with --theme animate-light or --theme
;; animate-dark. Its tokens, not a module-global setting, choose the result.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define card
    (rounded-rectangle #:id 'card #:center origin #:width 8 #:height 3
                       #:corner-radius 1/4 #:fill theme-surface
                       #:stroke theme-surface-edge #:stroke-width 3))
  (define heading
    (plain-text "One scene, two themes" #:id 'heading #:center (vec2 0 1/2)
                #:font-size 1/2 #:font-weight 'bold #:color theme-foreground))
  (define explanation
    (plain-text "The source remains unchanged." #:id 'explanation
                #:center (vec2 0 -1/2) #:font-size 1/4 #:color theme-muted))
  (scene-wait (scene-add (make-scene) card heading explanation) 1))

(module+ main
  (run-demo "colors/theme-switching.rkt" make-demo-scene))
