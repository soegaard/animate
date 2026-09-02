#lang racket/base

;; Construction coverage for the dedicated video examples added for the later
;; roadmap stages. Rendering is exercised separately because it is intentionally
;; expensive and, for formulas and svg-image, depends on optional renderers.

(require rackunit
         racket/runtime-path
         "../main.rkt")

(define-runtime-path examples-directory "../examples")

(module+ test
  (for ([example-and-labels
         (in-list
          (list (cons "generic-interpolable-values.rkt" '(title))
                (cons "parameter-handles.rkt" '(title))
                (cons "derived-groups.rkt" '(title))
                (cons "nested-addressing.rkt" '(title))
                (cons "nested-child-animation.rkt" '(title))
                (cons "automatic-formula-matching.rkt" '(title))
                (cons "tagged-formula-transitions.rkt" '(title))
                (cons "solving-linear-equation.rkt" '(title))
                (cons "glyph-level-formula-matching.rkt" '(title))
                (cons "glyph-outline-morph.rkt" '(title))
                (cons "compound-glyph-outline-morph.rkt" '(title))
                (cons "nested-transform-from-copy.rkt" '(title))
                (cons "named-layout-anchors.rkt" '(title))
                (cons "nested-live-attachments.rkt" '(title explanation))
                (cons "nested-attention.rkt" '(title explanation))
                (cons "structured-formula-derivation.rkt" '(title))
                (cons "general-shape-transform.rkt" '(title explanation))
                (cons "explanatory-camera-focus.rkt" '(title))
                (cons "perimeter-shape-morph.rkt" '(title explanation))
                (cons "live-attention-follow.rkt" '(title explanation))
                (cons "stationary-formula-derivation.rkt" '(title))
                (cons "live-anchor-constraints.rkt" '(title explanation))
                (cons "dynamic-endpoint-geometry.rkt" '(title explanation))
                (cons "mathematical-annotations.rkt" '(title explanation))
                (cons "secant-to-tangent.rkt" '(title explanation))
                (cons "adaptive-plotting.rkt" '(title explanation))
                (cons "formula-styling.rkt" '(title explanation))
                (cons "multiline-rich-text.rkt" '(title explanation))
                (cons "matrices-and-tables.rkt" '(title explanation))
                (cons "traced-cycloid.rkt" '(title explanation))
                (cons "composable-camera-movements.rkt" '(title explanation))
                (cons "authoring-sections.rkt" '(title explanation))
                (cons "graphs-and-networks.rkt" '(title explanation))
                (cons "animated-write.rkt" '(title))
                (cons "svg-subpart-animation.rkt" '(title))
                (cons "bitmap-image-visual.rkt" '(title))
                (cons "logarithmic-axes.rkt" '(title))
                (cons "implicit-curves.rkt" '(title))
                (cons "vector-fields.rkt" '(title))
                (cons "derived-function-graphs.rkt" '(title))
                (cons "renderer-resources.rkt" '(caption detail))
                (cons "render-diagnostics.rkt" '(title))))])
    (define example (car example-and-labels))
    (define make-demo-scene
      (dynamic-require (build-path examples-directory example) 'make-demo-scene))
    (check-not-exn make-demo-scene example)
    (define scene (make-demo-scene))
    ;; The default camera shows y coordinates from about -3.94 to 3.94.
    ;; Keep labels inside a conservative 3.5-unit vertical margin.
    (for ([label-id (in-list (cdr example-and-labels))])
      (define label (scene-visual-at scene label-id 0))
      (check-true
       (<= -7/2 (vec2-y (visual-position label)) 7/2)
       (format "~a label ~a should fit in the default camera" example label-id)))))
