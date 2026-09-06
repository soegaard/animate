#lang racket/base

(require rackunit
         "../private/3d/opengl/readback.rkt")

(module+ test
  ;; OpenGL's first row is the visual bottom. The GL target is premultiplied
  ;; RGBA: bottom-left red, bottom-right 50%-alpha green, top-left 25%-alpha
  ;; blue, and a canonical transparent top-right pixel.
  (define rgba
    (bytes 255 0 0 255
           0 128 0 128
           0 0 64 64
           0 0 0 0))
  (check-equal?
   (gl-rgba-bottom-up->argb-top-down 2 2 rgba)
   ;; top-left blue, transparent black, then bottom row, all as straight ARGB
   (bytes 64 0 0 255
          0 0 0 0
          255 255 0 0
          128 0 255 0))
  (check-true (immutable? (gl-rgba-bottom-up->argb-top-down 1 1 (bytes 1 2 3 4))))
  (check-exn exn:fail:contract?
             (lambda () (gl-rgba-bottom-up->argb-top-down 2 2 (bytes 1)))))
