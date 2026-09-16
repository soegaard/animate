#lang racket/base

;; Pure source: programs and content declarations only. Realization, annotation
;; preparation, and rendering must occur behind the parent preparation boundary.
(require animate/slides animate/slides/geometry
         (only-in animate/geometry/examples/equilateral-triangle equilateral-triangle))
(provide ordinary semantic dark-portrait)
(define construction (geometry-content equilateral-triangle))
(define (snapshot time) (content-state construction #:at time #:viewport '(12 7)))
(define (make-semantic theme fmt)
  (storyboard #:id 'geometry-worker-semantic #:theme theme #:format fmt
    (storyboard-shot 'before
      (hold-slide (slide #:layout 'figure-full [figure #:key 'construction (snapshot '(1 end))])
                  #:duration 1/4))
    (slide-transition #:effect 'match #:keys '(construction) #:depth 'semantic #:duration 1 #:easing 'smooth)
    (storyboard-shot 'after
      (hold-slide (slide #:layout 'figure+caption [figure #:key 'construction (snapshot 'end)]
                         [caption "One prepared construction; independent frame workers."])
                  #:duration 1/4))))
(define ordinary
  (storyboard #:id 'geometry-worker-ordinary
    (storyboard-shot 'construction
      (build-slide (slide #:layout 'figure-full [figure construction])
        (beat 'draw #:duration 2
          (play-content 'figure #:from '(1 end) #:to 'end #:duration 2 #:retime 'stretch))))))
(define semantic (make-semantic lecture-light widescreen))
(define dark-portrait (make-semantic lecture-dark portrait))
