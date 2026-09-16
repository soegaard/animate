#lang racket/base
(require racket/list (only-in racket/math nan? infinite?) "data.rkt")
(provide slides-error finite-number? positive-number? nonnegative-number?
         check-id check-number check-enum immutable-copy unique! selector-path
         path-prefix? paths-overlap? hash-copy/immutable)

(define (slides-error code path message . details)
  (raise (exn:fail:slides
          (format "animate/slides: ~a~a" message
                  (if (null? path) "" (format " [~s]" path)))
          (current-continuation-marks) code path details)))
(define (finite-number? x) (and (real? x) (not (nan? x)) (not (infinite? x))))
(define (positive-number? x) (and (finite-number? x) (> x 0)))
(define (nonnegative-number? x) (and (finite-number? x) (>= x 0)))
(define (check-id who x)
  (unless (and (symbol? x) (symbol-interned? x)
               (positive? (string-length (symbol->string x))))
    (raise-argument-error who "nonempty interned symbol?" x)) x)
(define (check-number who x [positive? #f])
  (unless ((if positive? positive-number? nonnegative-number?) x)
    (raise-argument-error who (if positive? "positive finite real?" "nonnegative finite real?") x)) x)
(define (check-enum who x choices)
  (unless (memq x choices) (raise-argument-error who (format "one of ~s" choices) x)) x)
(define (unique! who xs)
  (define duplicate (check-duplicates xs))
  (when duplicate (slides-error 'duplicate-name (list who duplicate) "names must be unique")))
(define (hash-copy/immutable h)
  (unless (hash? h) (raise-argument-error 'hash-copy/immutable "hash?" h))
  (for/hash ([(k v) (in-hash h)]) (values k (immutable-copy v))))
(define (immutable-copy x)
  ;; Opaque content (Picts, native Visuals, plans, factories) is intentionally
  ;; retained. Its adapter owns its immutability and reconstruction contract.
  (cond [(string? x) (string->immutable-string x)]
        [(bytes? x) (bytes->immutable-bytes x)]
        [(hash? x) (hash-copy/immutable x)]
        [(list? x) (map immutable-copy x)]
        [(pair? x) (cons (immutable-copy (car x)) (immutable-copy (cdr x)))]
        [(vector? x) (vector->immutable-vector (vector-map/copy x))]
        [else x]))
(define (vector-map/copy x) (list->vector (map immutable-copy (vector->list x))))
(define (selector-path x)
  (define path (if (symbol? x) (list x) x))
  (unless (and (list? path) (pair? path) (andmap symbol? path))
    (raise-argument-error 'selector-path "symbol or nonempty list of symbols" x))
  (for-each (lambda (x) (check-id 'selector-path x)) path)
  path)
(define (path-prefix? a b)
  (and (<= (length a) (length b)) (equal? a (take b (length a)))))
(define (paths-overlap? a b) (or (path-prefix? a b) (path-prefix? b a)))
