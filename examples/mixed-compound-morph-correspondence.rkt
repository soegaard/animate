#lang racket/base

;;;
;;; Mixed-Topology Compound Morph Correspondence Example
;;;

;; Compares stored-order normalized morphing with SCENE-AG topology-aware global
;; pairing for one compound path that interleaves open curves and closed loops.

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
   (cubic-bezier-path
    (vec2 -9 -2)
    (list
     (cubic-bezier-path-segment
      (vec2 -8 3)
      (vec2 -6 3)
      (vec2 -5 -1))))
   (polygon-path
    (list (vec2 -4 -2) (vec2 -1 -2) (vec2 -1 1) (vec2 -4 1)))
   (cubic-bezier-path
    (vec2 2 2)
    (list
     (cubic-bezier-path-segment
      (vec2 4 -3)
      (vec2 7 -2)
      (vec2 9 2))))
   (polygon-path
    (list (vec2 4 3) (vec2 7 3) (vec2 9 5) (vec2 7 7) (vec2 4 6)))))

(define (make-destination-path _source)
  ;; Each intended counterpart changes geometry as well as stored traversal.
  ;; Destination storage still keeps the open/closed pattern legal for ordinary
  ;; normalization, but swaps identities inside both topology classes.
  (define open-left-destination
    (cubic-bezier-path
     (vec2 -10 -1)
     (list
      (cubic-bezier-path-segment
       (vec2 -8 5)
       (vec2 -5 2)
       (vec2 -4 -2)))))
  (define closed-left-destination
    (polygon-path
     (list (vec2 -5 -3) (vec2 -1 -2) (vec2 0 1)
           (vec2 -2 3) (vec2 -5 1))))
  (define open-right-destination
    (cubic-bezier-path
     (vec2 1 1)
     (list
      (cubic-bezier-path-segment
       (vec2 3 -4)
       (vec2 7 -3)
       (vec2 10 3)))))
  (define closed-right-destination
    (polygon-path
     (list (vec2 3 3) (vec2 8 2) (vec2 10 5)
           (vec2 7 8) (vec2 3 6))))
  (combine-paths
   (path-geometry-reverse open-right-destination)
   (path-geometry-cycle-start
    (path-geometry-reverse closed-right-destination)
    2/5)
   (path-geometry-reverse open-left-destination)
   (path-geometry-cycle-start
    (path-geometry-reverse closed-left-destination)
    1/4)))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-destination-path source))
  (define camera
    (make-camera #:world-width 32
                 #:center origin
                 #:background "white"))
  (define stored-order-panel
    (make-path-visual source
                      #:id 'stored-order-panel
                      #:center (vec2 0 4)
                      #:scale 3/4
                      #:stroke "navy"
                      #:stroke-width 5))
  (define mixed-panel
    (make-path-visual source
                      #:id 'mixed-panel
                      #:center (vec2 0 -4)
                      #:scale 3/4
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define stored-label
    (plain-text "normalized only: identities cross within each topology class"
                #:id 'stored-label
                #:center (vec2 0 7.6)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "navy"))
  (define aligned-label
    (plain-text "SCENE-AG: open + closed global correspondence in one compound"
                #:id 'aligned-label
                #:center (vec2 0 -0.4)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define scene
    (scene-add (make-scene #:camera camera)
               stored-order-panel
               mixed-panel
               stored-label
               aligned-label))
  (define morphed
    (scene-play
     scene
     (morph-to-normalized stored-order-panel destination)
     (morph-to-mixed-compound-aligned mixed-panel destination)
     #:duration 4))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "mixed-compound-morph-correspondence.rkt"
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
