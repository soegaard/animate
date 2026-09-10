#lang racket/base

;; Renderer-side presentation of a resolved semantic text treatment.  Keeping
;; it separate from the scene/Pict adapter lets ordinary semantic text and a
;; temporary typewriter reveal share exactly the same stable box geometry.

(require racket/class
         (only-in pict blank cc-superimpose dc inset pict-ascent pict-descent pict-height pict-width)
         (only-in racket/draw make-brush make-pen)
         "camera.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "paint-pict.rkt"
         "render-color-context.rkt"
         "text-style.rkt")

(provide apply-text-treatment-to-pict
         text-treatment-content-pict
         text-treatment-decoration-pict
         text-treatment-cosmetic-border-pict)

;; Padding is measured from the resolved outer font size, in ems. These two
;; helpers intentionally separate text ink from its frame: a typewriter can
;; mask only ink while retaining one final-size background/border box.
(define (text-treatment-content-pict content treatment base-font-size camera)
  (if treatment
      (let-values ([(padding-x padding-y)
                    (text-treatment-padding-pixels treatment base-font-size camera)])
        (inset content padding-x padding-y))
      content))

(define (text-treatment-decoration-pict content treatment base-font-size camera
                                        #:horizontal-alignment [horizontal-alignment 'center]
                                        #:vertical-alignment [vertical-alignment 'center]
                                        #:include-border? [include-border? #t])
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
     (define draw-border? (and include-border? border-color (positive? border-width)))
     ;; Decoration is geometry around the padded text, not a second text run.
     ;; Preserve the padded text metrics so a `dc`'s default bottom baseline
     ;; cannot move a semantic baseline anchor.
     (define ascent (pict-ascent padded))
     (define descent (pict-descent padded))
     ;; General Paint coordinates are local to the receiving Visual: the text
     ;; anchor is (0,0), +x points right, and +y points up.  The treatment box
     ;; is drawn in Pict coordinates, where y points down, so pass that
     ;; conversion explicitly rather than treating its top-left as a new paint
     ;; origin.
     (define anchor-x
       (case horizontal-alignment
         [(left) 0]
         [(center) (/ width 2)]
         [(right) width]))
     (define anchor-y
       (case vertical-alignment
         [(top) 0]
         [(center) (/ height 2)]
         [(baseline) ascent]
         [(bottom) height]))
     (define (paint-point->pict point x y)
       (vec2 (+ x anchor-x
                (camera-length->pixels camera (vec2-x point)))
             (+ y anchor-y
                (camera-length->pixels camera (- (vec2-y point))))))
     (if (and (not background) (not draw-border?))
         (blank width height ascent descent)
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
                           (paint-point->pict point x y))))
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
          width height ascent descent))]))

;; apply-text-treatment-to-pict : pict? (or/c #f text-treatment?) positive-real? camera?
;;                                 -> pict?
;; The caller chooses whether `content` is an unanchored built-in layout or a
;; custom renderer's declared logical Pict. In both cases decoration and ink
;; share exactly one padded box.
(define (apply-text-treatment-to-pict content treatment base-font-size camera
                                      #:horizontal-alignment [horizontal-alignment 'center]
                                      #:vertical-alignment [vertical-alignment 'center]
                                      #:include-border? [include-border? #t])
  (if treatment
      (cc-superimpose
       (text-treatment-decoration-pict content treatment base-font-size camera
                                       #:horizontal-alignment horizontal-alignment
                                       #:vertical-alignment vertical-alignment
                                       #:include-border? include-border?)
       (text-treatment-content-pict content treatment base-font-size camera))
      content))

;; text-treatment-cosmetic-border-pict : pict? pict? text-treatment? vec2?
;;                                        alignment alignment -> (or/c #f pict?)
;; Draws the treatment outline after semantic scale, but before rotation.  The
;; box itself, its background, padding, and ink are local geometry; the border
;; is a cosmetic device-width pen and therefore must not be part of the Pict
;; that receives a nonuniform scale.
(define (text-treatment-cosmetic-border-pict anchored-scaled source treatment scale
                                              horizontal-alignment vertical-alignment)
  (cond [(or (not treatment)
             (not (text-treatment-border-color treatment))
             (not (positive? (text-treatment-border-width treatment))))
         #f]
        [else
         (define source-width (pict-width source))
         (define source-height (pict-height source))
         (define source-ascent (pict-ascent source))
         (define source-descent (pict-descent source))
         (define x-scale (vec2-x scale))
         (define y-scale (vec2-y scale))
         ;; These are the source offsets chosen by anchor-pict before scale.
         (define source-x
           (case horizontal-alignment
             [(left) source-width]
             [(center right) 0]))
         (define source-y
           (case vertical-alignment
             [(top) source-height]
             [(center bottom) 0]
             [(baseline) (- (max source-ascent source-descent) source-ascent)]))
         (define border-width (text-treatment-border-width treatment))
         (define border-color (text-treatment-border-color treatment))
         (define full-width (pict-width anchored-scaled))
         (define full-height (pict-height anchored-scaled))
         (define source-left (* source-x x-scale))
         (define source-top (* source-y y-scale))
         (define source-scaled-width (* source-width x-scale))
         (define source-scaled-height (* source-height y-scale))
         (dc
          (lambda (drawing-context x y)
            (define old-brush (send drawing-context get-brush))
            (define old-pen (send drawing-context get-pen))
            (dynamic-wind
              void
              (lambda ()
                (send drawing-context set-brush
                      (make-brush #:color "black" #:style 'transparent))
                (send drawing-context set-pen
                      (make-pen #:color
                                (paint->draw-color
                                 border-color
                                 (current-or-default-render-color-context))
                                #:width border-width #:style 'solid))
                (define inset (/ border-width 2))
                (send drawing-context draw-rectangle
                      (+ x source-left inset) (+ y source-top inset)
                      (max 0 (- source-scaled-width (* 2 inset)))
                      (max 0 (- source-scaled-height (* 2 inset)))))
              (lambda ()
                (send drawing-context set-brush old-brush)
                (send drawing-context set-pen old-pen))))
          full-width full-height
          (pict-ascent anchored-scaled)
          (pict-descent anchored-scaled))]))

(define (text-treatment-padding-pixels treatment base-font-size camera)
  (values
   (camera-length->pixels
    camera
    (* base-font-size (text-treatment-padding-x treatment)))
   (camera-length->pixels
    camera
    (* base-font-size (text-treatment-padding-y treatment)))))
