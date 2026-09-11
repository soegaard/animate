#lang racket/base

(require "../main.rkt")
(provide equilateral-triangle example-theme make-demo-timeline make-demo-scene)

(define (base-theme mode)
  (case mode
    [(dark) default-dark-geometry-theme]
    [else default-light-geometry-theme]))

(define (make-example-theme [mode 'light])
  (geometry-theme #:extends (base-theme mode)
    (stroke [width 2.5])
    (point [radius 0.055])
    (label [font-size 0.30])
    (highlighted (stroke [width 4.5]))))

(define example-theme (make-example-theme 'light))

(construction equilateral-triangle
  (given [A (point -2 0)] [B (point 2 0)])
  (require (distinct? A B))
  (timing
    [opening-pause 0.6]
    [read-delay 0.7]
    [action-duration 0.9]
    [step-pause 0.5])

  (layout (focus A B C))
  (style
    [cA [color-family blue]]
    [cB [color-family aqua]]
    [AB [color-family gold]]
    [AC [color-family gold]]
    [BC [color-family gold]])
  (initially (hide A B))
  (step "Start with two points A and B." (show A B))
  (step "Start with the segment AB." [AB (segment A B)])
  (step "Draw a circle centred at A through B." [cA (circle A B)])
  (step "Draw the corresponding circle centred at B." [cB (circle B A)])
  (step "Let C be their intersection."
    [C (intersection cA cB #:side-of AB 'left)])
  (step "Join C to A and B." [AC (segment A C)] [BC (segment B C)])
  (step "This is the required equilateral triangle."
    (deemphasize cA cB) (highlight AB AC BC))
  (result C AB AC BC))

(define (make-demo-timeline #:aspect [aspect 16/9] #:theme-mode [theme-mode 'light])
  (construction->timeline equilateral-triangle #:theme (make-example-theme theme-mode) #:aspect aspect))
(define (make-demo-scene #:width [width 1280] #:height [height 720] #:theme-mode [theme-mode 'light])
  (geometry-timeline->scene (make-demo-timeline #:aspect (/ width height) #:theme-mode theme-mode)
                            #:width width #:height height))
(module+ main
  (require "private/run-example.rkt")
  (run-geometry-example "equilateral-triangle"
                        (lambda (aspect theme-mode)
                          (make-demo-timeline #:aspect aspect #:theme-mode theme-mode))))
