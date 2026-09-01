#lang racket/base

;;;
;;; Per-Subpath Birth/Death Anchor Example
;;;

;; Demonstrates SCENE-AK sparse anchor maps. Two dying open curves collapse into
;; separate marked hubs, while two new closed loops grow from those same hubs.
;; A surviving upper curve still morphs visibly so the scene is not only a
;; birth/death demonstration.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define left-hub (vec2 -5 -1))
(define right-hub (vec2 5 -1))

(define (make-source-path)
  (combine-paths
   ;; Index 0: surviving upper open path.
   (cubic-bezier-path
    (vec2 -8 4)
    (list
     (cubic-bezier-path-segment
      (vec2 -4 7) (vec2 1 6) (vec2 8 4))))
   ;; Index 1: dies into the left hub.
   (cubic-bezier-path
    (vec2 -9 -3)
    (list
     (cubic-bezier-path-segment
      (vec2 -8 -6) (vec2 -5 -6) (vec2 -3 -4))))
   ;; Index 2: dies into the right hub.
   (polyline-path
    (list (vec2 3 -4) (vec2 6 -6) (vec2 9 -3)))))

(define (make-destination-path)
  (combine-paths
   ;; Index 0: surviving open path, reshaped and stored backwards.
   (path-geometry-reverse
    (cubic-bezier-path
     (vec2 -8 3)
     (list
      (cubic-bezier-path-segment
       (vec2 -3 7) (vec2 3 7) (vec2 8 3)))))
   ;; Index 1: new loop born from the left hub.
   (polygon-path
    (list (vec2 -9 -5) (vec2 -7 -7) (vec2 -3 -6)
          (vec2 -2 -3) (vec2 -6 -2)))
   ;; Index 2: new loop born from the right hub.
   (polygon-path
    (list (vec2 2 -5) (vec2 5 -7) (vec2 9 -5)
          (vec2 8 -2) (vec2 4 -2)))))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-destination-path))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define left-marker
    (point-marker #:id 'left-hub
                  #:center left-hub
                  #:shape 'diamond
                  #:size 1/2
                  #:fill "firebrick"
                  #:stroke "firebrick"))
  (define right-marker
    (point-marker #:id 'right-hub
                  #:center right-hub
                  #:shape 'diamond
                  #:size 1/2
                  #:fill "navy"
                  #:stroke "navy"))
  (define camera
    (make-camera #:world-width 24
                 #:center (vec2 0 0)
                 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AK: per-subpath birth/death anchors"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "darkgreen")
     #:camera camera
     #:at (vec2 0 7.1)))
  (define note
    (fixed-in-frame
     (plain-text "Each lower source/destination pair uses its own indexed hub"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -7.1)))
  (define scene
    (scene-add (make-scene #:camera camera)
               panel left-marker right-marker title note))
  (define intro (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing
      panel
      destination
      #:sample-count 32
      ;; The shared fallback is deliberately different from either hub.
      #:birth-anchor origin
      #:death-anchor origin
      #:birth-anchor-map (hash 1 left-hub 2 right-hub)
      #:death-anchor-map (hash 1 left-hub 2 right-hub))
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "per-subpath-topology-anchors.rkt"
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
