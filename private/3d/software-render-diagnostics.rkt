#lang racket/base

;;; Immutable Software-render Diagnostics

(provide (struct-out software-render-diagnostics))

(struct software-render-diagnostics
  (command-count source-triangle-count clipped-triangle-count raster-triangle-count pixel-count
                 stroke-command-count source-stroke-segment-count dash-segment-count
                 stroke-triangle-count visible-stroke-pixel-count hidden-stroke-pixel-count
                 always-stroke-pixel-count silhouette-edge-count crease-edge-count
                 boundary-edge-count)
  #:transparent)
