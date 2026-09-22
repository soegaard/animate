#lang racket/base

;; CI preflight for the required latex-pict/Poppler integration. Requiring the
;; Racket package alone does not load its native PDF bridge, so render one
;; display formula through Animate's ordinary Pict adapter before longer suites
;; obscure a missing Poppler GLib runtime.

(require (only-in pict pict? pict-height pict-width)
         animate
         animate/render)

(define formula
  (latex-formula "x^2 + y^2 = z^2" #:id 'formula-preflight #:mode 'display))
(define rendered
  (scene->pict (scene-add (make-scene) formula) 0))

(unless (and (pict? rendered)
             (positive? (pict-width rendered))
             (positive? (pict-height rendered)))
  (error 'check-formula-rendering
         "display formula rendering did not produce visible Pict geometry"))

(displayln "Animate display-formula/Poppler preflight passed")
