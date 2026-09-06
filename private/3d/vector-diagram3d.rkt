#lang racket/base

;;;
;;; Spatial Vector Diagrams
;;;

;; This small public-facing layer gives vector-diagram constructors a focused
;; home.  They share the finite-axis implementation because both rely on the
;; same physical arrow and group primitives.

(require "axes3d.rkt")

(provide basis-vectors3d
         vector-arrow3d
         vector-components3d)
