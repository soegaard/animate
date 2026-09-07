#lang racket/base

;;; SCENE-3D-T4: Deterministic Seed Sets

;; Poisson seeds are determined only by the box, minimum distance, count limit,
;; and explicit integer seed.  The prepared curves and point markers therefore
;; have stable identity and order regardless of render worker count.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define seed-bounds
  (aabb3 (vec3 -2 -2 -1) (vec3 2 2 1)))

(define seeds
  (poisson-seeds3d seed-bounds #:minimum-distance 11/10
                   #:count-limit 11 #:seed 20260907))

(define field
  (ode-field3d
   (lambda (x y _z) (vec3 (- y) x 1/4))
   #:cache-key 'seed-demo-swirl))

(define sampling
  (streamline-sample-policy3d #:maximum-chord-error 1/150
                              #:maximum-turn-angle (/ pi 18)
                              #:maximum-segment-length 1/6
                              #:minimum-segment-length 1/4000))

(define prepared-set
  (prepare-streamlines3d
   field seeds #:direction 'both #:parameterization 'arc-length
   #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-8
                                   #:absolute-tolerance 1e-10
                                   #:initial-step 1/10 #:maximum-step 1/5)
   #:termination (trajectory-termination3d #:time-limit 5 #:arc-length-limit 4)
   #:sample-policy sampling #:parallel? #t))

(define colors
  '("tomato" "goldenrod" "royalblue" "mediumseagreen" "orchid"
    "darkorange" "steelblue" "seagreen" "firebrick" "slateblue" "darkorchid"))

(define (make-demo-scene)
  (define world
    (view3d
     (append
      (for/list ([line (in-vector (prepared-streamline-set3d-streamlines prepared-set))]
                 [color (in-list colors)]
                 [index (in-naturals)])
        (adaptive-streamline3d line #:id (string->symbol (format "line-~a" index))
                               #:style (stroke3d #:color color #:width 3)))
      (for/list ([seed (in-vector (seed-set3d-points seeds))]
                 [index (in-naturals)])
        (point3d seed #:id (string->symbol (format "seed-~a" index))
                 #:style (point-style3d #:size 9 #:color "gold"))))
     #:id 'world #:center (vec2 0 0) #:width 7 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 8 7 9)
                                    #:look-at (vec3 0 0 0)
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (make-scene) world
    (plain-text "SCENE-3D-T4: deterministic seed sets"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "gold: local-seed Poisson sites     coloured: arc-length streamlines"
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 3) #:elevation (/ pi 28))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "deterministic-seed-sets.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
