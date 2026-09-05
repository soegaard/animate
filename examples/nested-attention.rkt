#lang racket/base

;;;
;;; SCENE-CE: Attention for a Nested SVG Part
;;;

;; `circumscribe` and `indicate` now accept the same explicit nested paths as
;; child animation, copying, callouts, and live attachments.

(require racket/runtime-path
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define-runtime-path assets-directory "assets")

(define (make-demo-scene)
  (define rocket
    (svg->visual
     (build-path assets-directory "roadmap-rocket.svg")
     #:id 'rocket-diagram
     #:scale 4/5))
  (define launch
    (group (list rocket)
           #:id 'launch
           #:center (vec2 0 -1/3)
           #:rotation -1/8))
  (define window-path
    '(launch rocket-diagram rocket window))
  (define title
    (plain-text "SCENE-CE: nested attention"
                #:id 'title
                #:center (vec2 0 3)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "The outline measures the nested SVG window in world coordinates."
                #:id 'explanation
                #:center (vec2 0 -3)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title explanation launch))
  (define circumscribed
    (scene-play initial
                (circumscribe window-path
                               #:padding 1/8
                               #:color "crimson"
                               #:stroke-width 3)
                #:duration 1))
  (define indicated
    (scene-play circumscribed
                (indicate window-path
                          #:padding 1/8
                          #:color "goldenrod"
                          #:stroke-width 3)
                #:duration 1))
  (scene-wait indicated 1))

(module+ main
  (run-demo "nested-attention.rkt" make-demo-scene))
