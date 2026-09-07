#lang racket/base

;;; SCENE-3D-T3: Prepared Adaptive Streamlines

;; The source field is evaluated only while these four streamlines are
;; prepared. The scene contains ordinary camera-independent sampled curves.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define swirl-field
  (ode-field3d
   (lambda (x y _z) (vec3 (- y) x 1/3))
   #:cache-key 'rising-swirl))

(define streamline-policy
  (streamline-sample-policy3d #:maximum-chord-error 1/200
                              #:maximum-turn-angle (/ pi 20)
                              #:maximum-segment-length 1/5
                              #:minimum-segment-length 1/4000))

(define streamline-termination
  (trajectory-termination3d #:time-limit 8 #:arc-length-limit 6))

(define prepared-lines
  (for/list ([seed (in-list (list (vec3 3/2 0 -1)
                                  (vec3 0 3/2 -1)
                                  (vec3 -3/2 0 -1)
                                  (vec3 0 -3/2 -1)))])
    (prepare-streamline3d
     swirl-field seed #:direction 'both #:parameterization 'arc-length
     #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-8
                                     #:absolute-tolerance 1e-10
                                     #:initial-step 1/10 #:maximum-step 1/5)
     #:termination streamline-termination #:sample-policy streamline-policy)))

(define colors '("tomato" "goldenrod" "royalblue" "mediumseagreen"))

(define (make-demo-scene)
  (define world
    (view3d
     (for/list ([line (in-list prepared-lines)] [color (in-list colors)]
                [index (in-naturals)])
       (adaptive-streamline3d line #:id (string->symbol (format "line-~a" index))
                              #:style (stroke3d #:color color #:width 3)))
     #:id 'world #:center (vec2 0 0) #:width 7 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 7 6 8)
                                    #:look-at (vec3 0 0 0)
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (make-scene) world
    (plain-text "SCENE-3D-T3: prepared adaptive streamlines"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "Arc-length parameterization; curve samples are world-space and camera-independent."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (camera3d-orbit-by 'world #:center origin3 #:azimuth (/ pi 4) #:elevation (/ pi 24))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "adaptive-streamlines.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
