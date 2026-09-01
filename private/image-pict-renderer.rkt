#lang racket/base

;;;
;;; Bitmap Image Pict Renderer
;;;

;; Loads immutable image Visual sources at the renderer boundary. A bounded
;; shared cache is deliberately performance-only: scene models retain only the
;; source pathname and never depend on cache contents for sampling.

(require racket/class
         (only-in pict bitmap pict-height pict-width scale)
         (only-in racket/draw bitmap%)
         "anchored-pict.rkt"
         "camera.rkt"
         "geometry.rkt"
         "image-visual.rkt"
         "pict-renderer.rkt"
         "visual-model.rkt")

(provide image-pict-renderer
         make-image-raster-cache)

(define maximum-image-raster-cache-entries 64)

(struct image-raster-cache (table lock)
  #:mutable)

; image-raster-cache stores bitmap% values keyed by immutable source path.

(define (make-image-raster-cache)
  (image-raster-cache (make-hash) (make-semaphore 1)))

(struct image-pict-renderer (raster-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (image-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (image-visual->pict visual
                         camera
                         (image-pict-renderer-raster-cache renderer)))])

; image-visual->pict : image-visual? camera? image-raster-cache? -> pict?
(define (image-visual->pict visual camera cache)
  (define source-pict
    (bitmap (cached-image-bitmap cache (image-visual-source visual))))
  (define source-width (pict-width source-pict))
  (define source-height (pict-height source-pict))
  (unless (and (positive? source-width)
               (positive? source-height))
    (raise-arguments-error
     'image-visual->pict
     "the loaded image must have positive dimensions"
     "source" (image-visual-source visual)
     "width" source-width
     "height" source-height))
  (define scale-value
    (visual-scale visual))
  (define desired-width
    (camera-length->pixels
     camera
     (* (image-visual-width visual)
        (vec2-x scale-value))))
  (define desired-height
    (camera-length->pixels
     camera
     (* (image-visual-height visual)
        (vec2-y scale-value))))
  (define scaled
    (scale source-pict
           (/ desired-width source-width)
           (/ desired-height source-height)))
  (rotate-pict-if-needed scaled (visual-rotation visual)))

; cached-image-bitmap : image-raster-cache? immutable-string? -> bitmap%
(define (cached-image-bitmap cache source)
  (call-with-semaphore
   (image-raster-cache-lock cache)
   (lambda ()
     (hash-ref!
      (image-raster-cache-table cache)
      source
      (lambda ()
        (when (>= (hash-count (image-raster-cache-table cache))
                  maximum-image-raster-cache-entries)
          ;; A full cache is discarded as one bounded, deterministic operation.
          ;; It changes only loading cost, never semantic rendering choices.
          (hash-clear! (image-raster-cache-table cache)))
        (define loaded
          (make-object bitmap% source))
        (unless (send loaded ok?)
          (raise-arguments-error
           'image-visual->pict
           "could not load the bitmap image source"
           "source" source))
        loaded)))))
