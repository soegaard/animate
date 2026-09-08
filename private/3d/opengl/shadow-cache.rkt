#lang racket/base

;;; Bounded LRU ownership for semantic OpenGL shadow maps

(provide (struct-out gl-shadow-cache-entry)
         (struct-out gl-shadow-cache)
         make-gl-shadow-cache
         gl-shadow-cache-ensure/current!
         gl-shadow-cache-clear/current!
         gl-shadow-cache-statistics)

(struct gl-shadow-cache-entry (key target byte-size last-used) #:transparent)
(struct gl-shadow-cache (entries allocations max-bytes bytes tick) #:mutable #:transparent)

(define (make-gl-shadow-cache #:max-bytes [max-bytes (* 64 1024 1024)])
  (unless (exact-positive-integer? max-bytes)
    (raise-argument-error 'make-gl-shadow-cache "exact-positive-integer?" max-bytes))
  (gl-shadow-cache (make-hash) 0 max-bytes 0 0))

;; The callbacks run with the caller's GL context already current. Keeping the
;; cache free of GL imports permits focused lifetime tests with fake targets.
(define (gl-shadow-cache-ensure/current! cache key byte-size make-target destroy-target)
  (unless (gl-shadow-cache? cache)
    (raise-argument-error 'gl-shadow-cache-ensure/current! "gl-shadow-cache?" cache))
  (unless (exact-positive-integer? byte-size)
    (raise-argument-error 'gl-shadow-cache-ensure/current! "exact-positive-integer?" byte-size))
  (unless (and (procedure? make-target) (procedure? destroy-target))
    (raise-argument-error 'gl-shadow-cache-ensure/current! "target creation and destruction procedures"
                          (list make-target destroy-target)))
  (define existing (hash-ref (gl-shadow-cache-entries cache) key #f))
  (cond [existing
         (set-gl-shadow-cache-tick! cache (add1 (gl-shadow-cache-tick cache)))
         (define touched
           (struct-copy gl-shadow-cache-entry existing
                        [last-used (gl-shadow-cache-tick cache)]))
         (hash-set! (gl-shadow-cache-entries cache) key touched)
         (values touched #t)]
        [else
         (define target (make-target))
         (set-gl-shadow-cache-tick! cache (add1 (gl-shadow-cache-tick cache)))
         (define created
           (gl-shadow-cache-entry key target byte-size (gl-shadow-cache-tick cache)))
         (hash-set! (gl-shadow-cache-entries cache) key created)
         (set-gl-shadow-cache-allocations! cache (add1 (gl-shadow-cache-allocations cache)))
         (set-gl-shadow-cache-bytes! cache (+ (gl-shadow-cache-bytes cache) byte-size))
         (evict/current! cache key destroy-target)
         (values created #f)]))

(define (gl-shadow-cache-clear/current! cache destroy-target)
  (unless (gl-shadow-cache? cache)
    (raise-argument-error 'gl-shadow-cache-clear/current! "gl-shadow-cache?" cache))
  (unless (procedure? destroy-target)
    (raise-argument-error 'gl-shadow-cache-clear/current! "procedure?" destroy-target))
  (for ([entry (in-hash-values (gl-shadow-cache-entries cache))])
    (destroy-target (gl-shadow-cache-entry-target entry)))
  (hash-clear! (gl-shadow-cache-entries cache))
  (set-gl-shadow-cache-bytes! cache 0)
  (void))

(define (gl-shadow-cache-statistics cache)
  (unless (gl-shadow-cache? cache)
    (raise-argument-error 'gl-shadow-cache-statistics "gl-shadow-cache?" cache))
  (hasheq 'entries (hash-count (gl-shadow-cache-entries cache))
          'allocations (gl-shadow-cache-allocations cache)
          'bytes (gl-shadow-cache-bytes cache)
          'max-bytes (gl-shadow-cache-max-bytes cache)))

(define (evict/current! cache protected-key destroy-target)
  (let loop ()
    (when (and (> (gl-shadow-cache-bytes cache) (gl-shadow-cache-max-bytes cache))
               (> (hash-count (gl-shadow-cache-entries cache)) 1))
      (define candidate
        (for/fold ([best #f]) ([(key entry) (in-hash (gl-shadow-cache-entries cache))])
          (cond [(equal? key protected-key) best]
                [(not best) (cons key entry)]
                [(< (gl-shadow-cache-entry-last-used entry)
                    (gl-shadow-cache-entry-last-used (cdr best)))
                 (cons key entry)]
                [else best])))
      (when candidate
        (destroy-target (gl-shadow-cache-entry-target (cdr candidate)))
        (hash-remove! (gl-shadow-cache-entries cache) (car candidate))
        (set-gl-shadow-cache-bytes!
         cache (- (gl-shadow-cache-bytes cache)
                  (gl-shadow-cache-entry-byte-size (cdr candidate))))
        (loop)))))
