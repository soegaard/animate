#lang racket/base

;; Drop this geometry/ directory into the animate repository root. The normal
;; API includes native scene conversion; core.rkt is available without animate.
(require "core.rkt" "animate.rkt")
(provide (all-from-out "core.rkt" "animate.rkt"))
