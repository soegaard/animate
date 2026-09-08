#lang racket/base

;;; SCENE-3D-V10: OpenGL material, light, and fragment inspection

;; A direct GRacket launcher for the same finite-light scene as
;; `lighting-inspector.rkt`, but through the explicit retained OpenGL project
;; backend.  Keeping this as a one-file launcher avoids the preview CLI when
;; an author wants terminal diagnostics beside the interactive inspector.

(require animate/preview
         "opengl-finite-lighting-project.rkt")

(module+ main
  (open-project-preview opengl-finite-lighting-project
                        #:title "Animate: OpenGL 3D lighting inspector"))
