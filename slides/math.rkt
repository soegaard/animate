#lang racket/base
(require (only-in "../math/main.rkt" presentation-plan?)
         "private/data.rkt" "private/check.rkt")
(provide math-content)
(define (math-content plan #:poster [poster 'end] #:fit [fit 'contain])
  (unless (presentation-plan? plan) (raise-argument-error 'math-content "presentation-plan?" plan))
  (check-enum 'math-content fit '(contain natural))
  (content-value 'math plan (hash 'poster poster 'fit fit)))
