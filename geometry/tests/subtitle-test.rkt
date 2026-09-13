#lang racket/base
(require rackunit "subtitle-checks.rkt")
(module+ test
  (for ([g (in-list subtitle-check-groups)])
    (test-case (car g) ((cdr g)))))
