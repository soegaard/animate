#lang racket/base

;;;
;;; Glyph Outline Morph Formula Visual
;;;

;; A transient interior formula Visual for compatible dvisvgm glyph outlines.
;; Its source and destination SVG fragments remain the exact timeline endpoints;
;; only samples strictly between zero and one use interpolated path geometry.

(require "affine-transform.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide (struct-out glyph-outline-morph-visual)
         make-glyph-outline-morph-visual)

(struct glyph-outline-morph-visual formula-visual
  (source-path destination-path fill stroke stroke-width progress)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (formula-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (formula-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (copy-glyph-outline-morph-visual
      visual
      (formula-visual-id visual)
      (affine-transform-with-translation
       (formula-visual-transform visual)
       position)
      (formula-visual-opacity visual)
      (glyph-outline-morph-visual-progress visual)))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (formula-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (copy-glyph-outline-morph-visual
      visual
      (formula-visual-id visual)
      transform
      (formula-visual-opacity visual)
      (glyph-outline-morph-visual-progress visual)))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (formula-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (and (finite-real? opacity) (<= 0 opacity 1))
       (raise-argument-error 'visual-with-opacity "finite real in [0, 1]" opacity))
     (copy-glyph-outline-morph-visual
      visual
      (formula-visual-id visual)
      (formula-visual-transform visual)
      opacity
      (glyph-outline-morph-visual-progress visual)))]
  #:methods gen:formula-identity-visual
  [(define (generic-formula-visual-with-id visual id)
     (unless (symbol? id)
       (raise-argument-error 'formula-visual-with-id "symbol?" id))
     (copy-glyph-outline-morph-visual
      visual
      id
      (formula-visual-transform visual)
      (formula-visual-opacity visual)
      (glyph-outline-morph-visual-progress visual)))]
  #:methods gen:formula-rendering-key
  [(define (generic-formula-rendering-key visual)
     (formula-visual-default-rendering-key visual))]
  #:methods gen:formula-transition-sampling
  [(define (generic-formula-visual-at-transition-progress visual progress)
     (unless (and (finite-real? progress) (<= 0 progress 1))
       (raise-argument-error
        'formula-visual-at-transition-progress
        "finite real in [0, 1]"
        progress))
     (copy-glyph-outline-morph-visual
      visual
      (formula-visual-id visual)
      (formula-visual-transform visual)
      (formula-visual-opacity visual)
      progress))])

;; glyph-outline-morph-visual retains a formula's transform and temporary
;; identity protocol while carrying one pair of already-normalized local paths.
;; The renderer interpolates the geometry at `progress` and applies fill using
;; the source SVG's odd-even style.

(define (make-glyph-outline-morph-visual source source-path destination-path
                                         fill stroke stroke-width)
  (unless (formula-visual? source)
    (raise-argument-error 'make-glyph-outline-morph-visual "formula-visual?" source))
  (unless (path-geometry-morph-compatible? source-path destination-path)
    (raise-arguments-error
     'make-glyph-outline-morph-visual
     "compatible normalized path geometries"
     "source-path" source-path
     "destination-path" destination-path))
  (unless (and (finite-real? stroke-width) (not (negative? stroke-width)))
    (raise-argument-error
     'make-glyph-outline-morph-visual
     "nonnegative finite real?"
     stroke-width))
  (glyph-outline-morph-visual
   (formula-visual-id source)
   (formula-visual-transform source)
   (formula-visual-opacity source)
   (formula-visual-source source)
   (formula-visual-mode source)
   (formula-visual-font-size source)
   (formula-visual-preamble source)
   (formula-visual-document-class-options source)
   (formula-visual-preview-options source)
   (formula-visual-horizontal-alignment source)
   (formula-visual-vertical-alignment source)
   source-path destination-path fill stroke stroke-width 0))

(define (copy-glyph-outline-morph-visual visual id transform opacity progress)
  (glyph-outline-morph-visual
   id
   transform
   opacity
   (formula-visual-source visual)
   (formula-visual-mode visual)
   (formula-visual-font-size visual)
   (formula-visual-preamble visual)
   (formula-visual-document-class-options visual)
   (formula-visual-preview-options visual)
   (formula-visual-horizontal-alignment visual)
   (formula-visual-vertical-alignment visual)
   (glyph-outline-morph-visual-source-path visual)
   (glyph-outline-morph-visual-destination-path visual)
   (glyph-outline-morph-visual-fill visual)
   (glyph-outline-morph-visual-stroke visual)
   (glyph-outline-morph-visual-stroke-width visual)
   progress))
