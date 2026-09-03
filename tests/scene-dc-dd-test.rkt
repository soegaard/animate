#lang racket/base

;;;
;;; SCENE-DC/DD Deterministic Flow and Numeric-Display Tests
;;;

(require rackunit
         racket/class
         racket/draw
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

  ;; A unit rotational field has the exact solution (cos t, sin t). Fixed-step
  ;; RK4 is accurate and direct arbitrary-time samples need no frame history.
  (define rotational-flow (lambda (x y) (vec2 (- y) x)))
  (check-vec2-close
   (ode-flow-position rotational-flow (vec2 1 0) (/ pi 2) #:step-size 1/100)
   (vec2 0 1)
   1e-7)
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
  (define particle
    (flow-particle coordinate-axes constant-flow (vec2 0 0) phase
                   #:id 'particle #:step-size 1/10))
  (define animated-flow
    (scene-play
     (scene-add (scene-set-value (make-scene) phase)
                coordinate-axes particle)
     (value-to phase 2)
     #:duration 1))
  (check-vec2-close
   (visual-position (scene-visual-at animated-flow 'particle 1))
   (axes-coordinates->point coordinate-axes 4 -2))

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
