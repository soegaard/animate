#lang racket/base

;;;
;;; SCENE-AV Animated Scalar Value Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define base
    (scene-set-value (make-scene) 'alpha 0))

  ;; Named scalar state is immutable scene state, independent of rendering.
  (check-true (scene-state-value-has? (scene-current-state base) 'alpha))
  (check-equal? (scene-current-value base 'alpha) 0)
  (check-equal? (scene-state-value-ref (scene-current-state base) 'alpha) 0)
  (check-false (scene-state-value-has? (scene-current-state base) 'missing))
  (check-exn exn:fail? (lambda () (scene-current-value base 'missing)))

  ;; Values and Visuals share one scene ID namespace.
  (define dot (circle #:id 'dot #:radius 1 #:fill "red"))
  (check-exn exn:fail?
             (lambda ()
               (scene-add (scene-set-value (make-scene) 'dot 1) dot)))
  (check-exn exn:fail?
             (lambda ()
               (scene-set-value (scene-add (make-scene) dot) 'dot 1)))

  ;; value-to validates the public request immediately where possible.
  (check-true (value-to-request? (value-to 'alpha 10)))
  (check-exn exn:fail:contract? (lambda () (value-to "alpha" 10)))
  (check-exn exn:fail:contract? (lambda () (value-to 'alpha +inf.0)))

  ;; A scalar transition is sampled directly and preserves exact endpoints.
  (define linear-scene
    (scene-play base (value-to 'alpha 10) #:duration 4))
  (check-equal? (scene-value-at linear-scene 'alpha 0) 0)
  (check-equal? (scene-value-at linear-scene 'alpha 1) 5/2)
  (check-equal? (scene-value-at linear-scene 'alpha 2) 5)
  (check-equal? (scene-value-at linear-scene 'alpha 4) 10)
  (check-equal? (scene-current-value linear-scene 'alpha) 10)
  (check-equal? (scene-state-value-ref (scene-sample linear-scene 2) 'alpha) 5)

  ;; Requested numeric representation is retained at the exact endpoint.
  (define inexact-end-scene
    (scene-play base (value-to 'alpha 7.0) #:duration 1))
  (check-equal? (scene-current-value inexact-end-scene 'alpha) 7.0)
  (check-false (exact? (scene-current-value inexact-end-scene 'alpha)))

  ;; Easing is inherited exactly like Visual animations.
  (define (square x) (* x x))
  (define eased-scene
    (scene-play base (value-to 'alpha 8) #:duration 4 #:easing square))
  (check-equal? (scene-value-at eased-scene 'alpha 2) 2)
  (check-equal? (scene-value-at eased-scene 'alpha 4) 8)

  ;; Sequential scalar leaves compile from exact prior endpoints.
  (define successive-scene
    (scene-play
     base
     (succession
      (value-to 'alpha 4)
      (value-to 'alpha 10))
     #:duration 4))
  (check-equal? (scene-value-at successive-scene 'alpha 1) 2)
  (check-equal? (scene-value-at successive-scene 'alpha 2) 4)
  (check-equal? (scene-value-at successive-scene 'alpha 3) 7)
  (check-equal? (scene-value-at successive-scene 'alpha 4) 10)

  ;; Local timing and composition apply to scalar and Visual leaves together.
  (define beta-base
    (scene-set-value base 'beta 10))
  (define composed-scene
    (scene-play
     beta-base
     (timed (value-to 'alpha 8) #:start 1 #:duration 2)
     (value-to 'beta 20)
     #:duration 4))
  (check-equal? (scene-value-at composed-scene 'alpha 1) 0)
  (check-equal? (scene-value-at composed-scene 'alpha 2) 4)
  (check-equal? (scene-value-at composed-scene 'alpha 3) 8)
  (check-equal? (scene-value-at composed-scene 'beta 2) 15)
  (check-equal? (scene-value-at composed-scene 'beta 4) 20)

  ;; Lagged scheduling works for values and retains the AQ limiting semantics.
  (define lagged-scene
    (scene-play
     beta-base
     (lagged-start
      (value-to 'alpha 8)
      (value-to 'beta 18)
      #:lag-ratio 1)
     #:duration 4))
  (check-equal? (scene-value-at lagged-scene 'alpha 2) 8)
  (check-equal? (scene-value-at lagged-scene 'beta 2) 10)
  (check-equal? (scene-value-at lagged-scene 'beta 3) 14)
  (check-equal? (scene-value-at lagged-scene 'beta 4) 18)

  ;; Same-value overlap is a normal scheduler component conflict; different
  ;; values and Visual motion can proceed independently.
  (check-exn
   (lambda (e)
     (and (exn:fail? e)
          (regexp-match? #rx"scalar-value" (exn-message e))))
   (lambda ()
     (scene-play
      base
      (animation-group
       (value-to 'alpha 4)
       (value-to 'alpha 8))
      #:duration 2)))

  (define mixed-base
    (scene-set-value (scene-add (make-scene) dot) 'alpha 0))
  (define mixed-scene
    (scene-play
     mixed-base
     (animation-group
      (value-to 'alpha 8)
      (move-to 'dot (vec2 4 0)))
     #:duration 4))
  (check-equal? (scene-value-at mixed-scene 'alpha 2) 4)
  (check-equal? (visual-position (scene-state-ref (scene-sample mixed-scene 2) 'dot))
                (vec2 2 0))

  ;; Missing values fail at scene compilation, while instantaneous replacement
  ;; and removal do not add timeline duration.
  (check-exn exn:fail?
             (lambda ()
               (scene-play (make-scene) (value-to 'missing 1))))
  (define replaced (scene-set-value base 'alpha 3))
  (check-equal? (scene-duration replaced) 0)
  (check-equal? (scene-current-value replaced 'alpha) 3)
  (define removed (scene-remove-value replaced 'alpha))
  (check-equal? (scene-duration removed) 0)
  (check-false (scene-state-value-has? (scene-current-state removed) 'alpha))
  (check-exn exn:fail? (lambda () (scene-remove-value removed 'alpha))))
