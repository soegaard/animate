#lang racket/base

;; A source-only storyboard: the parent prepares its inline TeX and stages the
;; recorded drawing before the project workers start.
(require animate/slides)

(provide film)

(define film
  (storyboard #:id 'inline-tex-worker #:theme lecture-dark
    (storyboard-shot
     'explain
     (build-slide
      (slide #:layout 'title
        [title "The derivative of $x^2$ is $2x$."]
        [subtitle "At $x_0$, $\\frac{\\Delta y}{\\Delta x}\\to2x_0$." ])
      #:initial 'hidden
      (beat 'reveal #:duration 1/2
            (reveal-slot 'title #:duration 1/4)
            (reveal-slot 'subtitle #:duration 1/4))))))
