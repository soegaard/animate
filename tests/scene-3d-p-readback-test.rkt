#lang racket/base

(require rackunit
         "../private/3d/opengl/readback.rkt")

(module+ test
  ;; OpenGL's first row is the visual bottom.  The colours below are
  ;; bottom-left red, bottom-right green, top-left blue, top-right white.
  (define rgba
    (bytes 255 0 0 255
           0 255 0 128
           0 0 255 64
           255 255 255 0))
  (check-equal?
   (gl-rgba-bottom-up->argb-top-down 2 2 rgba)
   ;; top-left blue, top-right white, then bottom row, all as straight ARGB
   (bytes 64 0 0 255
          0 255 255 255
          255 255 0 0
          128 0 255 0))
  (check-true (immutable? (gl-rgba-bottom-up->argb-top-down 1 1 (bytes 1 2 3 4))))
  (check-exn exn:fail:contract?
             (lambda () (gl-rgba-bottom-up->argb-top-down 2 2 (bytes 1)))))
