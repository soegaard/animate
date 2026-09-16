#lang racket/base
(require animate/slides animate/slides/gallery
         (only-in animate/slides/examples/gallery/semantic-domains))
(provide film)
(define film (make-slide-gallery #:entries '(semantic-math-geometry) #:theme lecture-dark))
