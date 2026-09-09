#lang racket/base

;;;
;;; Color Palette Ramp Tests
;;;

;; Checks that the frozen numerical ramps preserve their documented light-to-
;; dark ordering and that the yellow/pink/peach slots remain distinct swatches.

(require racket/list
         rackunit
         "../colors.rkt")

(define (relative-lightness color)
  (+ (* 0.2126 (channel->linear (/ (rgba-color-red color) 255.0)))
     (* 0.7152 (channel->linear (/ (rgba-color-green color) 255.0)))
     (* 0.0722 (channel->linear (/ (rgba-color-blue color) 255.0)))))

(define (channel->linear channel)
  (if (<= channel 0.04045)
      (/ channel 12.92)
      (expt (/ (+ channel 0.055) 1.055) 2.4)))

(module+ test
  (for ([group (in-list (take (palette-groups animate-palette) 9))])
    (define ramp (map (lambda (key) (palette-ref animate-palette key)) (cadr group)))
    (for ([first (in-list ramp)] [second (in-list (cdr ramp))])
      (check-true (> (relative-lightness first) (relative-lightness second))
                  (format "~a must decrease from a through e" (car group)))))
  (check-false (equal? (palette-ref animate-palette 'yellow-c)
                       (palette-ref animate-palette 'green-c)))
  (check-false (equal? (palette-ref animate-palette 'pink)
                       (palette-ref animate-palette 'peach)))
  (check-equal? (palette-ref animate-palette 'aqua-c)
                (rgb-color #x19 #xC5 #xCE)))
