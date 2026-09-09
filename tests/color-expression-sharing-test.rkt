#lang racket/base

;;; Shared colour-expression graphs have bounded distinct-node traversal

(require rackunit
         "../colors.rkt")

(module+ test
  ;; Each step retains the preceding expression twice: directly and beneath
  ;; opacity. This is linear in distinct nodes but would cause exponential
  ;; repeated recursive work without operation-local identity memoization.
  (define shared
    (for/fold ([spec theme-accent]) ([index (in-range 32)])
      (color-mix spec (color-opacity spec 1/2) 1/2)))
  (define themed
    (color-theme #:id 'shared-expression #:extends animate-light-theme
                 #:roles (hash 'shared shared)))
  (check-true (rgba-color? (resolve-color (role-color 'shared) themed)))
  ;; The same immutable node can be reused by multiple roles without changing
  ;; their numerical result or introducing a mutable global cache.
  (define reused
    (color-theme #:id 'reused-expression #:extends animate-light-theme
                 #:roles (hash 'left shared 'right shared)))
  (check-equal? (resolve-color (role-color 'left) reused)
                (resolve-color (role-color 'right) reused))
  ;; The readable tree schema cannot encode sharing. Export therefore has a
  ;; node budget rather than expanding one compact DAG without bound.
  (define expansion
    (for/fold ([spec theme-accent]) ([index (in-range 18)])
      (color-mix spec (color-opacity spec 1/2) 1/2)))
  (check-exn exn:fail?
             (lambda () (color-spec->datum expansion))))
