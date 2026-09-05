#lang racket/base

;;;
;;; Open-Compound Morph Correspondence Example
;;;

;; Compares stored-order normalized morphing with SCENE-AF automatic global
;; pairing and endpoint-direction correspondence for multiple open subpaths.

(require racket/cmdline
         animate
         animate/render)

(provide make-demo-scene)

(define (combine-paths . geometries)
  (path-geometry
   (apply append
          (for/list ([geometry (in-list geometries)])
            (path-geometry-subpaths geometry)))))

(define (make-source-path)
  (combine-paths
   (cubic-bezier-path
    (vec2 -8 -2)
    (list
     (cubic-bezier-path-segment
      (vec2 -7 3)
      (vec2 -4 3)
      (vec2 -3 -1))))
   (cubic-bezier-path
    (vec2 2 2)
    (list
     (cubic-bezier-path-segment
      (vec2 4 -3)
      (vec2 7 -2)
      (vec2 8 2))))))

(define (make-destination-path)
  (define left
    (cubic-bezier-path
     (vec2 -8 1)
     (list
      (cubic-bezier-path-segment
       (vec2 -7 -3)
       (vec2 -4 -2)
       (vec2 -2 2)))))
  (define right
    (cubic-bezier-path
     (vec2 2 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 3 3)
       (vec2 7 4)
       (vec2 8 0)))))
  ;; The destination intentionally stores right first and both curves backward.
  ;; Stored-order normalized morphing therefore crosses both identity and
  ;; endpoint correspondence; SCENE-AF may repair both only for interior frames.
  (combine-paths
   (path-geometry-reverse right)
   (path-geometry-reverse left)))

(define (make-demo-scene)
  (define source (make-source-path))
  (define destination (make-destination-path))
  (define camera
    (make-camera #:world-width 30
                 #:center origin
                 #:background "white"))
  (define stored-order-panel
    (make-path-visual source
                      #:id 'stored-order-panel
                      #:center (vec2 0 4)
                      #:scale 4/5
                      #:stroke "navy"
                      #:stroke-width 5))
  (define open-compound-panel
    (make-path-visual source
                      #:id 'open-compound-panel
                      #:center (vec2 0 -4)
                      #:scale 4/5
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define stored-label
    (plain-text "normalized only: stored subpaths cross-pair"
                #:id 'stored-label
                #:center (vec2 0 7)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "navy"))
  (define aligned-label
    (plain-text "SCENE-AF: global open-subpath pairing + endpoint direction"
                #:id 'aligned-label
                #:center (vec2 0 -1)
                #:font-size 2/5
                #:font-family 'swiss
                #:color "darkgreen"))
  (define scene
    (scene-add (make-scene #:camera camera)
               stored-order-panel
               open-compound-panel
               stored-label
               aligned-label))
  (define morphed
    (scene-play
     scene
     (morph-to-normalized stored-order-panel destination)
     (morph-to-open-compound-aligned open-compound-panel destination)
     #:duration 4))
  (scene-wait morphed 1))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "open-compound-morph-correspondence.rkt"
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
