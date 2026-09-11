#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide equilateral-triangle-chain example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction equilateral-triangle-chain
  (given [A (point -3.5 -0.8)] [B (point -1.5 -0.8)] [T (point 4.5 -0.8)])
  (initially (hide T) (hide-label T))
  (layout (focus A B C D E F G))
  (step "Construct an equilateral triangle on AB."
    [AB (segment A B)] [cA (circle A B)] [cB (circle B A)]
    [C (intersection cA cB #:side-of AB 'left)]
    [AC (segment A C)] [BC (segment B C)])
  (step "Copy AB along the base to locate D."
    (expand [D (c:copy-segment AB (ray B T))] #:auxiliaries 'hide))
  (step "Copy the sixty-degree angle at the new starting point."
    (expand [rE (c:copy-angle (angle B A C) (ray B D) 'left)] #:auxiliaries 'hide))
  (step "Copy the side length on the new ray to locate E."
    [E (c:copy-segment AB rE)] [BD (segment B D)] [BE (segment B E)] [DE (segment D E)])
  (step "Repeat once more to construct the third triangle."
    [F (c:copy-segment AB (ray D T))]
    [rG (c:copy-angle (angle B A C) (ray D F) 'left)]
    [G (c:copy-segment AB rG)]
    [DF (segment D F)] [DG (segment D G)] [FG (segment F G)])
  (step "All three triangles are equilateral with the same side length."
    [sides (marker (equal-length AB AC BC BD BE DE DF DG FG))]
    (hide cA cB rE rG))
  (assert (equal-length AB AC BC BD BE DE DF DG FG))
  (result A B C D E F G))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline equilateral-triangle-chain #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "equilateral-triangle-chain"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
