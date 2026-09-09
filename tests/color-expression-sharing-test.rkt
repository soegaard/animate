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
             (lambda () (color-spec->datum expansion)))

  ;; The same shared subtree is legal at its own root depth, but adding one
  ;; parent makes its deepest descendant exceed the theme limit.  This used to
  ;; slip through after the shallow role had marked the subtree "visited".
  (define boundary-subtree
    (for/fold ([spec theme-accent]) ([index (in-range 64)])
      (color-opacity spec 1/2)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (color-theme #:id 'shared-depth-boundary #:extends animate-light-theme
                  #:roles (hash 'a-shallow boundary-subtree
                                'z-deep (color-opacity boundary-subtree 1/2)))))

  ;; Per-expression output remains below 100,000 nodes, but the aggregate
  ;; theme datum must share that same configured serialization budget.
  (define serializable-subtree
    (for/fold ([spec theme-accent]) ([index (in-range 50)])
      (color-opacity spec 1/2)))
  (define many-roots
    (for/hash ([index (in-range 2000)])
      (values (string->symbol (format "bulk-~a" index)) serializable-subtree)))
  (define oversized-theme
    (color-theme #:id 'aggregate-serialization #:extends animate-light-theme
                 #:roles many-roots))
  (check-exn exn:fail:contract?
             (lambda () (theme->datum oversized-theme))))
