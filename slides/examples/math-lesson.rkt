#lang racket/base
(require animate/math animate/slides animate/slides/math)
(provide problem working plan subtraction-slide subtraction-clip film)
(define problem
  (math '(= (+ (* 3 x) 5) 17) #:id 'problem
        #:context (math-context #:real '(x))))
(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-rhs (evaluate #:at (rhs))]))
(define plan
  (present working #:style classroom
    #:groups '((subtract-five cancel-five evaluate-rhs))))
(define subtraction-slide
  (slide #:id 'subtract-card #:layout 'title+figure
    [title "Subtract five from both sides"]
    [figure (math-content plan #:poster 'end)]))
(define subtraction-clip
  (build-slide subtraction-slide
    (beat 'goal #:narration
      (narration "We want to remove the added five from the left side." #:draft-duration 4))
    (beat 'subtract #:narration
      (narration "Subtract five on both sides." #:draft-duration 3)
      (play-content 'figure #:to '(subtract-five end)))
    (beat 'cancel #:narration
      (narration "The opposite terms cancel on the left side." #:draft-duration 3)
      (play-content 'figure #:to '(cancel-five end)))
    (beat 'calculate #:narration
      (narration "Seventeen minus five is twelve." #:draft-duration 3)
      (play-content 'figure #:to '(evaluate-rhs end)))
    (beat 'read-result #:duration 3)))
;; Draft narration provides silent timing plus subtitles. It does not synthesize speech.
(define film
  (storyboard #:id 'subtract-five-lesson #:theme lecture-dark
    (storyboard-shot 'subtract-five subtraction-clip)))
