#lang racket/base
(require "private/prepare.rkt")
(provide prepare-slide! prepare-storyboard! prepared-slide? prepared-slide-clip? prepared-storyboard? prepared-duration)
(define (prepare-slide! source #:theme [theme #f] #:format [format #f] #:asset-base [base #f])
  (resolve-slide source #:theme theme #:format format #:effects? #t #:asset-base base))
(define (prepare-storyboard! source #:asset-base [base #f])
  (resolve-storyboard source #:effects? #t #:asset-base base))
