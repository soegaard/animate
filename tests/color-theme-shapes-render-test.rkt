#lang racket/base

;;;
;;; Themed 2D Shape Rendering Tests
;;;

;; Verifies that primitive fills, strokes, and structured paints retain their
;; authored tokens until the explicit scene/frame rendering boundary selects a
;; theme.  Pixel assertions sample opaque interiors rather than antialiased
;; edges.

(require racket/class
         rackunit
         "../colors.rkt"
         "../main.rkt"
         "../render.rkt"
         "../private/geometry.rkt"
         "../private/paint.rkt")

(module+ test
  (define warm-palette
    (color-palette #:id 'theme-render-warm-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#e02020"
                                  'red-c "#20a0e0")))
  (define cool-palette
    (color-palette #:id 'theme-render-cool-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#2060e0"
                                  'red-c "#e0a020")))
  (define warm-theme
    (color-theme #:id 'theme-render-warm
                 #:extends animate-light-theme
                 #:palette warm-palette))
  (define cool-theme
    (color-theme #:id 'theme-render-cool
                 #:extends animate-light-theme
                 #:palette cool-palette))

  (define test-camera
    (make-camera #:width 80 #:height 80 #:world-width 4 #:background "white"))

  ;; argb-at : bitmap% exact-nonnegative-integer? exact-nonnegative-integer?
  ;;           -> (list/c byte? byte? byte? byte?)
  ;; Reads one pixel in the backend's documented alpha-red-green-blue order.
  (define (argb-at bitmap x y)
    (define pixels (make-bytes 4))
    (send bitmap get-argb-pixels x y 1 1 pixels)
    (bytes->list pixels))

  (define token-circle
    (circle #:id 'token-circle
            #:radius 3/4
            #:fill aqua-c
            #:stroke pure-blue
            #:stroke-width 2))
  (define literal-circle
    (circle #:id 'literal-circle
            #:center (vec2 -3/2 0)
            #:radius 1/4
            #:fill pure-blue
            #:stroke #f
            #:stroke-width 0))
  (define token-gradient
    (rectangle #:id 'token-gradient
               #:center (vec2 3/2 0)
               #:width 1
               #:height 1
               #:fill
               (linear-gradient (vec2 -1/2 0) (vec2 1/2 0)
                                (list (paint-stop 0 aqua-c)
                                      (paint-stop 1 red-c)))
               #:stroke #f
               #:stroke-width 0))
  (define themed-scene
    (scene-wait
     (scene-add (make-scene) token-circle literal-circle token-gradient)
     1))

  (define warm-bitmap
    (scene-frame->bitmap themed-scene 0 #:fps 1 #:camera test-camera
                         #:theme warm-theme))
  (define cool-bitmap
    (scene-frame->bitmap themed-scene 0 #:fps 1 #:camera test-camera
                         #:theme cool-theme))

  ;; The token-filled circle changes with the selected explicit theme, while
  ;; the physically literal branding swatch is untouched.
  (check-equal? (argb-at warm-bitmap 40 40) '(255 224 32 32))
  (check-equal? (argb-at cool-bitmap 40 40) '(255 32 96 224))
  (check-equal? (argb-at warm-bitmap 10 40) '(255 0 0 255))
  (check-equal? (argb-at cool-bitmap 10 40) '(255 0 0 255))

  ;; Gradient stop tokens use the same context and differ under the two
  ;; palettes. The sample is well inside the rectangle, away from its border.
  (check-not-equal? (argb-at warm-bitmap 67 40)
                    (argb-at cool-bitmap 67 40)))
