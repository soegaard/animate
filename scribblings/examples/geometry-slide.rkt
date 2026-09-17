#lang racket/base
(require animate/slides animate/slides/geometry
         (only-in animate/geometry/examples/equilateral-triangle equilateral-triangle))
(provide card clip film)

;; doc: content begin
(define card
  (slide #:layout 'title+figure
    [title "Construct equal sides"]
    [figure (geometry-content equilateral-triangle)]))
;; doc: content end

;; doc: play begin
(define clip
  (build-slide card
    (beat 'construct
      #:narration
      (narration "Construct an equilateral triangle with two circles."
                 #:draft-duration 4)
      (play-content 'figure))
    (beat 'hold #:duration 2)))
;; doc: play end

(define film
  (storyboard #:id 'manual-geometry #:theme lecture-dark
    (storyboard-shot 'geometry-construction clip)))
