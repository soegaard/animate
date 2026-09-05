#lang racket/base
(require animate/experimental)

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define planet (circle #:id 'planet #:center (vec2 -2 0) #:radius 1/2 #:fill "gold"))
  (define moon (circle #:id 'moon #:center (vec2 2 0) #:radius 1/3 #:fill "lightgray"))
  (define system (group (list planet moon) #:id 'system))
  (define halo
    (derived-visual
     (circle #:id 'halo #:radius 4/5 #:fill #f #:stroke "crimson" #:stroke-width 3)
     (lambda (context template)
       (visual-with-position
        template
        (visual-position (derived-context-visual-ref context '(system planet)))))))
  (define title
    (plain-text "SCENE-BB: address a nested Visual by path" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (scene-wait
   (scene-play (scene-add (scene-add (scene-add (make-scene) system) halo) title)
               (move-to '(system planet) (vec2 1 0)) #:duration 3/2)
   1/2))

(module+ main (run-demo "nested-addressing.rkt" make-demo-scene))
