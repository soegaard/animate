#lang racket/base
(require "../core.rkt" "private/library-example.rkt")
(provide semantic-labels-demo example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))
(construction semantic-labels-demo
  (given [A (point -2.5 -1)] [B (point 2.5 -1)] [C (point -1.5 1.8)])
  (initially (hide-label C))
  (layout (label-side A 'below-left) (label-side B 'below-right)
          (label-side apex 'above)
          ;; Conventional triangle side labels lie outside the triangle: each
          ;; reference is the opposite vertex, so the label uses the other half-plane.
          (label-outside-of base-length C)
          (label-outside-of side-a A) (label-outside-of side-b B)
          (label-outside-of measured-a A)
          (label-position side-a 0.55) (label-position side-b 0.5)
          (label-position measured-a 0.55)
          (marker-radius alpha 0.34) (marker-radius beta 0.34)
          (marker-radius measured-alpha 0.24))
  (style [AB [color-family gold]]
         [measured-a [offset 0.07]] [measured-alpha [offset 0.07]])
  (step "The base AB has length 5 cm."
    [AB (segment A B)] [BC (segment B C)] [CA (segment C A)]
    [apex (point-label C "C")]
    [base-length (segment-label AB "5 cm")])
  (step "Let a and b denote the other two side lengths."
    (together [side-a (length-label BC "a")] [side-b (length-label CA "b")]))
  (step "The angles at A and B are α and β."
    (together [alpha (angle-label (angle B A C) "α")]
              [beta (angle-label (angle C B A) "β")]))
  (step "The length a can also be evaluated numerically."
    (hide side-a) [measured-a (length-label BC #:precision 2 #:unit "cm")])
  (step "The angle α has this measure in degrees."
    (hide alpha) [measured-alpha (angle-label (angle B A C) #:precision 1)])
  (step #:pause 1.5 "The symbols and measurements refer to the same geometry."
    (hide measured-a measured-alpha) (show side-a alpha))
  (result AB BC CA apex base-length side-a side-b alpha beta))
(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline semantic-labels-demo #:aspect aspect #:theme (make-library-theme mode)
    #:view (make-geometry-view #:center (point 0 0.25) #:world-width 9 #:aspect aspect #:margin 0.08)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode) #:width width #:height height))
(module+ main
  (run-library-example "semantic-labels" (lambda (aspect mode) (make-demo-timeline #:aspect aspect #:theme-mode mode))))
