#lang racket/base
(require animate/slides animate/slides/gallery)
(provide film make-demo)

;; doc: gallery begin
(define (make-demo effect)
  (make-slide-gallery #:entries (list effect) #:theme lecture-dark))
(define film (make-demo 'push-left))
;; doc: gallery end
