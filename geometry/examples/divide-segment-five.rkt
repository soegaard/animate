#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide divide-segment-five example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction divide-segment-five
  (given [A (point -3 0.6)] [B (point 3 0.6)] [T (point 3 -3)]
         [unit (segment (point -3 1.7) (point -2 1.7))])
  (initially (hide T) (hide-label T) (show-label unit))
  (layout (focus A B P5) (label-text unit "u") (label-side unit 'below)
          (label-side A 'left) (label-side B 'right)
          (label-text P1 "P₁") (label-text P2 "P₂") (label-text P3 "P₃")
          (label-text P4 "P₄") (label-text P5 "P₅")
          (label-text X1 "X₁") (label-text X2 "X₂") (label-text X3 "X₃") (label-text X4 "X₄")
          (label-side X1 'above) (label-side X2 'above)
          (label-side X3 'above) (label-side X4 'above))
  (style [AB [color-family gold]] [s1 [color-family gold]] [s2 [color-family gold]]
         [s3 [color-family gold]] [s4 [color-family gold]] [s5 [color-family gold]])
  (step "Start with AB, an auxiliary ray from A, and a unit length u."
    [AB (segment A B)] [r (ray A T)])
  (step (caption "Copy u along the ray to locate " P1 ".")
    (expand [P1 (c:copy-segment unit r)] #:auxiliaries 'hide)
    [e1 (segment A P1)])
  (step (caption "Copy u again to locate " P2 ".")
    [P2 (c:copy-segment unit (ray P1 T))] [e2 (segment P1 P2)])
  (step (caption "The next equal interval ends at " P3 ".")
    [P3 (c:copy-segment unit (ray P2 T))] [e3 (segment P2 P3)])
  (step (caption "The fourth interval ends at " P4 ".")
    [P4 (c:copy-segment unit (ray P3 T))] [e4 (segment P3 P4)])
  (step (caption "The fifth interval ends at " P5 ".")
    [P5 (c:copy-segment unit (ray P4 T))] [e5 (segment P4 P5)])
  (step "These five intervals are equal."
    [intervals (marker (equal-length e1 e2 e3 e4 e5))] (hide unit))
  (step (caption "Join " P5 " to B.") [g (line P5 B)])
  (step (caption "The parallel through " P1 " meets AB at " X1 ".")
    [q1 (c:parallel-through-point g P1)] [X1 (intersection q1 AB)]
    [arrows (marker (parallel g q1))])
  (step (caption "The parallel through " P2 " gives " X2 ".")
    [q2 (c:parallel-through-point g P2)] [X2 (intersection q2 AB)])
  (step (caption "The parallel through " P3 " gives " X3 ".")
    [q3 (c:parallel-through-point g P3)] [X3 (intersection q3 AB)])
  (step (caption "The parallel through " P4 " gives " X4 ".")
    [q4 (c:parallel-through-point g P4)] [X4 (intersection q4 AB)])
  (step #:pause 1.5 "The intercept theorem gives five equal parts of AB."
    (together [s1 (segment A X1)] [s2 (segment X1 X2)] [s3 (segment X2 X3)]
              [s4 (segment X3 X4)] [s5 (segment X4 B)])
    [parts (marker (equal-length s1 s2 s3 s4 s5))]
    (hide r g q1 q2 q3 q4 P1 P2 P3 P4 P5 e1 e2 e3 e4 e5 intervals arrows))
  (assert (equal-length unit e1 e2 e3 e4 e5) (equal-length s1 s2 s3 s4 s5)
          (parallel g q1) (parallel g q2) (parallel g q3) (parallel g q4)
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
