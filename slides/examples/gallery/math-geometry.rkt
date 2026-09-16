#lang racket/base

;; Two independently prepared native components share one explanatory layout.
;; The mathematical operations remain in animate/math; the layout layer only
;; allocates regions and advances the two component clocks.
(require "../../../math/main.rkt"
         "../../main.rkt" "../../math.rkt" "../../geometry.rkt"
         (only-in "../../../geometry/examples/equilateral-triangle.rkt" equilateral-triangle))
(provide gallery-entry-shots perimeter-plan)
(define perimeter
  (math '(= (* 3 s) 12) #:id 'perimeter #:context (math-context #:real '(s))))
(define perimeter-plan
  (present
   (derive perimeter
     [divide-three (both-sides 'divide 3)]
     [reduce-left (cancel-factor #:at (lhs) #:factor 3 #:keep-one? #t)]
     [remove-one (remove-unit #:at (lhs))]
     [evaluate-four (evaluate #:at (rhs))])
   #:style classroom #:groups '((divide-three reduce-left remove-one evaluate-four))))
(define (gallery-entry-shots id theme fmt)
  (define card
    (slide #:layout 'title+two-column [title "From a figure to an equation"]
      [left (geometry-content equilateral-triangle #:aspect 16/9)]
      [right (math-content perimeter-plan #:aspect 16/9)]
      [footer "Perimeter 12. Three equal sides. Each is 4."]))
  (list
   (storyboard-shot id
     (build-slide card
       (beat 'explain
         #:narration (narration "The sides are equal. Divide the perimeter by three." #:draft-duration 4)
         (play-content 'left)
         (play-content 'right))
       (beat 'hold #:duration 2)))))
