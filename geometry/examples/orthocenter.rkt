#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide orthocenter example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction orthocenter
  (given [A (point -2.5 -1.2)] [B (point 2.3 -1.2)] [C (point -0.4 2)])
  (require (noncollinear? A B C))
  (layout (focus A B C H) (label-side H 'above-right))
  (step "Start with triangle ABC." [AB (segment A B)] [BC (segment B C)] [CA (segment C A)])
  (step "Construct the altitude from A to the line through B and C."
    (expand [a (c:drop-perpendicular (line B C) A)] #:auxiliaries 'hide))
  (step "Construct the altitude from B." [b (c:drop-perpendicular (line A C) B)])
  (step "The two altitudes meet at H." [H (intersection a b)])
  (step "The altitude from C passes through the same point."
    [c (c:drop-perpendicular (line A B) C)])
  (step "H is the orthocenter of the triangle."
    [Ta (intersection a (line B C))] [Tb (intersection b (line A C))]
    [Tc (intersection c (line A B))]
    [ha (segment A Ta)] [hb (segment B Tb)] [hc (segment C Tc)]
    [corner (marker (perpendicular (line A B) hc #:at Tc))]
    (hide a b c))
  (assert (on H c) (on H a) (on H b)
          (perpendicular ha (line B C) #:at Ta)
          (perpendicular hb (line C A) #:at Tb))
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
