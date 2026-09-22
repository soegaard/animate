#lang racket/base

;;;
;;; Inline TeX Review Storyboard
;;;

;; A compact real storyboard used by the consolidated review runner. It is
;; ordinary author-facing slide code, not a review-only rendering path.

(require animate/slides)

(provide inline-tex-review-film)

(define before
  (slide #:layout 'title+body
    [title "The difference quotient"]
    [body
     (bullets
      [idea "For $h\\neq0$, compare two nearby values (price: \\$5)."]
      [slope "The secant slope is $\\frac{f(x_0+h)-f(x_0)}{h}$."])]
    [footer "$x_0$; \\$5"]))

(define after
  (slide #:layout 'title+body
    [title "Take the limit"]
    [body
     (paragraph-content
      "As $h\\to0$, $\\frac{(x_0+h)^2-x_0^2}{h}$ approaches $2x_0$.")]
    [footer "$2x_0$"]))

(define inline-tex-review-film
  (storyboard #:id 'inline-tex-review #:theme lecture-dark
    (storyboard-shot
     'before
     (build-slide before #:initial 'hidden
       (beat 'reveal #:duration 1
         (reveal-slot 'title #:duration 1/3)
         (reveal-slot 'body #:duration 2/3))))
    (slide-transition #:effect 'crossfade #:duration 1/2)
    (storyboard-shot
     'after
     (build-slide after #:initial 'hidden
       (beat 'reveal #:duration 1
         (reveal-slot 'title #:duration 1/3)
         (reveal-slot 'body #:duration 2/3))))))
