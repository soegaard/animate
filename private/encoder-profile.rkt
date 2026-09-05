#lang racket/base

;;;
;;; Encoder Profile Names
;;;

;; Maps Animate's portable encoder vocabulary to the concrete FFmpeg encoder
;; names used both by execution and by preflight capability checks.

(provide encoder-codec-name)

(define (encoder-codec-name codec)
  (case codec
    [(h264) "libx264"]
    [(hevc) "libx265"]
    [(vp9) "libvpx-vp9"]
    [(prores) "prores_ks"]
    [else (symbol->string codec)]))
