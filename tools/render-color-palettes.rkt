#lang racket/base

;;;
;;; Animate Palette Sheet Tool
;;;

;; The plural command is the documented entry point.  It delegates to the
;; original deterministic SVG generator so there is still exactly one source
;; of geometry and one source of numerical swatches.

(require racket/cmdline
         "render-color-palette-sheet.rkt")

(define output-path
  (command-line
   #:program "render-color-palettes.rkt"
   #:args [destination]
   destination))

(render-color-palette-sheet! output-path)
