#lang racket/base

;;;
;;; Advanced Experimental Building Blocks
;;;

;; This module intentionally contains lower-level escape hatches that are not
;; the ordinary relation-first authoring API.  A generic derived resolver may
;; close over arbitrary procedures, so it is useful for prototypes but cannot
;; provide the transparent dependency/cache semantics of relation-visual.

(require "private/derived-visual.rkt")

(provide (all-from-out "private/derived-visual.rkt"))
