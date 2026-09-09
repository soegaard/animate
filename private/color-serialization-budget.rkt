#lang racket/base

;;;
;;; Bounded Color Serialization Accounting
;;;

;; A complete theme datum contains palette metadata as well as color
;; expressions. Keep the accounting in this dependency-free module so every
;; serializer can share one budget without introducing a palette/style/theme
;; require cycle.

(provide color-serialization-budget?
         make-color-serialization-budget
         color-serialization-budget-count-node!
         color-serialization-budget-count-atom!
         color-serialization-budget-count-datum!
         color-serialization-budget-remaining-nodes)

(struct color-serialization-budget
  (who maximum-nodes maximum-atom-bytes nodes)
  #:mutable
  #:transparent)

(define (make-color-serialization-budget who
                                         #:maximum-nodes [maximum-nodes 100000]
                                         #:maximum-atom-bytes [maximum-atom-bytes 65536])
  (unless (symbol? who)
    (raise-argument-error 'make-color-serialization-budget "symbol?" who))
  (unless (exact-positive-integer? maximum-nodes)
    (raise-argument-error 'make-color-serialization-budget
                          "exact-positive-integer? as #:maximum-nodes"
                          maximum-nodes))
  (unless (exact-positive-integer? maximum-atom-bytes)
    (raise-argument-error 'make-color-serialization-budget
                          "exact-positive-integer? as #:maximum-atom-bytes"
                          maximum-atom-bytes))
  (color-serialization-budget who maximum-nodes maximum-atom-bytes 0))

(define (check-budget caller budget)
  (unless (color-serialization-budget? budget)
    (raise-argument-error caller "color-serialization-budget?" budget)))

(define (color-serialization-budget-count-node! budget)
  (check-budget 'color-serialization-budget-count-node! budget)
  (define next (add1 (color-serialization-budget-nodes budget)))
  (set-color-serialization-budget-nodes! budget next)
  (when (> next (color-serialization-budget-maximum-nodes budget))
    (raise-arguments-error
     (color-serialization-budget-who budget)
     "a complete serialized color datum within the configured node budget"
     "maximum nodes" (color-serialization-budget-maximum-nodes budget)
     "serialized nodes" next)))

(define (color-serialization-budget-remaining-nodes budget)
  (check-budget 'color-serialization-budget-remaining-nodes budget)
  (max 0 (- (color-serialization-budget-maximum-nodes budget)
            (color-serialization-budget-nodes budget))))

(define (color-serialization-budget-count-atom! budget value)
  (check-budget 'color-serialization-budget-count-atom! budget)
  (color-serialization-budget-count-node! budget)
  (define byte-count (serialized-atom-byte-count value))
  (when (> byte-count (color-serialization-budget-maximum-atom-bytes budget))
    (raise-arguments-error
     (color-serialization-budget-who budget)
     "a serialized color atom within the configured byte budget"
     "maximum atom bytes" (color-serialization-budget-maximum-atom-bytes budget)
     "atom bytes" byte-count)))

;; count-datum! accounts for the complete readable tree, not merely expression
;; nodes. Its callers pass only serializer-owned acyclic list data. Counting a
;; shared semantic value each time is intentional: `write` expands sharing.
(define (color-serialization-budget-count-datum! budget datum)
  (check-budget 'color-serialization-budget-count-datum! budget)
  (let loop ([pending (list datum)])
    (cond [(null? pending) (void)]
          [else
           (define value (car pending))
           (cond [(pair? value)
                  (color-serialization-budget-count-node! budget)
                  (loop (cons (car value) (cons (cdr value) (cdr pending))))]
                 [else
                  (color-serialization-budget-count-atom! budget value)
                  (loop (cdr pending))])])))

(define (serialized-atom-byte-count value)
  (cond [(string? value) (bytes-length (string->bytes/utf-8 value))]
        [(bytes? value) (bytes-length value)]
        [(symbol? value) (bytes-length (string->bytes/utf-8 (symbol->string value)))]
        [(keyword? value) (bytes-length (string->bytes/utf-8 (keyword->string value)))]
        [(char? value) (bytes-length (string->bytes/utf-8 (string value)))]
        [(number? value) (string-length (number->string value))]
        [(boolean? value) 1]
        [(null? value) 1]
        [else 1]))
