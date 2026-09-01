#lang racket/base

;;;
;;; Topology-Changing Morph Example
;;;

;; Demonstrates SCENE-AH real-subpath correspondence together with one open
;; subpath death and one closed-loop birth in the same compound path.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define (make-source-path)
  (combine-paths
   ;; Closed loop that remains and visibly changes shape.
   (polygon-path
    (list (vec2 -9 -1) (vec2 -6 -2) (vec2 -4 0)
          (vec2 -5 3) (vec2 -8 3)))
   ;; Open curve that remains, but destination stores it backwards.
   (cubic-bezier-path
    (vec2 0 2)
    (list
     (cubic-bezier-path-segment
      (vec2 2 5) (vec2 6 5) (vec2 9 1))))
   ;; This lower open curve has no destination partner and will collapse.
   (cubic-bezier-path
    (vec2 -1 -4)
    (list
     (cubic-bezier-path-segment
      (vec2 2 -7) (vec2 6 -7) (vec2 9 -4))))))

(define (make-destination-path)
  (combine-paths
   ;; Scrambled storage order: the surviving open curve comes first/backwards.
   (path-geometry-reverse
    (cubic-bezier-path
     (vec2 0 1)
     (list
      (cubic-bezier-path-segment
       (vec2 2 6) (vec2 7 4) (vec2 10 2)))))
   ;; New closed loop: no source closed loop is spatially near it, so it is born.
   (polygon-path
    (list (vec2 1 -5) (vec2 5 -6) (vec2 9 -4)
          (vec2 8 -1) (vec2 3 -1)))
   ;; Surviving closed loop, deliberately reversed and phase shifted.
   (path-geometry-cycle-start
    (path-geometry-reverse
     (polygon-path
      (list (vec2 -10 -1) (vec2 -7 -4) (vec2 -3 -2)
            (vec2 -3 2) (vec2 -6 4) (vec2 -10 2))))
    1/3)))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-destination-path))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define camera
    (make-camera #:world-width 27
                 #:center origin
                 #:background "white"))
  (define title
    (fixed-in-frame
     (plain-text "SCENE-AH: matched paths morph; one curve dies; one loop is born"
                 #:id 'title-text
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "darkgreen")
     #:camera camera
     #:at (vec2 0 7.1)))
  (define note
    (fixed-in-frame
     (plain-text "Unmatched subpaths collapse/grow at their own bounds centers"
                 #:id 'note-text
                 #:font-size 7/20
                 #:font-family 'swiss
                 #:color "dimgray")
     #:camera camera
     #:at (vec2 0 -7.1)))
  (define scene
    (scene-add (make-scene #:camera camera) panel title note))
  (define intro (scene-wait scene 1))
  (define morphed
    (scene-play
     intro
     (morph-to-topology-changing panel destination #:sample-count 32)
     #:duration 5))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "topology-changing-morphs.rkt"
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
