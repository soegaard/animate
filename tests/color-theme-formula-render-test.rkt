#lang racket/base

;;;
;;; Themed Formula Appearance Tests
;;;

;; Uses a deterministic injected formula Pict rather than an external TeX
;; process. The test isolates the common formula tint boundary and its
;; theme-aware appearance cache key.

(require racket/class
         rackunit
         (only-in pict filled-rectangle pict->bitmap)
         (only-in "../private/latex-formula-pict-renderer.rkt"
                  formula-visual-base-pict->pict)
         "../colors.rkt"
         "../main.rkt")

(module+ test
  (define gold-palette
    (color-palette #:id 'formula-gold-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#d0a020")))
  (define purple-palette
    (color-palette #:id 'formula-purple-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#7020d0")))
  (define gold-theme
    (color-theme #:id 'formula-gold-theme
                 #:extends animate-light-theme #:palette gold-palette))
  (define purple-theme
    (color-theme #:id 'formula-purple-theme
                 #:extends animate-light-theme #:palette purple-palette))
  (define camera
    (make-camera #:width 100 #:height 80 #:world-width 5))
  (define base
    (formula-assembly
     (list (latex-formula-part "x" #:name 'x))
     #:id 'formula-assembly))
  (define styled
    (formula-part-formula
     (formula-assembly-visual-ref (formula-color base 'x aqua-c) 'x)))

  (struct fake-formula-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render _renderer visual current-camera)
       (formula-visual-base-pict->pict
        visual current-camera
        (filled-rectangle 20 20 #:draw-border? #f)))])

  (define (center-argb source)
    (define bitmap (pict->bitmap source))
    (define pixels (make-bytes 4))
    (send bitmap get-argb-pixels
          (quotient (send bitmap get-width) 2)
          (quotient (send bitmap get-height) 2)
          1 1 pixels)
    (bytes->list pixels))

  (define renderers (list (fake-formula-renderer)))
  (check-equal? (center-argb (visual->pict styled camera #:renderers renderers
                                           #:theme gold-theme))
                '(255 208 160 32))
  (check-equal? (center-argb (visual->pict styled camera #:renderers renderers
                                           #:theme purple-theme))
                '(255 112 32 208))
  ;; The semantic source and part identity are stable across render choices.
  (check-equal? (formula-visual-source styled) "x")
  (check-equal? (visual-id styled) 'x))
