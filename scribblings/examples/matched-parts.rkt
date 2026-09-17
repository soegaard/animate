#lang racket/base
(require animate/slides)
(provide make-idea-panel before after film)

;; The words are ordinary text, but their correspondence comes from names.
;; Reordering the declaration list does not change those identities.
;; doc: parts begin
(define (make-idea-panel final?)
  (define row
    (semantic-group #:width 10 #:height 3
      (semantic-part 'observe "Observe"
                     #:x (if final? 6 0) #:y 0 #:width 4 #:height 1.2)
      (semantic-part 'explain "Explain"
                     #:x (if final? 0 6) #:y 1.6 #:width 4 #:height 1.2)))
  (semantic-group #:width 12 #:height 6
    (semantic-part 'ideas row #:x (if final? 0 1) #:y (if final? 1.4 0.4)
                   #:width (if final? 9 10) #:height 3)
    (semantic-part (if final? 'conclusion 'question)
                   (if final? "Connect the ideas." "What do we notice?")
                   #:x 1 #:y 4.5 #:width 10 #:height 1)))

;; doc: parts end

;; doc: slides begin
(define before
  (slide #:layout 'title+figure
    [title "The parts keep their identities"]
    [figure #:key 'ideas (make-idea-panel #f)]))
(define after
  (slide #:layout 'title+figure
    [title "The parts keep their identities"]
    [body "The panel moves. Its named children rearrange independently."]
    [figure #:key 'ideas (make-idea-panel #t)]))
;; doc: slides end

;; doc: match begin
(define film
  (storyboard #:id 'manual-parts #:theme lecture-dark
    (storyboard-shot 'before (hold-slide before #:duration 2))
    (slide-transition #:effect 'match #:keys '(ideas) #:depth 'semantic
                      #:duration 2.5 #:easing 'smooth)
    (storyboard-shot 'after (hold-slide after #:duration 3))))
;; doc: match end
