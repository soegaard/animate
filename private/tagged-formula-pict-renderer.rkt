#lang racket/base

;;;
;;; Tagged SVG Formula Pict Renderer
;;;

(require svg/svg
         "camera.rkt"
         "formula-visual.rkt"
         "latex-formula-pict-renderer.rkt"
         "pict-renderer.rkt"
         "renderer-resources.rkt"
         "tagged-formula.rkt")

(provide (struct-out tagged-formula-pict-renderer)
         make-tagged-formula-pict-cache)

(define (make-tagged-formula-pict-cache)
  (make-renderer-resource-cache #:max-entries 256))

(struct tagged-formula-pict-renderer (pict-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (tagged-formula-fragment-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (formula-visual-base-pict->pict
      visual
      camera
      (cached-tagged-formula-pict
       (tagged-formula-pict-renderer-pict-cache renderer)
       visual)))])

(define (cached-tagged-formula-pict cache visual)
  (renderer-resource-cache-ref!
   cache
   (list 'tagged-formula-fragment
         (tagged-formula-fragment-visual-svg-source visual))
   (lambda ()
     ;; SVG Picts can remain vector-backed; the entry bound prevents unbounded
     ;; retention without forcing a raster solely to estimate memory use.
     (values
      (svg-string->pict
       (tagged-formula-fragment-visual-svg-source visual))
      0))))
