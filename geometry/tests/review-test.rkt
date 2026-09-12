#lang racket/base
(require rackunit "review-checks.rkt")
(module+ test
  (for ([group (in-list review-check-groups)])
    (test-case (car group) ((cdr group)))))
