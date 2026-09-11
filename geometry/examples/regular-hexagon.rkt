#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide regular-hexagon example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction regular-hexagon
  (given [O (point 0 0)] [A (point 2 0)])
  (layout (focus O A B C D E F))
  (step "Start with a circle of radius OA." [k (circle O A)] [OA (segment O A)])
  (step "A circle centred at A, through O, locates the next vertex B."
    [cA (circle A O)] [B (intersection k cA #:side-of (ray O A) 'left)])
  (step "The angle AOB is sixty degrees. Copy it to the next radius."
    [unit-angle (angle A O B)]
    (expand [rC (c:copy-angle unit-angle (ray O B) 'left)] #:auxiliaries 'hide))
  (step "Copy the radius along that ray to locate C." [C (c:copy-segment OA rC)])
  (step "Repeat the same angle and radius three more times."
    [rD (c:copy-angle unit-angle (ray O C) 'left)] [D (c:copy-segment OA rD)]
    [rE (c:copy-angle unit-angle (ray O D) 'left)] [E (c:copy-segment OA rE)]
    [rF (c:copy-angle unit-angle (ray O E) 'left)] [F (c:copy-segment OA rF)])
  (step "Join adjacent vertices to complete the regular hexagon."
    [AB (segment A B)] [BC (segment B C)] [CD (segment C D)]
    [DE (segment D E)] [EF (segment E F)] [FA (segment F A)]
    (hide cA rC rD rE rF OA))
  (step "Every side has the same length as the circle's radius."
    [sides (marker (equal-length AB BC CD DE EF FA))])
  (assert (on B k) (on C k) (on D k) (on E k) (on F k)
          (equal-length OA AB BC CD DE EF FA))
  (result O A B C D E F k))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline regular-hexagon #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "regular-hexagon"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
