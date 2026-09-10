#lang racket/base

;; Renderer-side presentation of a resolved semantic text treatment.  Keeping
;; it separate from the scene/Pict adapter lets ordinary semantic text and a
;; temporary typewriter reveal share exactly the same stable box geometry.

(require racket/class
         (only-in pict cc-superimpose dc inset pict-height pict-width)
         (only-in racket/draw make-brush make-pen)
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "paint-pict.rkt"
         "render-color-context.rkt"
         "text-style.rkt")

(provide apply-text-treatment-to-pict)

;; apply-text-treatment-to-pict : pict? (or/c #f text-treatment?) positive-real? camera?
;;                                 -> pict?
;; Padding is measured from the resolved outer font size, in ems.  The input
;; Pict is already symmetrically anchored around the semantic text reference
;; point; symmetric inset therefore preserves that reference point for every
;; horizontal and vertical text anchor, including baseline.
(define (apply-text-treatment-to-pict content treatment base-font-size camera)
  (cond
    [(not treatment) content]
    [else
     (define padding-x
       (camera-length->pixels
        camera
        (* base-font-size (text-treatment-padding-x treatment))))
     (define padding-y
       (camera-length->pixels
        camera
        (* base-font-size (text-treatment-padding-y treatment))))
     (define padded (inset content padding-x padding-y))
     (define width (pict-width padded))
     (define height (pict-height padded))
     (define background (text-treatment-background treatment))
     (define border-color (text-treatment-border-color treatment))
     (define border-width (text-treatment-border-width treatment))
     (if (and (not background) (not border-color))
         padded
         (let ([decoration
                (dc
                 (lambda (drawing-context x y)
                   ;; `pict` requires a dc callback to restore its caller's
                   ;; mutable drawing state.  This matters for both regular
                   ;; rendering and the temporary Picts used by text effects.
                   (define old-brush (send drawing-context get-brush))
                   (define old-pen (send drawing-context get-pen))
                   (dynamic-wind
                     void
                     (lambda ()
                       (when background
                         (send drawing-context set-brush
                               (make-paint-brush
                                background
                                (lambda (point)
                                  (vec2 (+ x (camera-length->pixels camera (vec2-x point)))
                                        (+ y (camera-length->pixels camera (vec2-y point)))))))
                         (send drawing-context set-pen
                               (make-pen #:color "black" #:style 'transparent))
                         (send drawing-context draw-rectangle x y width height))
                       (when border-color
                         (send drawing-context set-brush
                               (make-brush #:color "black" #:style 'transparent))
                         (send drawing-context set-pen
                               (make-pen #:color
                                         (if (color-spec? border-color)
                                             (paint->draw-color
                                              border-color
                                              (current-or-default-render-color-context))
                                             border-color)
                                         #:width (max 1 border-width)
                                         #:style 'solid))
                         ;; Keep the cosmetic pen entirely inside the Pict
                         ;; extent. Its half-width is included in the final
                         ;; measured treatment box rather than being clipped.
                         (define inset-x (/ (max 1 border-width) 2))
                         (send drawing-context draw-rectangle
                               (+ x inset-x) (+ y inset-x)
                               (max 0 (- width (* 2 inset-x)))
                               (max 0 (- height (* 2 inset-x))))))
                     (lambda ()
                       (send drawing-context set-brush old-brush)
                       (send drawing-context set-pen old-pen))))
                 width height)])
           (cc-superimpose decoration padded)))]))
