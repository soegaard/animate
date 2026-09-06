#lang racket/base

;;;
;;; Bounded Camera-Independent Compilation Cache
;;;

;; Keeps pure compiled views outside author values.  An adapter-local weak
;; content identity survives camera-only updates without becoming a field of
;; the transparent immutable `view3d`, so an orbit rebuilds only frame
;; preparation and never rehashes/lower geometry.

(require "compiled-view3d.rkt"
         "view3d-visual.rkt")

(provide (struct-out compiled-view3d-cache-statistics-value)
         compiled-view3d-cache?
         make-compiled-view3d-cache
         compile-view3d/cached
         compiled-view3d-cache-clear!
         compiled-view3d-cache-statistics
         current-compiled-view3d-cache)

(struct compiled-view3d-cache-statistics-value (hits misses entries) #:transparent)
(struct compiled-view3d-cache (entries hits misses) #:mutable #:transparent)

; make-compiled-view3d-cache : -> compiled-view3d-cache?
;; Creates a weak cache suitable for one render or preview worker.
(define (make-compiled-view3d-cache)
  (compiled-view3d-cache (make-weak-hasheq) 0 0))

(define current-compiled-view3d-cache
  (make-parameter (make-compiled-view3d-cache)))

; compile-view3d/cached : view3d? [compiled-view3d-cache?] -> compiled-view3d?
;; Compiles once for unchanged spatial content regardless of camera movement.
(define (compile-view3d/cached view [cache (current-compiled-view3d-cache)])
  (unless (view3d? view)
    (raise-argument-error 'compile-view3d/cached "view3d?" view))
  (unless (compiled-view3d-cache? cache)
    (raise-argument-error 'compile-view3d/cached "compiled-view3d-cache?" cache))
  (define key (view3d-content-key view))
  (define found (hash-ref (compiled-view3d-cache-entries cache) key #f))
  (cond [found
         (set-compiled-view3d-cache-hits! cache (add1 (compiled-view3d-cache-hits cache)))
         found]
        [else
         (define compiled (compile-view3d view))
         (hash-set! (compiled-view3d-cache-entries cache) key compiled)
         (set-compiled-view3d-cache-misses! cache (add1 (compiled-view3d-cache-misses cache)))
         compiled]))

; compiled-view3d-cache-clear! : compiled-view3d-cache? -> void?
;; Releases cache reachability without modifying any immutable scene value.
(define (compiled-view3d-cache-clear! cache)
  (unless (compiled-view3d-cache? cache)
    (raise-argument-error 'compiled-view3d-cache-clear! "compiled-view3d-cache?" cache))
  (hash-clear! (compiled-view3d-cache-entries cache))
  (set-compiled-view3d-cache-hits! cache 0)
  (set-compiled-view3d-cache-misses! cache 0)
  (void))

; compiled-view3d-cache-statistics : compiled-view3d-cache? -> compiled-view3d-cache-statistics-value?
;; Returns an immutable observation of cache reuse.
(define (compiled-view3d-cache-statistics cache)
  (unless (compiled-view3d-cache? cache)
    (raise-argument-error 'compiled-view3d-cache-statistics "compiled-view3d-cache?" cache))
  (compiled-view3d-cache-statistics-value
   (compiled-view3d-cache-hits cache)
   (compiled-view3d-cache-misses cache)
   (hash-count (compiled-view3d-cache-entries cache))))
