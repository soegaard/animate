#lang racket/base

;;;
;;; SCENE-CY: General Affine Maps
;;;

;; Demonstrates a whole mathematical diagram under the shear matrix
;; [1 1; 0 1]. The title and matrix notation remain separate top-level Visuals,
;; while the grid, basis arrows, unit square, and arbitrary vector form one
;; transformed group.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define diagram
    (linear-transformation-diagram #:id 'diagram #:vector-end (vec2 3 2)))
  (define title
    (plain-text "SCENE-CY: general affine maps"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "A shear maps the grid, square, basis vectors, and v together."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define matrix-label
    (plain-text "A = [ 1  1 ; 0  1 ]"
                #:id 'matrix-label #:center (vec2 0 -18/5)
                #:font-size 1/4 #:font-family 'modern #:color "darkred"))
  (define initial
    (scene-wait
     (scene-add (make-scene) title explanation matrix-label diagram)
     1))
  (define sheared
    (scene-play
     initial
     (apply-matrix 'diagram (linear2 1 1
                                     0 1))
     #:duration 3))
  (scene-wait sheared 2))

(module+ main
  (run-demo "affine-linear-transformations.rkt" make-demo-scene))
