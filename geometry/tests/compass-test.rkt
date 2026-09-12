#lang racket/base
(require rackunit "compass-checks.rkt")
(module+ test
  (for ([group compass-check-groups])
    (test-case (car group) ((cdr group)))))
