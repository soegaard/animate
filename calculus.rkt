#lang racket/base

;;;
;;; Calculus Collection Façade
;;;

;; The public `animate/calculus` collection path follows Animate's established
;; one-file façades while the implementation remains split into calculus/main.
;; Re-exporting here keeps the documented ordinary require path independent of
;; the private source layout.

(require "calculus/main.rkt")

(provide (all-from-out "calculus/main.rkt"))
