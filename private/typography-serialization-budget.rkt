#lang racket/base

;; Bounded accounting for complete portable typography data.  It is separate
;; from color serialization so a typography datum can count its wrapper,
;; metadata, styles, treatments, paints, and nested color data as one tree.

(provide typography-serialization-budget?
         make-typography-serialization-budget
         typography-serialization-budget-reserve!
         typography-serialization-budget-count-datum!)

(struct typography-serialization-budget (who maximum-nodes maximum-atom-bytes nodes)
  #:mutable
  #:transparent)

(define (make-typography-serialization-budget who
                                               #:maximum-nodes [maximum-nodes 100000]
                                               #:maximum-atom-bytes [maximum-atom-bytes 65536])
  (unless (symbol? who)
    (raise-argument-error 'make-typography-serialization-budget "symbol?" who))
  (unless (exact-positive-integer? maximum-nodes)
    (raise-argument-error 'make-typography-serialization-budget
                          "exact-positive-integer? as #:maximum-nodes" maximum-nodes))
  (unless (exact-positive-integer? maximum-atom-bytes)
    (raise-argument-error 'make-typography-serialization-budget
                          "exact-positive-integer? as #:maximum-atom-bytes" maximum-atom-bytes))
  (typography-serialization-budget who maximum-nodes maximum-atom-bytes 0))

;; Reserve known output nodes before a serializer allocates a large derived
;; list.  This is deliberately separate from `count-datum!`: callers use it
;; only for a source-structure preflight, then verify the completed datum with
;; a fresh complete-tree accounting pass.
(define (typography-serialization-budget-reserve! budget amount)
  (unless (typography-serialization-budget? budget)
    (raise-argument-error 'typography-serialization-budget-reserve!
                          "typography-serialization-budget?" budget))
  (unless (exact-nonnegative-integer? amount)
    (raise-argument-error 'typography-serialization-budget-reserve!
                          "exact-nonnegative-integer?" amount))
  (define next (+ (typography-serialization-budget-nodes budget) amount))
  (set-typography-serialization-budget-nodes! budget next)
  (when (> next (typography-serialization-budget-maximum-nodes budget))
    (raise-arguments-error
     (typography-serialization-budget-who budget)
     "a complete serialized typography datum within the configured node budget"
     "maximum nodes" (typography-serialization-budget-maximum-nodes budget)
     "serialized nodes" next)))

(define (typography-serialization-budget-count-datum! budget datum)
  (unless (typography-serialization-budget? budget)
    (raise-argument-error 'typography-serialization-budget-count-datum!
                          "typography-serialization-budget?" budget))
  ;; Count every repeated occurrence because `write` expands sharing.  A
  ;; separately retained ancestor set still rejects a malformed cyclic datum
  ;; without treating ordinary shared immutable data as a cycle.
  (let loop ([pending (list (cons datum (hasheq)))])
    (cond
      [(null? pending) (void)]
      [else
       (define work (car pending))
       (define value (car work))
       (define ancestors (cdr work))
       (if (pair? value)
           (let ()
             (when (hash-has-key? ancestors value)
               (raise-arguments-error
                (typography-serialization-budget-who budget)
                "an acyclic complete typography datum"
                "cyclic value" value))
             (count-node! budget)
             (define next-ancestors (hash-set ancestors value #t))
             (loop (cons (cons (car value) next-ancestors)
                         (cons (cons (cdr value) next-ancestors)
                               (cdr pending)))))
           (begin
             (count-atom! budget value)
             (loop (cdr pending))))])))

(define (count-node! budget)
  (define next (add1 (typography-serialization-budget-nodes budget)))
  (set-typography-serialization-budget-nodes! budget next)
  (when (> next (typography-serialization-budget-maximum-nodes budget))
    (raise-arguments-error
     (typography-serialization-budget-who budget)
     "a complete serialized typography datum within the configured node budget"
     "maximum nodes" (typography-serialization-budget-maximum-nodes budget)
     "serialized nodes" next)))

(define (count-atom! budget value)
  (count-node! budget)
  (define byte-count (atom-byte-count value))
  (when (> byte-count (typography-serialization-budget-maximum-atom-bytes budget))
    (raise-arguments-error
     (typography-serialization-budget-who budget)
     "a serialized typography atom within the configured byte budget"
     "maximum atom bytes" (typography-serialization-budget-maximum-atom-bytes budget)
     "atom bytes" byte-count)))

(define (atom-byte-count value)
  (cond [(string? value) (bytes-length (string->bytes/utf-8 value))]
        [(bytes? value) (bytes-length value)]
        [(symbol? value) (bytes-length (string->bytes/utf-8 (symbol->string value)))]
        [(keyword? value) (bytes-length (string->bytes/utf-8 (keyword->string value)))]
        [(char? value) (bytes-length (string->bytes/utf-8 (string value)))]
        [(number? value) (string-length (number->string value))]
        [(boolean? value) 1]
        [(null? value) 1]
        [else 1]))
