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
