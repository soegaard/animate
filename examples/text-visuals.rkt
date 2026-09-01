#lang racket/base

;;;
;;; Text Visuals Example
;;;

;; Renders the canonical SCENE-L plain-text, anchor, group, transform, and fade
;; example as PNG frames and optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Animates a text card and two anchor-aligned labels.
(define (make-demo-scene)
  (define title
    (plain-text "Visual Animation"
                #:id 'title
                #:center (vec2 0 2/5)
                #:font-size 4/5
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "white"))
  (define subtitle
    (plain-text "Racket + Rhombus"
                #:id 'subtitle
                #:center (vec2 0 -3/5)
                #:font-size 2/5
                #:font-family 'modern
                #:color "lightcyan"))
  (define card
    (group
     (list
      (rectangle #:id 'card-background
                 #:width 7
                 #:height 3
                 #:fill "royalblue"
                 #:stroke "navy"
                 #:stroke-width 4)
      title
      subtitle)
     #:id 'card
     #:center (vec2 -6 1)
     #:rotation -1/5
     #:scale 3/4
     #:opacity 9/10))
  (define left-label
    (plain-text "left anchor"
                #:id 'left-label
                #:center (vec2 -5 -5/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-style 'italic
                #:color "darkgreen"
                #:horizontal-alignment 'left
                #:vertical-alignment 'baseline))
  (define right-label
    (plain-text "right anchor"
                #:id 'right-label
                #:center (vec2 5 -5/2)
                #:font-size 2/5
                #:font-family 'swiss
                #:font-style 'italic
                #:color "darkred"
                #:horizontal-alignment 'right
                #:vertical-alignment 'baseline))
  (define entrance
    (scene-play (make-scene)
                (move-to card origin)
                (rotate-to card 0)
                (scale-to card 1)
                (fade-in card)
                (fade-in left-label)
                (fade-in right-label)
                #:duration 2))
  (define emphasis
    (scene-play entrance
                (move-to card (vec2 0 1/2))
                (rotate-by card 1/12)
                (scale-to card 6/5)
                (fade-to left-label 2/5)
                (fade-to right-label 2/5)
                #:duration 1))
  (define exit
    (scene-play emphasis
                (move-to card (vec2 6 1))
                (rotate-by card 1/4)
                (scale-to card 3/4)
                (fade-out card)
                (fade-out left-label)
                (fade-out right-label)
                #:duration 3/2))
  (scene-wait exit 1/2))


;;;
;;; Command-Line Entry Point
;;;

(module+ main
  ; output-directory : path-string?
  ;;   Gives the directory that receives numbered PNG frames.
  (define output-directory
    "frames")

  ; output-video : (or/c path-string? false/c)
  ;;   Gives the optional MP4 output path.
  (define output-video
    #f)

  (command-line
   #:program "text-visuals.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))

  ; frame-paths : (listof path?)
  ;;   Gives the numbered PNG paths written for the demo.
  (define frame-paths
    (render-frames! (make-demo-scene)
                    output-directory
                    #:fps 30))

  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)

  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
