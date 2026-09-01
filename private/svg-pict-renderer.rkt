#lang racket/base

;;;
;;; Full-Fidelity SVG Pict Renderer
;;;

(require (only-in pict pict-height pict-width scale)
         svg/svg
         "anchored-pict.rkt"
         "camera.rkt"
         "geometry.rkt"
         "pict-renderer.rkt"
         "renderer-resources.rkt"
         "svg-image-visual.rkt"
         "visual-model.rkt")

(provide (struct-out svg-pict-renderer)
         make-svg-pict-cache)

; make-svg-pict-cache : -> renderer-resource-cache?
;; Caches parsed/static SVG Picts by source path. Its byte estimate bounds the
;; common raster-backed cases while the entry limit also bounds vector Picts.
(define (make-svg-pict-cache)
  (make-renderer-resource-cache #:max-entries 64 #:max-bytes (* 64 1024 1024)))

(struct svg-pict-renderer (pict-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (svg-image-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (svg-image-visual->pict visual
                             camera
                             (svg-pict-renderer-pict-cache renderer)))])

; svg-image-visual->pict : svg-image-visual? camera? renderer-resource-cache?
;;                         -> pict?
(define (svg-image-visual->pict visual camera cache)
  (define source-pict
    (cached-svg-pict cache (svg-image-visual-source visual)))
  (define source-width (pict-width source-pict))
  (define source-height (pict-height source-pict))
  (unless (and (positive? source-width)
               (positive? source-height))
    (raise-arguments-error
     'svg-image-visual->pict
     "the SVG renderer must produce positive dimensions"
     "source" (svg-image-visual-source visual)
     "width" source-width
     "height" source-height))
  (define scale-value (visual-scale visual))
  (define desired-width
    (camera-length->pixels camera
                           (* (svg-image-visual-width visual)
                              (vec2-x scale-value))))
  (define desired-height
    (camera-length->pixels camera
                           (* (svg-image-visual-height visual)
                              (vec2-y scale-value))))
  (rotate-pict-if-needed
   (scale source-pict
          (/ desired-width source-width)
          (/ desired-height source-height))
   (visual-rotation visual)))

; cached-svg-pict : renderer-resource-cache? immutable-string? -> pict?
(define (cached-svg-pict cache source)
  (renderer-resource-cache-ref!
   cache
   (list 'svg source)
   (lambda ()
     (define rendered
       (with-handlers
           ([exn:fail?
             (lambda (exception)
               (raise-arguments-error
                'svg-image-visual->pict
                "could not render the SVG image source"
                "source" source
                "exception message" (exn-message exception)))])
         (svg-file->pict source)))
     (values rendered
             (* 4
                (inexact->exact (ceiling (pict-width rendered)))
                (inexact->exact (ceiling (pict-height rendered))))))))
