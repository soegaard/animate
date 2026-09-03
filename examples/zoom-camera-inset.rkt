#lang racket/base

;;;
;;; Zoom Camera Inset Example
;;;

;; SCENE-DO adds `camera-view`: a fixed frame-space inset that renders a live
;; world-space target through another orthographic camera. The inset below is
;; not a copied scene; the moving point is resolved from the same scene sample
;; as the large view.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define outer-camera
    (make-camera #:width 960
                 #:height 540
                 #:world-width 14
                 #:background "white"))
  (define detail-camera
    (make-camera #:width 480
                 #:height 270
                 #:world-width 3
                 #:center origin
                 #:background "ivory"))
  (define horizontal-axis
    (line (vec2 -3 0) (vec2 3 0)
          #:id 'horizontal-axis
          #:stroke "lightsteelblue"
          #:stroke-width 2))
  (define vertical-axis
    (line (vec2 0 -5/2) (vec2 0 5/2)
          #:id 'vertical-axis
          #:stroke "lightsteelblue"
          #:stroke-width 2))
  (define orbit
    (circle #:id 'orbit
            #:center origin
            #:radius 12/5
            #:fill #f
            #:stroke "steelblue"
            #:stroke-width 3))
  (define diameter
    (line (vec2 -12/5 0) (vec2 12/5 0)
          #:id 'diameter
          #:stroke "cornflowerblue"
          #:stroke-width 3))
  (define marker
    (circle #:id 'marker
            #:center (vec2 -2 0)
            #:radius 1/5
            #:fill "tomato"
            #:stroke "firebrick"
            #:stroke-width 2))
  (define diagram
    (group (list horizontal-axis vertical-axis orbit diameter marker)
           #:id 'diagram
           #:center origin))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-DO: zoom camera inset"
                 #:id 'title
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:font-weight 'bold
                 #:color "navy")
     #:camera outer-camera
     #:at (vec2 0 33/10)))
  (define explanation
    (fixed-in-frame
     (plain-text "one live diagram, rendered through two cameras"
                 #:id 'explanation
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera outer-camera
     #:at (vec2 0 27/10)))
  (define zoom-label
    (fixed-in-frame
     (plain-text "zoomed view"
                 #:id 'zoom-label
                 #:font-size 1/4
     #:font-family 'swiss
     #:color "dimgray")
     #:camera outer-camera
     #:at (vec2 43/10 3/10)))
  (define inset
    (camera-view 'diagram
                 #:id 'zoom
                 #:camera detail-camera
                 #:frame-camera outer-camera
                 #:at (vec2 43/10 3/2)
                 #:width 3
                 #:opacity 19/20))
  (define initial
    (scene-add (make-scene #:camera outer-camera)
               diagram title explanation zoom-label inset))
  (define introduced
    (scene-wait initial 1))
  (define animated
    (scene-play
     introduced
     (animation-group
      (move-to '(diagram marker) (vec2 2 0))
      (camera-pan-by (vec2 1 0)))
     #:duration 4))
  (scene-wait animated 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "zoom-camera-inset.rkt"
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
