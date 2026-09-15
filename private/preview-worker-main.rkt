#lang racket/base

;;;
;;; Legacy Preview Worker Entry Point
;;;

;; The shared render-worker entry point owns the protocol and executable loop.
;; Requiring this compatibility module is deliberately inert; only `racket -m`
;; starts a child loop.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "render-worker-main.rkt")

;; Exports
(provide run-preview-worker!)


;;;
;;; Compatibility Procedure
;;;

; run-preview-worker! : -> void?
;;   Runs the shared worker loop for callers retaining the former entry point.
(define (run-preview-worker!)
  (run-render-worker!))


;;;
;;; Explicit Executable Entry Point
;;;

(module+ main
  (run-preview-worker!))
