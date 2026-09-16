#lang racket/base

;; Internal, immutable rendering input. A playback timeline deliberately omits
;; the compiler program/realization: sampling needs events and presentation maps,
;; not source expressions, source locations, free-point search, or callbacks.
;; The codec validates and deep-copies the fields at the preparation boundary.
(provide (struct-out prepared-geometry-render))
(struct prepared-geometry-render
  (pixels captions? view order environment playback
          labels texts placements counts styles reveals
          caption-size caption-y caption-height guide-style attention-style)
  #:transparent)
