#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide divide-segment-five example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction divide-segment-five
  (given [A (point -3 0.6)] [B (point 3 0.6)] [T (point 3 -3)]
         [unit (segment (point -3 -2.8) (point -2 -2.8))])
  (initially (hide T) (hide-label T))
  (layout (focus A B P5) (label-side X1 'above) (label-side X2 'above)
          (label-side X3 'above) (label-side X4 'above))
  (style [AB [color-family gold]])
  (step "Start with AB and an auxiliary ray from A."
    [AB (segment A B)] [r (ray A T)])
  (step "Mark one unit along the auxiliary ray."
    (expand [P1 (c:copy-segment unit r)] #:auxiliaries 'hide))
  (step "Mark four more equal steps along the same ray."
    [P2 (c:copy-segment unit (ray P1 T))]
    [P3 (c:copy-segment unit (ray P2 T))]
    [P4 (c:copy-segment unit (ray P3 T))]
    [P5 (c:copy-segment unit (ray P4 T))])
  (step "Join the fifth point to B." [g (line P5 B)])
  (step "Through each earlier point, draw a parallel to this line."
    [q1 (c:parallel-through-point g P1)]
    [q2 (c:parallel-through-point g P2)]
    [q3 (c:parallel-through-point g P3)]
    [q4 (c:parallel-through-point g P4)])
  (step "The parallel lines meet AB at the four division points."
    [X1 (intersection q1 AB)] [X2 (intersection q2 AB)]
    [X3 (intersection q3 AB)] [X4 (intersection q4 AB)])
  (step "The intercept theorem gives five equal parts."
    [s1 (segment A X1)] [s2 (segment X1 X2)] [s3 (segment X2 X3)]
    [s4 (segment X3 X4)] [s5 (segment X4 B)]
    [parts (marker (equal-length s1 s2 s3 s4 s5))]
    (hide r g q1 q2 q3 q4 P1 P2 P3 P4 P5 unit))
  (assert (equal-length s1 s2 s3 s4 s5)
          (on X1 AB) (on X2 AB) (on X3 AB) (on X4 AB))
  (result A X1 X2 X3 X4 B s1 s2 s3 s4 s5))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline divide-segment-five #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "divide-segment-five"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
