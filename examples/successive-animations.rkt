#lang racket/base

;;;
;;; Successive Animations Example
;;;

;; SCENE-AO composes ordinary Visual animation requests sequentially inside one
;; scene-play. Direct succession children receive equal consecutive time slices.

(require racket/cmdline
         racket/math
         "../main.rkt")

(provide make-demo-scene)

(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 18
                 #:background "white"))
  (define card
    (rectangle #:id 'card
               #:width 2
               #:height 1
               #:center (vec2 -6 0)
               #:fill "seagreen"
               #:stroke "darkgreen"
               #:stroke-width 3))
  (define left-marker
    (circle #:id 'left-marker
            #:radius 1/10
            #:center (vec2 -6 -2)
            #:fill "dimgray"))
  (define center-marker
    (circle #:id 'center-marker
            #:radius 1/10
            #:center (vec2 0 -2)
            #:fill "dimgray"))
  (define right-marker
    (circle #:id 'right-marker
            #:radius 1/10
            #:center (vec2 6 -2)
            #:fill "dimgray"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AO: succession"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "move -> rotate -> scale -> move; four equal slices in one clip"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (scene-add (make-scene #:camera camera)
               left-marker center-marker right-marker card title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (succession
      (move-to card origin)
      (rotate-by card (/ pi 2))
      (scale-by card 3/2)
      (move-to card (vec2 6 0)))
     #:duration 6
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "successive-animations.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n"
          (length frame-paths)
          output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
