#lang racket/base
(require animate/slides)
(provide comparison-layout comparison film)
(define comparison-layout
  (layout #:id 'comparison
    #:slots (list (slot-spec 'heading #:required? #t #:role 'title)
                   (slot-spec 'left #:required? #t)
                   (slot-spec 'right #:required? #t))
    #:arrange
    (vbox
     (region 'heading #:basis 'content)
     (hbox #:grow 1 #:gap 'column-gap
       (region 'left #:grow 1)
       (region 'right #:grow 1)))
    #:portrait
    (vbox
     (region 'heading #:basis 'content)
     (region 'left #:grow 1)
     (region 'right #:grow 1))
    #:fallback 'wide))
(define comparison
  (slide #:id 'comparison #:layout comparison-layout
    [heading "One description, two outputs"]
    [left (bullets [pict "slide->pict"] [static "Documents and static previews."])]
    [right (bullets [scene "slide->scene"] [movie "Ordinary native animation."]) ]))
(define film
  (storyboard #:id 'comparison #:theme lecture-light
    (storyboard-shot 'comparison (hold-slide comparison #:duration 5))))
