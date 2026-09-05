#lang racket/base
(require animate/experimental)

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define center (parameter 'center (vec2 -4 0)))
(define hue (parameter 'hue (rgba-color 35 120 215 1)))

(define (make-demo-scene)
  (define token
    (derived-visual
     (circle #:id 'token #:radius 3/5 #:fill "royalblue")
     (lambda (context template)
       (visual-with-fill-color
        (visual-with-position template (derived-context-value-ref context center))
        (derived-context-value-ref context hue)))))
  (define title
    (plain-text "SCENE-AZ: reusable parameter handles" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define start
    (scene-add (scene-add (scene-set-value (scene-set-value (make-scene) center) hue)
                          token)
               title))
  (scene-wait
   (scene-play start
               (animation-group
                (value-to center (vec2 4 0))
                (value-to hue (rgba-color 225 100 55 1)))
               #:duration 3)
   1/2))

(module+ main (run-demo "parameter-handles.rkt" make-demo-scene))
