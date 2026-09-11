#lang racket/base

;; Existing examples now use the public standard library rather than a second
;; implementation with different contracts or narration.
(require (only-in "../constructions.rkt" perpendicular-bisector))
(provide perpendicular-bisector)
