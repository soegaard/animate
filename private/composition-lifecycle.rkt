#lang racket/base

;;;
;;; Immutable request lifecycle descriptions
;;;

;; The effect/request layer classifies its own concrete requests, while this
;; module owns the shared immutable vocabulary. Keeping the data model pure
;; lets composition diagnostics, project tooling, and inspectors describe
;; structural preconditions without depending on renderer state.

(provide lifecycle-effect
         lifecycle-effect?
         lifecycle-effect-target
         lifecycle-effect-requires
         lifecycle-effect-result
         lifecycle-effect-temporary?
         lifecycle-effect-exact-endpoint?
         lifecycle-effect-valid-presence?
         lifecycle-effect->data)

(struct lifecycle-effect
  (target requires result temporary? exact-endpoint?)
  #:transparent
  #:guard
  (lambda (target requires result temporary? exact-endpoint? who)
    (unless (memq requires '(present absent either))
      (raise-argument-error who "'present, 'absent, or 'either as requires" requires))
    (unless (memq result '(present absent unchanged))
      (raise-argument-error who "'present, 'absent, or 'unchanged as result" result))
    (unless (boolean? temporary?)
      (raise-argument-error who "boolean? as temporary?" temporary?))
    (unless (boolean? exact-endpoint?)
      (raise-argument-error who "boolean? as exact-endpoint?" exact-endpoint?))
    (values target requires result temporary? exact-endpoint?)))

(define (lifecycle-effect-valid-presence? effect present?)
  (unless (lifecycle-effect? effect)
    (raise-argument-error 'lifecycle-effect-valid-presence? "lifecycle-effect?" effect))
  (unless (boolean? present?)
    (raise-argument-error 'lifecycle-effect-valid-presence? "boolean?" present?))
  (case (lifecycle-effect-requires effect)
    [(present) present?]
    [(absent) (not present?)]
    [else #t]))

(define (lifecycle-effect->data effect)
  (unless (lifecycle-effect? effect)
    (raise-argument-error 'lifecycle-effect->data "lifecycle-effect?" effect))
  (hasheq 'target (lifecycle-effect-target effect)
          'requires (lifecycle-effect-requires effect)
          'result (lifecycle-effect-result effect)
          'temporary? (lifecycle-effect-temporary? effect)
          'exact-endpoint? (lifecycle-effect-exact-endpoint? effect)))
