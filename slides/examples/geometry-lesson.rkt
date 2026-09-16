#lang racket/base
(require animate/slides animate/slides/geometry
         (only-in animate/geometry/examples/equilateral-triangle equilateral-triangle))
(provide card film)
(define card
  (slide #:id 'construction #:layout 'title+figure
    [title "Constructing an equilateral triangle"]
    [figure (geometry-content equilateral-triangle)]))
(define film
  (storyboard #:id 'geometry-lesson #:theme lecture-light
    (storyboard-shot 'construction
      (build-slide card
        (beat 'introduce #:duration 2)
        ;; The native component's duration wins if it exceeds this silent draft.
        (beat 'construct #:narration (narration "Construct equal sides using the two circles." #:draft-duration 4)
          (play-content 'figure))
        (beat 'result #:duration 3)))))
