#lang racket/base

;;; SCENE-3D-T2: Explicit Trajectory Termination Policies

;; Each line is prepared once with a different stopping policy.  The endpoint
;; dots deliberately use the immutable termination records, rather than a
;; second field evaluation or a guessed final time.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define wall-bounds
  (aabb3 (vec3 -7/2 -2 -1) (vec3 1 2 1)))

(define bounded-path
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) (vec3 1 0 0)) (vec3 -3 -1 0)
   #:time-range (cons 0 6) #:step-size 1/8
   #:termination (trajectory-termination3d #:bounds wall-bounds)))

(define arc-path
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) (vec3 1 1/2 0)) (vec3 -3 0 0)
   #:time-range (cons 0 6) #:step-size 1/8
   #:termination (trajectory-termination3d #:arc-length-limit 3)))

(define arrival-plane
  (ode-event3d #:id 'arrival
               #:function (lambda (point) (- (vec3-x point) 1))))

(define event-path
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) (vec3 1 0 0)) (vec3 -3 1 0)
   #:time-range (cons 0 6) #:step-size 1/8
   #:termination (trajectory-termination3d #:events (list arrival-plane))))

(define (endpoint trajectory)
  (trajectory-termination-hit3d-position
   (vector-ref (ode-trajectory3d-termination trajectory) 0)))

(define (trace trajectory id color)
  (define end-time (cdr (ode-trajectory3d-time-range trajectory)))
  (polyline3d
   (for/list ([index (in-range 101)])
     (ode-trajectory3d-position trajectory (* end-time (/ index 100))))
   #:id id #:style (stroke3d #:color color #:width 4)))

(define (make-demo-scene)
  (define bound-phase (parameter 'bound-time 0))
  (define arc-phase (parameter 'arc-time 0))
  (define event-phase (parameter 'event-time 0))
  (define world
    (view3d
     (list
      (trace bounded-path 'bound-trace "tomato")
      (trace arc-path 'arc-trace "goldenrod")
      (trace event-path 'event-trace "royalblue")
      (point3d (endpoint bounded-path) #:id 'bound-stop
               #:style (point-style3d #:size 14 #:color "tomato"))
      (point3d (endpoint arc-path) #:id 'arc-stop
               #:style (point-style3d #:size 14 #:color "goldenrod"))
      (point3d (endpoint event-path) #:id 'event-stop
               #:style (point-style3d #:size 14 #:color "royalblue"))
      (flow-particle3d bounded-path bound-phase #:id 'bound-particle
                       #:style (point-style3d #:size 9 #:color "tomato"))
      (flow-particle3d arc-path arc-phase #:id 'arc-particle
                       #:style (point-style3d #:size 9 #:color "goldenrod"))
      (flow-particle3d event-path event-phase #:id 'event-particle
                       #:style (point-style3d #:size 9 #:color "royalblue")))
     #:id 'world #:center (vec2 0 0) #:width 8 #:height 5
     #:background "aliceblue" #:render-mode 'opaque
     #:camera (perspective-camera3d #:position (vec3 7 5 9)
                                    #:look-at (vec3 -1 0 0)
                                    #:vertical-field-of-view (/ pi 7))))
  (scene-play
   (scene-add
    (scene-set-value
     (scene-set-value
      (scene-set-value (make-scene) bound-phase)
      arc-phase)
     event-phase)
    world
    (plain-text "SCENE-3D-T2: explicit stopping policies"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "red: AABB exit     gold: arc-length budget     blue: terminal event"
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (animation-group
    (value-to bound-phase (cdr (ode-trajectory3d-time-range bounded-path)))
    (value-to arc-phase (cdr (ode-trajectory3d-time-range arc-path)))
    (value-to event-phase (cdr (ode-trajectory3d-time-range event-path)))
    (camera3d-orbit-by 'world #:center (vec3 -1 0 0)
                       #:azimuth (/ pi 7) #:elevation (/ pi 32)))
   #:duration 5))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "trajectory-termination.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
