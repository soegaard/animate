#lang racket/base

;;;
;;; Mapped Staggering Example
;;;

;; stagger-map evaluates the factory once per source target in source order,
;; then schedules the resulting ordinary requests with lagged-start timing.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (smoothstep progress)
  (* progress progress (- 3 (* 2 progress))))

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 18
                 #:background "white"))
  (define dots
    (list
     (circle #:id 'blue #:radius 7/10 #:center (vec2 -6 2)
             #:fill "royalblue" #:stroke "midnightblue" #:stroke-width 3)
     (circle #:id 'green #:radius 7/10 #:center (vec2 -6 0)
             #:fill "seagreen" #:stroke "darkgreen" #:stroke-width 3)
     (circle #:id 'red #:radius 7/10 #:center (vec2 -6 -2)
             #:fill "tomato" #:stroke "darkred" #:stroke-width 3)))
  (define title
    (fixed-in-frame
     (plain-text "FX-A: stagger-map"
                 #:id 'title
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "factory source index chooses each destination; reverse changes only schedule order"
                 #:id 'note
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -4)))
  (define base
    (apply scene-add (make-scene #:camera camera) title note dots))
  (define animated
    (scene-play
     (scene-wait base 1)
     (stagger-map
      dots
      (lambda (dot source-index)
        (move-to dot
                 (vec2 (+ 3 source-index)
                       (vec2-y (visual-position dot)))))
      #:lag-ratio 1/2
      #:order 'reverse)
     #:duration 5
     #:easing smoothstep))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "stagger-map.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
