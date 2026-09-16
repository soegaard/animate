#lang racket/base
(require animate/slides)
(provide film)
(define film
  (storyboard #:id 'fixture #:theme lecture-light
    (storyboard-shot 'short
      (hold-slide (slide #:layout 'title [title "Worker test"]) #:duration 1/2))))
