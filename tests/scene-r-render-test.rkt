#lang racket/base

;;;
;;; SCENE-R Sampled Function Graph Rendering Tests
;;;

;; Tests path-renderer reuse, clipping bounds, axes alignment, Create frames,
;; scene composition, frame counts, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 300
                 #:height 180
                 #:world-width 30
                 #:background "white"))

  ; coordinate-axes : axes-visual?
  ;;   Gives four-by-four axes without tips for exact render bounds.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4
          #:stroke "navy"
          #:stroke-width 0
          #:tick-size 1/5
          #:x-tip? #f
          #:y-tip? #f))

  ; diagonal-graph : path-visual?
  ;;   Gives y = x with zero cosmetic stroke width for exact bounds.
  (define diagonal-graph
    (function-graph coordinate-axes
                    values
                    #:id 'diagonal-graph
                    #:sample-count 5
                    #:stroke "crimson"
                    #:stroke-width 0))

  ; diagonal-pict : pict?
  ;;   Gives the default path-renderer output for diagonal-graph.
  (define diagonal-pict
    (visual->pict diagonal-graph test-camera))

  ;; Four world units become forty pixels. The path renderer adds one pixel of
  ;; symmetric safety padding at every side.
  (check-equal? (pict-width diagonal-pict) 42)
  (check-equal? (pict-height diagonal-pict) 42)

  ; clipping-axes : axes-visual?
  ;;   Gives a two-by-two displayed coordinate rectangle.
  (define clipping-axes
    (axes #:id 'clipping-axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  ; clipped-graph : path-visual?
  ;;   Gives the clipped visible portion of y = 2x.
  (define clipped-graph
    (function-graph clipping-axes
                    (lambda (x) (* 2 x))
                    #:id 'clipped-graph
                    #:sample-count 3
                    #:stroke-width 0))

  ; clipped-pict : pict?
  ;;   Gives a narrow graph spanning the full visible y range.
  (define clipped-pict
    (visual->pict clipped-graph test-camera))

  (check-equal? (pict-width clipped-pict) 12)
  (check-equal? (pict-height clipped-pict) 22)

  ;; Graph and axes transforms are snapshots with identical placement.
  ; transformed-axes : axes-visual?
  ;;   Gives translated, rotated, and non-uniformly scaled axes.
  (define transformed-axes
    (visual-with-position
     (visual-with-rotation
      (visual-with-scale coordinate-axes (vec2 3/2 3/4))
      1/8)
     (vec2 2 -1)))

  ; transformed-graph : path-visual?
  ;;   Gives y = x aligned with transformed-axes at construction time.
  (define transformed-graph
    (function-graph transformed-axes
                    values
                    #:id 'transformed-graph
                    #:sample-count 9
                    #:stroke "seagreen"
                    #:stroke-width 2))

  (check-equal? (visual-transform transformed-graph)
                (visual-transform transformed-axes))

  ;; The graph is an ordinary path Visual, so Create reveals it by ordered arc
  ;; length while the axes can fade in independently.
  ; entrance : scene?
  ;;   Introduces axes and creates the diagonal graph over one second.
  (define entrance
    (scene-play (make-scene)
                (fade-in coordinate-axes)
                (create diagonal-graph)
                #:duration 1))

  ; animation : scene?
  ;;   Holds the complete graph for one quarter second.
  (define animation
    (scene-wait entrance 1/4))

  (check-equal? (scene-frame-count animation #:fps 4) 5)

  ; start-pict : pict?
  ;;   Gives the first frame with transparent axes and empty graph geometry.
  (define start-pict
    (scene->pict animation
                 0
                 #:camera test-camera))

  ; middle-pict : pict?
  ;;   Gives an interior frame with partly visible axes and graph.
  (define middle-pict
    (scene->pict animation
                 1/2
                 #:camera test-camera))

  ; end-pict : pict?
  ;;   Gives the exact structural endpoint with full axes and graph.
  (define end-pict
    (scene->pict animation
                 1
                 #:camera test-camera))

  (check-equal? (pict-width start-pict) 300)
  (check-equal? (pict-height start-pict) 180)
  (check-equal? (pict-width middle-pict) 300)
  (check-equal? (pict-height middle-pict) 180)
  (check-equal? (pict-width end-pict) 300)
  (check-equal? (pict-height end-pict) 180)

  ; temporary-root : path?
  ;;   Gives an isolated directory root for deterministic PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-r~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; first-paths : (listof path?)
      ;;   Gives the first complete rendering of the graph animation.
      (define first-paths
        (render-frames! animation
                        (build-path temporary-root "first")
                        #:fps 4
                        #:camera test-camera))

      ; second-paths : (listof path?)
      ;;   Gives the repeated rendering of the same semantic animation.
      (define second-paths
        (render-frames! animation
                        (build-path temporary-root "second")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length first-paths) 5)
      (check-equal? (length second-paths) 5)
      (check-equal? (map file->bytes first-paths)
                    (map file->bytes second-paths))
      (check-false
       (equal? (file->bytes (car first-paths))
               (file->bytes (car (reverse first-paths))))))
    (lambda ()
      (delete-directory/files temporary-root))))
