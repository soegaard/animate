#lang racket/base

;;;
;;; Compound Morph Correspondence Example
;;;

;; Compares stored-order normalized morphing with SCENE-AD automatic global
;; closed-subpath pairing plus SCENE-AC phase/direction alignment.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define (make-source-path)
  (define outer
    (polygon-path
     (list (vec2 -5 -3)
           (vec2 4 -4)
           (vec2 6 1)
           (vec2 2 5)
           (vec2 -4 4)
           (vec2 -6 0))))
  (define inner
    (polygon-path
     (list (vec2 -2 -1)
           (vec2 0 -2)
           (vec2 2 0)
           (vec2 0 2))))
  (combine-paths outer inner))

(define (make-stored-destination-path)
  (define outer
    (polygon-path
     (list (vec2 -6 -2)
           (vec2 3 -5)
           (vec2 7 0)
           (vec2 3 5)
           (vec2 -3 5)
           (vec2 -7 1))))
  (define inner
    (polygon-path
     (list (vec2 -2 0)
           (vec2 0 -5/2)
           (vec2 5/2 0)
           (vec2 0 2))))
  ;; Deliberately store the inner loop first and the outer loop second. Each is
  ;; also given an inconvenient phase/direction so the lower panel must use both
  ;; SCENE-AD pairing and SCENE-AC loop alignment.
  (combine-paths
   (path-geometry-cycle-start
    (path-geometry-reverse inner)
    1/3)
   (path-geometry-cycle-start outer 2/5)))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-stored-destination-path))
  (define camera
    (make-camera #:world-width 28
                 #:center origin
                 #:background "white"))
  (define stored-order-panel
    (make-path-visual source
                      #:id 'stored-order-panel
                      #:center (vec2 0 4)
                      #:scale 3/5
                      #:fill "lightsteelblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define compound-aligned-panel
    (make-path-visual source
                      #:id 'compound-aligned-panel
                      #:center (vec2 0 -4)
                      #:scale 3/5
                      #:fill "honeydew"
                      #:stroke "seagreen"
                      #:stroke-width 4))
  (define stored-label
    (plain-text "normalized only: subpaths cross-paired by storage order"
                #:id 'stored-label
                #:center (vec2 0 36/5)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "navy"))
  (define aligned-label
    (plain-text "SCENE-AD: global subpath pairing + loop alignment"
                #:id 'aligned-label
                #:center origin
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define scene
    (scene-add (make-scene #:camera camera)
               stored-order-panel
               compound-aligned-panel
               stored-label
               aligned-label))
  (define morphed
    (scene-play
     scene
     (morph-to-normalized stored-order-panel destination)
     (morph-to-compound-aligned compound-aligned-panel destination)
     #:duration 4))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "compound-morph-correspondence.rkt"
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
