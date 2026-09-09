#lang racket/base

;;;
;;; Themed Text Rendering Tests
;;;

;; A text raster contains resolved pixels, so it must be keyed by the selected
;; theme appearance. This covers both ordinary and inline rich-text colors.

(require racket/class
         rackunit
         "../colors.rkt"
         "../main.rkt")

(module+ test
  (define amber-palette
    (color-palette #:id 'text-amber-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#d08020")))
  (define violet-palette
    (color-palette #:id 'text-violet-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#6020d0")))
  (define amber-theme
    (color-theme #:id 'text-amber-theme
                 #:extends animate-light-theme #:palette amber-palette))
  (define violet-theme
    (color-theme #:id 'text-violet-theme
                 #:extends animate-light-theme #:palette violet-palette))
  (define camera
    (make-camera #:width 180 #:height 80 #:world-width 9 #:background "white"))
  (define caption
    (rich-text #:id 'themed-caption #:font-size 3/5
               (text-span "theme " #:color aqua-c)
               (text-span "literal" #:color pure-blue)))
  (define scene (scene-wait (scene-add (make-scene) caption) 1))

  (define (bitmap-bytes bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)

  (define amber
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera #:theme amber-theme))
  (define violet
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera #:theme violet-theme))
  (check-not-equal? (bitmap-bytes amber) (bitmap-bytes violet))
  (check-equal? (visual-id (scene-visual-at scene 'themed-caption 0))
                'themed-caption)
  (check-equal? (text-visual-content (scene-visual-at scene 'themed-caption 0))
                "theme literal"))
