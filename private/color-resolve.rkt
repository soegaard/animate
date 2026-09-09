#lang racket/base

;;;
;;; Explicit Color Resolution
;;;

;; Defines the public pure boundary from a color specification and immutable
;; theme snapshot to one concrete RGBA color.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "color-style.rkt"
         "color-theme.rkt")

;; Exports
(provide resolve-color)


;;;
;;; Public Resolution
;;;

;; resolve-color : color-spec? color-theme? -> rgba-color?
;;   Resolves one literal, token, or expression under an explicit theme.
(define (resolve-color color theme)
  (resolve-color-in-theme color theme))
