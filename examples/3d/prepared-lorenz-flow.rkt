#lang racket/base

;;; SCENE-3D-K: Prepared Lorenz Flow

;; A Lorenz field is prepared once into an immutable adaptive trajectory.  The
;; traced curve is sampled from that data, and the moving point/tangent arrow
;; read only per-frame prepared samples while PNG workers render independently.

(require racket/cmdline
         (only-in racket/math pi)
         animate
         animate/3d
         animate/render)

(provide make-demo-scene)

(define sigma 10)
(define rho 28)
(define beta 8/3)

;; The autonomous form has exactly the documented `(x y z)` field signature.
(define (lorenz x y z)
  (vec3 (* sigma (- y x))
        (- (* x (- rho z)) y)
        (- (* x y) (* beta z))))

(define prepared-lorenz
  (prepare-ode-trajectory3d
   lorenz (vec3 0 1 21/20)
   #:time-range (cons 0 20)
   #:solver (adaptive-rk45 #:relative-tolerance 1e-6
                           #:absolute-tolerance 1e-8
                           #:initial-step 1/100
                           #:maximum-step 1/20)))

(define (lorenz-trace trajectory)
  (define range (ode-trajectory3d-time-range trajectory))
  (define start (car range))
  (define end (cdr range))
  ;; Dense adaptive lookup is history-free; these are stable parameter values,
  ;; not points remembered from a previous rendered frame.
  (polyline3d
   (for/list ([index (in-range 1201)])
     (ode-trajectory3d-position
      trajectory (+ start (* (/ index 1200) (- end start)))))
   #:id 'trace #:style (stroke3d #:width 2 #:color "royalblue")))

(define (make-demo-scene)
  (define phase (parameter 'time 0))
  (define camera
    (perspective-camera3d #:position (vec3 45 28 58)
                          #:look-at (vec3 0 0 25)
                          #:vertical-field-of-view (/ pi 5)))
  (define world
    (view3d
     (list
      ;; A sparse explicit grid gives the velocity field a deterministic,
      ;; inspectable order without overwhelming the attractor trace.
      (vector-field3d lorenz #:id 'field
                      #:x-range '(-16 16) #:y-range '(-16 16) #:z-range '(8 42)
                      #:x-count 3 #:y-count 3 #:z-count 3
                      #:normalize? #t #:length-range '(3/5 6/5)
                      #:color-by-magnitude? #t #:opacity 3/4)
      (lorenz-trace prepared-lorenz)
      (flow-particle3d prepared-lorenz phase #:id 'particle
                       #:style (point-style3d #:size 12 #:color "gold")
                       #:tangent-length 4
                       #:tangent-shaft-style (stroke3d #:width 2 #:color "tomato")
                       #:tangent-tip-style (arrow-style3d #:color "tomato")))
     #:id 'world #:center (vec2 0 -1/4) #:width 8 #:height 5
     #:camera camera #:background "aliceblue" #:render-mode 'opaque))
  (define title
    (plain-text "SCENE-3D-K: prepared Lorenz flow"
                #:id 'title #:center (vec2 0 15/4) #:font-size 1/3
                #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define caption
    (plain-text "RK45 prepares the path; particle, tangent, and camera are random-access samples."
                #:id 'caption #:center (vec2 0 -29/10) #:font-size 1/5
                #:font-family 'swiss #:color "darkslategray"))
  (scene-play
   (scene-add (scene-set-value (make-scene) phase) world title caption)
   (animation-group
    (value-to phase 20)
    (camera3d-orbit-by 'world #:center (vec3 0 0 25)
                       #:azimuth (/ pi 3) #:elevation (/ pi 18)))
   #:duration 6))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line #:program "prepared-lorenz-flow.rkt"
                #:args ([frames-directory "frames"] [mp4-file #f])
                (set! output-directory frames-directory)
                (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30 #:workers 2))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
