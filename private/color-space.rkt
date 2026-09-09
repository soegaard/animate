#lang racket/base

;;;
;;; Shared sRGB Colour Space Mathematics
;;;

;; The transfer functions live below both 2D colour expressions and 3D
;; rendering.  Channels use the normalized [0,1] representation here; public
;; rgba-color RGB fields continue to use [0,255].

(require "geometry.rkt")

(provide srgb-channel->linear
         linear-channel->srgb)


;; srgb-channel->linear : unit-real? -> unit-real?
;; Converts an IEC 61966-2-1 encoded sRGB channel to linear light.
(define (srgb-channel->linear channel)
  (check-unit-channel 'srgb-channel->linear channel)
  (cond [(<= channel 0.04045) (/ channel 12.92)]
        [else (expt (/ (+ channel 0.055) 1.055) 2.4)]))

;; linear-channel->srgb : unit-real? -> unit-real?
;; Converts an IEC 61966-2-1 linear-light channel to encoded sRGB.
(define (linear-channel->srgb channel)
  (check-unit-channel 'linear-channel->srgb channel)
  (cond [(<= channel 0.0031308) (* channel 12.92)]
        [else (- (* 1.055 (expt channel (/ 1.0 2.4))) 0.055)]))

(define (check-unit-channel who channel)
  (unless (and (finite-real? channel) (<= 0 channel 1))
    (raise-argument-error who "finite real in [0, 1]" channel)))
