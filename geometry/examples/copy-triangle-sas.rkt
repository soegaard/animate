#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide copy-triangle-sas example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction copy-triangle-sas
  (given [A (point -4 -0.8)] [B (point -1.6 -0.8)] [C (point -3.1 1.5)]
         [O (point 1 -1)] [target (ray O (point 3.5 -0.3))])
  (layout (focus A B C O B2 C2)
          (label-text O "A′") (label-text B2 "B′") (label-text C2 "C′"))
  (style [A2B2 [color-family gold]] [A2C2 [color-family gold]] [B2C2 [color-family gold]])
  (step "The source triangle and a new starting ray are given."
    [AB (segment A B)] [AC (segment A C)] [BC (segment B C)])
  (step "Copy AB onto the new ray."
    (expand [B2 (c:copy-segment AB target)] #:auxiliaries 'hide))
  (step "Copy the included angle at A to the new vertex."
    (expand [r2 (c:copy-angle (angle B A C) target 'left)] #:auxiliaries 'hide))
  (step "Copy AC onto the new ray." [C2 (c:copy-segment AC r2)])
  (step "Join the three new vertices."
    [A2B2 (segment O B2)] [A2C2 (segment O C2)] [B2C2 (segment B2 C2)])
  (step "Two sides and their included angle match the source triangle."
    [side-one (marker (equal-length AB A2B2))]
    [side-two (marker (equal-length AC A2C2))]
    [included (marker (equal-angle (angle B A C) (angle B2 O C2)))]
    (hide target r2))
  (step "The triangles are congruent by SAS." (highlight A2B2 A2C2 B2C2))
  (assert (equal-length AB A2B2) (equal-length AC A2C2) (equal-length BC B2C2)
          (equal-angle (angle B A C) (angle B2 O C2)))
  (result O B2 C2 A B C))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline copy-triangle-sas #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "copy-triangle-sas"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
