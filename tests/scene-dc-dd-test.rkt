#lang racket/base

;;;
;;; SCENE-DC/DD Deterministic Flow and Numeric-Display Tests
;;;

(require rackunit
         racket/class
         racket/draw
         racket/file
         racket/math
         "../main.rkt")

(module+ test
  (define (check-vec2-close actual expected [tolerance 1e-8])
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  (define constant-flow (lambda (_x _y) (vec2 2 -1)))
  (check-vec2-close
   (ode-flow-position constant-flow (vec2 1 3) 5 #:step-size 1/4)
   (vec2 11 -2))
  (check-vec2-close
   (ode-flow-position constant-flow (vec2 1 3) -2 #:step-size 1/4)
   (vec2 -3 5))

  ;; A three-argument field receives the physical ODE time at each RK stage.
  ;; Here x' = t, y' = 0 has the exact solution x(t) = t²/2 from the origin.
  (define time-driven-flow (lambda (time _x _y) (vec2 time 0)))
  (check-vec2-close
   (ode-flow-position time-driven-flow origin 3 #:step-size 1/4)
   (vec2 9/2 0))
  (define time-driven-trajectory
    (prepare-ode-trajectory
     time-driven-flow origin #:time-range (cons -2 3) #:step-size 1/4
     #:checkpoint-every 3))
  (for ([time (in-list (list -2 -3/4 0 9/8 3))])
    (check-equal?
     (ode-trajectory-position time-driven-trajectory time)
     (ode-flow-position time-driven-flow origin time #:step-size 1/4)))

  ;; Prepared trajectories preserve the direct fixed-RK4 result while bounding
  ;; arbitrary lookups by their checkpoint stride in either time direction.
  (define constant-trajectory
    (prepare-ode-trajectory
     constant-flow (vec2 1 3)
     #:time-range (cons -2 5)
     #:step-size 1/4 #:checkpoint-every 3))
  (check-equal? (ode-trajectory-time-range constant-trajectory) (cons -2 5))
  (check-equal? (ode-trajectory-step-size constant-trajectory) 1/4)
  (check-equal? (ode-trajectory-checkpoint-every constant-trajectory) 3)
  (for ([time (in-list (list -2 -3/4 0 9/8 5))])
    (check-vec2-close
     (ode-trajectory-position constant-trajectory time)
     (ode-flow-position constant-flow (vec2 1 3) time #:step-size 1/4)))
  (check-exn exn:fail:contract?
             (lambda () (ode-trajectory-position constant-trajectory 6)))

  ;; A unit rotational field has the exact solution (cos t, sin t). Fixed-step
  ;; RK4 is accurate and direct arbitrary-time samples need no frame history.
  (define rotational-flow (lambda (x y) (vec2 (- y) x)))
  (check-vec2-close
   (ode-flow-position rotational-flow (vec2 1 0) (/ pi 2) #:step-size 1/100)
   (vec2 0 1)
   1e-7)
  ;; A prepared lookup follows exactly the same canonical full-step/remainder
  ;; path as the direct solver, including negative time and an inexact query.
  (define rotational-trajectory
    (prepare-ode-trajectory
     rotational-flow (vec2 1 0)
     #:time-range (cons -2 2)
     #:step-size 1/10 #:checkpoint-every 4))
  (for ([time (in-list (list -7/10 0 13/10 (/ pi 2)))])
    (check-equal?
     (ode-trajectory-position rotational-trajectory time)
     (ode-flow-position rotational-flow (vec2 1 0) time #:step-size 1/10)))
  (define orbit
    (streamline-points rotational-flow (vec2 1 0)
                       #:direction 'both #:step-size 1/10 #:steps 3))
  (check-equal? (length orbit) 7)
  (check-vec2-close (list-ref orbit 3) (vec2 1 0))

  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -3 3 1)
          #:y-range (axis-range -3 3 1)
          #:x-length 6 #:y-length 6))
  (define flow-lines
    (streamlines coordinate-axes rotational-flow
                 (list (vec2 1 0) (vec2 2 0))
                 #:id 'flow-lines #:step-size 1/10 #:steps 20))
  (define flow-scene
    (scene-wait
     (scene-add (make-scene) coordinate-axes flow-lines)
     1))
  (check-true (group-visual?
               (scene-visual-at flow-scene 'flow-lines 0)))
  (check-true (path-visual?
               (scene-visual-at flow-scene '(flow-lines flow-lines-0) 0)))
  (check-true (is-a? (scene-frame->bitmap flow-scene 0) bitmap%))

  (define phase (parameter 'phase 0))
  (define particle-trajectory
    (prepare-ode-trajectory
     constant-flow (vec2 0 0)
     #:time-range (cons 0 2)
     #:step-size 1/10))
  (define particle
    (flow-particle coordinate-axes particle-trajectory phase
                   #:id 'particle))
  ;; Flow particles deliberately have no legacy raw-field form: they require a
  ;; bounded prepared trajectory so their renderer behaviour is explicit.
  (check-exn exn:fail:contract?
             (lambda ()
               (flow-particle coordinate-axes constant-flow phase #:id 'raw)))
  (define animated-flow
    (scene-play
     (scene-add (scene-set-value (make-scene) phase)
                coordinate-axes particle)
     (value-to phase 2)
     #:duration 1))
  (check-vec2-close
   (visual-position (scene-visual-at animated-flow 'particle 1))
   (axes-coordinates->point coordinate-axes 4 -2))

  ;; render-frames! prepares requested positions once. The ODE field runs for
  ;; the half-step during preparation, then no renderer worker calls it again.
  (define field-call-count (box 0))
  (define (counted-flow x y)
    (set-box! field-call-count (add1 (unbox field-call-count)))
    (vec2 y (- x)))
  (define counted-trajectory
    (prepare-ode-trajectory
     counted-flow (vec2 1 0)
     #:time-range (cons 0 1)
     #:step-size 1 #:checkpoint-every 1))
  (set-box! field-call-count 0)
  (define counted-phase (parameter 'counted-phase 0))
  (define counted-particle
    (flow-particle coordinate-axes counted-trajectory counted-phase
                   #:id 'counted-particle))
  (define counted-scene
    (scene-play
     (scene-add (scene-set-value (make-scene) counted-phase)
                coordinate-axes counted-particle)
     (value-to counted-phase 1)
     #:duration 1))
  (define output-directory
    (make-temporary-file "animate-ode-frame-samples~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (render-frames! counted-scene output-directory #:fps 2)
     ;; Frame times are 0 and 1/2. The prepass needs one RK4 remainder only.
     (check-equal? (unbox field-call-count) 4))
   (lambda () (delete-directory/files output-directory)))

  ;; A batch shares the canonical suffix inside each checkpoint interval. The
  ;; four selected times below are 0, 3/4, 3/2, and 9/4. With a stride of four,
  ;; their full-step prefixes advance only from 0 to 2 (8 field calls), then
  ;; the three nonzero remainders use 12 more calls. Independent lookup would
  ;; repeat one prefix and need 24 calls instead.
  (define batched-call-count (box 0))
  (define (batched-flow x y)
    (set-box! batched-call-count (add1 (unbox batched-call-count)))
    (vec2 y (- x)))
  (define batched-trajectory
    (prepare-ode-trajectory
     batched-flow (vec2 1 0)
     #:time-range (cons 0 4)
     #:step-size 1 #:checkpoint-every 4))
  (set-box! batched-call-count 0)
  (define batched-phase (parameter 'batched-phase 0))
  (define batched-scene
    (scene-play
     (scene-add (scene-set-value (make-scene) batched-phase)
                coordinate-axes
                (flow-particle coordinate-axes batched-trajectory batched-phase
                               #:id 'batched-particle))
     (value-to batched-phase 3)
     #:duration 2))
  (define batched-output-directory
    (make-temporary-file "animate-ode-batched-samples~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (render-frames! batched-scene batched-output-directory #:fps 2)
     (check-equal? (unbox batched-call-count) 20))
   (lambda () (delete-directory/files batched-output-directory)))

  ;; Formatting has intentional trailing zeroes, grouping, and sign behavior.
  (check-equal? (format-integer -1234567 #:grouping? #t) "-1,234,567")
  (check-equal? (format-decimal 1234.5 #:decimal-places 2 #:grouping? #t
                                #:show-sign? #t #:unit " m")
                "+1,234.50 m")
  (check-equal? (text-visual-content
                 (integer 12 #:id 'integer #:show-sign? #t))
                "+12")
  (check-equal? (text-visual-content
                 (decimal-number 2 #:id 'decimal #:decimal-places 3))
                "2.000")

  ;; Parameter displays sample named scene values. Decimal anchoring produces
  ;; two local children around the fixed group reference point.
  (define value (parameter 'value 9.9))
  (define decimal-display
    (parameter-display value #:id 'display #:center (vec2 2 3)
                       #:decimal-places 1 #:anchor 'decimal))
  (define sign-display
    (parameter-display value #:id 'sign-display #:kind 'integer #:anchor 'sign))
  ;; Parameter displays are now fixed-structure relation Visuals backed by a
  ;; transparent built-in formatting specification, not opaque derived
  ;; resolver closures. The specification is also the conservative cache key.
  (check-true (relation-visual? decimal-display))
  (check-true
   (parameter-display-relation-spec?
    (relation-visual-cache-key decimal-display)))
  (check-eq? (relation-visual-cacheability decimal-display) 'serializable)
  (define display-scene
    (scene-play
     (scene-add (scene-set-value (make-scene) value)
                decimal-display sign-display)
     (value-to value 10)
     #:duration 1))
  (check-true (group-visual?
               (scene-visual-at display-scene 'display 1)))
  (check-equal? (visual-position
                 (scene-visual-at display-scene 'display 1))
                (vec2 2 3))
  (check-equal? (text-visual-content
                 (scene-visual-at display-scene '(display fraction) 1))
                ".0")
  (check-equal? (text-visual-content
                 (scene-visual-at display-scene 'sign-display 1))
                "+10")

  (check-exn exn:fail:contract?
             (lambda () (ode-flow-position 42 origin 1)))
  (check-exn exn:fail:contract?
             (lambda () (streamline-points constant-flow origin #:steps 0)))
  (check-exn exn:fail:contract?
             (lambda () (format-decimal 1 #:decimal-places -1))))
