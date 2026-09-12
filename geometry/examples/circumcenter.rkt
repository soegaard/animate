#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide circumcenter example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction circumcenter
  (given [A (point -2 -1)] [B (point 2.4 -1)] [C (point 0.3 2)])
  (require (noncollinear? A B C))
  (layout (focus A B C O) (fit-circle k)
          (label-side A 'below-left) (label-side B 'below-right)
          (label-side C 'above) (label-side O 'below-right))
  (style [k [color-family gold]])
  (step "Start with triangle ABC." [AB (segment A B)] [BC (segment B C)] [CA (segment C A)])
  (step "Construct the perpendicular bisector of AB."
    [m (c:perpendicular-bisector A B)])
  (step "Construct the perpendicular bisector of AC."
    [n (c:perpendicular-bisector A C)])
  (step "The two bisectors meet at the circumcenter O." [O (intersection m n)])
  (step "O is equally distant from the three vertices."
    [OA (segment O A)] [OB (segment O B)] [OC (segment O C)]
    [radii (marker (equal-length OA OB OC))])
  (step #:pause 1.5 "The circle centred at O through A also passes through B and C."
    [k (circle O A)] (hide m n) (deemphasize OA OB OC))
  (assert (equal-length OA OB OC) (on A k) (on B k) (on C k))
  (result O k A B C))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline circumcenter #:padding 0.7 #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "circumcenter"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
