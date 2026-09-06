#lang racket/base

;;;
;;; Byte-Bounded Retained Geometry Cache
;;;

(require racket/list)

(provide (struct-out gl-geometry-entry)
         (struct-out gl-geometry-cache)
         make-gl-geometry-cache
         gl-geometry-cache-ensure!
         gl-geometry-cache-clear!
         gl-geometry-cache-statistics)

(struct gl-geometry-entry
  (key variant vao vertex-buffer index-buffer index-count byte-size last-used
       context-generation destroy)
  #:mutable
  #:transparent)

(struct gl-geometry-cache (capacity entries clock hits misses uploads evictions bytes)
  #:mutable
  #:transparent)

(define (make-gl-geometry-cache capacity)
  (unless (exact-positive-integer? capacity)
    (raise-argument-error 'make-gl-geometry-cache "exact-positive-integer?" capacity))
  (gl-geometry-cache capacity (make-hash) 0 0 0 0 0 0))

(define (cache-key key variant) (cons key variant))

(define (next-tick! cache)
  (define tick (add1 (gl-geometry-cache-clock cache)))
  (set-gl-geometry-cache-clock! cache tick)
  tick)

;; `construct` must return a fresh entry with byte-size and a destruction
;; closure.  Keeping it an argument allows fake-GL tests to cover failures and
;; eviction without a live driver.
(define (gl-geometry-cache-ensure! cache key variant construct)
  (unless (gl-geometry-cache? cache)
    (raise-argument-error 'gl-geometry-cache-ensure! "gl-geometry-cache?" cache))
  (unless (procedure? construct)
    (raise-argument-error 'gl-geometry-cache-ensure! "procedure?" construct))
  (define identifier (cache-key key variant))
  (define existing (hash-ref (gl-geometry-cache-entries cache) identifier #f))
  (cond [existing
         (set-gl-geometry-entry-last-used! existing (next-tick! cache))
         (set-gl-geometry-cache-hits! cache (add1 (gl-geometry-cache-hits cache)))
         (values existing #t)]
        [else
         (define entry (construct))
         (unless (gl-geometry-entry? entry)
           (raise-arguments-error 'gl-geometry-cache-ensure!
                                  "construct to return gl-geometry-entry?"
                                  "result" entry))
         (unless (and (equal? key (gl-geometry-entry-key entry))
                      (eq? variant (gl-geometry-entry-variant entry)))
           (raise-arguments-error 'gl-geometry-cache-ensure!
                                  "an entry matching its requested key and variant"
                                  "requested-key" key "requested-variant" variant
                                  "entry" entry))
         (set-gl-geometry-entry-last-used! entry (next-tick! cache))
         (evict-for! cache (gl-geometry-entry-byte-size entry))
         (hash-set! (gl-geometry-cache-entries cache) identifier entry)
         (set-gl-geometry-cache-bytes!
          cache (+ (gl-geometry-cache-bytes cache) (gl-geometry-entry-byte-size entry)))
         (set-gl-geometry-cache-misses! cache (add1 (gl-geometry-cache-misses cache)))
         (set-gl-geometry-cache-uploads! cache (add1 (gl-geometry-cache-uploads cache)))
         (values entry #f)]))

(define (evict-for! cache incoming-bytes)
  ;; A single geometry bigger than the stated budget remains usable, but every
  ;; inactive entry is removed first.  Returning no live entry is safer than
  ;; failing after a successful upload for a valid large surface.
  (let loop ()
    (when (and (positive? (hash-count (gl-geometry-cache-entries cache)))
               (> (+ (gl-geometry-cache-bytes cache) incoming-bytes)
                  (gl-geometry-cache-capacity cache)))
      (define oldest
        (argmin gl-geometry-entry-last-used
                (hash-values (gl-geometry-cache-entries cache))))
      ((gl-geometry-entry-destroy oldest))
      (hash-remove! (gl-geometry-cache-entries cache)
                    (cache-key (gl-geometry-entry-key oldest)
                               (gl-geometry-entry-variant oldest)))
      (set-gl-geometry-cache-bytes!
       cache (- (gl-geometry-cache-bytes cache) (gl-geometry-entry-byte-size oldest)))
      (set-gl-geometry-cache-evictions! cache (add1 (gl-geometry-cache-evictions cache)))
      (loop))))

(define (gl-geometry-cache-clear! cache)
  (unless (gl-geometry-cache? cache)
    (raise-argument-error 'gl-geometry-cache-clear! "gl-geometry-cache?" cache))
  (for ([entry (in-hash-values (gl-geometry-cache-entries cache))])
    ((gl-geometry-entry-destroy entry)))
  (hash-clear! (gl-geometry-cache-entries cache))
  (set-gl-geometry-cache-clock! cache 0)
  (set-gl-geometry-cache-hits! cache 0)
  (set-gl-geometry-cache-misses! cache 0)
  (set-gl-geometry-cache-uploads! cache 0)
  (set-gl-geometry-cache-evictions! cache 0)
  (set-gl-geometry-cache-bytes! cache 0)
  (void))

(define (gl-geometry-cache-statistics cache)
  (unless (gl-geometry-cache? cache)
    (raise-argument-error 'gl-geometry-cache-statistics "gl-geometry-cache?" cache))
  (hasheq 'entries (hash-count (gl-geometry-cache-entries cache))
          'bytes (gl-geometry-cache-bytes cache)
          'hits (gl-geometry-cache-hits cache)
          'misses (gl-geometry-cache-misses cache)
          'uploads (gl-geometry-cache-uploads cache)
          'evictions (gl-geometry-cache-evictions cache)))
