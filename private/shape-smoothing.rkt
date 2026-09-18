#lang racket/base

;; Pixel alignment is appropriate for some UI drawing, but not for the continuous
;; geometry of Animate's circles and rectangles. In 'aligned/'unsmoothed mode,
;; racket/draw adjusts an ellipse's stroke separately from its fill.
(require racket/class
         (only-in pict dc draw-pict pict? pict-width pict-height
                  pict-ascent pict-descent))
(provide shape-pict-with-smoothed-drawing)

;; Keep the choice inside the delayed draw callback: setting a DC mode while
;; constructing a Pict would not affect a later SVG, Scribble, or bitmap draw.
;; Restore the caller's mode even if a renderer raises an exception. This wrapper
;; changes no dimensions, coordinates, pen width, transforms, or semantic data.
(define (shape-pict-with-smoothed-drawing source)
  (unless (pict? source)
    (raise-argument-error 'shape-pict-with-smoothed-drawing "pict?" source))
  (dc (lambda (drawing-context x y)
        (define previous (send drawing-context get-smoothing))
        (dynamic-wind
          (lambda () (send drawing-context set-smoothing 'smoothed))
          (lambda () (draw-pict source drawing-context x y))
          (lambda () (send drawing-context set-smoothing previous))))
      (pict-width source) (pict-height source)
      (pict-ascent source) (pict-descent source)))
