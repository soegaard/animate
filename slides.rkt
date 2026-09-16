#lang racket/base

;; Public collection-path facade.  Racket resolves `animate/slides` to this
;; file; the implementation itself remains in the slides/ subcollection.
(require "slides/main.rkt")
(provide (all-from-out "slides/main.rkt"))
