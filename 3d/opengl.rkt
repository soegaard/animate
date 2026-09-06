#lang racket/base

;;;
;;; Explicit Racket/OpenGL 3D Backend
;;;

;; Requiring this module is the opt-in boundary that loads racket/gui/base and
;; the `opengl` package.  It is intentionally not re-exported by `animate`,
;; `animate/3d`, or `animate/3d/render`, which remain headless.

(require "../private/3d/opengl/renderer.rkt")

(provide opengl-renderer3d
         opengl-renderer3d?
         opengl-renderer3d-available?
         opengl-renderer3d-info
         opengl-renderer3d-statistics
         opengl-renderer3d-reset-statistics!
         opengl-renderer3d-release!
         opengl-renderer3d-spec
         opengl-renderer3d-spec?)
