#lang racket/base

;; SCENE-3D-P's smallest author-facing OpenGL backend smoke example.
;; It makes no spatial scene because P-0 is intentionally a context/FBO check.
;; Run it with GRacket; it writes a capability report to rendered-examples/.

(module+ main
  (dynamic-require "../../tools/opengl-info.rkt" #f))
