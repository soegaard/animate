#lang racket/base

;;;
;;; SCENE-AZ Scene Parameter Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; A parameter is an immutable scene-value declaration, not mutable updater
  ;; state. It carries one stable identity and its initial semantic value.
  (define theta (parameter 'theta 0))
  (define center (parameter 'center (vec2 -2 1)))
  (check-true (scene-parameter? theta))
  (check-equal? (parameter-id theta) 'theta)
  (check-equal? (parameter-initial-value theta) 0)
  (check-equal? (parameter-id center) 'center)
  (check-equal? (parameter-initial-value center) (vec2 -2 1))
  (check-exn exn:fail:contract? (lambda () (parameter "theta" 0)))
  (check-exn exn:fail:contract? (lambda () (parameter 'bad "unsupported")))

  ;; scene-set-value's two-argument form installs the declared initial value.
  ;; Every existing symbol-based operation also accepts the reusable handle.
  (define base
    (scene-set-value (scene-set-value (make-scene) theta) center))
  (check-true (scene-state-value-has? (scene-current-state base) theta))
  (check-true (scene-state-value-has? (scene-current-state base) 'center))
  (check-equal? (scene-state-value-ref (scene-current-state base) theta) 0)
  (check-equal? (scene-current-value base theta) 0)
  (check-equal? (scene-current-value base center) (vec2 -2 1))

  ;; Parameters target the normal generic-value timeline, including derived
  ;; contexts and the exact same easing/scheduling compilation path.
  (define follower
    (derived-visual
     (circle #:id 'follower #:radius 1 #:fill "blue")
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context theta)
              (vec2-y (derived-context-value-ref context center)))))))
  (define animated
    (scene-play
     (scene-add base follower)
     (animation-group
      (value-to theta 4)
      (value-to center (vec2 2 3)))
     #:duration 4))
  (check-equal? (scene-value-at animated theta 2) 2)
  (check-equal? (scene-value-at animated center 2) (vec2 0 2))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample animated 2) 'follower))
   (vec2 2 2))
  (check-equal? (scene-current-value animated theta) 4)
  (check-equal? (scene-current-value animated center) (vec2 2 3))

  ;; The three-argument form remains the explicit replacement API, including
  ;; when the target is a parameter handle.
  (define overridden
    (scene-set-value base theta 10))
  (check-equal? (scene-current-value overridden theta) 10)
  (check-equal? (scene-current-value overridden 'theta) 10)
  (define removed
    (scene-remove-value overridden theta))
  (check-false (scene-state-value-has? (scene-current-state removed) theta))
  (check-exn exn:fail?
             (lambda () (scene-current-value removed theta)))

  ;; Ambiguous or invalid convenience calls are rejected at their boundary.
  (check-exn exn:fail:contract?
             (lambda () (scene-set-value (make-scene) 'theta)))
  (check-exn exn:fail:contract?
             (lambda () (value-to "theta" 1)))
  (check-exn exn:fail:contract?
             (lambda () (scene-current-value base "theta"))))
