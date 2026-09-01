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
         "renderer-resources.rkt"
         "visual-model.rkt")

(provide (struct-out image-pict-renderer)
         make-image-raster-cache)

; make-image-raster-cache : -> renderer-resource-cache?
;; Creates the bounded adapter-owned bitmap source cache.
(define (make-image-raster-cache)
  (make-renderer-resource-cache #:max-entries 64))

(struct image-pict-renderer (raster-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (image-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (image-visual->pict visual
                         camera
                         (image-pict-renderer-raster-cache renderer)))])

; image-visual->pict : image-visual? camera? renderer-resource-cache? -> pict?
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

; cached-image-bitmap : renderer-resource-cache? immutable-string? -> bitmap%
(define (cached-image-bitmap cache source)
  (renderer-resource-cache-ref!
   cache
   (list 'bitmap source)
   (lambda ()
     (define loaded
       (make-object bitmap% source))
     (unless (send loaded ok?)
       (raise-arguments-error
        'image-visual->pict
        "could not load the bitmap image source"
        "source" source))
     (values loaded
             (* 4 (send loaded get-width) (send loaded get-height))))))
