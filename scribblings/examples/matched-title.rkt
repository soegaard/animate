#lang racket/base
(require animate/slides)
(provide title before after film)

;; doc: title begin
(define title (paragraph-content "Keep the idea" #:align 'left))
;; doc: title end

;; doc: cards begin
(define before
  (slide #:layout 'title
    [title #:key 'topic #:align 'center title]
    [subtitle "A centered introduction"]))
(define after
  (slide #:layout 'title+body
    [title #:key 'topic title]
    [body "The same prepared title moves to its new position.
Only the supporting content changes."]))
;; doc: cards end

;; doc: bridge begin
(define film
  (storyboard #:id 'manual-title-match #:theme lecture-dark
    (storyboard-shot 'before (hold-slide before #:duration 1.2))
    (slide-transition #:effect 'match #:keys '(topic)
                      #:duration 1 #:easing 'smooth)
    (storyboard-shot 'after (hold-slide after #:duration 1.8))))
;; doc: bridge end
