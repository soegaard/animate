#lang racket/base

;; Construction coverage for the dedicated video examples added for the later
;; roadmap stages. Rendering is exercised separately because it is intentionally
;; expensive and, for formulas and svg-image, depends on optional renderers.

(require rackunit
         racket/runtime-path)

(define-runtime-path examples-directory "../examples")

(module+ test
  (for ([example
         (in-list
          '("generic-interpolable-values.rkt"
            "parameter-handles.rkt"
            "derived-groups.rkt"
            "nested-addressing.rkt"
            "nested-child-animation.rkt"
            "automatic-formula-matching.rkt"
            "svg-subpart-animation.rkt"
            "bitmap-image-visual.rkt"
            "logarithmic-axes.rkt"
            "implicit-curves.rkt"
            "vector-fields.rkt"
            "derived-function-graphs.rkt"
            "renderer-resources.rkt"
            "render-diagnostics.rkt"))])
    (define make-demo-scene
      (dynamic-require (build-path examples-directory example) 'make-demo-scene))
    (check-not-exn make-demo-scene example)))
