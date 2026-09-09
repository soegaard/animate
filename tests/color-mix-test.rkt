#lang racket/base

;;;
;;; Color Mix Tests
;;;

;; Confirms that declarations retain endpoints and that explicit resolution
;; distinguishes encoded-sRGB from the default linear-light interpolation.

(require rackunit
         "../colors.rkt")

(module+ test
  (define encoded (color-mix black white 1/2 #:space 'srgb))
  (define linear (color-mix black white 1/2 #:space 'srgb-linear))
  (define encoded-result (resolve-color encoded animate-light-theme))
  (define linear-result (resolve-color linear animate-light-theme))
  (check-= (rgba-color-red encoded-result) 127.5 1e-10)
  (check-= (rgba-color-red linear-result) 187.51603067837462 1e-10)
  (check-true (> (rgba-color-red linear-result)
                  (rgba-color-red encoded-result)))
  (check-eq? (color-mix aqua-c red-c 0) aqua-c)
  (check-eq? (color-mix aqua-c red-c 1) red-c)

  ;; Premultiplied interpolation prevents a transparent black endpoint from
  ;; darkening the surviving red contribution.
  (define premultiplied
    (resolve-color
     (color-mix pure-red (rgba-color 0 0 0 0) 1/2)
     animate-light-theme))
  (check-= (rgba-color-red premultiplied) 255 1e-10)
  (check-= (rgba-color-alpha premultiplied) 1/2 1e-10)
  (define straight
    (resolve-color
     (color-mix pure-red (rgba-color 0 0 0 0) 1/2
                #:space 'srgb #:alpha-mode 'straight)
     animate-light-theme))
  (check-= (rgba-color-red straight) 127.5 1e-10)
  (check-= (rgba-color-alpha straight) 1/2 1e-10))
