#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide triangle-midline example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

;; Deliberately scalene and acute: the result should not rely on symmetry.
(construction triangle-midline
  (given [A (point -2.4 -1)] [B (point 2.2 -1)] [C (point -1.05 1.5)])
  (layout (focus A B C M N) (label-side M 'left) (label-side N 'right))
  (layout (label-side A 'below-left) (label-side B 'below-right) (label-side C 'above))
  (style [MN [color-family gold]])
  (step "Start with triangle ABC." [AB (segment A B)] [BC (segment B C)] [AC (segment A C)])
  (step "Construct the midpoint M of AC."
    (expand [M (c:bisect-segment A C)] #:auxiliaries 'hide))
  (step "Construct the midpoint N of BC." [N (c:bisect-segment B C)])
  (step "Join the two midpoints." [MN (segment M N)])
  (step "M and N divide their respective sides into equal halves."
    [halves-AC (marker (midpoint-of M AC))]
    [halves-BC (marker (midpoint-of N BC))])
  (step #:pause 1.5 "The midline is parallel to AB and has half its length."
    [arrows (marker (parallel AB MN))])
  ;; Kernel midpoint is used only as a postcondition oracle, not as the algorithm.
  (assert (midpoint-of M AC) (midpoint-of N BC) (parallel AB MN)
          (equal-length MN (segment A (midpoint A B))))
  (result M N MN A B C))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline triangle-midline #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "triangle-midline"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
