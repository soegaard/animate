#lang racket/base

(require "../core.rkt" "private/library-example.rkt" (prefix-in helper: "helpers.rkt"))
(provide perpendicular-bisector-demo example-theme make-demo-timeline make-demo-scene)

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

(construction perpendicular-bisector-demo
  (given [A (point)] [B (point)])
  (require (distinct? A B))
  (timing
    [opening-pause 0.6]
    [read-delay 1.0]
    [action-duration 0.9]
    [step-pause 0.5])

  (layout (focus A B M) (prefer (distance A B) 3.5))
  (style [AB [color-family gold]] [m [color-family gold]])
  (step "Start with an arbitrary segment AB." [AB (segment A B)])
  (step "Construct its perpendicular bisector."
    (expand [m (helper:perpendicular-bisector A B)]))
  (step "The line meets AB at M."
    [M (intersection m AB)]
    [midmark (marker (midpoint-of M AB))])
  (assert (midpoint-of M AB)
          (perpendicular AB m #:at M))
  (step #:pause 1.5 "M is the midpoint, and the two lines are perpendicular."
    [right-angle (marker (perpendicular AB m #:at M))]
    (highlight m M midmark right-angle))
  (result m M midmark right-angle))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [theme-mode 'light])
  (construction->timeline perpendicular-bisector-demo #:theme (make-example-theme theme-mode) #:aspect aspect))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [theme-mode 'light])
  (library-example->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode theme-mode)
                            #:width width #:height height))
(module+ main
  (run-library-example "perpendicular-bisector"
                        (lambda (aspect theme-mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode theme-mode))))
