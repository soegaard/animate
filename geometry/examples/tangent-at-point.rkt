#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide tangent-at-point example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction tangent-at-point
  (given [O (point 0 0)] [P (point 1.5 1)])
  (layout (focus O P) (fit-circle k) (label-side O 'below-left) (label-side P 'above-right))
  (style [k [color-family aqua]] [t [color-family gold]])
  (step "Start with a circle and a point P on its circumference." [k (circle O P)])
  (step "Join P to the centre O." [OP (segment O P)])
  (step "Construct the perpendicular to OP at P."
    (expand [t (c:erect-perpendicular (line O P) P)] #:auxiliaries 'hide))
  (step #:pause 1.5 "A perpendicular to the radius at its endpoint is tangent to the circle."
    [corner (marker (perpendicular OP t #:at P))])
  (assert (on P k) (perpendicular OP t #:at P))
  (result O P k t))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline tangent-at-point #:padding 0.7 #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "tangent-at-point"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
