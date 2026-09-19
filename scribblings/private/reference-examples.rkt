#lang racket/base

;; One isolated evaluator per reference page. Examples inspect semantic model
;; values; they do not invoke TeX, write image files, or render animation frames.
(require scribble/example)
(provide (all-from-out scribble/example)
         make-visuals-reference-eval)

(define (make-visuals-reference-eval)
  (define evaluator (make-base-eval))
  (evaluator '(require animate))
  evaluator)
