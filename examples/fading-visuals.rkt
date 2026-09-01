#lang racket/base

;;;
;;; Fading Visuals Example
;;;

;; Renders the canonical SCENE-J opacity example as PNG frames and optionally
;; assembles them as an MP4 file.


;;;
;;; Imports
;;;

(require racket/cmdline
         "../main.rkt")


;;;
;;; Scene Definition
;;;

; make-demo-scene : -> scene?
;;   Introduces, dims, restores, and removes Visuals through semantic opacity.
(define (make-demo-scene)
  (define panel
    (rectangle #:id 'panel
               #:center (vec2 0 0)
               #:width 8
               #:height 4
               #:fill "cornflowerblue"
               #:stroke "navy"
               #:stroke-width 3))
  (define token
    (circle #:id 'token
            #:center (vec2 -5 0)
            #:opacity 4/5
            #:radius 4/5
            #:fill "gold"
            #:stroke "darkorange"
            #:stroke-width 3))
  (define guide
    (line (vec2 -5 -2)
          (vec2 5 -2)
          #:id 'guide
          #:stroke "crimson"
          #:stroke-width 5))
  (define entrance
    (scene-play
     (scene-add (make-scene) panel guide)
     (fade-to panel 1/4)
     (move-to token (vec2 0 0))
     (rotate-by token 1)
     (fade-in token)
     #:duration 3/2))
  (define exit
    (scene-play entrance
                (fade-to panel 1)
                (move-to token (vec2 5 0))
                (fade-out guide)
                #:duration 1))
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
   #:program "fading-visuals.rkt"
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
