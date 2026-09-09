#lang racket/base

;;;
;;; Corrective immutable lifecycle-model tests
;;;

(require rackunit
         "../main.rkt"
         "../private/animation.rkt"
         "../private/composition-lifecycle.rkt")

(module+ test
  (define marker (circle #:id 'marker #:radius 1/4))
  (define introduced
    (car (animation-request-lifecycle-effects (enter marker))))
  (check-equal? (lifecycle-effect-target introduced) 'marker)
  (check-equal? (lifecycle-effect-requires introduced) 'absent)
  (check-equal? (lifecycle-effect-result introduced) 'present)
  (check-true (lifecycle-effect-valid-presence? introduced #f))
  (check-false (lifecycle-effect-valid-presence? introduced #t))

  (define removed
    (car (animation-request-lifecycle-effects (leave 'marker))))
  (check-equal? (lifecycle-effect-requires removed) 'present)
  (check-equal? (lifecycle-effect-result removed) 'absent)

  ;; A helper-producing request has a stable target lifecycle plus an open
  ;; interval helper lifecycle. The explicit ID remains the helper identity.
  (define attention-effects
    (animation-request-lifecycle-effects (indicate 'marker #:id 'callout)))
  (check-equal? (length attention-effects) 2)
  (check-equal? (lifecycle-effect-target (cadr attention-effects)) 'callout)
  (check-true (lifecycle-effect-temporary? (cadr attention-effects)))
  (check-equal? (lifecycle-effect-result (cadr attention-effects)) 'absent)
  (check-equal?
   (hash-ref (lifecycle-effect->data (cadr attention-effects)) 'requires)
   'absent))
