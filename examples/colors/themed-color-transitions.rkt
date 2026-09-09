#lang racket/base

;; A color transition preserves its symbolic endpoints until each frame is
;; rendered under an explicit theme.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define disk
    (circle #:id 'disk #:center origin #:radius 1
            #:fill theme-accent #:stroke theme-axis #:stroke-width 3))
  (define caption
    (plain-text "theme accent to warning" #:id 'caption #:center (vec2 0 -2)
                #:font-size 1/4 #:color theme-muted))
  (define initial (scene-add (make-scene) disk caption))
  (scene-play initial (fill-color-to disk theme-warning) #:duration 2))

(module+ main
  (run-demo "colors/themed-color-transitions.rkt" make-demo-scene))
