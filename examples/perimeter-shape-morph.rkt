#lang racket/base

;;;
;;; SCENE-CJ: Shape-Aware Perimeter Morphing
;;;

;; Circle and rectangle primitives share canonical cardinal/corner perimeter
;; anchors. The square's four corners therefore round evenly into a circle.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CJ: shape-aware perimeter morph"
                #:id 'title #:center (vec2 0 3)
                #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Matching cardinal anchors makes every square corner round evenly."
                #:id 'explanation #:center (vec2 0 5/2)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define square
    (rectangle #:id 'square #:center origin #:width 2 #:height 2
               #:fill "cornflowerblue" #:stroke "navy" #:stroke-width 3))
  (define disk
    (circle #:id 'disk #:center origin #:radius 1
            #:fill "seagreen" #:stroke "darkgreen" #:stroke-width 3))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation square) 1))
  (define morphed
    (scene-play initial
                (transform-shape square disk
                                 #:mode 'morph
                                 #:correspondence 'perimeter)
                #:duration 2))
  (scene-wait morphed 2))

(module+ main
  (run-demo "perimeter-shape-morph.rkt" make-demo-scene))
