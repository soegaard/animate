#lang racket/base

;;;
;;; Penalized Topology-Changing Morph Example
;;;

;; Compares SCENE-AH/AI's forced equal-count correspondence with SCENE-AJ's
;; optional death+birth rejection. The same distant source/destination pair is
;; shown twice: the upper path sweeps across the scene, while the lower path
;; collapses locally and regrows locally because that costs less than matching.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define source-path
  (cubic-bezier-path
   (vec2 -9 0)
   (list
    (cubic-bezier-path-segment
     (vec2 -8 3/2) (vec2 -5 3/2) (vec2 -4 0)))))

(define destination-path
  (cubic-bezier-path
   (vec2 4 0)
   (list
    (cubic-bezier-path-segment
     (vec2 5 -3/2) (vec2 8 -3/2) (vec2 9 0)))))

(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 27
                 #:center origin
                 #:background "white"))
  (define forced-panel
    (make-path-visual source-path
                      #:id 'forced-panel
                      #:center (vec2 0 3)
                      #:stroke "slateblue"
                      #:stroke-width 5))
  (define penalized-panel
    (make-path-visual source-path
                      #:id 'penalized-panel
                      #:center (vec2 0 -3)
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define forced-label
    (plain-text "forced: one correspondence sweeps across"
                #:id 'forced-label
                #:center (vec2 0 5.2)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "slateblue"))
  (define penalized-label
    (plain-text "penalized: collapse left + grow right"
                #:id 'penalized-label
                #:center (vec2 0 -5.2)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AJ: reject a poor morph correspondence"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 7.1)))
  (define note
    (fixed-in-frame
     (plain-text "birth penalty 2 + death penalty 2 is cheaper than the distant real match"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -7.1)))
  (define scene
    (scene-add
     (make-scene #:camera camera)
     forced-panel
     penalized-panel
     forced-label
     penalized-label
     title
     note))
  (define intro
    (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing
      forced-panel
      destination-path
      #:sample-count 32)
     (morph-to-topology-changing
      penalized-panel
      destination-path
      #:sample-count 32
      #:birth-penalty 2
      #:death-penalty 2)
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "penalized-topology-changing-morphs.rkt"
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
