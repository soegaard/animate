#lang racket/base

;;;
;;; Preview Diagnostics and Trace
;;;

(require racket/file
         racket/list
         racket/path
         (only-in "geometry.rkt" finite-real?))

(provide (struct-out preview-diagnostic)
         (struct-out preview-trace)
         make-preview-trace
         preview-trace-record!
         preview-trace->datum
         preview-write-trace!)

;; A trace is append-only, with a bounded recent history. Each entry records
;; raw monotonic timing data rather than attempting to infer frame timing from
;; GUI callbacks.
(struct preview-diagnostic (kind milliseconds data) #:transparent)
(struct preview-trace (capacity entries) #:mutable #:transparent)

(define (make-preview-trace #:capacity [capacity 512])
  (unless (exact-positive-integer? capacity)
    (raise-argument-error 'make-preview-trace "exact-positive-integer?" capacity))
  (preview-trace capacity '()))

(define (preview-trace-record! trace kind milliseconds [data #hasheq()])
  (unless (preview-trace? trace)
    (raise-argument-error 'preview-trace-record! "preview-trace?" trace))
  (unless (symbol? kind)
    (raise-argument-error 'preview-trace-record! "symbol?" kind))
  (unless (and (finite-real? milliseconds) (not (negative? milliseconds)))
    (raise-argument-error 'preview-trace-record! "nonnegative finite real?" milliseconds))
  (unless (hash? data)
    (raise-argument-error 'preview-trace-record! "hash?" data))
  (define all
    (cons (preview-diagnostic kind milliseconds
                              (make-immutable-hash (hash->list data)))
          (preview-trace-entries trace)))
  (define next
    (take all (min (preview-trace-capacity trace) (length all))))
  (set-preview-trace-entries! trace next)
  (void))

(define (preview-trace->datum trace)
  (unless (preview-trace? trace)
    (raise-argument-error 'preview-trace->datum "preview-trace?" trace))
  (hasheq 'capacity (preview-trace-capacity trace)
          'events
          (for/list ([event (in-list (reverse (preview-trace-entries trace)))])
            (hasheq 'kind (preview-diagnostic-kind event)
                    'milliseconds (preview-diagnostic-milliseconds event)
                    'data (preview-diagnostic-data event)))))

;; Writes a machine-readable Racket datum; consumers can parse it without a
;; JSON dependency and bug reports retain exact symbol names and hash keys.
(define (preview-write-trace! trace path)
  (unless (path-string? path)
    (raise-argument-error 'preview-write-trace! "path-string?" path))
  (make-parent-directory* path)
  (call-with-output-file path #:exists 'truncate/replace
    (lambda (out)
      (write (preview-trace->datum trace) out)
      (newline out)))
  path)

(define (make-parent-directory* path)
  (define parent (path-only (if (path? path) path (string->path path))))
  (when parent (make-directory* parent)))
