#lang racket/base

;;; SCENE-3D-T1: Event-Aware Prepared Trajectory

;; The terminal plane event is found while the path is prepared.  Every later
;; trace and particle frame reads the shortened immutable trajectory only.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define terminal-plane
  (ode-event3d
   #:id 'arrival-plane
   #:function (lambda (point) (- (vec3-x point) 2))
   #:direction 'increasing
   #:cache-key 'x=2))

(define prepared-path
  (prepare-ode-trajectory3d
   (ode-field3d (lambda (_x _y _z) (vec3 1 1/4 1/6))
                #:cache-key 'constant-diagonal-flow)
   (vec3 -3 -5/4 -5/6)
   #:time-range (cons 0 8)
   #:solver (fixed-rk4-solver3d #:step-size 1/4)
   #:events (list terminal-plane)))

(define path-end (cdr (ode-trajectory3d-time-range prepared-path)))

(define (path-trace)
  (polyline3d
   (for/list ([index (in-range 161)])
     (ode-trajectory3d-position prepared-path (* path-end (/ index 160))))
   #:id 'trace #:style (stroke3d #:color "royalblue" #:width 4)))

(define (make-demo-scene)
  (define phase (parameter 'time 0))
  (define event-hit (vector-ref (ode-trajectory3d-event-hits prepared-path) 0))
  (define endpoint (ode-event-hit3d-position event-hit))
  (define world
    (view3d
     (list
      (path-trace)
      (point3d endpoint #:id 'arrival
               #:style (point-style3d #:size 16 #:color "gold"))
      (flow-particle3d prepared-path phase #:id 'particle
                       #:style (point-style3d #:size 12 #:color "tomato")
                       #:tangent-length 1/2
                       #:tangent-shaft-style (stroke3d #:width 2 #:color "tomato")
                       #:tangent-tip-style (arrow-style3d #:color "tomato")))
     #:id 'world #:center (vec2 0 -1/3) #:width 8 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 6 4 8)
                                    #:look-at (vec3 -1/2 -5/8 -5/12)
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (scene-set-value (make-scene) phase) world
    (plain-text "SCENE-3D-T1: terminal event roots"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "The gold point is an x = 2 event root, inserted as the immutable path endpoint."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (animation-group
    (value-to phase path-end)
    (camera3d-orbit-by 'world #:center (vec3 -1/2 -5/8 -5/12)
                       #:azimuth (/ pi 6) #:elevation (/ pi 32)))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "event-aware-trajectory.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
