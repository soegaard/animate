#lang racket/base

;;;
;;; SCENE-CH Explanatory Camera Focus
;;;

;; Focus one nested SVG detail together with the explanatory annotation that
;; gives it meaning, then return to the complete diagram. Frame-fixed titles
;; are deliberately not context: they remain an overview concern.

(require racket/cmdline
         racket/runtime-path
         "../main.rkt")

(provide make-demo-scene)

(define-runtime-path assets-directory "assets")


;;; Scene Definition

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CH: explanatory camera focus"
                #:id 'title
                #:center (vec2 0 3)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define rocket
    (svg->visual
     (build-path assets-directory "roadmap-rocket.svg")
     #:id 'rocket-diagram
     #:scale 6/5))
  (define launch
    (group (list rocket)
           #:id 'launch
           #:center (vec2 -2 0)))
  (define window-path
    '(launch rocket-diagram rocket window))
  (define note-panel
    (rectangle #:id 'note-panel
               #:width 4
               #:height 3/2
               #:fill "aliceblue"
               #:stroke "navy"
               #:stroke-width 2))
  (define note-heading
    (plain-text "window"
                #:id 'note-heading
                #:center (vec2 0 1/4)
                #:font-size 3/10
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define note-detail
    (plain-text "focus includes the explanation"
                #:id 'note-detail
                #:center (vec2 0 -1/4)
                #:font-size 1/5
                #:font-family 'swiss
                #:color "darkslategray"))
  (define focus-note
    (group (list note-panel note-heading note-detail)
           #:id 'focus-note
           #:center (vec2 3/2 0)))
  (define initial-camera
    (make-camera #:world-width 16 #:center (vec2 0 0)))
  (define initial
    (scene-add (make-scene #:camera initial-camera)
               title launch focus-note))
  (define focused
    (scene-play
     initial
     (camera-focus initial
                   window-path
                   #:context (list focus-note)
                   #:padding 1/2)
     #:duration 3/2))
  (define overview
    (scene-play
     focused
     (camera-fit-scene focused #:padding 1/2)
     #:duration 3/2))
  (scene-wait overview 1))


;;; Command-Line Entry Point

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "explanatory-camera-focus.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
