#lang racket/base

;; SCENE-AV named scalar-value example.

(require animate)

(provide make-demo-scene)

(define (make-demo-scene)
  (define initial
    (scene-set-value
     (scene-set-value (make-scene) 'x 0)
     'phase 0))
  (scene-play
   initial
   (animation-group
    (value-to 'x 10)
    (succession
     (value-to 'phase 1)
     (value-to 'phase 0)))
   #:duration 4))

(module+ main
  (define demo (make-demo-scene))
  (for ([time (in-list '(0 1 2 3 4))])
    (printf "t=~a  x=~a  phase=~a\n"
            time
            (scene-value-at demo 'x time)
            (scene-value-at demo 'phase time))))
