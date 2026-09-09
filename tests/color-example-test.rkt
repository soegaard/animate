#lang racket/base

;;;
;;; Color Example Declaration Tests
;;;

;; Loading a color example must remain lazy: no renderer, TeX command, or
;; output process runs until an author calls its exported constructor.

(require racket/file
         rackunit
         racket/runtime-path
         "../colors.rkt")

(define-runtime-path examples-directory "../examples/colors")

(define color-example-names
  '(palette-sheet
    theme-switching
    literals-and-tokens
    themed-formula-derivation
    themed-color-transitions
    themed-plots-and-series
    themed-surface
    custom-theme))

(module+ test
  (for ([name (in-list color-example-names)])
    (define path (build-path examples-directory (format "~a.rkt" name)))
    (check-true (file-exists? path) (path->string path))
    (check-true (procedure? (dynamic-require path 'make-demo-scene))
                (path->string path)))
  (define custom-path (build-path examples-directory "custom-theme.rkt"))
  (check-true (color-theme? (dynamic-require custom-path 'demo-theme)))
  ;; The executable entry point selects the exported custom snapshot instead
  ;; of merely declaring it beside a default-theme render call.
  (check-true
   (regexp-match? #px"run-demo.*#:theme demo-theme"
                  (file->string custom-path))))
