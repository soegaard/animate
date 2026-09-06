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
  (for* ([top-y (in-range height)] [x (in-range width)])
    (define source (+ x (* (- height 1 top-y) width)))
    (define destination (+ x (* top-y width)))
    (define source-byte (* 4 source))
    (define destination-byte (* 4 destination))
    ;; Keep alpha straight: premultiplication belongs neither here nor in the
    ;; protocol result.  The existing Pict adapter makes the same assumption.
    (bytes-set! argb destination-byte (bytes-ref rgba (+ source-byte 3)))
    (bytes-set! argb (+ destination-byte 1) (bytes-ref rgba source-byte))
    (bytes-set! argb (+ destination-byte 2) (bytes-ref rgba (+ source-byte 1)))
    (bytes-set! argb (+ destination-byte 3) (bytes-ref rgba (+ source-byte 2))))
  (bytes->immutable-bytes argb))
