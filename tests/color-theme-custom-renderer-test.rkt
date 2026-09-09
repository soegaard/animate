#lang racket/base

;;;
;;; Themed Custom Renderer Tests
;;;

;; The public render-color->draw-color helper lets custom Pict renderers use
;; the context selected by the high-level render operation without any mutable
;; process-wide theme lookup.

(require racket/class
         rackunit
         (only-in pict filled-rectangle)
         "../colors.rkt"
         "../main.rkt"
         "../render.rkt")

(module+ test
  (struct swatch-visual (id center)
    #:transparent
    #:methods gen:visual
    [(define (visual-id value) (swatch-visual-id value))
     (define (visual-position value) (swatch-visual-center value))
     (define (visual-with-position value position)
       (struct-copy swatch-visual value [center position]))])

  (struct swatch-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (swatch-visual? visual))
     (define (pict-renderer-render _renderer _visual camera)
       (define side (camera-length->pixels camera 1))
       (filled-rectangle side side #:draw-border? #f
                         #:color (render-color->draw-color aqua-c)))])

  (define orange-palette
    (color-palette #:id 'custom-orange-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#e07020")))
  (define green-palette
    (color-palette #:id 'custom-green-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#20b060")))
  (define orange-theme
    (color-theme #:id 'custom-orange-theme
                 #:extends animate-light-theme #:palette orange-palette))
  (define green-theme
    (color-theme #:id 'custom-green-theme
                 #:extends animate-light-theme #:palette green-palette))
  (define camera
    (make-camera #:width 80 #:height 80 #:world-width 4 #:background "white"))
  (define swatch (swatch-visual 'custom-swatch origin))
  (define scene (scene-wait (scene-add (make-scene) swatch) 1))
  (define renderers (cons (swatch-renderer) default-pict-renderers))

  (define (center-argb bitmap)
    (define pixels (make-bytes 4))
    (send bitmap get-argb-pixels 40 40 1 1 pixels)
    (bytes->list pixels))

  (check-equal?
   (center-argb
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera
                         #:renderers renderers #:theme orange-theme))
   '(255 224 112 32))
  (check-equal?
   (center-argb
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera
                         #:renderers renderers #:theme green-theme))
   '(255 32 176 96)))
