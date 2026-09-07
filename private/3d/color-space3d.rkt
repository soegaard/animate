#lang racket/base

;;;
;;; Linear-light colour and output policy for the 3D renderers
;;;

;; `rgba-color` remains Animate's public, semantic sRGB colour value.  This
;; module deliberately uses a distinct internal value for linear light: its
;; RGB channels are unit-less, nonnegative radiometric values and may exceed
;; one before tone mapping.  Keeping the representations separate prevents an
;; accidental early clamp from silently discarding emitted or specular energy.

(require "../color-style.rkt"
         "../geometry.rkt")

(provide (struct-out linear-rgba3d)
         srgb-channel->linear
         linear-channel->srgb
         rgba-srgb->linear
         rgba-linear->srgb
         linear-rgba3d-over
         (struct-out tone-map3d)
         default-tone-map3d
         tone-map3d-apply)

(struct linear-rgba3d (red green blue alpha)
  #:transparent
  #:guard
  (lambda (red green blue alpha who)
    (for ([channel (in-list (list red green blue))]
          [name (in-list '(red green blue))])
      (unless (and (finite-real? channel) (>= channel 0))
        (raise-arguments-error who
                               "nonnegative finite linear RGB channels"
                               "channel" name
                               "value" channel)))
    (unless (and (finite-real? alpha) (<= 0 alpha 1))
      (raise-arguments-error who "a finite alpha in [0, 1]" "alpha" alpha))
    (values red green blue alpha)))

;; The IEC 61966-2-1 sRGB transfer curve.  Both public channel helpers use
;; normalized channels in [0,1]; semantic `rgba-color` values use [0,255] and
;; are converted by the two RGBA helpers below.
(define (srgb-channel->linear channel)
  (check-unit-channel 'srgb-channel->linear channel)
  (cond [(<= channel 0.04045) (/ channel 12.92)]
        [else (expt (/ (+ channel 0.055) 1.055) 2.4)]))

(define (linear-channel->srgb channel)
  (check-unit-channel 'linear-channel->srgb channel)
  (cond [(<= channel 0.0031308) (* channel 12.92)]
        [else (- (* 1.055 (expt channel (/ 1.0 2.4))) 0.055)]))

(define (rgba-srgb->linear color)
  (unless (rgba-color? color)
    (raise-argument-error 'rgba-srgb->linear "rgba-color?" color))
  (linear-rgba3d (srgb-channel->linear (/ (rgba-color-red color) 255.0))
                 (srgb-channel->linear (/ (rgba-color-green color) 255.0))
                 (srgb-channel->linear (/ (rgba-color-blue color) 255.0))
                 (rgba-color-alpha color)))

(define (rgba-linear->srgb color)
  (unless (linear-rgba3d? color)
    (raise-argument-error 'rgba-linear->srgb "linear-rgba3d?" color))
  ;; Conversion is intentionally strict.  Callers must tone-map before
  ;; storing a display colour, rather than hiding a policy choice here.
  (for ([channel (in-list (list (linear-rgba3d-red color)
                                (linear-rgba3d-green color)
                                (linear-rgba3d-blue color)))])
    (check-unit-channel 'rgba-linear->srgb channel))
  (rgba-color (* 255 (linear-channel->srgb (linear-rgba3d-red color)))
              (* 255 (linear-channel->srgb (linear-rgba3d-green color)))
              (* 255 (linear-channel->srgb (linear-rgba3d-blue color)))
              (linear-rgba3d-alpha color)))

;; Straight-alpha source-over in linear light.
(define (linear-rgba3d-over source destination)
  (unless (linear-rgba3d? source)
    (raise-argument-error 'linear-rgba3d-over "linear-rgba3d?" source))
  (unless (linear-rgba3d? destination)
    (raise-argument-error 'linear-rgba3d-over "linear-rgba3d?" destination))
  (define source-alpha (linear-rgba3d-alpha source))
  (define destination-alpha (linear-rgba3d-alpha destination))
  (define result-alpha (+ source-alpha (* (- 1 source-alpha) destination-alpha)))
  (define (channel source-channel destination-channel)
    (if (zero? result-alpha)
        0
        (/ (+ (* source-alpha source-channel)
              (* (- 1 source-alpha) destination-alpha destination-channel))
           result-alpha)))
  (linear-rgba3d (channel (linear-rgba3d-red source) (linear-rgba3d-red destination))
                 (channel (linear-rgba3d-green source) (linear-rgba3d-green destination))
                 (channel (linear-rgba3d-blue source) (linear-rgba3d-blue destination))
                 result-alpha))

;; The white point controls the shoulder for Reinhard mode: a value equal to
;; the white point maps to one half.  `clamp` deliberately ignores it; it is
;; retained in the immutable value so switching modes does not discard a
;; caller's configured tone-map intent.
(struct tone-map3d (mode exposure white-point)
  #:transparent
  #:guard
  (lambda (mode exposure white-point who)
    (unless (memq mode '(clamp reinhard))
      (raise-argument-error who "(or/c 'clamp 'reinhard)" mode))
    (unless (and (finite-real? exposure) (>= exposure 0))
      (raise-argument-error who "nonnegative finite exposure" exposure))
    (unless (and (finite-real? white-point) (positive? white-point))
      (raise-argument-error who "positive finite white point" white-point))
    (values mode exposure white-point)))

(define default-tone-map3d (tone-map3d 'clamp 1 1))

(define (tone-map3d-apply policy color)
  (unless (tone-map3d? policy)
    (raise-argument-error 'tone-map3d-apply "tone-map3d?" policy))
  (unless (linear-rgba3d? color)
    (raise-argument-error 'tone-map3d-apply "linear-rgba3d?" color))
  (define (map-channel channel)
    (define exposed (* (tone-map3d-exposure policy) channel))
    (case (tone-map3d-mode policy)
      [(clamp) (min 1 exposed)]
      [(reinhard) (/ exposed (+ exposed (tone-map3d-white-point policy)))]))
  (linear-rgba3d (map-channel (linear-rgba3d-red color))
                 (map-channel (linear-rgba3d-green color))
                 (map-channel (linear-rgba3d-blue color))
                 (linear-rgba3d-alpha color)))

(define (check-unit-channel who channel)
  (unless (and (finite-real? channel) (<= 0 channel 1))
    (raise-argument-error who "finite real in [0, 1]" channel)))
