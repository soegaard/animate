#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide reflect-point example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction reflect-point
  (given [l (line (point -3 0) (point 3 0))] [P (point -0.6 1.7)])
  (require (not (on P l)))
  (layout (focus P H Q) (label-side P 'above) (label-side H 'above-left) (label-side Q 'below))
  (style [l [color axis]] [PH [color-family gold]] [HQ [color-family gold]])
  (step "Drop the perpendicular from P to the line."
    [n (c:drop-perpendicular l P)])
  (step "Call the foot of the perpendicular H." [H (intersection n l)] [PH (segment P H)])
  (step "Continue from H along the perpendicular, away from P."
    [away (ray H (end-point n))])
  (step "Copy PH onto this ray to locate Q."
    (expand [Q (c:copy-segment PH away)] #:auxiliaries 'hide)
    [HQ (segment H Q)])
  (step "H is halfway between P and Q, and PQ is perpendicular to the mirror line."
    [equal-parts (marker (equal-length PH HQ))]
    [corner (marker (perpendicular l (line P Q) #:at H))]
    (hide n away))
  (step #:pause 1.5 "Q is the reflection of P across the line." (highlight Q))
  (assert (on H l) (midpoint-of H (segment P Q))
          (perpendicular l (line P Q) #:at H))
  (result P H Q l))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline reflect-point #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "reflect-point"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
