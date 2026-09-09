#lang racket/base

;;;
;;; Progressive Subset Reveals
;;;

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960 #:height 540 #:world-width 18 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "FX-C: progressive subset reveals"
                 #:id 'title #:font-size 2/5 #:font-family 'swiss
                 #:font-weight 'bold #:color "navy")
     #:camera camera #:at (vec2 0 4)))
  (define note
    (fixed-in-frame
     (plain-text "source order stays stable while each tile enters on its own schedule"
                 #:id 'note #:font-size 7/20 #:font-family 'swiss #:color "dimgray")
     #:camera camera #:at (vec2 0 -4)))
  (define tiles
    (list
     (rectangle #:id 'first #:width 2 #:height 2 #:center (vec2 -3 0)
                #:fill "gold" #:stroke "sienna" #:stroke-width 4)
     (rectangle #:id 'second #:width 2 #:height 2 #:center (vec2 0 0)
                #:fill "mediumturquoise" #:stroke "teal" #:stroke-width 4)
     (rectangle #:id 'third #:width 2 #:height 2 #:center (vec2 3 0)
                #:fill "plum" #:stroke "indigo" #:stroke-width 4)))
  (define base (scene-add (make-scene #:camera camera) title note))
  (define introduced
    (scene-play
     (scene-wait base 1/2)
     (reveal-subsets
      tiles
      (lambda (tile source-index)
        (enter tile
               #:translation-offset (vec2 0 (+ 2 source-index))
               #:scale-factor 1/4))
      #:lag-ratio 1/2)
     #:duration 3))
  (scene-wait introduced 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "progressive-reveals.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
