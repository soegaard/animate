#lang racket/base

;;;
;;; Composable Camera Movements Example
;;;

;; SCENE-CV puts camera leaves into the same timed/composed scheduling language
;; as Visual animation: the camera first pans to the moving point, then follows
;; it while zooming in as a parallel companion component.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (make-demo-scene)
  (define camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 20
                 #:background "white"))
  (define route
    (line (vec2 -9 0)
          (vec2 9 0)
          #:id 'route
          #:stroke "lightsteelblue"
          #:stroke-width 5))
  (define left-stop
    (circle #:id 'left-stop
            #:center (vec2 -4 0)
            #:radius 1/2
            #:fill "lightsteelblue"
            #:stroke "midnightblue"
            #:stroke-width 3))
  (define right-stop
    (circle #:id 'right-stop
            #:center (vec2 4 0)
            #:radius 1/2
            #:fill "lightsteelblue"
            #:stroke "midnightblue"
            #:stroke-width 3))
  (define marker
    (circle #:id 'marker
            #:center (vec2 -7 0)
            #:radius 2/5
            #:fill "tomato"
            #:stroke "firebrick"
            #:stroke-width 3))
  (define left-label
    (plain-text "pan"
                #:id 'left-label
                #:center (vec2 -4 -1)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "midnightblue"))
  (define right-label
    (plain-text "follow + zoom"
                #:id 'right-label
                #:center (vec2 4 -1)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "midnightblue"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-CV: composable camera motion"
                 #:id 'title
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera camera
     #:at (vec2 0 3)))
  (define note
    (fixed-in-frame
     (plain-text "succession: pan  →  parallel: follow + zoom"
                 #:id 'explanation
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -3)))
  (define base
    (scene-add (make-scene #:camera camera)
               route left-stop right-stop marker left-label right-label title note))
  (define intro
    (scene-wait base 1))
  (define animated
    (scene-play
     intro
     (animation-group
      (succession
       (camera-pan-to (vec2 -4 0))
       (animation-group
        (camera-follow marker)
        (camera-zoom-by 2)))
      (succession
       (move-to marker (vec2 -4 0))
       (move-to marker (vec2 4 0))))
     #:duration 6))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "composable-camera-movements.rkt"
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
