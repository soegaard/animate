#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide incircle example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction incircle
  (given [A (point -2.5 -1.2)] [B (point 2.3 -1.2)] [C (point -0.4 2)])
  (require (noncollinear? A B C))
  (layout (focus A B C I T) (fit-circle k)
          (label-side A 'below-left) (label-side B 'below-right) (label-side C 'above)
          (label-side I 'above-right) (label-side T 'below)
          (label-side U 'left) (label-side V 'right))
  (style [k [color-family gold]])
  (step "Start with triangle ABC."
    (together [AB (segment A B)] [BC (segment B C)] [CA (segment C A)]))
  (step "Bisect the angle at A."
    (expand [ra (c:angle-bisector B A C)] #:auxiliaries 'hide))
  (step "Bisect the angle at B." [rb (c:angle-bisector A B C)])
  (step "The angle bisectors meet at the incenter I."
    [I (intersection ra rb)] (hide ra rb))
  (step "Drop the perpendicular from I to AB."
    (expand [h (c:drop-perpendicular (line A B) I)] #:auxiliaries 'hide))
  (step "Its foot T determines the radius of the incircle."
    [T (intersection h AB)] [IT (segment I T)]
    [contact (marker (perpendicular AB IT #:at T))] (hide h))
  (step "Draw the circle with centre I and radius IT." [k (circle I T)])
  (step "The perpendicular from I meets AC at U."
    [U (intersection (c:drop-perpendicular (line A C) I) CA)]
    [IU (segment I U)] [contact-U (marker (perpendicular CA IU #:at U))])
  (step "The perpendicular from I meets BC at V."
    [V (intersection (c:drop-perpendicular (line B C) I) BC)]
    [IV (segment I V)] [contact-V (marker (perpendicular BC IV #:at V))])
  (step "These three perpendicular distances are equal."
    [radii (marker (equal-length IT IU IV))])
  (step #:pause 1.5 "The circle touches all three sides of the triangle."
    (deemphasize IT IU IV))
  (assert (on T AB) (on U CA) (on V BC)
          (equal-length IT IU IV) (on U k) (on V k)
          (perpendicular IT AB #:at T)
          (perpendicular IU CA #:at U) (perpendicular IV BC #:at V))
  (result I T U V k A B C))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline incircle #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "incircle"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
