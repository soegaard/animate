#lang racket/base

;; Cache only within one explicit resolution. No frame or worker can mutate a
;; retained plan; no global cache can accidentally reuse a different appearance.
(provide call-with-preparation-session preparation-ref!)
(define current-preparations (make-parameter #f))
(define (call-with-preparation-session thunk)
  (if (current-preparations)
      (thunk)
      (parameterize ([current-preparations (make-hash)]) (thunk))))
(define (preparation-ref! key make-value)
  (if (current-preparations)
      (hash-ref! (current-preparations) key make-value)
      (make-value)))
