#lang racket/base

;;;
;;; Oklab Color Tests
;;;

;; The red vector is from the Oklab reference implementation published by
;; Björn Ottosson.  It protects the matrix constants independently from a
;; theme, renderer, or RGBA storage convention.

(require rackunit
         "../colors.rkt"
         "../private/oklab.rkt")

(module+ test
  (define red-lab (linear-rgb->oklab '(1 0 0)))
  (check-= (car red-lab) 0.6279553606 1e-9)
  (check-= (cadr red-lab) 0.2248630611 1e-9)
  (check-= (caddr red-lab) 0.1258462985 1e-9)
  (define red-round-trip (oklab->linear-rgb red-lab))
  (check-= (car red-round-trip) 1 1e-7)
  (check-= (cadr red-round-trip) 0 1e-7)
  (check-= (caddr red-round-trip) 0 1e-7)

  ;; Gamut reduction never emits an out-of-range sRGB channel.
  (for ([channel (in-list (oklab->gamut-mapped-linear-rgb '(0.6 0.4 0.2)))])
    (check-true (<= 0 channel 1)))

  ;; Oklab is a declared mix policy, not an alias for encoded sRGB.
  (define oklab (color-mix pure-red pure-blue 1/2 #:space 'oklab))
  (define encoded (color-mix pure-red pure-blue 1/2 #:space 'srgb))
  (check-true (rgba-color? oklab))
  (check-not-equal? oklab encoded)
  (check-not-exn
   (lambda ()
     (resolve-color (color-mix aqua-c red-c 1/2 #:space 'oklab)
                    animate-light-theme))))
