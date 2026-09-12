#lang racket/base
(require rackunit "transform-label-checks.rkt")
(module+ test
  (for ([g transform-label-check-groups])
    (test-case (car g) ((cdr g)))))
