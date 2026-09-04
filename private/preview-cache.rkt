#lang racket/base

;;;
;;; Byte-Bounded Preview Cache
;;;

;; The preview controller is the sole owner of a cache instance.  This module
;; therefore keeps mutation private to that actor while offering deterministic
;; LRU behavior that can be tested without GUI or renderer dependencies.

(require racket/list)

(provide preview-cache?
         make-preview-cache
         preview-cache-byte-limit
         preview-cache-byte-count
         preview-cache-count
         preview-cache-ref!
         preview-cache-set!
         preview-cache-clear!)

(struct cache-entry (value bytes touch)
  #:transparent)

(struct preview-cache (byte-limit entries byte-count next-touch)
  #:mutable
  #:transparent)

(define (make-preview-cache byte-limit)
  (unless (exact-positive-integer? byte-limit)
    (raise-argument-error 'make-preview-cache "exact-positive-integer?" byte-limit))
  (preview-cache byte-limit (make-hash) 0 0))

(define (preview-cache-count cache)
  (check-cache 'preview-cache-count cache)
  (hash-count (preview-cache-entries cache)))

(define (preview-cache-ref! cache key [missing #f])
  (check-cache 'preview-cache-ref! cache)
  (define entries (preview-cache-entries cache))
  (define entry (hash-ref entries key #f))
  (cond
    [entry
     (define touch (next-touch! cache))
     (hash-set! entries key
                (cache-entry (cache-entry-value entry)
                             (cache-entry-bytes entry)
                             touch))
     (cache-entry-value entry)]
    [else missing]))

(define (preview-cache-set! cache key value bytes)
  (check-cache 'preview-cache-set! cache)
  (unless (exact-nonnegative-integer? bytes)
    (raise-argument-error 'preview-cache-set! "exact-nonnegative-integer?" bytes))
  (define entries (preview-cache-entries cache))
  (define previous (hash-ref entries key #f))
  (when previous
    (set-preview-cache-byte-count!
     cache
     (- (preview-cache-byte-count cache) (cache-entry-bytes previous))))
  ;; An object larger than the complete budget is intentionally not retained.
  ;; It is still returned to the current preview request by its producer.
  (cond
    [(> bytes (preview-cache-byte-limit cache))
     (when previous (hash-remove! entries key))]
    [else
     (hash-set! entries key (cache-entry value bytes (next-touch! cache)))
     (set-preview-cache-byte-count!
      cache
      (+ (preview-cache-byte-count cache) bytes))
     (evict-to-limit! cache)])
  (void))

(define (preview-cache-clear! cache)
  (check-cache 'preview-cache-clear! cache)
  (hash-clear! (preview-cache-entries cache))
  (set-preview-cache-byte-count! cache 0)
  (void))

(define (next-touch! cache)
  (define next (add1 (preview-cache-next-touch cache)))
  (set-preview-cache-next-touch! cache next)
  next)

(define (evict-to-limit! cache)
  (let loop ()
    (when (> (preview-cache-byte-count cache) (preview-cache-byte-limit cache))
      (define oldest-key
        (for/fold ([oldest-key #f] [oldest-touch +inf.0]
                   #:result oldest-key)
                  ([(key entry) (in-hash (preview-cache-entries cache))])
          (if (< (cache-entry-touch entry) oldest-touch)
              (values key (cache-entry-touch entry))
              (values oldest-key oldest-touch))))
      (define entry (hash-ref (preview-cache-entries cache) oldest-key))
      (hash-remove! (preview-cache-entries cache) oldest-key)
      (set-preview-cache-byte-count!
       cache
       (- (preview-cache-byte-count cache) (cache-entry-bytes entry)))
      (loop))))

(define (check-cache who value)
  (unless (preview-cache? value)
    (raise-argument-error who "preview-cache?" value)))
