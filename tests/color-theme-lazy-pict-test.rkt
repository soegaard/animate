#lang racket/base

;;;
;;; Themed Lazy Pict Tests
;;;

;; A Pict callback may run after its construction call returns.  The adapter
;; must retain the selected immutable context instead of consulting a later
;; render operation's theme.

(require racket/class
         rackunit
         (only-in pict pict->bitmap)
         "../colors.rkt"
         "../main.rkt")

(module+ test
  (define first-palette
    (color-palette #:id 'lazy-first-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#c02020")))
  (define second-palette
    (color-palette #:id 'lazy-second-palette
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#2020c0")))
  (define first-theme
    (color-theme #:id 'lazy-first-theme
                 #:extends animate-light-theme
                 #:palette first-palette))
  (define second-theme
    (color-theme #:id 'lazy-second-theme
                 #:extends animate-light-theme
                 #:palette second-palette))
  (define camera
    (make-camera #:width 80 #:height 80 #:world-width 4))
  (define visual
    (circle #:id 'lazy-token-circle
            #:radius 1
            #:fill aqua-c
            #:stroke #f
            #:stroke-width 0))

  (define (center-argb source)
    (define bitmap (pict->bitmap source))
    (define pixels (make-bytes 4))
    (send bitmap get-argb-pixels
          (quotient (send bitmap get-width) 2)
          (quotient (send bitmap get-height) 2)
          1 1 pixels)
    (bytes->list pixels))

  (define first-pict (visual->pict visual camera #:theme first-theme))
  (define second-pict (visual->pict visual camera #:theme second-theme))

  ;; Draw the second Pict first. Its callback must not overwrite the context
  ;; captured in the first Pict.
  (check-equal? (center-argb second-pict) '(255 32 32 192))
  (check-equal? (center-argb first-pict) '(255 192 32 32)))
