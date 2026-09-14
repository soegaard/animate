#lang racket/base

;;;
;;; Native Rendering Probes
;;;
;; Runs optional actual animate and TeX integration checks in the caller-selected output
;; directory.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "tests/native-integration.rkt" racket/cmdline)

;;;
;;; Construction and Operations
;;;
; output : path-string?
;;   Names the command-line probe output directory.
(define output
  "math-output/probes")

; theme : (or/c 'light 'dark)
;;   Selects the background used for the actual native probes.
(define theme 'light)

; dense? : boolean?
;;   Includes intermediate frames from every transformation family by default.
(define dense? #t)

(command-line
  #:once-each
  ["--dark" "Render dark probes." (set! theme 'dark)]
  ["--checkpoints-only" "Only render mathematical checkpoints." (set! dense? #f)]
  #:args ([directory output]) (set! output directory))

(run-native-integration! output #:theme theme #:dense? dense?)
