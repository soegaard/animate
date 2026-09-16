#lang racket/base
(require (only-in "../geometry/core.rkt" geometry-program? geometry-timeline?)
         "private/data.rkt" "private/check.rkt")
(provide geometry-content)
(define (geometry-content program-or-timeline #:poster [poster 'end] #:fit [fit 'contain])
  (unless (or (geometry-program? program-or-timeline) (geometry-timeline? program-or-timeline))
    (raise-argument-error 'geometry-content "geometry program or timeline" program-or-timeline))
  (check-enum 'geometry-content fit '(contain natural))
  (content-value 'geometry program-or-timeline (hash 'poster poster 'fit fit)))
