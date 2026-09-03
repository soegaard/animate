#lang racket/base

;;;
;;; SCENE-DQ: Robust Pointwise Maps
;;;

;; A coarse semantic grid is adaptively refined while z -> z^2 bends it.  A
;; separate reciprocal curve demonstrates that samples at its pole split the
;; image into two branches instead of adding a false line across infinity.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (square-map z) (* z z))

(define (adaptive-grid)
  (define xs '(-1 -1/2 0 1/2 1))
  (define ys '(-1 -1/2 0 1/2 1))
  (group
   (append
    (for/list ([x (in-list xs)])
      (line (vec2 x -1) (vec2 x 1)
            #:id (string->symbol (format "vertical-~a" x))
            #:stroke "steelblue" #:stroke-width 3/2))
    (for/list ([y (in-list ys)])
      (line (vec2 -1 y) (vec2 1 y)
            #:id (string->symbol (format "horizontal-~a" y))
            #:stroke "steelblue" #:stroke-width 3/2)))
   #:id 'square-grid))

(define (reciprocal-x point)
  (define x (vec2-x point))
  (if (zero? x)
      (error 'reciprocal-x "pole at x = 0")
      (vec2 (/ 3/4 x) (vec2-y point))))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DQ: robust pointwise maps"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Adaptive samples curve z ↦ z²; a pole becomes two separate branches."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define grid-caption
    (plain-text "complex grid: z ↦ z²"
                #:id 'grid-caption #:center (vec2 0 33/20)
                #:font-size 1/4 #:font-family 'modern #:color "navy"))
  (define reciprocal-caption
    (plain-text "x ↦ 3/(4x): split at x = 0"
                #:id 'reciprocal-caption #:center (vec2 0 -13/5)
                #:font-size 1/4 #:font-family 'modern #:color "darkred"))
  ;; The small cell field makes the standard argument/modulus colour convention
  ;; visible without requiring a renderer-specific continuous raster effect.
  (define domain-colours
    (complex-domain-coloring square-map
                             #:id 'domain-colours
                             #:x-min -7/5 #:x-max 7/5
                             #:y-min -7/5 #:y-max 7/5
                             #:columns 14 #:rows 14
                             #:brightness 11/20 #:opacity 1/4))
  (define reciprocal
    (line (vec2 -3/2 -2) (vec2 3/2 -2)
          #:id 'reciprocal #:stroke "crimson" #:stroke-width 3))
  (define initial
    (scene-wait
     (scene-add (make-scene)
                title explanation domain-colours (adaptive-grid) reciprocal
                grid-caption reciprocal-caption)
     1))
  (define mapped
    (scene-play
     initial
     (apply-complex-function 'square-grid square-map
                             #:samples 1 #:tolerance 1/48 #:max-depth 8)
     (apply-pointwise 'reciprocal reciprocal-x
                      #:samples 1 #:tolerance 1/32 #:max-depth 7
                      #:discontinuities 'split)
     #:duration 3))
  (scene-wait mapped 2))

(module+ main
  (run-demo "robust-pointwise-maps.rkt" make-demo-scene))
