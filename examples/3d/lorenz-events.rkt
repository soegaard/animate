#lang racket/base

;;; SCENE-3D-T: Nonterminal Lorenz Event Crossings

;; The two event declarations share the z = 25 surface but retain their
;; physical crossing directions.  The event markers, trace, and particle all
;; consume the one prepared trajectory; rendering a later frame never calls
;; the Lorenz field or either event procedure.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define sigma 10)
(define rho 28)
(define beta 8/3)

(define (lorenz x y z)
  (vec3 (* sigma (- y x))
        (- (* x (- rho z)) y)
        (- (* x y) (* beta z))))

(define z-rise
  (ode-event3d #:id 'z-rise
               #:function (lambda (point) (- (vec3-z point) 25))
               #:direction 'increasing #:terminal? #f
               #:cache-key 'lorenz-z=25-rise))

(define z-fall
  (ode-event3d #:id 'z-fall
               #:function (lambda (point) (- (vec3-z point) 25))
               #:direction 'decreasing #:terminal? #f
               #:cache-key 'lorenz-z=25-fall))

(define lorenz-trajectory
  (prepare-ode-trajectory3d
   (ode-field3d lorenz #:cache-key 'lorenz-10-28-8/3 #:autonomous? #t)
   (vec3 0 1 21/20)
   #:time-range (cons 0 18)
   #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-6
                                    #:absolute-tolerance 1e-8
                                    #:initial-step 1/100
                                    #:maximum-step 1/20)
   #:events (list z-rise z-fall)))

(define trajectory-end (cdr (ode-trajectory3d-time-range lorenz-trajectory)))

(define (lorenz-trace)
  (polyline3d
   (for/list ([index (in-range 1441)])
     (ode-trajectory3d-position lorenz-trajectory
                                (* trajectory-end (/ index 1440))))
   #:id 'trace #:style (stroke3d #:width 2 #:color "midnightblue")))

(define (event-markers)
  (group3d
   (for/list ([hit (in-vector (ode-trajectory3d-event-hits lorenz-trajectory))]
              [index (in-naturals)])
     (point3d (ode-event-hit3d-position hit)
              #:id (string->symbol (format "event-~a" index))
              #:style
              (point-style3d #:size 10
                             #:color (if (eq? (ode-event-hit3d-event-id hit) 'z-rise)
                                         "gold" "tomato"))))
   #:id 'event-markers))

(define (make-demo-scene)
  (define phase (parameter 'time 0))
  (define world
    (view3d
     (list (lorenz-trace)
           (event-markers)
           (flow-particle3d lorenz-trajectory phase #:id 'particle
                            #:style (point-style3d #:size 12 #:color "white")
                            #:tangent-length 4
                            #:tangent-shaft-style (stroke3d #:width 2 #:color "white")
                            #:tangent-tip-style (arrow-style3d #:color "white")))
     #:id 'world #:center (vec2 0 -1/4) #:width 8 #:height 5
     #:camera (perspective-camera3d #:position (vec3 45 28 58)
                                    #:look-at (vec3 0 0 25)
                                    #:vertical-field-of-view (/ pi 5))
     #:background "aliceblue" #:render-mode 'opaque))
  (scene-play
   (scene-add
    (scene-set-value (make-scene) phase) world
    (plain-text "SCENE-3D-T: Lorenz event crossings"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy")
    (plain-text "Gold rises and red falls through z = 25; every marker is a retained dense event root."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
   (animation-group
    (value-to phase trajectory-end)
    (camera3d-orbit-by 'world #:center (vec3 0 0 25)
                       #:azimuth (/ pi 3) #:elevation (/ pi 18)))
   #:duration 6))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "lorenz-events.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
