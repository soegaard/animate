#lang racket/base

;; A renderable, tool-free tour of the transition catalogue. The native video
;; runner can load this exported storyboard just like any other example.
(require animate/slides animate/slides/gallery
         (only-in "gallery/transitions.rkt"))
(provide film)
(define film
  (make-slide-gallery #:entries '(cut crossfade match push-left wipe-left cover-left uncover-left zoom fade-through)
                      #:theme lecture-dark))
