#lang racket/base

;;;
;;; SCENE-DK: Semantic Nested Affine Transforms
;;;

;; A complete diagram first receives a shear.  Its named unit square is then
;; independently reflected in world coordinates and recoloured, while the
;; rest of the already-sheared diagram stays in place.  This exercises affine
;; composition through an ordinary nested Visual tree.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define diagram
    (linear-transformation-diagram #:id 'diagram #:vector-end (vec2 3 2)))
  (define title
    (plain-text "SCENE-DK: semantic nested affine transforms"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Shear the diagram, then independently reflect its named unit square."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-wait
     (scene-add (make-scene) title explanation diagram)
     1))
  (define sheared
    (scene-play
     initial
     (apply-matrix 'diagram
                   (linear2 1 3/5
                            0 1))
     #:duration 2))
  (define reflected-square
    (scene-play
     sheared
     (apply-matrix '(diagram unit-square)
                   (linear2 -1 0
                             0 1))
     (fill-color-to '(diagram unit-square) "tomato")
     #:duration 2))
  (scene-wait reflected-square 2))

(module+ main
  (run-demo "semantic-nested-affine-transforms.rkt" make-demo-scene))
