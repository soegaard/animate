#lang racket/base
(require rackunit "example-refinement-checks.rkt")
(module+ test
  (for ([group example-refinement-check-groups])
    (test-case (car group) ((cdr group)))))
