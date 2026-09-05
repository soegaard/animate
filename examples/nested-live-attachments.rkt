#lang racket/base

;;;
;;; SCENE-CD: Live Attachments to Nested Visuals
;;;

;; A world-space highlight and a frame-space callout both target an imported
;; SVG child through one nested path. They stay connected while the enclosing
;; group moves and rotates.

(require racket/math
         racket/runtime-path
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
           #:center (vec2 -2 0)
           #:rotation -1/10))
  (define window-path
    '(launch rocket-diagram rocket window))
  (define badge
    (follow-anchor
     (circle #:id 'window-badge
             #:center origin
             #:radius 11/20
             #:fill "white"
             #:stroke "gold"
             #:stroke-width 4)
     window-path))
  (define note
    (callout
     (plain-text "nested window"
                 #:id 'window-note
                 #:center origin
                 #:font-size 7/25
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     window-path
     #:at (vec2 4 5/2)
     #:connector-stroke "darkorange"
     #:connector-width 3))
  (define title
    (plain-text "SCENE-CD: live nested attachments"
                #:id 'title
                #:center (vec2 0 16/5)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "A highlight and callout follow the SVG window through its parent transform."
                #:id 'explanation
                #:center (vec2 0 -16/5)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "darkslategray"))
  (define initial
    (scene-add (make-scene) title explanation launch badge note))
  (define shown
    (scene-wait initial 1))
  (define moved
    (scene-play shown
                (move-to launch (vec2 1 -1/2))
                (rotate-to launch (/ pi 7))
                #:duration 2))
  (scene-wait moved 1))

(module+ main
  (run-demo "nested-live-attachments.rkt" make-demo-scene))
