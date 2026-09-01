#lang racket/base

;;;
;;; Full-Fidelity SVG Render Visual Tests
;;;

(require racket/class
         rackunit
         racket/runtime-path
         (only-in pict pict-height pict-width)
         "../main.rkt")

(define-runtime-path fixture "scene-svg-render-fixture.svg")

(module+ test
  ;; This fixture intentionally needs gradients, clipping, text, and rotation:
  ;; features outside the semantic svg->visual subset but supported by svg/svg.
  (define visual
    (svg-image fixture
               #:id 'full-svg
               #:center (vec2 1 2)
               #:width 8
               #:height 4))
  (check-true (svg-image-visual? visual))
  (check-equal? (visual-id visual) 'full-svg)
  (check-equal? (visual-position visual) (vec2 1 2))
  (check-true (immutable? (svg-image-visual-source visual)))
  (check-equal? (svg-image-visual-width visual) 8)
  (check-equal? (svg-image-visual-height visual) 4)
  (define viewport
    (make-camera #:width 160 #:height 80 #:world-width 16))
  ;; Rendered dimensions follow declared world geometry, not the SVG viewport.
  (define rendered (visual->pict visual viewport))
  (check-equal? (pict-width rendered) 80)
  (check-equal? (pict-height rendered) 40)
  (define animated
    (scene-play
     (scene-add (make-scene) visual)
     (move-to visual (vec2 5 -2))
     (scale-to visual (vec2 3/2 1/2))
     (fade-to visual 1/2)
     #:duration 2))
  (define midpoint (scene-visual-at animated 'full-svg 1))
  (check-equal? (visual-position midpoint) (vec2 3 -0))
  (check-equal? (visual-scale midpoint) (vec2 5/4 3/4))
  (check-equal? (visual-opacity midpoint) 3/4)
  (check-equal?
   (send (scene-frame->bitmap animated 0 #:fps 1 #:camera viewport) get-width)
   160)
  (check-exn exn:fail:contract?
             (lambda ()
               (svg-image fixture #:id 'bad #:width 0 #:height 4))))
