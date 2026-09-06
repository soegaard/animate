#lang racket/base

;;;
;;; Backend-Neutral Spatial Renderer Protocol
;;;

;; Semantic 3D authoring values stay immutable and renderer-neutral. This
;; module owns the effectful boundary: requests contain a compiled scene plus a
;; frame specification, and retained renderer instances own all cache state.

(require racket/class
         racket/draw
         racket/generic
         "../preview-cancellation.rkt"
         "compiled-view3d.rkt"
         "geometry-fingerprint3d.rkt"
         "raster-target3d.rkt"
         "renderer3d-statistics.rkt"
         "software-render-diagnostics.rkt"
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
         view3d->render3d-request
         (struct-out renderer3d-render-result)
         renderer3d-render-result->bitmap
         (struct-out renderer3d-statistics)
         renderer3d-statistics-reset!
         renderer3d-statistics-snapshot
         software-renderer3d
         software-renderer3d?
         retained-software-renderer3d
         retained-software-renderer3d?
         retained-software-renderer3d-cache-hits
         retained-software-renderer3d-cache-misses
         retained-software-renderer3d-cache-size
         default-software-renderer3d
         current-view3d-renderer3d)


;;;
;;; Protocol Values
;;;

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

;; The request excludes a raw view3d. Compilation captures camera-independent
;; data first, so a camera orbit affects only frame preparation.
(struct render3d-request (compiled-view frame-spec cancellation-token)
  #:transparent
  #:guard
  (lambda (compiled-view frame-spec cancellation-token who)
    (unless (compiled-view3d? compiled-view)
      (raise-argument-error who "compiled-view3d?" compiled-view))
    (unless (frame3d-spec? frame-spec)
      (raise-argument-error who "frame3d-spec?" frame-spec))
    (unless (or (not cancellation-token) (cancellation-token? cancellation-token))
      (raise-argument-error who "(or/c #f cancellation-token?)" cancellation-token))
    (values compiled-view frame-spec cancellation-token)))

; view3d->render3d-request : view3d? exact-positive-integer? exact-positive-integer?
;                            [#:cancellation-token (or/c #f cancellation-token?)]
;                            -> render3d-request?
(define (view3d->render3d-request view width height #:cancellation-token [cancellation-token #f])
  (unless (view3d? view)
    (raise-argument-error 'view3d->render3d-request "view3d?" view))
  (render3d-request (compile-view3d view)
                    (view3d->frame3d-spec view width height)
                    cancellation-token))

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

(define-generics renderer3d
  (renderer3d-id renderer3d)
  (renderer3d-capabilities renderer3d)
  (renderer3d-fingerprint renderer3d request)
  (renderer3d-prepare renderer3d request)
  (renderer3d-render renderer3d preparation request)
  (renderer3d-release renderer3d))

(define reference-capabilities
  (renderer3d-capability-set #f #t #t #t #t #t #t #t #t))


;;;
;;; Reference Preparation and Rendering
;;;

(define (request-fingerprint request)
  ;; This is a cache key, never a claim that structurally equal views carry the
  ;; same authoring identity. Compiled geometry keys establish that separately.
  (vector 'animate-software-renderer3d-v2
          (render3d-request-compiled-view request)
          (render3d-request-frame-spec request)))

(define (prepare-reference request)
  (prepare-compiled-view3d-opaque
   (render3d-request-compiled-view request)
   (render3d-request-frame-spec request)
   #:cancellation-token (render3d-request-cancellation-token request)))

(define (render-reference preparation request statistics statistics-lock)
  (define raster-start (current-inexact-milliseconds))
  (define rendered
    (render-prepared-view3d-opaque
     preparation
     #:cancellation-token (render3d-request-cancellation-token request)))
  (define raster-finished (current-inexact-milliseconds))
  (define target (software-render-result-target rendered))
  (define readback-start (current-inexact-milliseconds))
  (define bytes (raster-target3d->argb-bytes target))
  (define readback-finished (current-inexact-milliseconds))
  (define diagnostics (software-render-result-diagnostics rendered))
  (statistics-update!
   statistics statistics-lock
   (lambda ()
     (renderer3d-statistics-state-add!
      statistics 'raster-triangle-count
      (software-render-diagnostics-raster-triangle-count diagnostics))
     (renderer3d-statistics-state-add!
      statistics 'pixel-count
      (software-render-diagnostics-pixel-count diagnostics))
     (renderer3d-statistics-state-add!
      statistics 'raster-milliseconds (- raster-finished raster-start))
     (renderer3d-statistics-state-add!
      statistics 'readback-milliseconds (- readback-finished readback-start))))
  (renderer3d-render-result
   (raster-target3d-width target)
   (raster-target3d-height target)
   bytes
   diagnostics))

(define (record-preparation! statistics statistics-lock request preparation elapsed)
  (define diagnostics (software-render-preparation-diagnostics preparation))
  (statistics-update!
   statistics statistics-lock
   (lambda ()
     (renderer3d-statistics-state-add! statistics 'spatial-compilations 1)
     (renderer3d-statistics-state-add!
      statistics 'instance-count
      (vector-length
       (compiled-view3d-instances (render3d-request-compiled-view request))))
     (renderer3d-statistics-state-add!
      statistics 'source-triangle-count
      (software-render-diagnostics-source-triangle-count diagnostics))
     (renderer3d-statistics-state-add!
      statistics 'clipped-triangle-count
      (software-render-diagnostics-clipped-triangle-count diagnostics))
     (renderer3d-statistics-state-add! statistics 'preparation-milliseconds elapsed))))

(define (prepare-reference/record request statistics statistics-lock)
  (define start (current-inexact-milliseconds))
  (define preparation (prepare-reference request))
  (record-preparation! statistics statistics-lock request preparation
                       (- (current-inexact-milliseconds) start))
  preparation)

(define (statistics-update! statistics lock update)
  (call-with-semaphore lock update))


;;;
;;; Stateless Reference Renderer
;;;

(struct software-renderer3d-value (statistics lock)
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id _self) 'software-reference)
   (define (renderer3d-capabilities _self) reference-capabilities)
   (define (renderer3d-fingerprint _self request) (request-fingerprint request))
   (define (renderer3d-prepare self request)
     ;; No retained geometry exists here, but every fingerprint and miss remains
     ;; visible in the same measurement schema as the retained backend.
     (statistics-update!
      (software-renderer3d-value-statistics self)
      (software-renderer3d-value-lock self)
      (lambda ()
        (for ([geometry (in-vector
                         (compiled-view3d-geometries
                          (render3d-request-compiled-view request)))])
          (renderer3d-statistics-state-add!
           (software-renderer3d-value-statistics self) 'geometry-fingerprints 1)
          (renderer3d-statistics-state-add!
           (software-renderer3d-value-statistics self) 'geometry-cache-misses 1)
          (renderer3d-statistics-state-add!
           (software-renderer3d-value-statistics self) 'geometry-cache-bytes
           (geometry-key3d-byte-length (compiled-geometry3d-key geometry))))))
     (prepare-reference/record request
                               (software-renderer3d-value-statistics self)
                               (software-renderer3d-value-lock self)))
   (define (renderer3d-render self preparation request)
     (render-reference preparation request
                       (software-renderer3d-value-statistics self)
                       (software-renderer3d-value-lock self)))
   (define (renderer3d-release self)
     (statistics-update!
      (software-renderer3d-value-statistics self)
      (software-renderer3d-value-lock self)
      (lambda () (renderer3d-statistics-state-reset!
                   (software-renderer3d-value-statistics self))))
     (void))])

(define (software-renderer3d)
  (software-renderer3d-value (make-renderer3d-statistics-state) (make-semaphore 1)))

(define software-renderer3d? software-renderer3d-value?)


;;;
;;; Retained Software Renderer
;;;

;; Frame entries hold camera-space data. Geometry entries are separate and are
;; keyed by semantic geometry only, so camera motion reports geometry hits even
;; when every frame preparation must be rebuilt.
(struct retained-software-entry (preparation last-used) #:mutable #:transparent)
(struct retained-software-geometry-entry (geometry byte-length last-used)
  #:mutable #:transparent)

(struct retained-software-renderer3d-value
  (capacity entries geometry-entries clock geometry-clock hits misses lock statistics)
  #:mutable
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id _self) 'retained-software-reference)
   (define (renderer3d-capabilities _self) reference-capabilities)
   (define (renderer3d-fingerprint _self request) (request-fingerprint request))
   (define (renderer3d-prepare self request)
     (call-with-semaphore
      (retained-software-renderer3d-value-lock self)
      (lambda ()
        (define canonical-request (canonicalize-geometry-request self request))
        (define key (renderer3d-fingerprint self canonical-request))
        (define tick (next-frame-tick! self))
        (define existing
          (hash-ref (retained-software-renderer3d-value-entries self) key #f))
        (cond
          [existing
           (set-retained-software-entry-last-used! existing tick)
           (set-retained-software-renderer3d-value-hits!
            self (add1 (retained-software-renderer3d-value-hits self)))
           (retained-software-entry-preparation existing)]
          [else
           (define start (current-inexact-milliseconds))
           (define preparation (prepare-reference canonical-request))
           ;; The lock is reentrant only by design of this local branch, so
           ;; record here directly rather than trying to take it again.
           (record-preparation-under-held-lock!
            (retained-software-renderer3d-value-statistics self)
            canonical-request preparation (- (current-inexact-milliseconds) start))
           (evict-oldest! (retained-software-renderer3d-value-entries self)
                          (retained-software-renderer3d-value-capacity self)
                          retained-software-entry-last-used)
           (hash-set! (retained-software-renderer3d-value-entries self)
                      key (retained-software-entry preparation tick))
           (set-retained-software-renderer3d-value-misses!
            self (add1 (retained-software-renderer3d-value-misses self)))
           preparation]))))
   (define (renderer3d-render self preparation request)
     (render-reference preparation request
                       (retained-software-renderer3d-value-statistics self)
                       (retained-software-renderer3d-value-lock self)))
   (define (renderer3d-release self)
     (call-with-semaphore
      (retained-software-renderer3d-value-lock self)
      (lambda ()
        (hash-clear! (retained-software-renderer3d-value-entries self))
        (hash-clear! (retained-software-renderer3d-value-geometry-entries self))
        (set-retained-software-renderer3d-value-clock! self 0)
        (set-retained-software-renderer3d-value-geometry-clock! self 0)
        (set-retained-software-renderer3d-value-hits! self 0)
        (set-retained-software-renderer3d-value-misses! self 0)
        (renderer3d-statistics-state-reset!
         (retained-software-renderer3d-value-statistics self))))
     (void))])

(define (retained-software-renderer3d #:capacity [capacity 32])
  (unless (exact-positive-integer? capacity)
    (raise-argument-error 'retained-software-renderer3d
                          "exact-positive-integer?" capacity))
  (retained-software-renderer3d-value
   capacity (make-hash) (make-hash) 0 0 0 0 (make-semaphore 1)
   (make-renderer3d-statistics-state)))

(define retained-software-renderer3d? retained-software-renderer3d-value?)

(define (canonicalize-geometry-request renderer request)
  (define compiled (render3d-request-compiled-view request))
  (define canonical-geometries '())
  (for ([geometry (in-vector (compiled-view3d-geometries compiled))])
    (define key (compiled-geometry3d-key geometry))
    (define statistics (retained-software-renderer3d-value-statistics renderer))
    (renderer3d-statistics-state-add! statistics 'geometry-fingerprints 1)
    (define tick (next-geometry-tick! renderer))
    (define existing
      (hash-ref (retained-software-renderer3d-value-geometry-entries renderer) key #f))
    (cond
      [existing
       (unless (mesh3d-semantic-geometry=?
                (compiled-geometry3d-mesh geometry)
                (compiled-geometry3d-mesh
                 (retained-software-geometry-entry-geometry existing)))
         (raise-arguments-error 'renderer3d-prepare
                                "a collision-free geometry key"
                                "geometry-key" key))
       (set-retained-software-geometry-entry-last-used! existing tick)
       (renderer3d-statistics-state-add! statistics 'geometry-cache-hits 1)
       (set! canonical-geometries
             (append canonical-geometries
                     (list (retained-software-geometry-entry-geometry existing))))]
      [else
       (evict-oldest! (retained-software-renderer3d-value-geometry-entries renderer)
                      (retained-software-renderer3d-value-capacity renderer)
                      retained-software-geometry-entry-last-used
                      (lambda (entry)
                        (renderer3d-statistics-state-add!
                         statistics 'geometry-cache-bytes
                         (- (retained-software-geometry-entry-byte-length entry)))))
       (define byte-length (geometry-key3d-byte-length key))
       (hash-set! (retained-software-renderer3d-value-geometry-entries renderer)
                  key (retained-software-geometry-entry geometry byte-length tick))
       (renderer3d-statistics-state-add! statistics 'geometry-cache-misses 1)
       (renderer3d-statistics-state-add! statistics 'geometry-cache-bytes byte-length)
       (set! canonical-geometries (append canonical-geometries (list geometry)))]))
  (render3d-request
   (compiled-view3d
    (vector->immutable-vector (list->vector canonical-geometries))
    (compiled-view3d-instances compiled)
    (compiled-view3d-strokes compiled)
    (compiled-view3d-point-markers compiled)
    (compiled-view3d-arrow-markers compiled)
    (compiled-view3d-edge-overlays compiled)
    (compiled-view3d-background compiled)
    (compiled-view3d-render-mode compiled)
    (compiled-view3d-transparency-mode compiled))
   (render3d-request-frame-spec request)
   (render3d-request-cancellation-token request)))

(define (record-preparation-under-held-lock! statistics request preparation elapsed)
  (define diagnostics (software-render-preparation-diagnostics preparation))
  (renderer3d-statistics-state-add! statistics 'spatial-compilations 1)
  (renderer3d-statistics-state-add!
   statistics 'instance-count
   (vector-length (compiled-view3d-instances (render3d-request-compiled-view request))))
  (renderer3d-statistics-state-add!
   statistics 'source-triangle-count
   (software-render-diagnostics-source-triangle-count diagnostics))
  (renderer3d-statistics-state-add!
   statistics 'clipped-triangle-count
   (software-render-diagnostics-clipped-triangle-count diagnostics))
  (renderer3d-statistics-state-add! statistics 'preparation-milliseconds elapsed))

(define (next-frame-tick! renderer)
  (define tick (add1 (retained-software-renderer3d-value-clock renderer)))
  (set-retained-software-renderer3d-value-clock! renderer tick)
  tick)

(define (next-geometry-tick! renderer)
  (define tick (add1 (retained-software-renderer3d-value-geometry-clock renderer)))
  (set-retained-software-renderer3d-value-geometry-clock! renderer tick)
  tick)

;; Last-used ticks are unique, so this LRU selection has no hash-order tie.
(define (evict-oldest! entries capacity last-used [on-evict void])
  (when (>= (hash-count entries) capacity)
    (define-values (oldest-key _oldest-tick)
      (for/fold ([oldest-key #f] [oldest-tick +inf.0])
                ([(candidate-key entry) (in-hash entries)])
        (if (< (last-used entry) oldest-tick)
            (values candidate-key (last-used entry))
            (values oldest-key oldest-tick))))
    (when oldest-key
      (define entry (hash-ref entries oldest-key))
      (on-evict entry)
      (hash-remove! entries oldest-key))))

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


;;;
;;; Public Statistics
;;;

(define (renderer3d-statistics-reset! renderer)
  (cond [(software-renderer3d? renderer)
         (statistics-update!
          (software-renderer3d-value-statistics renderer)
          (software-renderer3d-value-lock renderer)
          (lambda () (renderer3d-statistics-state-reset!
                       (software-renderer3d-value-statistics renderer))))]
        [(retained-software-renderer3d? renderer)
         (statistics-update!
          (retained-software-renderer3d-value-statistics renderer)
          (retained-software-renderer3d-value-lock renderer)
          (lambda () (renderer3d-statistics-state-reset!
                       (retained-software-renderer3d-value-statistics renderer))))]
        [else
         (raise-argument-error 'renderer3d-statistics-reset!
                               "built-in software renderer3d?" renderer)])
  (void))

(define (renderer3d-statistics-snapshot renderer)
  (cond [(software-renderer3d? renderer)
         (call-with-semaphore
          (software-renderer3d-value-lock renderer)
          (lambda () (renderer3d-statistics-state-snapshot
                       (software-renderer3d-value-statistics renderer))))]
        [(retained-software-renderer3d? renderer)
         (call-with-semaphore
          (retained-software-renderer3d-value-lock renderer)
          (lambda () (renderer3d-statistics-state-snapshot
                       (retained-software-renderer3d-value-statistics renderer))))]
        [else
         (raise-argument-error 'renderer3d-statistics-snapshot
                               "built-in software renderer3d?" renderer)]))


;;;
;;; Default Renderer and Pict Conversion
;;;

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
