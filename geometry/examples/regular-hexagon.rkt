#lang racket/base

;; A complete authoring example using the standard construction library.
;; Loading it is headless; native rendering starts only in the main submodule.
(require "../core.rkt" (prefix-in c: "../constructions.rkt")
         "private/library-example.rkt")
(provide regular-hexagon example-theme make-demo-timeline make-demo-scene)
(define example-theme (make-library-theme 'light))

(construction regular-hexagon
  (given [O (point 0 0)] [A (point 2 0)])
  (layout (focus O A B C D E F) (fit-circle k)
          (label-side A 'right) (label-side B 'above-right) (label-side C 'above-left)
          (label-side D 'left) (label-side E 'below-left) (label-side F 'below-right)
          (label-text seed-angle "60°"))
  (step "Start with a circle of radius OA." [k (circle O A)] [OA (segment O A)])
  (step "A circle centred at A through O locates the next vertex."
    [cA (circle A O)])
  (step "Call the upper intersection B." [B (intersection k cA #:side-of (ray O A) 'left)])
  (step "OA, OB and AB are equal, so angle AOB is sixty degrees."
    (together [OB (segment O B)] [AB (segment A B)])
    [seed-angle (marker (angle A O B))] (show-label seed-angle) (hide cA))
  (step "Copy the sixty-degree angle onto the next radius."
    [unit-angle (angle A O B)]
    (hide seed-angle)
    [rC (c:copy-angle unit-angle (ray O B) 'left)] )
  (step "Copy the radius along this ray to locate C." [C (c:copy-segment OA rC)])
  (step "Turn through sixty degrees again and locate D."
    [rD (c:copy-angle unit-angle (ray O C) 'left)] [D (c:copy-segment OA rD)])
  (step "Repeat the same angle and radius to locate E."
    [rE (c:copy-angle unit-angle (ray O D) 'left)] [E (c:copy-segment OA rE)])
  (step "One more repetition gives F."
    [rF (c:copy-angle unit-angle (ray O E) 'left)] [F (c:copy-segment OA rF)])
  (step "Join the vertices around the circle."
    (together [BC (segment B C)] [CD (segment C D)] [DE (segment D E)]
              [EF (segment E F)] [FA (segment F A)])
    (hide rC rD rE rF OB seed-angle))
  (step #:pause 1.5 "Every side has the same length as the radius OA."
    [sides (marker (equal-length OA AB BC CD DE EF FA))])
  (assert (on B k) (on C k) (on D k) (on E k) (on F k)
          (equal-length OA OB AB BC CD DE EF FA))
  (result O A B C D E F k))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [mode 'light])
  (construction->timeline regular-hexagon #:padding 0.7 #:aspect aspect #:theme (make-library-theme mode)))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode mode)
                          #:width width #:height height))
(module+ main
  (run-library-example "regular-hexagon"
                        (lambda (aspect mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode mode))))
