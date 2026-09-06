#lang racket/base

;;;
;;; Centralized RacketGL Binding Surface
;;;

;; No other OpenGL implementation module requires `opengl` directly.  Keeping
;; the FFI binding here makes the context boundary auditable and lets unit
;; tests exercise resource/cache state machines with ordinary Racket callbacks.

(require opengl
         opengl/util
         ffi/vector)

(provide (all-from-out opengl
                       opengl/util
                       ffi/vector))
