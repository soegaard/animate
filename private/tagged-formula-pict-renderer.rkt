#lang racket/base

;;;
;;; Tagged SVG Formula Pict Renderer
;;;

(require svg/svg
         "camera.rkt"
         "color-style.rkt"
         "formula-style.rkt"
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
     (tagged-formula-renderable? visual))
   (define (pict-renderer-render renderer visual camera)
     (formula-visual-base-pict->pict
      visual
      camera
      (cached-tagged-formula-pict
       (tagged-formula-pict-renderer-pict-cache renderer)
       visual)))])

(define (cached-tagged-formula-pict cache visual)
  (define svg-source (tagged-formula-render-svg-source visual))
  (renderer-resource-cache-ref!
   cache
   (list 'tagged-formula-fragment
         svg-source)
   (lambda ()
     ;; SVG Picts can remain vector-backed; the entry bound prevents unbounded
     ;; retention without forcing a raster solely to estimate memory use.
     (values
      (svg-string->pict
       svg-source)
      0))))

(define (tagged-formula-renderable? visual)
  (tagged-formula-fragment-visual?
   (tagged-formula-render-base visual)))

(define (tagged-formula-render-base visual)
  (if (formula-styled-visual? visual)
      (formula-styled-visual-base visual)
      visual))

;; tagged-formula-render-svg-source : formula-visual? -> string?
;; dvisvgm produces self-painted glyph SVG: its default `fill` is black rather
;; than Pict's current drawing colour.  A Pict `colorize` wrapper therefore
;; cannot recolour it.  Install one fragment-local CSS rule at the SVG boundary
;; instead. dvisvgm's visible glyphs are `<use>` references to outline paths
;; in `<defs>`; styling those outline paths (rather than the use group) also
;; works with the SVG renderer's intentionally isolated `<use>` expansion.
(define (tagged-formula-render-svg-source visual)
  (define base (tagged-formula-render-base visual))
  (define source (tagged-formula-fragment-visual-svg-source base))
  (if (formula-styled-visual? visual)
      (regexp-replace
       ;; dvisvgm emits exactly one root closing tag. Replacing that tag avoids
       ;; relying on a trailing-whitespace regexp convention.
       #rx"</svg>"
       source
       (string-append
        (tagged-formula-style-element
         (formula-styled-visual-color visual))
        "</svg>"))
      source))

;; tagged-formula-style-element : color-spec? -> string?
;; The SVG parser understands CSS rgba() values, including fractional alpha
;; during an ordinary fill-color interpolation. `!important` deliberately
;; outranks any TeX-originating presentation attribute: selected formula parts
;; have one caller-selected colour.
(define (tagged-formula-style-element color)
  (define rgba (color-spec->rgba-color color 'tagged-formula-style-element))
  (define css-color
    (format "rgba(~a,~a,~a,~a)"
            (inexact-channel (rgba-color-red rgba))
            (inexact-channel (rgba-color-green rgba))
            (inexact-channel (rgba-color-blue rgba))
            (inexact-channel (rgba-color-alpha rgba))))
  (format
   "<style>path{fill:~a !important;stroke:~a !important;}</style>"
   css-color
   css-color))

(define (inexact-channel value)
  (exact->inexact value))
