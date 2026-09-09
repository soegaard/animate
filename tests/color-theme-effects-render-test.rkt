#lang racket/base

;;;
;;; Themed Temporary Effect Rendering Tests
;;;

;; Typewriter's revealed text and cursor are renderer-facing temporary
;; presentations. Both retain semantic colors until their selected frame is
;; painted.

(require racket/class
         rackunit
         "../colors.rkt"
         "../main.rkt")

(module+ test
  (define red-palette
    (color-palette #:id 'effect-red-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#d02020")))
  (define blue-palette
    (color-palette #:id 'effect-blue-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#2020d0")))
  (define red-theme
    (color-theme #:id 'effect-red-theme
                 #:extends animate-light-theme #:palette red-palette))
  (define blue-theme
    (color-theme #:id 'effect-blue-theme
                 #:extends animate-light-theme #:palette blue-palette))
  (define camera
    (make-camera #:width 180 #:height 80 #:world-width 9 #:background "white"))
  (define caption
    (plain-text "theme" #:id 'effect-caption #:font-size 3/5 #:color aqua-c))
  (define scene
    (scene-play (make-scene)
                (typewrite caption #:cursor? #t #:cursor-style aqua-c)
                #:duration 2))

  (define (bitmap-bytes bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)

  (define red-frame
    (scene-frame->bitmap scene 1 #:fps 2 #:camera camera #:theme red-theme))
  (define blue-frame
    (scene-frame->bitmap scene 1 #:fps 2 #:camera camera #:theme blue-theme))
  (check-not-equal? (bitmap-bytes red-frame) (bitmap-bytes blue-frame))
  (check-equal? (visual-id (scene-visual-at scene 'effect-caption 1/2))
                'effect-caption))
