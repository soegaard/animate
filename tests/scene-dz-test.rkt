#lang racket/base

;;;
;;; SCENE-DZ Time Reparameterization Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define (check-close actual expected)
    (check-= actual expected 1e-9))

  ;; A profile is a speed over wall-clock progress, normalized by its total
  ;; integral. This increasing profile has covered 2/5 of the distance halfway
  ;; through the clip, not merely half.
  (define accelerating
    (change-speed '((0 1) (1/2 3) (1 3))))
  (check-true (rate-function? accelerating))
  (check-equal? (rate-function-name accelerating) 'change-speed)
  (check-equal? (accelerating 0) 0)
  (check-equal? (accelerating 1) 1)
  (check-close (accelerating 1/2) 2/5)
  (check-equal?
   (rate-function->datum accelerating)
   '(change-speed ((0 1) (1/2 3) (1 3))))

  ;; The higher-order constructors remain transparent callable descriptions.
  (define bezier
    (cubic-bezier #:x1 1/4 #:y1 1/10 #:x2 1/4 #:y2 1))
  (check-true (rate-function? bezier))
  (check-equal? (bezier 0) 0)
  (check-equal? (bezier 1) 1)
  (check-true (> (bezier 1/4) 1/4))
  (check-true (rate-function? (spring)))
  (check-equal? ((spring) 0) 0)
  (check-equal? ((spring) 1) 1)

  (define reversed (reverse-rate (rush-into)))
  (check-close (reversed 1/2) ((rush-from) 1/2))
  (define composed (compose-rate (smoothstep) (squish-rate linear #:from 1/4 #:to 3/4)))
  (check-equal? (composed 0) 0)
  (check-equal? (composed 1) 1)
  (check-equal? ((squish-rate linear #:from 1/4 #:to 3/4) 1/4) 0)
  (check-equal? ((squish-rate linear #:from 1/4 #:to 3/4) 3/4) 1)

  ;; `timed` already gives each request a local rate-function slot. The speed
  ;; profile therefore reparameterizes one request without affecting the scene
  ;; architecture or any neighboring scheduled request.
  (define dot
    (circle #:id 'dot #:center origin #:radius 1/4 #:fill "royalblue"))
  (define reparameterized-scene
    (scene-play
     (scene-add (make-scene) dot)
     (timed (move-to 'dot (vec2 5 0)) #:duration 2 #:easing accelerating)
     #:duration 2))
  (check-close
   (vec2-x (visual-position (scene-visual-at reparameterized-scene 'dot 1)))
   2)
  (check-equal?
   (scene-visual-at reparameterized-scene 'dot 2)
   (visual-with-position dot (vec2 5 0)))

  ;; Profiles are validated as a genuine, strictly increasing unit-time speed
  ;; schedule, rather than accepting ambiguous or negative clock descriptions.
  (check-exn exn:fail:contract?
             (lambda () (change-speed '((0 1) (1/2 0) (1 1)))))
  (check-exn exn:fail:contract?
             (lambda () (change-speed '((0 1) (0 2) (1 1)))))
  (check-exn exn:fail:contract?
             (lambda () (change-speed '((1/4 1) (1 1)))))
  (check-exn exn:fail:contract?
             (lambda () (squish-rate linear #:from 1/2 #:to 1/2))))
