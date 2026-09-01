#lang racket/base

;;;
;;; Anchored Pict Layout
;;;

;; Places a Pict around a semantic text or formula anchor and applies local
;; affine deformation without changing the model layer.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in pict
                  blank
                  pict-ascent
                  pict-descent
                  pict-height
                  pict-width
                  pin-over
                  rotate
                  scale)
         "geometry.rkt"
         (only-in "text-visual.rkt"
                  text-horizontal-alignment?
                  text-vertical-alignment?))

;; Exports
(provide anchor-pict
         scale-pict-if-needed
         rotate-pict-if-needed)


;;;
;;; Anchor Layout
;;;

; anchor-pict : pict?
;               text-horizontal-alignment?
;               text-vertical-alignment?
;               -> pict?
;;   Places source in a symmetric Pict whose center is the semantic anchor.
(define (anchor-pict source
                     horizontal-alignment
                     vertical-alignment)
  (define-values (half-width x-offset)
    (horizontal-anchor-layout source horizontal-alignment))
  (define-values (half-height y-offset)
    (vertical-anchor-layout source vertical-alignment))
  (pin-over (blank (* 2 half-width)
                   (* 2 half-height))
            x-offset
            y-offset
            source))

; horizontal-anchor-layout : pict? text-horizontal-alignment?
;                            -> (values nonnegative-real? real?)
;;   Returns horizontal half-extent and source offset around the anchor.
(define (horizontal-anchor-layout source alignment)
  (define width
    (pict-width source))
  (case alignment
    [(left)
     (values width width)]
    [(center)
     (values (/ width 2) 0)]
    [(right)
     (values width 0)]
    [else
     (raise-argument-error
      'horizontal-anchor-layout
      "text-horizontal-alignment?"
      alignment)]))

; vertical-anchor-layout : pict? text-vertical-alignment?
;                          -> (values nonnegative-real? real?)
;;   Returns vertical half-extent and source offset around the anchor.
(define (vertical-anchor-layout source alignment)
  (define height
    (pict-height source))
  (case alignment
    [(top)
     (values height height)]
    [(center)
     (values (/ height 2) 0)]
    [(baseline)
     (define ascent
       (pict-ascent source))
     (define descent
       (pict-descent source))
     (define half-height
       (max ascent descent))
     (values half-height
             (- half-height ascent))]
    [(bottom)
     (values height 0)]
    [else
     (raise-argument-error
      'vertical-anchor-layout
      "text-vertical-alignment?"
      alignment)]))


;;;
;;; Local Pict Transforms
;;;

; scale-pict-if-needed : pict? vec2? -> pict?
;;   Applies independent x and y scale around the centered semantic anchor.
(define (scale-pict-if-needed source scale-factor)
  (unless (vec2? scale-factor)
    (raise-argument-error
     'scale-pict-if-needed
     "vec2?"
     scale-factor))
  (define x-scale
    (vec2-x scale-factor))
  (define y-scale
    (vec2-y scale-factor))
  (if (and (= x-scale 1)
           (= y-scale 1))
      source
      (scale source x-scale y-scale)))

; rotate-pict-if-needed : pict? finite-real? -> pict?
;;   Rotates source counter-clockwise unless angle is zero.
(define (rotate-pict-if-needed source angle)
  (if (zero? angle)
      source
      (rotate source angle)))
