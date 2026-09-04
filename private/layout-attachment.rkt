#lang racket/base

;;;
;;; Shared Renderer-Layout Anchor Vocabulary
;;;

;; Renderer-aware relations, endpoint builders, and attachment conveniences
;; use the same nine box anchors.  This small module deliberately owns only
;; the vocabulary; the former attachment wrapper has been replaced by
;; first-class layout relations.

(provide layout-attachment-anchor?)

(define layout-attachment-anchor-symbols
  '(bottom-left bottom bottom-right
                left center right
                top-left top top-right))

(define (layout-attachment-anchor? value)
  (and (symbol? value)
       (memq value layout-attachment-anchor-symbols)
       #t))
