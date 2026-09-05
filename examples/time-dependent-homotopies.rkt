#lang racket/base

;;;
;;; SCENE-DW: Time-Dependent Homotopies
;;;

;; The curved grid at every frame is H(p, alpha), evaluated from the original
;; grid geometry. It is not a linear interpolation toward the final wavy grid.

(require racket/math
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (grid-line-id direction index)
  (string->symbol (format "~a-~a" direction index)))

(define (make-demo-scene)
  (define vertical-lines
    (for/list ([x (in-range -3 4)])
      (line (vec2 x -2) (vec2 x 2)
            #:id (grid-line-id 'vertical x)
            #:stroke "steelblue" #:stroke-width 1)))
  (define horizontal-lines
    (for/list ([y (in-range -2 3)])
      (line (vec2 -3 y) (vec2 3 y)
            #:id (grid-line-id 'horizontal y)
            #:stroke "steelblue" #:stroke-width 1)))
  (define grid
    (group
     (append vertical-lines
             horizontal-lines
             (list
              (circle #:id 'marker #:center origin #:radius 1/4
                      #:fill "gold" #:stroke "darkgoldenrod" #:stroke-width 2)))
     #:id 'grid))
  (define title
    (plain-text "SCENE-DW: time-dependent homotopy"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Every frame evaluates H(p, α) directly from the original grid."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define formula
    (plain-text "H(x, y, α) = (x + α sin(2y), y)"
                #:id 'formula #:center (vec2 0 -27/10)
                #:font-size 1/4 #:font-family 'modern #:color "darkred"))
  (define initial
    (scene-wait
     (scene-add (make-scene) title explanation grid formula)
     1))
  (define deformed
    (scene-play
     initial
     (apply-homotopy
      'grid
      (lambda (point alpha)
        (vec2 (+ (vec2-x point)
                 (* alpha (sin (* 2 (vec2-y point)))))
              (vec2-y point)))
     #:samples 4 #:tolerance 1/96 #:max-depth 8)
     #:duration 3
     #:easing (smooth)))
  (scene-wait deformed 1))

(module+ main
  (run-demo "time-dependent-homotopies.rkt" make-demo-scene))
