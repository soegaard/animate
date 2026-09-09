#lang racket/base

;; Pixel-space semantics are shared by the software rasterizer and OpenGL's
;; explicit stroke triangles.  Test the half-open viewport and centre samples
;; without a live context so any one-pixel drift is caught before CI probes.

(require rackunit
         "../private/geometry.rkt"
         "../private/3d/viewport3d.rkt")

(module+ test
  (check-equal? (ndc3d->screen (vec2 -1 1) 8 6) '(0 . 0))
  (check-equal? (ndc3d->screen (vec2 1 -1) 8 6) '(8 . 6))
  (check-equal? (ndc3d->screen (vec2 0 0) 8 6) '(4 . 3))
  (check-equal? (screen3d->ndc 0 0 8 6) '(-1 . 1))
  (check-equal? (screen3d->ndc 8 6 8 6) '(1 . -1))
  (check-equal? (pixel3d-center 0 0) '(1/2 . 1/2))
  (check-equal? (pixel3d-center 7 5) '(15/2 . 11/2)))
