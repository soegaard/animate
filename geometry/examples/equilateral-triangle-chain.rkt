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
  (layout (focus A B C D E F G)
          (label-side A 'below) (label-side B 'below) (label-side C 'above)
          (label-side D 'below) (label-side E 'above) (label-side F 'below) (label-side G 'above))
  (step "Start with segment AB." [AB (segment A B)])
  (step "Draw equal circles at A and B." [cA (circle A B)] [cB (circle B A)])
  (step "Their upper intersection is C." [C (intersection cA cB #:side-of AB 'left)])
  (step "Joining C to A and B gives an equilateral triangle."
    (together [AC (segment A C)] [BC (segment B C)]) (hide cA cB))
  (step "Copy AB along the base to locate D."
    (expand [D (c:copy-segment AB (ray B T))] #:auxiliaries 'hide)
    [BD (segment B D)])
  (step "Copy the sixty-degree angle at the new starting point."
    (expand [rE (c:copy-angle (angle B A C) (ray B D) 'left)] #:auxiliaries 'hide))
  (step "Copy the side length on this ray to locate E." [E (c:copy-segment AB rE)])
  (step "Join E to the two endpoints of the new base."
    (together [BE (segment B E)] [DE (segment D E)]) (hide rE))
  (step "One more copy of AB locates F."
    [F (c:copy-segment AB (ray D T))] [DF (segment D F)])
  (step "Copy the same angle at D."
    [rG (c:copy-angle (angle B A C) (ray D F) 'left)])
  (step "Copy the side length to locate G." [G (c:copy-segment AB rG)])
  (step "Join G to D and F."
    (together [DG (segment D G)] [FG (segment F G)]) (hide rG))
  (step #:pause 1.5 "All three triangles are equilateral with the same side length."
    [sides (marker (equal-length AB AC BC BD BE DE DF DG FG))])
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
