#lang racket/base

;;;
;;; OpenGL Readback Conversion
;;;

;; OpenGL returns bottom-up RGBA bytes.  Animate's renderer protocol promises
;; top-down straight-alpha ARGB bytes, exactly the order expected by racket/draw.

(provide gl-rgba-bottom-up->argb-top-down)

; gl-rgba-bottom-up->argb-top-down : exact-positive-integer? exact-positive-integer?
;                                     bytes? -> immutable-bytes?
(define (gl-rgba-bottom-up->argb-top-down width height rgba)
  (unless (exact-positive-integer? width)
    (raise-argument-error 'gl-rgba-bottom-up->argb-top-down "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'gl-rgba-bottom-up->argb-top-down "exact-positive-integer?" height))
  (unless (and (bytes? rgba) (= (bytes-length rgba) (* 4 width height)))
    (raise-argument-error 'gl-rgba-bottom-up->argb-top-down
                          "RGBA bytes matching the declared dimensions" rgba))
  (define argb (make-bytes (bytes-length rgba)))
  (define row-bytes (* 4 width))
  ;; First flip rows as blocks. Channel conversion and unpremultiplication then
  ;; happen in one linear pass rather than repeatedly calculating pixel rows.
  (for ([top-y (in-range height)])
    (bytes-copy! argb (* top-y row-bytes) rgba (* (- height 1 top-y) row-bytes)
                 (* (- height top-y) row-bytes)))
  (for ([index (in-range 0 (bytes-length argb) 4)])
    (define red (bytes-ref argb index))
    (define green (bytes-ref argb (+ index 1)))
    (define blue (bytes-ref argb (+ index 2)))
    (define alpha (bytes-ref argb (+ index 3)))
    ;; OpenGL's internal target is premultiplied RGBA; the public protocol is
    ;; straight top-down ARGB. Zero-alpha pixels deliberately canonicalise RGB.
    (define (straight channel)
      (if (zero? alpha) 0
          (min 255 (inexact->exact (round (* 255 (/ channel alpha)))))))
    (bytes-set! argb index alpha)
    (bytes-set! argb (+ index 1) (straight red))
    (bytes-set! argb (+ index 2) (straight green))
    (bytes-set! argb (+ index 3) (straight blue)))
  (bytes->immutable-bytes argb))
