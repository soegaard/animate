#lang racket/base

;; Open a genuine authored timeline in the interactive preview.  In contrast
;; to source-block-hot-reload.rkt's `block` selector, this window's `section`
;; selector contains editorial time ranges supplied by the author.

(require "authoring-sections.rkt"
         "../preview.rkt")

(module+ main
  (void
   (open-scene-preview (make-demo-timeline)
                       #:title "Animate: authored sections")))
