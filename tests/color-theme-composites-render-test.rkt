#lang racket/base

;;;
;;; Themed Composite Rendering Tests
;;;

;; Exercises normal group recursion and affine composition.  The same authored
;; composite is rendered twice; only its palette-token appearance may differ.

(require racket/class
         rackunit
         "../colors.rkt"
         "../main.rkt")

(module+ test
  (define coral-palette
    (color-palette #:id 'composite-coral-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#d04040")))
  (define indigo-palette
    (color-palette #:id 'composite-indigo-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#4040d0")))
  (define coral-theme
    (color-theme #:id 'composite-coral-theme
                 #:extends animate-light-theme #:palette coral-palette))
  (define indigo-theme
    (color-theme #:id 'composite-indigo-theme
                 #:extends animate-light-theme #:palette indigo-palette))
  (define camera
    (make-camera #:width 100 #:height 80 #:world-width 5 #:background "white"))
  (define child
    (rectangle #:id 'composite-child #:width 1 #:height 1
               #:fill aqua-c #:stroke #f #:stroke-width 0))
  (define composite
    (group (list child) #:id 'composite))
  (define moved-composite
    (visual-with-position composite (vec2 1/2 0)))
  (define scene
    (scene-wait (scene-add (make-scene) moved-composite) 1))

  (define (bitmap-bytes bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)

  (define coral
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera #:theme coral-theme))
  (define indigo
    (scene-frame->bitmap scene 0 #:fps 1 #:camera camera #:theme indigo-theme))
  (check-not-equal? (bitmap-bytes coral) (bitmap-bytes indigo))
  (check-equal? (visual-id (scene-visual-at scene 'composite 0)) 'composite)
  (check-equal? (visual-position (scene-visual-at scene 'composite 0)) (vec2 1/2 0)))
