#lang racket/base

;;;
;;; SCENE-DN: Adaptive, Time-Dependent ODE Flow
;;;

;; A projectile uses the non-autonomous field x' = 1, y' = 2 - t.  Adaptive
;; RK45 prepares immutable dense nodes until the downward y = 0 event, then a
;; normal phase parameter drives the particle without any renderer-side solver.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (trajectory-visual axes-value trajectory)
  (define range (ode-trajectory-time-range trajectory))
  (define start (car range))
  (define end (cdr range))
  ;; Dense output supplies arbitrary-time samples.  data-plot turns these
  ;; numeric coordinates into one tangent-continuous cubic path, which avoids
  ;; visible polyline joints at the projectile's turning point.
  (define coordinates
    (for/list ([index (in-range 241)])
      (define time (+ start (* (/ index 240) (- end start))))
      (ode-trajectory-position trajectory time)))
  (data-plot axes-value coordinates
             #:id 'trajectory #:clip? #f #:interpolation 'smooth
             #:stroke "steelblue" #:stroke-width 3))

(define (make-demo-scene)
  (define coordinate-axes
    (axes #:id 'axes
          #:center (vec2 0 -2/5)
          #:x-range (axis-range -1 5 1)
          #:y-range (axis-range -1 5/2 1)
          #:x-length 7 #:y-length 7/2 #:y-tip? #f
          #:stroke "midnightblue"))
  ;; x' = 1 and y' = 2 - t gives a visible time-dependent parabola.
  (define projectile-field
    (lambda (time _x _y)
      (vec2 1 (- 2 time))))
  (define ground-event
    (ode-event (lambda (_time _x y) y)
               #:direction 'decreasing #:name 'ground-contact))
  (define trajectory
    (prepare-ode-trajectory
     projectile-field origin
     #:time-range (cons 0 5)
     #:solver (adaptive-rk45 #:relative-tolerance 1e-8
                             #:absolute-tolerance 1e-10
                             #:initial-step 1/10)
     #:event ground-event))
  (define end-time (cdr (ode-trajectory-time-range trajectory)))
  (define phase (parameter 'time 0))
  (define title
    (plain-text "SCENE-DN: adaptive time-dependent ODE flow"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "RK45 dense output ends at the downward y = 0 event."
                #:id 'explanation #:center (vec2 0 31/10)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define status
    (plain-text "x' = 1,   y' = 2 − t       event: y = 0 (downward)"
                #:id 'status #:center (vec2 0 -17/5)
                #:font-size 1/4 #:font-family 'modern #:color "darkred"))
  (define ground
    ;; Stop at the base of the x-axis arrowhead.  The ground is deliberately
    ;; drawn above the axes, but must not continue through the blue tip.
    (let ([x-tip-base
           (- (axis-range-maximum (axes-visual-x-range coordinate-axes))
              (/ (axes-visual-tip-length coordinate-axes)
                 (axes-x-unit-length coordinate-axes)))])
      (line (axes-coordinates->point coordinate-axes -1 0)
            (axes-coordinates->point coordinate-axes x-tip-base 0)
            #:id 'ground #:stroke "sienna" #:stroke-width 2)))
  (define particle
    (flow-particle coordinate-axes trajectory phase
                   #:id 'particle #:shape 'circle #:size 1/4
                   #:fill "crimson" #:stroke "firebrick" #:stroke-width 2))
  (define initial
    (scene-wait
     (scene-add (scene-set-value (make-scene) phase)
                coordinate-axes ground (trajectory-visual coordinate-axes trajectory)
                particle title explanation status)
     1))
  (scene-wait
   (scene-play initial (value-to phase end-time) #:duration 3)
   1))

(module+ main
  (run-demo "adaptive-ode-trajectory.rkt" make-demo-scene))
