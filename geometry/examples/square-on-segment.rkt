#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide square-on-segment example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction square-on-segment
  (given [A (point -1.4 -1.4)] [B (point 1.4 -1.4)])
  (layout (focus A B C D)
          (label-side A 'below-left) (label-side B 'below-right)
          (label-side C 'above-right) (label-side D 'above-left))
  (style [AB [color-family gold]] [AD [color-family gold]]
         [BC [color-family gold]] [CD [color-family gold]])
  (step "Start with the given segment AB." [AB (segment A B)])
  (step "Construct a perpendicular at A."
    (expand [n (c:erect-perpendicular (line A B) A)] #:auxiliaries 'hide))
  (step "Use the ray on the left of the directed segment AB."
    [up (ray A (end-point n))])
  (step "Copy AB onto this ray to locate D."
    (expand [D (c:copy-segment AB up)] #:auxiliaries 'hide)
    [AD (segment A D)])
  (step "Draw a line through B parallel to AD."
    [m (c:parallel-through-point (line A D) B)])
  (step "Draw a line through D parallel to AB."
    [p (c:parallel-through-point (line A B) D)])
  (step "Their intersection is the fourth vertex C."
    [C (intersection m p)] [BC (segment B C)] [CD (segment C D)])
  (step "The four equal sides and the right angle determine a square."
    [sides (marker (equal-length AB BC CD AD))]
    [corner (marker (perpendicular AB AD #:at A))]
    (hide n up m p))
  (assert (equal-length AB BC CD AD)
          (perpendicular AB AD #:at A) (perpendicular AB BC #:at B)
          (perpendicular BC CD #:at C) (parallel AB CD))
  (result A B C D AB BC CD AD))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline square-on-segment #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "square-on-segment"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
