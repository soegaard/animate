#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define amplitude (parameter 'amplitude 1))

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -4 4 1) #:y-range (axis-range -4 4 1)
          #:x-length 8 #:y-length 6 #:stroke "navy" #:stroke-width 3))
  (define graph
    (derived-function-graph
     coordinate-axes
     (lambda (context x)
       (* (derived-context-value-ref context amplitude) (sin x)))
     #:id 'sine-wave #:sample-count 161 #:stroke "purple" #:stroke-width 4))
  (define title
    (plain-text "SCENE-BN: a parameter-driven function graph" #:id 'title
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (define start
    (scene-add (scene-add (scene-add (scene-set-value (make-scene) amplitude) coordinate-axes) graph) title))
  (scene-wait
   (scene-play start
               (animation-group (value-to amplitude 3) (fade-to title 2/5))
               #:duration 3)
   1/2))

(module+ main (run-demo "derived-function-graphs.rkt" make-demo-scene))
