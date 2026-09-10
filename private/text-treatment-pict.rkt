#lang racket/base

;; Renderer-side presentation of a resolved semantic text treatment.  Keeping
;; it separate from the scene/Pict adapter lets ordinary semantic text and a
;; temporary typewriter reveal share exactly the same stable box geometry.

(require racket/class
         (only-in pict blank cc-superimpose dc inset pict-height pict-width)
         (only-in racket/draw make-brush make-pen)
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "paint-pict.rkt"
         "render-color-context.rkt"
         "text-style.rkt")

(provide apply-text-treatment-to-pict
         text-treatment-content-pict
         text-treatment-decoration-pict)

;; Padding is measured from the resolved outer font size, in ems. These two
;; helpers intentionally separate text ink from its frame: a typewriter can
;; mask only ink while retaining one final-size background/border box.
(define (text-treatment-content-pict content treatment base-font-size camera)
  (if treatment
      (let-values ([(padding-x padding-y)
                    (text-treatment-padding-pixels treatment base-font-size camera)])
        (inset content padding-x padding-y))
      content))

(define (text-treatment-decoration-pict content treatment base-font-size camera)
  (cond
    [(not treatment) #f]
    [else
     (define padded
       (text-treatment-content-pict content treatment base-font-size camera))
     (define width (pict-width padded))
     (define height (pict-height padded))
     (define background (text-treatment-background treatment))
     (define border-color (text-treatment-border-color treatment))
     (define border-width (text-treatment-border-width treatment))
     ;; A color paired with width zero is explicitly no border, not a one-pixel
     ;; fallback. The requested positive width remains exact.
     (define draw-border? (and border-color (positive? border-width)))
     (if (and (not background) (not draw-border?))
         (blank width height)
         (dc
          (lambda (drawing-context x y)
            ;; `pict` requires a dc callback to restore its caller's mutable
            ;; drawing state. This matters for regular rendering and temporary
            ;; Picts used by text effects.
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
                (when draw-border?
                  (send drawing-context set-brush
                        (make-brush #:color "black" #:style 'transparent))
                  (send drawing-context set-pen
                        (make-pen #:color
                                  (paint->draw-color
                                   border-color
                                   (current-or-default-render-color-context))
                                  #:width border-width
                                  #:style 'solid))
                  ;; Keep the cosmetic pen inside the measured treatment box.
                  (define pen-inset (/ border-width 2))
                  (send drawing-context draw-rectangle
                        (+ x pen-inset) (+ y pen-inset)
                        (max 0 (- width (* 2 pen-inset)))
                        (max 0 (- height (* 2 pen-inset))))))
              (lambda ()
                (send drawing-context set-brush old-brush)
                (send drawing-context set-pen old-pen))))
          width height))]))

;; apply-text-treatment-to-pict : pict? (or/c #f text-treatment?) positive-real? camera?
;;                                 -> pict?
;; The caller chooses whether `content` is an unanchored built-in layout or a
;; custom renderer's declared logical Pict. In both cases decoration and ink
;; share exactly one padded box.
(define (apply-text-treatment-to-pict content treatment base-font-size camera)
  (if treatment
      (cc-superimpose
       (text-treatment-decoration-pict content treatment base-font-size camera)
       (text-treatment-content-pict content treatment base-font-size camera))
      content))

(define (text-treatment-padding-pixels treatment base-font-size camera)
  (values
   (camera-length->pixels
    camera
    (* base-font-size (text-treatment-padding-x treatment)))
   (camera-length->pixels
    camera
    (* base-font-size (text-treatment-padding-y treatment)))))
