#lang racket/base

;;;
;;; SCENE-CP: Secant to Tangent
;;;

;; One immutable parameter h controls the second graph point. The live derived
;; group rebuilds the ordinary secant-slope construction for each sampled h;
;; no updater or frame history is needed as the secant approaches the tangent.

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define h (parameter 'h 2))

(define (parabola x)
  (/ (* x x) 4))

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes #:center (vec2 0 -1/2)
          #:x-range (axis-range -3 3 1) #:y-range (axis-range -1 3 1)
          #:x-length 6 #:y-length 4 #:stroke "slategray" #:stroke-width 2
          #:x-tip? #f #:y-tip? #f))
  (define graph
    (function-graph coordinate-axes parabola #:id 'parabola
                    #:sample-count 161 #:stroke "royalblue" #:stroke-width 4))
  (define tangent
    (tangent-line coordinate-axes parabola 1 #:id 'tangent #:dx 1/100 #:length 3
                  #:stroke "crimson" #:stroke-width 3))
  (define secant
    (derived-visual
     (secant-slope-group coordinate-axes parabola 1 2 #:id 'secant)
     (lambda (context _template)
       (secant-slope-group
        coordinate-axes parabola 1 (derived-context-value-ref context h)
        #:id 'secant #:secant-stroke "darkorange" #:guide-stroke "gray"))))
  (define title
    (plain-text "SCENE-CP: derivative from a shrinking secant"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "One parameter h moves the second point toward x = 1."
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define h-label
    (plain-text "h → 0" #:id 'h-label #:center (vec2 2 9/5)
                #:font-size 1/4 #:color "darkorange"))
  (define initial
    (scene-add (scene-set-value (make-scene) h)
               coordinate-axes graph tangent secant title explanation h-label))
  (scene-wait
   (scene-play initial (value-to h 1/5) #:duration 3)
   1))

(module+ main
  (run-demo "secant-to-tangent.rkt" make-demo-scene))
