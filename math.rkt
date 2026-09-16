#lang racket/base

;; Public facade for the semantic mathematics subcollection.
;; Keep rendering/CAS adapters explicit in animate/math/render and animate/math/cas.
(require "math/main.rkt")
(provide (all-from-out "math/main.rkt"))
