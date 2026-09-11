#lang racket/base

(require "../main.rkt")
(provide perpendicular-through-point example-theme make-demo-timeline make-demo-scene)

(define (base-theme mode)
  (case mode
    [(dark) default-dark-geometry-theme]
    [else default-light-geometry-theme]))

(define (make-example-theme [mode 'light])
  (geometry-theme #:extends (base-theme mode)
    (stroke [width 2.5])
    (point [radius 0.055])
    (label [font-size 0.30])
    (circle (deemphasized (stroke [dash (7 5)])))
    (marker (size 0.18) (spacing 0.08) (radius 0.26))
    (highlighted (stroke [width 4.5]))))

(define example-theme (make-example-theme 'light))

(construction perpendicular-through-point
  (given [l (line (point -3 0) (point 3 0))] [P (point 0 0)])
  (require (on P l))
  (timing
    [opening-pause 0.6]
    [read-delay 1.0]
    [action-duration 0.9]
    [step-pause 0.5])

  (layout (focus P A B C D) (prefer (distance A P) 1.5))
  (style
    [l [color axis]]
    [cP [color-family purple]]
    [cA [color-family blue]]
    [cB [color-family aqua]]
    [m [color-family gold]])
  (step "Choose a point A on the line, different from P."
    [A (choose (point-on l #:except P))])
  (step "Draw a circle centred at P through A." [cP (circle P A)])
  (step "Let B be its other intersection with the line."
    [B (intersection cP l #:other-than A)])
  (step "Draw equal circles centred at A and B."
    [cA (circle A B)] [cB (circle B A)])
  (step "The circles meet at C and D." [(C D) (intersections cA cB)])
  (step "Draw the line through C and D." [m (line C D)])
  (step "This is the perpendicular to l through P."
    [right-angle (marker (perpendicular l m #:at P))]
    (deemphasize cP cA cB) (hide-label A B C D) (highlight m P right-angle))
  (result m right-angle))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [theme-mode 'light])
  (construction->timeline perpendicular-through-point #:theme (make-example-theme theme-mode) #:aspect aspect))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [theme-mode 'light])
  (geometry-timeline->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode theme-mode)
                            #:width width #:height height))
(module+ main
  (require "private/run-example.rkt")
  (run-geometry-example "perpendicular-through-point"
                        (lambda (aspect theme-mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode theme-mode))))
