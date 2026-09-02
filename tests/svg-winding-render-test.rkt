#lang racket/base

;;;
;;; SVG Closed-Contour Winding Regression
;;;

;; dvisvgm formula glyphs commonly contain an outer closed contour and one or
;; more oppositely wound closed counters.  Preserve that winding when converting
;; SVG paths: otherwise holes in glyphs such as a, b, and 4 become filled.

(require rackunit
         racket/class
         (only-in pict pict->bitmap)
         svg/svg)

(define (pixel-alpha bitmap x y)
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 pixels)
  (bytes-ref pixels 0))

(module+ test
  (define ring
    (svg-string->pict
     "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"40\" height=\"40\" viewBox=\"0 0 40 40\"><path fill=\"black\" fill-rule=\"nonzero\" d=\"M 0 0 H 40 V 40 H 0 Z M 10 10 V 30 H 30 V 10 Z\"/></svg>"))
  (define bitmap (pict->bitmap ring))
  ;; The outer contour paints; the oppositely wound inner closed contour is a
  ;; transparent counter rather than a black filled square.
  (check-true (> (pixel-alpha bitmap 5 5) 0))
  (check-equal? (pixel-alpha bitmap 20 20) 0))
