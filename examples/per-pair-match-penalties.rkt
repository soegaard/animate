#lang racket/base

;;;
;;; Per-Pair Match Penalty Example
;;;

;; Both panels contain two open cubic subpaths and both destinations visibly
;; change shape. The upper panel uses geometric correspondence and morphs each
;; curve locally. The lower panel adds one large original-index real-match
;; penalty, making the global assignment exchange the two destination identities.

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
   ;; Source index 0: upper arch.
   (cubic-bezier-path
    (vec2 -5 3)
    (list
     (cubic-bezier-path-segment
      (vec2 -2 5) (vec2 2 5) (vec2 5 3))))
   ;; Source index 1: lower arch.
   (cubic-bezier-path
    (vec2 -5 -3)
    (list
     (cubic-bezier-path-segment
      (vec2 -2 -5) (vec2 2 -5) (vec2 5 -3))))))

(define destination-path
  (combine-paths
   ;; Destination index 0 stays in the upper region but bends downward.
   (cubic-bezier-path
    (vec2 -5 3)
    (list
     (cubic-bezier-path-segment
      (vec2 -2 1) (vec2 2 1) (vec2 5 3))))
   ;; Destination index 1 stays in the lower region but bends upward.
   (cubic-bezier-path
    (vec2 -5 -3)
    (list
     (cubic-bezier-path-segment
      (vec2 -2 -1) (vec2 2 -1) (vec2 5 -3))))))

(define (make-demo-scene)
  (define camera
    (make-camera #:world-width 30
                 #:center origin
                 #:background "white"))
  (define geometric-panel
    (make-path-visual source-path
                      #:id 'geometric-panel
                      #:center (vec2 -7 0)
                      #:stroke "slateblue"
                      #:stroke-width 5))
  (define penalized-panel
    (make-path-visual source-path
                      #:id 'penalized-panel
                      #:center (vec2 7 0)
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define geometric-label
    (plain-text "geometric costs: both curves morph locally"
                #:id 'geometric-label
                #:center (vec2 -7 6)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "slateblue"))
  (define penalized-label
    (plain-text "pair penalty (source 0 . destination 0): global assignment swaps"
                #:id 'penalized-label
                #:center (vec2 7 6)
                #:font-size 7/20
                #:font-family 'swiss
                #:color "darkgreen"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AM: per-pair real-match penalties"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     #:camera camera
     #:at (vec2 0 8)))
  (define note
    (fixed-in-frame
     (plain-text "pair keys are original (source-index . destination-index) values"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -8)))
  (define scene
    (scene-add (make-scene #:camera camera)
               geometric-panel penalized-panel
               geometric-label penalized-label title note))
  (define intro (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing
      geometric-panel
      destination-path
      #:sample-count 32)
     (morph-to-topology-changing
      penalized-panel
      destination-path
      #:sample-count 32
      #:match-penalty-map (hash (cons 0 0) 1000))
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "per-pair-match-penalties.rkt"
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
