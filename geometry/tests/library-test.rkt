#lang racket/base
(require rackunit "library-checks.rkt")
(module+ test
  (for ([group (in-list library-check-groups)])
    (test-case (car group) ((cdr group)))))
