#lang racket/base

;;;
;;; Color Space Tests
;;;

(require rackunit
         "../private/color-space.rkt"
         (prefix-in three: "../private/3d/color-space3d.rkt"))

(module+ test
  (check-= (srgb-channel->linear 0.04045) 0.0031308049535603713 1e-15)
  (check-= (linear-channel->srgb 0.0031308) 0.040449936 1e-12)
  ;; The 3D facade and common pure color module intentionally expose the same
  ;; transfer functions rather than independent approximations.
  (check-= (three:srgb-channel->linear 1/2)
           (srgb-channel->linear 1/2)
           1e-15)
  (check-= (three:linear-channel->srgb 1/2)
           (linear-channel->srgb 1/2)
           1e-15)
  (for ([value (in-list (list -1/10 11/10 +inf.0 -inf.0 +nan.0))])
    (check-exn exn:fail:contract? (lambda () (srgb-channel->linear value)))
    (check-exn exn:fail:contract? (lambda () (linear-channel->srgb value)))))
