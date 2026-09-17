#lang racket/base
(require animate/slides)
(provide opening rule-slide rule-clip recap-slide recap-clip film)
;; doc: opening begin
(define opening
  (hold-slide
   (slide #:id 'opening-card #:layout 'title
     [title "A function is a rule"]
     [subtitle "A small example: double, then add one."])
   #:duration 3))
;; doc: opening end

;; doc: rule begin
(define rule-slide
  (slide #:id 'rule-card #:layout 'title+two-column
    [title #:key 'lesson-heading "A function is a rule"]
    [left (bullets [double "Double the input."] [add "Add one."])]
    [right (paragraph-content "Input: 3\nDouble it: 6\nAdd one: 7")]))
;; doc: rule end

;; doc: rule-timing begin
(define rule-clip
  (build-slide rule-slide #:initial '(title)
    (beat 'rule #:duration 4 (reveal-slot 'left #:duration 0.5))
    (beat 'example #:duration 5 (reveal-slot 'right #:duration 0.5))
    (beat 'read #:duration 2)))
;; doc: rule-timing end

;; doc: recap begin
(define recap-slide
  (slide #:id 'recap-card #:layout 'title+body
    [title #:key 'lesson-heading "A function is a rule"]
    [body (bullets [rule "The rule is f(x) = 2x + 1."]
                    [example "For input 3, the output is 7."])]))
(define recap-clip
  (build-slide recap-slide #:initial '(title)
    (beat 'summary #:duration 5 (reveal-slot 'body #:duration 0.5))))
;; doc: recap end

;; Exactly 19.6 seconds. Transition time is additional, never stolen from a beat.
;; doc: storyboard begin
(define film
  (storyboard #:id 'function-lesson #:theme lecture-light
    (storyboard-shot 'opening opening)
    (storyboard-cut)
    (storyboard-shot 'rule rule-clip)
    (slide-transition #:effect 'match #:keys '(lesson-heading) #:duration 0.6)
    (storyboard-shot 'recap recap-clip)))

;; doc: storyboard end
