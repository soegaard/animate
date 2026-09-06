#lang racket/base

(require rackunit
         "../private/3d/opengl/geometry-cache.rkt")

(module+ test
  (define destroyed '())
  (define (entry key bytes)
    (gl-geometry-entry key 'smooth-indexed #f #f #f 3 bytes 0 0
                       (lambda () (set! destroyed (cons key destroyed)))))
  (define cache (make-gl-geometry-cache 20))
  (define-values (first first-hit?)
    (gl-geometry-cache-ensure! cache 'first 'smooth-indexed
                               (lambda () (entry 'first 10))))
  (check-false first-hit?)
  (define-values (same same-hit?)
    (gl-geometry-cache-ensure! cache 'first 'smooth-indexed
                               (lambda () (error 'test "must not construct on hit"))))
  (check-true same-hit?)
  (check-eq? first same)
  ;; Adding 15 bytes evicts the LRU 10-byte resource before the insertion.
  (call-with-values
   (lambda ()
     (gl-geometry-cache-ensure! cache 'second 'smooth-indexed
                                (lambda () (entry 'second 15))))
   (lambda _values (void)))
  (check-equal? destroyed '(first))
  (check-equal? (gl-geometry-cache-statistics cache)
                (hasheq 'entries 1 'bytes 15 'hits 1 'misses 2 'uploads 2 'evictions 1))
  (gl-geometry-cache-clear! cache)
  (check-equal? destroyed '(second first)))
