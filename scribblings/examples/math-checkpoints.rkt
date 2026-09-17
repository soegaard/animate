#lang racket/base
(require animate/math animate/slides animate/slides/math)
(provide problem working plan equation before-card after-card film)

;; doc: problem begin
(define problem
  (math '(= (+ (* 3 x) 5) 17) #:id 'problem
        #:context (math-context #:real '(x))))
;; doc: problem end

;; doc: derive begin
(define working
  (derive problem
    [subtract-five (both-sides 'subtract 5)]
    [cancel-five (cancel-addends #:at (lhs))]
    [evaluate-rhs (evaluate #:at (rhs))]))
;; doc: derive end

;; doc: plan begin
(define plan
  (present working #:style classroom
           #:groups '((subtract-five cancel-five evaluate-rhs))))
(define equation (math-content plan))

;; doc: plan end

;; doc: before begin
(define before-card
  (slide #:layout 'title+figure
    [title "Keep the algebra, change the layout"]
    [figure #:key 'work
     (content-state equation #:at '(subtract-five start)
                    #:viewport '(12 7))]))
;; doc: before end

;; doc: after begin
(define after-card
  (slide #:layout 'title+figure
    [title "Keep the algebra, change the layout"]
    [body "Subtract five on both sides. Cancel the opposites. Evaluate the right side."]
    [figure #:key 'work
     (content-state equation #:at '(evaluate-rhs end)
                    #:viewport '(12 7))]))

;; doc: after end

;; doc: match begin
(define film
  (storyboard #:id 'math-checkpoints #:theme lecture-dark
    (storyboard-shot 'before (hold-slide before-card #:duration 2))
    (slide-transition #:effect 'match #:keys '(work)
                      #:depth 'semantic #:duration 4 #:easing 'smooth)
    (storyboard-shot 'after (hold-slide after-card #:duration 3))))

;; doc: match end
