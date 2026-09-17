#lang racket/base

(require scribble/example)

(provide (all-from-out scribble/example)
         make-guide-eval)

;; Create one isolated evaluator per Guide chapter. `guide-pict` exists only
;; inside the evaluator: `eval:alts` can therefore show a plain user-facing
;; `(scene->pict ...)` call while evaluating a documentation-sized rendering.
(define (make-guide-eval)
  (define ev (make-base-eval))
  (ev '(require (only-in pict frame scale)))
  (ev
   '(define (guide-pict p)
      ;; Scale the ordinary 1280x720 Scene result first, then add the border so
      ;; the border remains one Pict unit instead of being scaled with the image.
      (frame (scale p 3/8)
             #:color "gray"
             #:line-width 1)))
  ev)
