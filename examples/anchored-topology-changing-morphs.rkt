#lang racket/base

;;;
;;; Explicit Birth/Death Anchor Example
;;;

;; Demonstrates SCENE-AI topology-changing correspondence with a shared explicit
;; local anchor: one lower curve collapses into the marked hub while a new lower
;; loop grows from that same hub. A surviving upper curve still morphs visibly.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define anchor origin)

(define (make-source-path)
  (combine-paths
   ;; Surviving upper open path.
   (cubic-bezier-path
    (vec2 -9 3)
    (list
     (cubic-bezier-path-segment
      (vec2 -6 6) (vec2 -2 6) (vec2 1 3))))
   ;; Dying lower curve, intentionally far left of the custom hub.
   (cubic-bezier-path
    (vec2 -9 -4)
    (list
     (cubic-bezier-path-segment
      (vec2 -7 -7) (vec2 -3 -7) (vec2 -1 -4))))))

(define (make-destination-path)
  (combine-paths
   ;; Same semantic survivor, deliberately stored backwards and reshaped.
   (path-geometry-reverse
    (cubic-bezier-path
     (vec2 -9 2)
     (list
      (cubic-bezier-path-segment
       (vec2 -5 7) (vec2 0 5) (vec2 2 2)))))
   ;; New lower closed loop, intentionally far right of the hub.
   (polygon-path
    (list (vec2 3 -5) (vec2 7 -6) (vec2 10 -3)
          (vec2 8 0) (vec2 4 0)))))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-destination-path))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define hub
    (point-marker #:id 'hub
                  #:center anchor
                  #:shape 'diamond
                  #:size 1/2
                  #:fill "firebrick"
                  #:stroke "firebrick"))
  (define camera
    (make-camera #:world-width 27
                 #:center origin
                 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AI: explicit birth/death anchor"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "darkgreen")
     #:camera camera
     #:at (vec2 0 7.1)))
  (define note
    (fixed-in-frame
     (plain-text "The lower curve dies into the red hub; a new loop is born from it"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -7.1)))
  (define scene
    (scene-add (make-scene #:camera camera) panel hub title note))
  (define intro (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing
      panel
      destination
      #:sample-count 32
      #:birth-anchor anchor
      #:death-anchor anchor)
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "anchored-topology-changing-morphs.rkt"
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
