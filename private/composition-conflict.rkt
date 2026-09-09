#lang racket/base

;;;
;;; Pure composition conflict vocabulary
;;;

;; Concrete request families supply immutable effect summaries. This module
;; deliberately does not know Visuals, scene state, or renderers; it only
;; compares already-resolved write coordinates.

(provide (struct-out request-effects)
         request-effects-first-write-conflict)

(struct request-effects
  (reads writes structural-reads structural-writes helpers)
  #:transparent)

(define (request-effects-first-write-conflict left right)
  (unless (request-effects? left)
    (raise-argument-error
     'request-effects-first-write-conflict "request-effects?" left))
  (unless (request-effects? right)
    (raise-argument-error
     'request-effects-first-write-conflict "request-effects?" right))
  (for/first ([coordinate (in-list (request-effects-writes left))]
              #:when (member coordinate (request-effects-writes right)))
    coordinate))
