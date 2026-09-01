#lang racket/base

;;;
;;; Per-Subpath Topology Penalty Example
;;;

;; Compares one shared AJ birth/death cost with SCENE-AL sparse original-index
;; overrides. Both source pairs are distant. Shared low costs replace both; the
;; lower panel assigns high death/birth costs to the upper pair only, so that
;; pair remains a real morph while the lower pair still collapses/regrows.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define source-path
  (combine-paths
   ;; Source index 0: upper pair protected in SCENE-AL panel.
   (cubic-bezier-path
    (vec2 -9 3/2)
    (list
     (cubic-bezier-path-segment
      (vec2 -8 3) (vec2 -5 3) (vec2 -4 3/2))))
   ;; Source index 1: retains the shared cheap death cost.
   (cubic-bezier-path
    (vec2 -9 -3/2)
    (list
     (cubic-bezier-path-segment
      (vec2 -8 -3) (vec2 -5 -3) (vec2 -4 -3/2))))))

(define destination-path
  (combine-paths
   ;; Destination index 0: lower destination is stored first and remains cheap.
   (cubic-bezier-path
    (vec2 4 -3/2)
    (list
     (cubic-bezier-path-segment
      (vec2 5 -1/4) (vec2 8 -1/4) (vec2 9 -3/2))))
   ;; Destination index 1: upper destination gets the high birth override.
   (cubic-bezier-path
    (vec2 4 3/2)
    (list
     (cubic-bezier-path-segment
      (vec2 5 1/4) (vec2 8 1/4) (vec2 9 3/2))))))

(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 30
                 #:center origin
                 #:background "white"))
  (define shared-panel
    (make-path-visual source-path
                      #:id 'shared-panel
                      #:center (vec2 0 4)
                      #:stroke "slateblue"
                      #:stroke-width 5))
  (define mapped-panel
    (make-path-visual source-path
                      #:id 'mapped-panel
                      #:center (vec2 0 -4)
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define shared-label
    (plain-text "shared costs 2/2: both pairs collapse + regrow"
                #:id 'shared-label
                #:center (vec2 0 7)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "slateblue"))
  (define mapped-label
    (plain-text "sparse overrides: upper pair 20/20, lower pair 2/2"
                #:id 'mapped-label
                #:center (vec2 0 -7)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AL: per-subpath birth/death costs"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 8)))
  (define note
    (fixed-in-frame
     (plain-text "maps use original source/destination indexes even after global pairing"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -8)))
  (define scene
    (scene-add (make-scene #:camera camera)
               shared-panel mapped-panel shared-label mapped-label title note))
  (define intro (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing
      shared-panel
      destination-path
      #:sample-count 32
      #:birth-penalty 2
      #:death-penalty 2)
     (morph-to-topology-changing
      mapped-panel
      destination-path
      #:sample-count 32
      #:birth-penalty 2
      #:death-penalty 2
      #:birth-penalty-map (hash 1 20)
      #:death-penalty-map (hash 0 20))
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "per-subpath-topology-penalties.rkt"
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
