#lang racket/base

;;;
;;; Formula Visuals Example
;;;

;; Renders the canonical SCENE-M LaTeX formula, anchor, group, transform, and
;; fade example as PNG frames and optionally assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Animates a formula card and one baseline-anchored inline formula.
(define (make-demo-scene)
  (define identity-formula
    (latex-formula "e^{i\\pi}+1=0"
                   #:id 'identity-formula
                   #:center (vec2 0 1/2)
                   #:font-size 1/2))
  (define series-formula
    (latex-formula
     "\\sum_{k=1}^{n} k = \\frac{n(n+1)}{2}"
     #:id 'series-formula
     #:center (vec2 0 -1)
     #:font-size 1/3))
  (define card-title
    (plain-text "Mathematical formulas"
                #:id 'card-title
                #:center (vec2 0 3/2)
                #:font-size 1/3
                #:font-family 'swiss
                #:font-weight 'bold
                #:color "navy"))
  (define formula-card
    (group
     (list
      (rectangle #:id 'card-background
                 #:width 8
                 #:height 5
                 #:fill "aliceblue"
                 #:stroke "navy"
                 #:stroke-width 4)
      card-title
      identity-formula
      series-formula)
     #:id 'formula-card
     #:center (vec2 -6 1)
     #:rotation -1/6
     #:scale 3/4
     #:opacity 9/10))
  (define inline-formula
    (latex-formula "f'(x)=2x"
                   #:id 'inline-formula
                   #:center (vec2 -5 -5/2)
                   #:mode 'inline
                   #:font-size 2/5
                   #:horizontal-alignment 'left
                   #:vertical-alignment 'baseline))
  (define entrance
    (scene-play (make-scene)
                (move-to formula-card origin)
                (rotate-to formula-card 0)
                (scale-to formula-card 1)
                (fade-in formula-card)
                (fade-in inline-formula)
                #:duration 2))
  (define emphasis
    (scene-play entrance
                (move-to formula-card (vec2 0 1/2))
                (rotate-by formula-card 1/12)
                (scale-to formula-card 6/5)
                (move-to inline-formula (vec2 -2 -5/2))
                (scale-to inline-formula 3/2)
                #:duration 1))
  (define exit
    (scene-play emphasis
                (move-to formula-card (vec2 6 1))
                (rotate-by formula-card 1/4)
                (scale-to formula-card 3/4)
                (fade-out formula-card)
                (fade-out inline-formula)
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
   #:program "formula-visuals.rkt"
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
