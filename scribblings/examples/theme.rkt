#lang racket/base
(require animate/slides animate/typography)
(provide course-theme)

(define base-type (slide-theme-typography lecture-dark))
(define course-type
  (typography-theme #:id 'course-type #:extends base-type
    #:styles
    (hash 'title
          (text-style-update (typography-ref base-type 'title)
                             #:font-family 'roman #:font-size 0.72))))

(define course-theme
  (slide-theme #:id 'course #:extends lecture-dark
    #:typography course-type
    #:spacing (hash 'safe-x 0.8 'column-gap 0.7)
    #:decorations (hash 'title-rule? #t)))
