#lang racket/base

;;;
;;; SCENE-DS: Mathematical Animation Effects
;;;

;; The temporary effects are independent overlays over one live curve. The
;; final panel introduces three ordinary Visuals with centre growth, arrow
;; growth, and outline-then-fill, respectively.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DS: mathematical animation effects"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Live focus, flash, passing trace, wiggle, growth, and border-to-fill."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define curve
    (make-path-visual
     (polyline-path (list (vec2 -5/2 1/2) (vec2 -3/2 3/4) (vec2 -1/2 0)
                          (vec2 1/2 1) (vec2 3/2 -1/4) (vec2 5/2 1/2)))
     #:id 'curve #:fill #f #:stroke "steelblue" #:stroke-width 3))
  (define curve-caption
    (plain-text "a semantic path" #:id 'curve-caption #:center (vec2 0 -1/2)
                #:font-size 1/4 #:font-family 'modern #:color "midnightblue"))
  (define grown-dot
    (circle #:id 'grown-dot #:center (vec2 -2 -2) #:radius 2/5
            #:fill "coral" #:stroke "firebrick" #:stroke-width 2))
  (define grown-arrow
    (arrow (vec2 -3/5 -2) (vec2 3/5 -2) #:id 'grown-arrow
           #:stroke "darkgreen" #:stroke-width 3))
  (define filled-panel
    (make-path-visual
     (polygon-path (list (vec2 3/2 -12/5) (vec2 5/2 -12/5)
                         (vec2 5/2 -8/5) (vec2 3/2 -8/5)))
     #:id 'filled-panel #:fill "gold" #:stroke "sienna" #:stroke-width 2))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation curve curve-caption) 1))
  (define flashed (scene-play initial (flash 'curve #:color "gold") #:duration 1))
  (define focused (scene-play flashed (focus-on 'curve #:color "mediumpurple") #:duration 1))
  (define traced
    (scene-play focused
                (show-passing-flash 'curve #:color "crimson" #:time-width 1/4)
                (wiggle 'curve #:angle 1/20)
                #:duration 2))
  (scene-wait
   (scene-play traced
               (grow-from-center grown-dot)
               (grow-arrow grown-arrow)
               (draw-border-then-fill filled-panel)
               #:duration 2)
   1))

(module+ main
  (run-demo "mathematical-effects.rkt" make-demo-scene))
