#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define logarithmic-axes
    (axes #:id 'logarithmic-axes
          #:x-range (axis-range 1 1000 1)
          #:y-range (axis-range 1 1000 1)
          #:x-scale 'log #:y-scale 'log
          #:x-log-base 10 #:y-log-base 10
          ;; Logarithmic coordinate 1 maps to local zero, so translate the
          ;; positive-only display rectangle back around the scene origin.
          #:center (vec2 -4 -3)
          #:x-length 8 #:y-length 6
          #:x-tip? #f #:y-tip? #f #:stroke "navy" #:stroke-width 3))
  (define grid
    (axes-grid-lines logarithmic-axes #:id 'grid
                     #:stroke "lightgray" #:stroke-width 1))
  (define labels
    (axes-number-labels logarithmic-axes #:id-prefix 'log-label
                        #:font-size 1/4 #:color "navy"))
  (define diagram
    (group (append (list grid logarithmic-axes) labels) #:id 'diagram))
  (define graph
    (function-graph logarithmic-axes (lambda (x) x)
                    #:id 'identity #:sample-count 121
                    #:stroke "red" #:stroke-width 4))
  (define title
    (plain-text "SCENE-BJ: logarithmic axes" #:id 'title
                #:center (vec2 0 7/2) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (make-scene)
               (animation-group (fade-in diagram) (create graph) (fade-in title))
               #:duration 2)
   1/2))

(module+ main (run-demo "logarithmic-axes.rkt" make-demo-scene))
