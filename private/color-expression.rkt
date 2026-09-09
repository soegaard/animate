#lang racket/base

;;;
;;; Color Expressions
;;;

;; Defines immutable, unresolved color-expression representation. Validation
;; belongs to the color-style facade so it can recognize literal and token
;; specifications without introducing renderer or theme dependencies.


;;;
;;; Imports and Exports
;;;

;; Exports
(provide mix-color?
         mix-color-from
         mix-color-to
         mix-color-amount
         mix-color-space
         mix-color-alpha-mode
         alpha-color?
         alpha-color-source
         alpha-color-operation
         alpha-color-amount
         color-expression?
         make-mix-color
         make-alpha-color)


;;;
;;; Data Representation
;;;

;; Constructors remain private to Animate. Values stored by these structures are
;; normalized immutable color specifications supplied by private/color-style.
(struct mix-color (from to amount space alpha-mode) #:transparent)
(struct alpha-color (source operation amount) #:transparent)


;;;
;;; Predicates and Internal Constructors
;;;

;; color-expression? : any/c -> boolean?
;;   Reports whether value is an unresolved mix or alpha expression.
(define (color-expression? value)
  (or (mix-color? value) (alpha-color? value)))

;; make-mix-color : any/c any/c finite-real? symbol? symbol? -> mix-color?
;;   Packages an already-validated unresolved mix expression.
(define (make-mix-color from to amount space alpha-mode)
  (mix-color from to amount space alpha-mode))

;; make-alpha-color : any/c symbol? finite-real? -> alpha-color?
;;   Packages an already-validated unresolved alpha expression.
(define (make-alpha-color source operation amount)
  (alpha-color source operation amount))
