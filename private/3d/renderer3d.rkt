#lang racket/base

;;;
;;; Backend-Neutral Spatial Renderer Protocol
;;;

;; The spatial tree is immutable author data.  This module is deliberately the
;; opposite: it describes effectful renderer instances and their replaceable
;; retained preparations.  A backend may cache GPU objects, software-space
;; triangles, or an optional adapter's native resources here, but never inside
;; a mesh3d, material3d, or view3d value.

(require racket/class
         racket/draw
         racket/generic
         "../preview-cancellation.rkt"
         "raster-target3d.rkt"
         "software-renderer3d.rkt"
         "view3d-visual.rkt")

(provide gen:renderer3d
         renderer3d?
         renderer3d-id
         renderer3d-capabilities
         renderer3d-fingerprint
         renderer3d-prepare
         renderer3d-render
         renderer3d-release
         (struct-out renderer3d-capability-set)
         (struct-out render3d-request)
         (struct-out renderer3d-render-result)
         renderer3d-render-result->bitmap
         software-renderer3d
         software-renderer3d?
         retained-software-renderer3d
         retained-software-renderer3d?
         retained-software-renderer3d-cache-hits
         retained-software-renderer3d-cache-misses
         retained-software-renderer3d-cache-size
         default-software-renderer3d
         current-view3d-renderer3d)

;; The capability value belongs to the backend protocol rather than a project
;; declaration.  Project validation re-exports this exact record as its nested
;; `three-dimensional` capability, avoiding parallel claims about what a
;; renderer can actually do.
(struct renderer3d-capability-set
  (wireframe opaque-triangles perspective orthographic depth-buffer flat-shading
             smooth-shading transparency clipping-planes)
  #:transparent
  #:guard
  (lambda (wireframe opaque-triangles perspective orthographic depth-buffer
                    flat-shading smooth-shading transparency clipping-planes who)
    (for ([value (in-list (list wireframe opaque-triangles perspective orthographic
                                depth-buffer flat-shading smooth-shading
                                transparency clipping-planes))])
      (unless (boolean? value)
        (raise-argument-error who "boolean?" value)))
    (values wireframe opaque-triangles perspective orthographic depth-buffer
            flat-shading smooth-shading transparency clipping-planes)))

;; The request is ephemeral backend input, never part of a semantic scene.  A
;; caller may pass the preview cancellation token so both preparing and
;; rasterizing remain cooperatively interruptible.
(struct render3d-request (view width height cancellation-token)
  #:transparent
  #:guard
  (lambda (view width height cancellation-token who)
    (unless (view3d? view)
      (raise-argument-error who "view3d?" view))
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer?" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer?" height))
    (unless (or (not cancellation-token) (cancellation-token? cancellation-token))
      (raise-argument-error who "(or/c #f cancellation-token?)" cancellation-token))
    (values view width height cancellation-token)))

;; Every backend returns copied ARGB bytes, not a backend target.  This keeps
;; the view3d Pict boundary backend-neutral and lets `renderer3d-release` drop
;; all native resources without invalidating an already-produced frame.
(struct renderer3d-render-result (width height argb-bytes diagnostics)
  #:transparent
  #:guard
  (lambda (width height argb-bytes diagnostics who)
    (unless (exact-positive-integer? width)
      (raise-argument-error who "exact-positive-integer?" width))
    (unless (exact-positive-integer? height)
      (raise-argument-error who "exact-positive-integer?" height))
    (unless (and (bytes? argb-bytes) (= (bytes-length argb-bytes) (* 4 width height)))
      (raise-argument-error who "ARGB bytes for the declared dimensions" argb-bytes))
    (values width height (bytes->immutable-bytes argb-bytes) diagnostics)))

;; The protocol separates fingerprint/prepare/render/release so an accelerated
;; backend can retain native geometry while a new request supplies a new camera
;; or frame target.  The reference implementation below uses the same contract
;; and so is the conformance oracle rather than a special rendering path.
(define-generics renderer3d
  (renderer3d-id renderer3d)
  (renderer3d-capabilities renderer3d)
  (renderer3d-fingerprint renderer3d request)
  (renderer3d-prepare renderer3d request)
  (renderer3d-render renderer3d preparation request)
  (renderer3d-release renderer3d))

(define reference-capabilities
  (renderer3d-capability-set #f #t #t #t #t #t #t #t #t))

(define (request-fingerprint request)
  ;; Structural equality is intentional.  It has no semantic authority: it is
  ;; merely a cache key for immutable input values.  Procedural derived shapes
  ;; naturally fall back to identity equality and simply miss the cache.
  (vector 'animate-software-renderer3d-v1
          (render3d-request-view request)
          (render3d-request-width request)
          (render3d-request-height request)))

(define (prepare-reference request)
  (prepare-view3d-opaque
   (render3d-request-view request)
   (render3d-request-width request)
   (render3d-request-height request)
   #:cancellation-token (render3d-request-cancellation-token request)))

(define (render-reference preparation request)
  (define rendered
    (render-prepared-view3d-opaque
     preparation
     #:cancellation-token (render3d-request-cancellation-token request)))
  (define target (software-render-result-target rendered))
  (renderer3d-render-result
   (raster-target3d-width target)
   (raster-target3d-height target)
   (raster-target3d->argb-bytes target)
   (software-render-result-diagnostics rendered)))

;; A stateless instance is useful for strict conformance tests and for callers
;; that explicitly want no retained resources.
(struct software-renderer3d-value ()
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id _self) 'software-reference)
   (define (renderer3d-capabilities _self) reference-capabilities)
   (define (renderer3d-fingerprint _self request) (request-fingerprint request))
   (define (renderer3d-prepare _self request) (prepare-reference request))
   (define (renderer3d-render _self preparation request)
     (render-reference preparation request))
   (define (renderer3d-release _self) (void))])

(define (software-renderer3d)
  (software-renderer3d-value))

(define software-renderer3d? software-renderer3d-value?)

;; Cache entries contain only prepared camera-space triangles and never a
;; mutable raster target.  The bounded least-recently-used policy makes reuse
;; predictable without allowing a long-running preview to retain an unbounded
;; number of independent sampled scenes.
(struct retained-software-entry (preparation last-used) #:mutable #:transparent)

(struct retained-software-renderer3d-value
  (capacity entries clock hits misses lock)
  #:mutable
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id _self) 'retained-software-reference)
   (define (renderer3d-capabilities _self) reference-capabilities)
   (define (renderer3d-fingerprint _self request) (request-fingerprint request))
   (define (renderer3d-prepare self request)
     ;; Preview and PNG workers can share the default backend.  Hold the small
     ;; retained-cache transaction as one critical section, including a miss's
     ;; preparation, so two workers cannot concurrently populate the same key
     ;; with mutable hash-table updates.
     (call-with-semaphore
      (retained-software-renderer3d-value-lock self)
      (lambda ()
        (define key (renderer3d-fingerprint self request))
        (define tick (add1 (retained-software-renderer3d-value-clock self)))
        (set-retained-software-renderer3d-value-clock! self tick)
        (define existing
          (hash-ref (retained-software-renderer3d-value-entries self) key #f))
        (cond
          [existing
           (set-retained-software-entry-last-used! existing tick)
           (set-retained-software-renderer3d-value-hits!
            self (add1 (retained-software-renderer3d-value-hits self)))
           (retained-software-entry-preparation existing)]
          [else
           (define preparation (prepare-reference request))
           (define entries (retained-software-renderer3d-value-entries self))
           (when (>= (hash-count entries)
                     (retained-software-renderer3d-value-capacity self))
             (define-values (oldest-key _oldest-tick)
               (for/fold ([oldest-key #f] [oldest-tick +inf.0])
                         ([(candidate-key entry) (in-hash entries)])
                 (if (< (retained-software-entry-last-used entry) oldest-tick)
                     (values candidate-key (retained-software-entry-last-used entry))
                     (values oldest-key oldest-tick))))
             (when oldest-key (hash-remove! entries oldest-key)))
           (hash-set! entries key (retained-software-entry preparation tick))
           (set-retained-software-renderer3d-value-misses!
            self (add1 (retained-software-renderer3d-value-misses self)))
           preparation]))))
   (define (renderer3d-render _self preparation request)
     (render-reference preparation request))
   (define (renderer3d-release self)
     (call-with-semaphore
      (retained-software-renderer3d-value-lock self)
      (lambda ()
        (hash-clear! (retained-software-renderer3d-value-entries self))
        (set-retained-software-renderer3d-value-clock! self 0)
        (set-retained-software-renderer3d-value-hits! self 0)
        (set-retained-software-renderer3d-value-misses! self 0)))
     (void))])

(define (retained-software-renderer3d #:capacity [capacity 32])
  (unless (exact-positive-integer? capacity)
    (raise-argument-error 'retained-software-renderer3d
                          "exact-positive-integer?" capacity))
  (retained-software-renderer3d-value capacity (make-hash) 0 0 0 (make-semaphore 1)))

(define retained-software-renderer3d? retained-software-renderer3d-value?)
(define (retained-software-renderer3d-cache-hits renderer)
  (check-retained-software-renderer 'retained-software-renderer3d-cache-hits renderer)
  (call-with-semaphore
   (retained-software-renderer3d-value-lock renderer)
   (lambda () (retained-software-renderer3d-value-hits renderer))))
(define (retained-software-renderer3d-cache-misses renderer)
  (check-retained-software-renderer 'retained-software-renderer3d-cache-misses renderer)
  (call-with-semaphore
   (retained-software-renderer3d-value-lock renderer)
   (lambda () (retained-software-renderer3d-value-misses renderer))))
(define (retained-software-renderer3d-cache-size renderer)
  (check-retained-software-renderer 'retained-software-renderer3d-cache-size renderer)
  (call-with-semaphore
   (retained-software-renderer3d-value-lock renderer)
   (lambda () (hash-count (retained-software-renderer3d-value-entries renderer)))))

(define (check-retained-software-renderer who renderer)
  (unless (retained-software-renderer3d? renderer)
    (raise-argument-error who "retained-software-renderer3d?" renderer)))

(define default-software-renderer3d
  (retained-software-renderer3d))

(define current-view3d-renderer3d
  (make-parameter
   default-software-renderer3d
   (lambda (value)
     (unless (renderer3d? value)
       (raise-argument-error 'current-view3d-renderer3d "renderer3d?" value))
     value)))

(define (renderer3d-render-result->bitmap result)
  (unless (renderer3d-render-result? result)
    (raise-argument-error 'renderer3d-render-result->bitmap
                          "renderer3d-render-result?" result))
  (define bitmap
    (make-object bitmap%
                 (renderer3d-render-result-width result)
                 (renderer3d-render-result-height result)
                 #f #t))
  (send bitmap set-argb-pixels
        0 0
        (renderer3d-render-result-width result)
        (renderer3d-render-result-height result)
        (renderer3d-render-result-argb-bytes result))
  bitmap)
