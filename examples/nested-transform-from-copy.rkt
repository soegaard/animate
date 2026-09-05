#lang racket/base

;;;
;;; SCENE-CB: Copying a Nested SVG Subpart
;;;

(require racket/runtime-path
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  ;; `svg->visual` preserves nested element ids.  The window is addressed as
  ;; (rocket-diagram rocket window), while its enclosing transforms stay private to the
  ;; imported diagram.
  (define rocket
    (svg->visual
     (build-path assets-directory "roadmap-rocket.svg")
     #:id 'rocket-diagram #:center (vec2 -2 0) #:rotation -1/10 #:scale 4/5))
  (define copied-window
    (circle #:id 'window-copy #:center (vec2 2 0) #:radius 3/4
            #:fill "white" #:stroke "navy" #:stroke-width 3))
  (define title
    (plain-text
     "SCENE-CB: copy a nested SVG part"
     #:id 'title #:center (vec2 0 5/2)
     #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define source-label
    (plain-text
     "window inside the imported rocket"
     #:id 'source-label #:center (vec2 -2 -13/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define destination-label
    (plain-text
     "independent copy"
     #:id 'destination-label #:center (vec2 2 -13/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define note
    (plain-text
     "The original window stays in the rocket while its copy travels out."
     #:id 'note #:center (vec2 0 -17/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title source-label destination-label note rocket))
  (define shown
    (scene-wait initial 1))
  (define copied
    (scene-play
     shown
     (transform-from-copy
      '(rocket-diagram rocket window) copied-window #:path-arc 1/2)
     #:duration 2))
  (scene-wait copied 1))

(module+ main
  (run-demo "nested-transform-from-copy.rkt" make-demo-scene))
