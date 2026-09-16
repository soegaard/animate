#lang racket/base
(require "../../main.rkt" "../../geometry.rkt"
         (only-in "../../../geometry/examples/equilateral-triangle.rkt" equilateral-triangle))
(provide gallery-entry-shots)
(define (gallery-entry-shots id theme fmt)
  (define card
    (slide #:layout 'title+figure [title "Construct equal sides"]
      [figure (geometry-content equilateral-triangle)]))
  (list
   (storyboard-shot id
     (build-slide card
       (beat 'construct
         #:narration (narration "Construct an equilateral triangle with two circles." #:draft-duration 4)
         (play-content 'figure))
       (beat 'hold #:duration 2)))))
