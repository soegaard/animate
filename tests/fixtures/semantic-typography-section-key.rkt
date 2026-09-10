#lang racket/base

;; This fixture is instantiated in fresh namespaces by the semantic typography
;; regression test. Keeping the inherited-override marker inside the module
;; body reproduces the old module-instantiation failure mode.

(require "../../authoring.rkt"
         "../../main.rkt"
         "../../private/section-renderer.rkt")

(provide semantic-section-key)

(define (semantic-section-key)
  (define heading (title-text "A semantic title" #:id 'heading))
  (define timeline
    (make-authored-timeline
     (scene-wait (scene-add (make-scene) heading) 1)
     #:sections (list (section 'only 0 1))))
  (automatic-section-cache-key
   timeline (timeline-section timeline 'only)
   #:fps 1 #:camera #f #:renderers '() #:asset-files '()))
