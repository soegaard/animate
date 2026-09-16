#lang racket/base
(require "../../main.rkt" "../../math.rkt"
         (only-in "../math-lesson.rkt" plan))
(provide gallery-entry-shots)
(define (gallery-entry-shots id theme fmt)
  (define card
    (slide #:layout 'title+figure [title "Keep both sides equal"]
      [figure (math-content plan)]))
  (list
   (storyboard-shot id
     (build-slide card
       (beat 'read #:duration 1.2)
       (beat 'subtract #:narration (narration "Subtract five on both sides." #:draft-duration 2)
         (play-content 'figure #:to '(subtract-five end)))
       (beat 'cancel #:narration (narration "The opposite terms cancel." #:draft-duration 2)
         (play-content 'figure #:to '(cancel-five end)))
       (beat 'calculate #:narration (narration "The right side is twelve." #:draft-duration 2)
         (play-content 'figure #:to '(evaluate-rhs end)))
       (beat 'hold #:duration 1.8)))))
