#lang racket/base

;; The theme is an ordinary immutable value. Exporting it makes the explicit
;; renderer choice visible instead of changing process-wide color state.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene
         demo-theme)

(define demo-theme
  (color-theme #:id 'violet-demo #:extends animate-dark-theme
               #:display-name "Violet demo"
               #:roles (hash 'accent purple-b
                             'highlight (color-opacity purple-b 1/3))
               #:series (list purple-b aqua-b gold-b red-b)))

(define (make-demo-scene)
  (define panel
    (rounded-rectangle #:id 'panel #:center origin #:width 7 #:height 3
                       #:corner-radius 1/3 #:fill theme-surface
                       #:stroke theme-surface-edge #:stroke-width 3))
  (define title
    (plain-text "Custom theme" #:id 'title #:center (vec2 0 1/2)
                #:font-size 1/2 #:font-weight 'bold #:color theme-accent))
  (define note
    (plain-text "Render with this module's demo-theme." #:id 'note
                #:center (vec2 0 -1/2) #:font-size 1/4 #:color theme-muted))
  (scene-wait (scene-add (make-scene) panel title note) 1))

(module+ main
  (run-demo "colors/custom-theme.rkt" make-demo-scene))
