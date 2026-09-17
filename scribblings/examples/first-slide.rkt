#lang racket/base
(require animate/slides)
(provide welcome opening film)

;; doc: card begin
(define welcome
  (slide #:id 'welcome #:layout 'title
    [title "Solving equations"]
    [subtitle "Keep both sides equal."]))
;; doc: card end

;; doc: build begin
(define opening
  (build-slide welcome #:initial 'hidden
    (beat 'heading #:duration 1
      (reveal-slot 'title #:duration 0.4))
    (beat 'explanation #:duration 3
      (reveal-slot 'subtitle #:duration 0.5))))
;; doc: build end

(define film
  (storyboard #:id 'hello #:theme lecture-light
    (storyboard-shot 'opening opening)))
