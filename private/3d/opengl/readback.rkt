#lang racket/base

;;;
;;; OpenGL Readback Conversion
;;;

;; OpenGL returns bottom-up RGBA bytes.  Animate's renderer protocol promises
;; top-down straight-alpha ARGB bytes, exactly the order expected by racket/draw.

(require ffi/vector
         "../../color-style.rkt"
         "../color-space3d.rkt")

(provide gl-rgba-bottom-up->argb-top-down
         gl-linear-rgba-bottom-up->argb-top-down)

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

;; `rgba` has premultiplied linear RGB values in bottom-up GL order.  It is
;; straightened before applying the shared final output policy, then converted
;; into Animate's top-down straight-alpha ARGB byte representation.
(define (gl-linear-rgba-bottom-up->argb-top-down width height rgba tone-map)
  (unless (exact-positive-integer? width)
    (raise-argument-error 'gl-linear-rgba-bottom-up->argb-top-down
                          "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'gl-linear-rgba-bottom-up->argb-top-down
                          "exact-positive-integer?" height))
  (unless (and (f32vector? rgba) (= (f32vector-length rgba) (* 4 width height)))
    (raise-argument-error 'gl-linear-rgba-bottom-up->argb-top-down
                          "f32vector of linear RGBA samples matching dimensions" rgba))
  (unless (tone-map3d? tone-map)
    (raise-argument-error 'gl-linear-rgba-bottom-up->argb-top-down "tone-map3d?" tone-map))
  (define argb (make-bytes (* 4 width height)))
  (for* ([top-y (in-range height)] [x (in-range width)])
    (define source-index (* 4 (+ x (* (- height 1 top-y) width))))
    (define target-index (* 4 (+ x (* top-y width))))
    (define alpha (clamp-unit (f32vector-ref rgba (+ source-index 3))))
    (define (straight offset)
      (if (zero? alpha)
          0
          (max 0 (/ (f32vector-ref rgba (+ source-index offset)) alpha))))
    (define display
      (rgba-linear->srgb
       (tone-map3d-apply tone-map
                         (linear-rgba3d (straight 0) (straight 1) (straight 2) alpha))))
    (bytes-set! argb target-index (channel-byte (* 255 (rgba-color-alpha display))))
    (bytes-set! argb (+ target-index 1) (channel-byte (rgba-color-red display)))
    (bytes-set! argb (+ target-index 2) (channel-byte (rgba-color-green display)))
    (bytes-set! argb (+ target-index 3) (channel-byte (rgba-color-blue display))))
  (bytes->immutable-bytes argb))

(define (clamp-unit value)
  (min 1 (max 0 value)))

(define (channel-byte value)
  (inexact->exact (round (max 0 (min 255 value)))))
