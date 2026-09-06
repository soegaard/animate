#lang racket/base

;;; Immutable Software-render Diagnostics

(provide (struct-out software-render-diagnostics))

(struct software-render-diagnostics
  (command-count source-triangle-count clipped-triangle-count raster-triangle-count pixel-count)
  #:transparent)
