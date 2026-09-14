#lang racket/base

;;;
;;; Native Module Loading
;;;
;; Centralizes effectful native-module resolution and its injectable test boundary. A
;; contract-model loader is never presented as the real renderer.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/runtime-path define-runtime-path)
  (for-syntax racket/base)
  "validation.rkt")

;; Exports
(provide native current-native-loader native-root)

;;;
;;; Construction and Operations
;;;
; native-root : path?
;;   Locates the parent repository public animate module.
(define-runtime-path native-root "../../main.rkt")

; native-private : path?
;;   Locates the parent repository native adapter helpers.
(define-runtime-path native-private "../../private")

; default-loader : any/c symbol? -> any/c
;;   Loads an approved native module binding or reports the missing dependency.
(define (default-loader scope name)
  (define module
    (case scope
      [(animate) native-root]
      [(tagged) (build-path native-private "tagged-formula.rkt")]
      [(formula) (build-path native-private "formula-visual.rkt")]
      [(parts) (build-path native-private "formula-parts-visual.rkt")]
      [(pict) 'pict]
      [(svg) 'svg/svg]
      [else (error 'animate/math "Unknown native module scope: ~s" scope)]))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (error 'animate/math
                       "Unable to load ~a from ~a. Put math/ in the animate repository root and install animate's dependencies.\n~a"
                       name
                       module
                       (exn-message e)))])
    (dynamic-require module name)))

; current-native-loader : (parameter/c procedure?)
;;   Selects a native-module loader for an explicit dynamic adapter extent.
(define current-native-loader
  (make-parameter default-loader
    (lambda (loader) (check-procedure 'current-native-loader loader 2))))

; native : any/c symbol? -> procedure?
;;   Resolves a native binding through the explicit loader without a global registry.
(define (native scope name)
  ((current-native-loader) scope name))
