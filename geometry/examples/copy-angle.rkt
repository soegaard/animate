#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide copy-angle-demo example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction copy-angle-demo
  (given [A (point -1.2 0)] [B (point -3 0)] [C (point -2.2 1.6)]
         [O (point 1 -0.2)] [target (ray O (point 3.3 0.2))])
  (layout (focus A B C O) (label-text source-mark "α") (label-text target-mark "α")
          (label-side A 'below) (label-side B 'below-left) (label-side C 'above)
          (label-side O 'left))
  (style [r [color-family gold]])
  (step "The source angle and a target ray are given."
    [BA (segment B A)] [BC (segment B C)]
    [source-mark (marker (angle A B C))] (show-label source-mark))
  (step "Copy the angle onto the right side of the target ray."
    (expand [r (c:copy-angle (angle A B C) target 'right)] #:auxiliaries 'hide))
  (step #:pause 1.5 "The two angles have equal measure."
    [target-mark (marker (angle (end-point target) O (end-point r)))]
    (show-label target-mark))
  (assert (equal-angle (angle A B C) (angle (end-point target) O (end-point r)))
          (side-of? (end-point r) target 'right))
  (result r O A B C))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline copy-angle-demo #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "copy-angle"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
