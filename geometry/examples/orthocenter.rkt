#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide orthocenter example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

;; Deliberately scalene and acute: the result should not rely on symmetry.
(construction orthocenter
  (given [A (point -2.5 -1.2)] [B (point 2.3 -1.2)] [C (point -0.9 1.6)])
  (require (noncollinear? A B C))
  (layout (focus A B C H) (label-offset H (point 0.38 -0.6))
          (label-side A 'below-left) (label-side B 'below-right) (label-side C 'above)
          (label-text Ta "T₁") (label-text Tb "T₂") (label-text Tc "T₃")
          (label-side Ta 'right) (label-side Tb 'left) (label-side Tc 'below))
  (style [ha [color-family gold]] [hb [color-family gold]] [hc [color-family gold]])
  (step "Start with triangle ABC."
    (together [AB (segment A B)] [BC (segment B C)] [CA (segment C A)]))
  (step "Construct the altitude from A to the line through B and C."
    (expand [a (c:drop-perpendicular (line B C) A)] #:auxiliaries 'hide))
  (step (caption "The altitude meets BC at " Ta ".")
    [Ta (intersection a (line B C))] [ha (segment A Ta)]
    [corner-a (marker (perpendicular (line B C) ha #:at Ta))])
  (step "Construct the altitude from B." [b (c:drop-perpendicular (line A C) B)])
  (step (caption "Its foot on AC is " Tb ".")
    [Tb (intersection b (line A C))] [hb (segment B Tb)]
    [corner-b (marker (perpendicular (line A C) hb #:at Tb))])
  (step "The two altitudes meet at H." [H (intersection a b)])
  (step "The altitude from C passes through the same point."
    [c (c:drop-perpendicular (line A B) C)])
  (step (caption "The third foot is " Tc ".")
    [Tc (intersection c (line A B))] [hc (segment C Tc)]
    [corner (marker (perpendicular (line A B) hc #:at Tc))])
  (step #:pause 1.5 "H is the orthocenter of the triangle." (hide a b c))
  (assert (on H c) (on H a) (on H b)
          (perpendicular ha (line B C) #:at Ta)
          (perpendicular hb (line C A) #:at Tb)
          (perpendicular hc (line A B) #:at Tc))
  (result H A B C Ta Tb Tc))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline orthocenter #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "orthocenter"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
