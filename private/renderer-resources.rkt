#lang racket/base

;;;
;;; Renderer Resource Caches
;;;

;; A bounded, thread-safe cache for adapter-owned resources such as frozen text
;; rasters, LaTeX appearances, and loaded bitmap sources. Cached data never
;; appears in a scene model or influences timeline sampling.

(require racket/list)

(provide make-renderer-resource-cache
         renderer-resource-cache?
         renderer-resource-cache-ref!
         renderer-resource-cache-clear!
         renderer-resource-cache-statistics
         (struct-out renderer-resource-cache-stats))

(struct renderer-resource-entry (value bytes stamp)
  #:transparent)

(struct renderer-resource-cache
  (table max-entries max-bytes byte-count clock hits misses evictions lock)
  #:mutable)

(struct renderer-resource-cache-stats
  (entries bytes hits misses evictions)
  #:transparent)

; make-renderer-resource-cache : [#:max-entries exact-positive-integer?]
;                                [#:max-bytes (or/c false/c exact-positive-integer?)]
;                                -> renderer-resource-cache?
(define (make-renderer-resource-cache #:max-entries [max-entries 256]
                                      #:max-bytes [max-bytes #f])
  (unless (exact-positive-integer? max-entries)
    (raise-argument-error
     'make-renderer-resource-cache
     "exact-positive-integer?"
     max-entries))
  (unless (or (not max-bytes)
              (exact-positive-integer? max-bytes))
    (raise-argument-error
     'make-renderer-resource-cache
     "(or/c false/c exact-positive-integer?)"
     max-bytes))
  (renderer-resource-cache (make-hash)
                           max-entries
                           max-bytes
                           0
                           0
                           0
                           0
                           0
                           (make-semaphore 1)))

; renderer-resource-cache-ref! : renderer-resource-cache? any/c
;                                 (-> (values any/c exact-nonnegative-integer?))
;                                 -> any/c
;; Returns one cached resource, loading it exactly once while the cache lock is
;; held when absent. The loader's byte estimate controls optional cache bounds.
(define (renderer-resource-cache-ref! cache key load)
  (unless (renderer-resource-cache? cache)
    (raise-argument-error 'renderer-resource-cache-ref!
                          "renderer-resource-cache?"
                          cache))
  (unless (and (procedure? load)
               (procedure-arity-includes? load 0))
    (raise-argument-error
     'renderer-resource-cache-ref!
     "procedure accepting zero arguments"
     load))
  (call-with-semaphore
   (renderer-resource-cache-lock cache)
   (lambda ()
     (define table (renderer-resource-cache-table cache))
     (cond
       [(hash-has-key? table key)
        (define entry (hash-ref table key))
        (set-renderer-resource-cache-hits!
         cache (add1 (renderer-resource-cache-hits cache)))
        (define stamp (next-resource-stamp! cache))
        (hash-set! table key
                   (struct-copy renderer-resource-entry entry [stamp stamp]))
        (renderer-resource-entry-value entry)]
       [else
        (set-renderer-resource-cache-misses!
         cache (add1 (renderer-resource-cache-misses cache)))
        (define-values (value bytes) (load))
        (unless (exact-nonnegative-integer? bytes)
          (raise-arguments-error
           'renderer-resource-cache-ref!
           "the resource loader must return an exact nonnegative byte estimate"
           "key" key
           "bytes" bytes))
        (when (resource-cacheable? cache bytes)
          (make-resource-room! cache bytes)
          (hash-set! table
                     key
                     (renderer-resource-entry value
                                              bytes
                                              (next-resource-stamp! cache)))
          (set-renderer-resource-cache-byte-count!
           cache
           (+ (renderer-resource-cache-byte-count cache) bytes)))
        value]))))

; renderer-resource-cache-clear! : renderer-resource-cache? -> void?
;; Removes resources while retaining cumulative diagnostic counters.
(define (renderer-resource-cache-clear! cache)
  (unless (renderer-resource-cache? cache)
    (raise-argument-error 'renderer-resource-cache-clear!
                          "renderer-resource-cache?"
                          cache))
  (call-with-semaphore
   (renderer-resource-cache-lock cache)
   (lambda ()
     (hash-clear! (renderer-resource-cache-table cache))
     (set-renderer-resource-cache-byte-count! cache 0))))

; renderer-resource-cache-statistics : renderer-resource-cache?
;                                      -> renderer-resource-cache-stats?
(define (renderer-resource-cache-statistics cache)
  (unless (renderer-resource-cache? cache)
    (raise-argument-error 'renderer-resource-cache-statistics
                          "renderer-resource-cache?"
                          cache))
  (call-with-semaphore
   (renderer-resource-cache-lock cache)
   (lambda ()
     (renderer-resource-cache-stats
      (hash-count (renderer-resource-cache-table cache))
      (renderer-resource-cache-byte-count cache)
      (renderer-resource-cache-hits cache)
      (renderer-resource-cache-misses cache)
      (renderer-resource-cache-evictions cache)))))

; resource-cacheable? : renderer-resource-cache? exact-nonnegative-integer?
;;                       -> boolean?
(define (resource-cacheable? cache bytes)
  (or (not (renderer-resource-cache-max-bytes cache))
      (<= bytes (renderer-resource-cache-max-bytes cache))))

; make-resource-room! : renderer-resource-cache? exact-nonnegative-integer?
;;                      -> void?
;; Evicts least-recently-used entries until another resource fits.
(define (make-resource-room! cache incoming-bytes)
  (let loop ()
    (when (or (>= (hash-count (renderer-resource-cache-table cache))
                  (renderer-resource-cache-max-entries cache))
              (and (renderer-resource-cache-max-bytes cache)
                   (> (+ (renderer-resource-cache-byte-count cache)
                         incoming-bytes)
                      (renderer-resource-cache-max-bytes cache))))
      (define oldest-key
        (least-recent-resource-key (renderer-resource-cache-table cache)))
      (define oldest
        (hash-ref (renderer-resource-cache-table cache) oldest-key))
      (hash-remove! (renderer-resource-cache-table cache) oldest-key)
      (set-renderer-resource-cache-byte-count!
       cache
       (- (renderer-resource-cache-byte-count cache)
          (renderer-resource-entry-bytes oldest)))
      (set-renderer-resource-cache-evictions!
       cache
       (add1 (renderer-resource-cache-evictions cache)))
      (loop))))

; least-recent-resource-key : hash? -> any/c
(define (least-recent-resource-key table)
  (define keys (hash-keys table))
  (unless (pair? keys)
    (error 'least-recent-resource-key "expected a nonempty resource cache"))
  (for/fold ([oldest-key (car keys)])
            ([key (in-list (cdr keys))])
    (if (< (renderer-resource-entry-stamp (hash-ref table key))
           (renderer-resource-entry-stamp (hash-ref table oldest-key)))
        key
        oldest-key)))

; next-resource-stamp! : renderer-resource-cache? -> exact-positive-integer?
(define (next-resource-stamp! cache)
  (define next (add1 (renderer-resource-cache-clock cache)))
  (set-renderer-resource-cache-clock! cache next)
  next)
