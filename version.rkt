#lang racket/base

;;;
;;; Animate Release Identity
;;;

;; Defines the one release identity shared by the package, command-line tools,
;; diagnostics, and documentation.


;;;
;;; Imports and Exports
;;;

;; Exports
(provide animate-version
         animate-stage)


;;;
;;; Release Identity
;;;

; animate-version : string?
;;   Gives the current prototype package version.
(define animate-version
  "1.22.0")

; animate-stage : symbol?
;;   Identifies the current implementation stage.
(define animate-stage
  'SCENE-3D-P)
