#lang racket/base

;;;
;;; Acyclic Live Layout Conveniences
;;;

;; These constructors are thin, declarative names over the renderer-aware
;; attachment model. The Pict adapter resolves a target attachment recursively,
;; so a finite acyclic chain remains live at every sampled scene state.

(require "attachment.rkt"
         "geometry.rkt"
         "layout-attachment.rkt"
         "visual-model.rkt")

(provide follow-anchor
         keep-above
         keep-below
         keep-left-of
         keep-right-of)

;; follow-anchor is the explicit SCENE-DE name for a general live relationship.
(define (follow-anchor content target
                       #:offset [offset origin]
                       #:target-anchor [target-anchor 'center]
                       #:self-anchor [self-anchor 'center])
  (attach-to content target
             #:offset offset
             #:target-anchor target-anchor
             #:self-anchor self-anchor))

(define (keep-above content target #:gap [gap 0])
  (check-gap 'keep-above gap)
  (follow-anchor content target
                 #:target-anchor 'top #:self-anchor 'bottom
                 #:offset (vec2 0 gap)))

(define (keep-below content target #:gap [gap 0])
  (check-gap 'keep-below gap)
  (follow-anchor content target
                 #:target-anchor 'bottom #:self-anchor 'top
                 #:offset (vec2 0 (- gap))))

(define (keep-left-of content target #:gap [gap 0])
  (check-gap 'keep-left-of gap)
  (follow-anchor content target
                 #:target-anchor 'left #:self-anchor 'right
                 #:offset (vec2 (- gap) 0)))

(define (keep-right-of content target #:gap [gap 0])
  (check-gap 'keep-right-of gap)
  (follow-anchor content target
                 #:target-anchor 'right #:self-anchor 'left
                 #:offset (vec2 gap 0)))

(define (check-gap who gap)
  (unless (and (finite-real? gap) (not (negative? gap)))
    (raise-argument-error who "nonnegative finite real?" gap)))
