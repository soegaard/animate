#lang racket/base

;;;
;;; Renderer-Aware Layout Attachments
;;;

;; A layout-attached Visual is deliberately a small declarative wrapper rather
;; than a derived Visual.  Its target point is a renderer-measured box anchor,
;; which is only meaningful once a sampled scene, camera, and renderer list are
;; available.  The Pict adapter resolves the placement at that point; scene
;; state itself remains renderer-independent and therefore arbitrarily
;; sampleable.

(require "geometry.rkt"
         "visual-model.rkt")

(provide layout-attached-visual?
         layout-attached-visual-content
         layout-attached-visual-target
         layout-attached-visual-target-anchor
         layout-attached-visual-self-anchor
         layout-attached-visual-offset
         layout-attachment-anchor?
         make-layout-attached-visual)

(define layout-attachment-anchor-symbols
  '(bottom-left bottom bottom-right
                left center right
                top-left top top-right))

; layout-attachment-anchor? : any/c -> boolean?
;; Reports whether value names one of the nine shared rendered-box anchors.
(define (layout-attachment-anchor? value)
  (and (symbol? value)
       (memq value layout-attachment-anchor-symbols)))

(define attachment-content-id visual-id)
(define attachment-content-position visual-position)
(define attachment-content-with-position visual-with-position)

(struct layout-attached-visual-value
  (content target target-anchor self-anchor offset)
  #:transparent
  #:guard
  (lambda (content target target-anchor self-anchor offset who)
    (unless (visual? content)
      (raise-argument-error who "visual?" content))
    (unless (or (symbol? target)
                (and (list? target)
                     (pair? target)
                     (andmap symbol? target)))
      (raise-argument-error who "Visual ID or nonempty Visual path" target))
    (unless (layout-attachment-anchor? target-anchor)
      (raise-argument-error who "layout-attachment-anchor?" target-anchor))
    (unless (layout-attachment-anchor? self-anchor)
      (raise-argument-error who "layout-attachment-anchor?" self-anchor))
    (unless (vec2? offset)
      (raise-argument-error who "vec2?" offset))
    (values content target target-anchor self-anchor offset))
  #:methods gen:visual
  [(define (visual-id attachment)
     (attachment-content-id
      (layout-attached-visual-value-content attachment)))
   (define (visual-position attachment)
     (attachment-content-position
      (layout-attached-visual-value-content attachment)))
   (define (visual-with-position attachment position)
     (struct-copy
      layout-attached-visual-value
      attachment
      [content
       (attachment-content-with-position
        (layout-attached-visual-value-content attachment)
        position)]))])

; layout-attached-visual? : any/c -> boolean?
;; Reports whether value is a renderer-aware top-level attachment wrapper.
(define (layout-attached-visual? value)
  (layout-attached-visual-value? value))

; make-layout-attached-visual : visual? (or/c symbol? visual-path?)
;                               layout-attachment-anchor?
;                               layout-attachment-anchor? vec2?
;                               -> layout-attached-visual?
;; Internal constructor used by attach-to after public validation has selected
;; renderer-aware placement.
(define (make-layout-attached-visual content target target-anchor self-anchor offset)
  (layout-attached-visual-value
   content target target-anchor self-anchor offset))

;; Keep the concrete representation private while exporting the public
;; predicate/accessors above.
(define layout-attached-visual-content
  layout-attached-visual-value-content)
(define layout-attached-visual-target
  layout-attached-visual-value-target)
(define layout-attached-visual-target-anchor
  layout-attached-visual-value-target-anchor)
(define layout-attached-visual-self-anchor
  layout-attached-visual-value-self-anchor)
(define layout-attached-visual-offset
  layout-attached-visual-value-offset)
