#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define center (vec2 -4 -2))
  (define dot
    (derived-visual
     (circle #:id 'dot #:radius 3/5 #:fill "royalblue")
     (lambda (context template)
       (visual-with-fill-color
        (visual-with-position template (derived-context-value-ref context 'center))
        (derived-context-value-ref context 'color)))))
  (define title
    (plain-text "SCENE-AY: generic interpolable values" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define base
    (scene-add
     (scene-add
      (scene-set-value
       (scene-set-value (make-scene) 'center center)
       'color (rgba-color 45 90 210 1))
      dot)
     title))
  (define animated
    (scene-play base
                (animation-group
                 (value-to 'center (vec2 4 2))
                 (value-to 'color (rgba-color 230 80 65 1)))
                #:duration 3))
  (scene-wait animated 1/2))

(module+ main (run-demo "generic-interpolable-values.rkt" make-demo-scene))
