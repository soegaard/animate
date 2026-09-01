#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define count (parameter 'count 2))

(define (make-demo-scene)
  (define ticks
    (derived-visual
     (group '() #:id 'ticks)
     (lambda (context template)
       (define n (inexact->exact (round (derived-context-value-ref context count))))
       (group
        (for/list ([index (in-range n)])
          (circle #:id (string->symbol (format "tick-~a" index))
                  #:center (vec2 (- (* index 6/5) 18/5) 0)
                  #:radius 1/3 #:fill "seagreen" #:stroke "darkgreen"))
        #:id (visual-id template)))))
  (define title
    (plain-text "SCENE-BA: a derived group grows" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (scene-add (scene-add (scene-set-value (make-scene) count) ticks) title)
               (value-to count 7) #:duration 3)
   1/2))

(module+ main (run-demo "derived-groups.rkt" make-demo-scene))
