#lang racket/base

;;; SCENE-3D-T7: Prepared Flow-Map Volume Cell

;; One 2 x 2 x 2 seed lattice is integrated once.  The visible deformed grid,
;; translucent gold hexahedron, and tube bundle then use that same retained
;; source-to-endpoint map; rendering an arbitrary camera frame does not solve
;; the ODE again.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define expansion-field
  (ode-field3d
   (lambda (x y z) (vec3 (* 2/5 x) (* -1/5 y) (* 1/10 z)))
   #:cache-key 'anisotropic-expansion))

(define seed-lattice
  (grid-seeds3d #:x-range (list -1 1) #:y-range (list -1 1) #:z-range (list -1 1)
                #:counts '(2 2 2)))

(define prepared-map
  (prepare-flow-map3d expansion-field seed-lattice
                      #:start-time 0 #:end-time 1
                      #:solver (fixed-rk4-solver3d #:step-size 1/20)))

(define (make-demo-scene)
  (define world
    (view3d
     (list
      (axes3d #:id 'axes #:x-range (list -2 2) #:y-range (list -2 2) #:z-range (list -2 2)
              #:stroke-style (stroke3d #:color "lightsteelblue" #:width 1))
      (spatial-with-opacity
       (flow-volume-cell3d
        prepared-map 0 #:id 'deformed-cell
        #:material (material3d #:color "gold" #:shading 'flat #:ambient 4/5 #:diffuse 1/5
                               #:double-sided? #t))
       3/5)
      (flow-map-grid3d prepared-map #:id 'deformed-grid)
     (trajectory-bundle3d prepared-map #:id 'seed-trajectories #:radius 1/40 #:sides 8 #:samples 24))
     #:id 'world #:center (vec2 0 0) #:width 7 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 6 5 8)
                                    #:look-at origin3
                                    #:vertical-field-of-view (/ pi 7))
     #:lights (list (ambient-light3d #:intensity 3/5)
                    (directional-light3d (vec3 1 -1 2) #:intensity 2/5))))
  (scene-play
   (scene-add
    (make-scene) world
    (plain-text "SCENE-3D-T7: retained flow-map volume"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "gold: one deformed seed cell       blue: retained endpoint grid and seed trajectories"
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 3) #:elevation (/ pi 28))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "flow-map-volume.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
