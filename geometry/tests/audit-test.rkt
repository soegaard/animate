#lang racket/base
(require rackunit "audit-checks.rkt")
(module+ test
  (for ([group audit-check-groups])
    (test-case (car group) ((cdr group)))))
