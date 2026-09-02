#lang racket/base

;;;
;;; Glyph Outline Morph Pict Renderer
;;;

(require "camera.rkt"
         "glyph-outline-morph-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "path-pict-renderer.rkt"
         "pict-renderer.rkt"
         "visual-model.rkt")

(provide (struct-out glyph-outline-morph-pict-renderer))

(struct glyph-outline-morph-pict-renderer ()
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (glyph-outline-morph-visual? visual))
   (define (pict-renderer-render _renderer visual camera)
     ;; The semantic formula transform supplies the route, rotation, and scale;
     ;; path geometry itself is local to the cropped dvisvgm glyph viewport.
     (path-visual->pict
      (visual-with-transform
       (make-path-visual
        (path-geometry-lerp
         (glyph-outline-morph-visual-source-path visual)
         (glyph-outline-morph-visual-destination-path visual)
         (glyph-outline-morph-visual-progress visual))
        #:id (visual-id visual)
        #:center origin
        #:fill (glyph-outline-morph-visual-fill visual)
        #:stroke (glyph-outline-morph-visual-stroke visual)
        #:stroke-width (glyph-outline-morph-visual-stroke-width visual))
       (visual-transform visual))
      camera))])
