#lang racket/base

;;;
;;; Renderer Metrics
;;;

;; Counters live with an effectful renderer instance, never in a semantic mesh
;; or view.  A snapshot is immutable, so callers can safely compare frames or
;; serialise benchmark results while preview rendering continues elsewhere.


;;;
;;; Imports and Exports
;;;

(require racket/math)

(provide (struct-out renderer3d-statistics)
         make-renderer3d-statistics-state
         renderer3d-statistics-state-reset!
         renderer3d-statistics-state-snapshot
         renderer3d-statistics-state-add!)


;;;
;;; Immutable Public Snapshot and Mutable Private State
;;;

(struct renderer3d-statistics
  (spatial-compilations
   geometry-fingerprints
   geometry-cache-hits
   geometry-cache-misses
   geometry-cache-bytes
   instance-count
   source-triangle-count
   clipped-triangle-count
   raster-triangle-count
   pixel-count
   bitmap-conversion-count
   preparation-milliseconds
   raster-milliseconds
   readback-milliseconds)
  #:transparent)

(struct renderer3d-statistics-state
  (spatial-compilations
   geometry-fingerprints
   geometry-cache-hits
   geometry-cache-misses
   geometry-cache-bytes
   instance-count
   source-triangle-count
   clipped-triangle-count
   raster-triangle-count
   pixel-count
   bitmap-conversion-count
   preparation-milliseconds
   raster-milliseconds
   readback-milliseconds)
  #:mutable
  #:transparent)

(define (make-renderer3d-statistics-state)
  (renderer3d-statistics-state 0 0 0 0 0 0 0 0 0 0 0 0.0 0.0 0.0))

(define (renderer3d-statistics-state-reset! state)
  (unless (renderer3d-statistics-state? state)
    (raise-argument-error 'renderer3d-statistics-state-reset!
                          "renderer3d-statistics-state?" state))
  (for ([setter (in-list (list set-renderer3d-statistics-state-spatial-compilations!
                               set-renderer3d-statistics-state-geometry-fingerprints!
                               set-renderer3d-statistics-state-geometry-cache-hits!
                               set-renderer3d-statistics-state-geometry-cache-misses!
                               set-renderer3d-statistics-state-geometry-cache-bytes!
                               set-renderer3d-statistics-state-instance-count!
                               set-renderer3d-statistics-state-source-triangle-count!
                               set-renderer3d-statistics-state-clipped-triangle-count!
                               set-renderer3d-statistics-state-raster-triangle-count!
                               set-renderer3d-statistics-state-pixel-count!
                               set-renderer3d-statistics-state-bitmap-conversion-count!
                               set-renderer3d-statistics-state-preparation-milliseconds!
                               set-renderer3d-statistics-state-raster-milliseconds!
                               set-renderer3d-statistics-state-readback-milliseconds!))])
    (setter state 0))
  (void))

(define (renderer3d-statistics-state-snapshot state)
  (unless (renderer3d-statistics-state? state)
    (raise-argument-error 'renderer3d-statistics-state-snapshot
                          "renderer3d-statistics-state?" state))
  (renderer3d-statistics
   (renderer3d-statistics-state-spatial-compilations state)
   (renderer3d-statistics-state-geometry-fingerprints state)
   (renderer3d-statistics-state-geometry-cache-hits state)
   (renderer3d-statistics-state-geometry-cache-misses state)
   (renderer3d-statistics-state-geometry-cache-bytes state)
   (renderer3d-statistics-state-instance-count state)
   (renderer3d-statistics-state-source-triangle-count state)
   (renderer3d-statistics-state-clipped-triangle-count state)
   (renderer3d-statistics-state-raster-triangle-count state)
   (renderer3d-statistics-state-pixel-count state)
   (renderer3d-statistics-state-bitmap-conversion-count state)
   (renderer3d-statistics-state-preparation-milliseconds state)
   (renderer3d-statistics-state-raster-milliseconds state)
   (renderer3d-statistics-state-readback-milliseconds state)))

(define (renderer3d-statistics-state-add! state field amount)
  (unless (renderer3d-statistics-state? state)
    (raise-argument-error 'renderer3d-statistics-state-add!
                          "renderer3d-statistics-state?" state))
  (unless (and (real? amount) (not (nan? amount)))
    (raise-argument-error 'renderer3d-statistics-state-add!
                          "non-NaN real?" amount))
  (define accessor+setter
    (case field
      [(spatial-compilations)
       (cons renderer3d-statistics-state-spatial-compilations
             set-renderer3d-statistics-state-spatial-compilations!)]
      [(geometry-fingerprints)
       (cons renderer3d-statistics-state-geometry-fingerprints
             set-renderer3d-statistics-state-geometry-fingerprints!)]
      [(geometry-cache-hits)
       (cons renderer3d-statistics-state-geometry-cache-hits
             set-renderer3d-statistics-state-geometry-cache-hits!)]
      [(geometry-cache-misses)
       (cons renderer3d-statistics-state-geometry-cache-misses
             set-renderer3d-statistics-state-geometry-cache-misses!)]
      [(geometry-cache-bytes)
       (cons renderer3d-statistics-state-geometry-cache-bytes
             set-renderer3d-statistics-state-geometry-cache-bytes!)]
      [(instance-count)
       (cons renderer3d-statistics-state-instance-count
             set-renderer3d-statistics-state-instance-count!)]
      [(source-triangle-count)
       (cons renderer3d-statistics-state-source-triangle-count
             set-renderer3d-statistics-state-source-triangle-count!)]
      [(clipped-triangle-count)
       (cons renderer3d-statistics-state-clipped-triangle-count
             set-renderer3d-statistics-state-clipped-triangle-count!)]
      [(raster-triangle-count)
       (cons renderer3d-statistics-state-raster-triangle-count
             set-renderer3d-statistics-state-raster-triangle-count!)]
      [(pixel-count)
       (cons renderer3d-statistics-state-pixel-count
             set-renderer3d-statistics-state-pixel-count!)]
      [(bitmap-conversion-count)
       (cons renderer3d-statistics-state-bitmap-conversion-count
             set-renderer3d-statistics-state-bitmap-conversion-count!)]
      [(preparation-milliseconds)
       (cons renderer3d-statistics-state-preparation-milliseconds
             set-renderer3d-statistics-state-preparation-milliseconds!)]
      [(raster-milliseconds)
       (cons renderer3d-statistics-state-raster-milliseconds
             set-renderer3d-statistics-state-raster-milliseconds!)]
      [(readback-milliseconds)
       (cons renderer3d-statistics-state-readback-milliseconds
             set-renderer3d-statistics-state-readback-milliseconds!)]
      [else
       (raise-argument-error 'renderer3d-statistics-state-add!
                             "known renderer statistics field" field)]))
  (define accessor (car accessor+setter))
  (define setter (cdr accessor+setter))
  (setter state (+ (accessor state) amount))
  (void))
