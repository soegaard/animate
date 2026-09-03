#lang racket/base

;;;
;;; SCENE-DC/DD: Deterministic Streamlines and Numeric Displays
;;;

;; A phase parameter drives both the particle's RK4 solution and its decimal
;; readout. Each animation frame can be sampled independently: neither the
;; particle nor the label depends on a previously rendered frame.

(require racket/math
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -3 3 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 6 #:y-length 6
          #:stroke "midnightblue"))
  ;; The circular field (x', y') = (-y, x) makes the integral curves easy to
  ;; recognize. The field is in mathematical coordinate units per unit time.
  (define rotation-field
    (lambda (x y) (vec2 (- y) x)))
  (define flow-lines
    (streamlines coordinate-axes rotation-field
                 (list (vec2 1 0) (vec2 2 0) (vec2 3/2 0))
                 #:id 'flow-lines #:direction 'both
                 #:step-size 1/40 #:steps 126
                 #:stroke "steelblue" #:stroke-width 2 #:opacity 3/5))
  (define phase (parameter 'time 0.0))
  (define particle-trajectory
    (prepare-ode-trajectory
     rotation-field (vec2 2 0)
     #:time-range (cons 0 (* 2 pi))
     #:step-size 1/10))
  (define particle
    (flow-particle coordinate-axes particle-trajectory phase
                   #:id 'particle
                   #:size 1/4 #:fill "crimson" #:stroke "firebrick"))
  (define title
    (plain-text "SCENE-DC/DD: deterministic flow"
                #:id 'title #:center (vec2 0 18/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Prepared RK4 checkpoints drive the particle; the decimal point stays fixed."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define time-label
    (plain-text "time t ="
                #:id 'time-label #:center (vec2 -1 -18/5)
                #:font-size 1/4 #:font-family 'swiss #:color "darkred"
                #:horizontal-alignment 'right))
  (define time-display
    (parameter-display phase #:id 'time-display #:center (vec2 -3/5 -18/5)
                       #:kind 'decimal #:decimal-places 2 #:unit " s"
                       #:anchor 'decimal #:font-size 1/4
                       #:font-family 'modern #:color "darkred"))
  (define initial
    (scene-wait
     (scene-add (scene-set-value (make-scene) phase)
                coordinate-axes flow-lines particle
                title explanation time-label time-display)
     1))
  (define moving
    (scene-play initial
                (value-to phase (* 2 pi))
                #:duration 3))
  (scene-wait moving 1))

(module+ main
  (run-demo "streamlines-and-numeric-display.rkt" make-demo-scene))
