#lang racket/base

;;;
;;; SCENE-DN Adaptive and Time-Dependent ODE Tests
;;;

(require rackunit
         racket/class
         racket/draw
         racket/file
         racket/math
         "../main.rkt"
         "../render.rkt")

(module+ test
  (define (check-vec2-close actual expected [tolerance 1e-7])
    (check-= (vec2-x actual) (vec2-x expected) tolerance)
    (check-= (vec2-y actual) (vec2-y expected) tolerance))

  (define solver
    (adaptive-rk45 #:relative-tolerance 1e-8 #:absolute-tolerance 1e-10
                   #:initial-step 1/10 #:minimum-step 1e-8 #:maximum-step 1/2))
  (check-true (adaptive-rk45? solver))
  (check-equal? (adaptive-rk45-relative-tolerance solver) 1e-8)
  (check-exn exn:fail:contract?
             (lambda () (adaptive-rk45 #:minimum-step 1 #:initial-step 1/2)))

  ;; The field can use time explicitly. RK45's fifth-order endpoint handles the
  ;; polynomial solution x(t) = t²/2 accurately, including a dense query that
  ;; is not itself an accepted solver node.
  (define time-field (lambda (time _x _y) (vec2 time 0)))
  (define time-trajectory
    (prepare-ode-trajectory
     time-field origin #:time-range (cons -2 3) #:solver solver))
  (check-true (ode-trajectory? time-trajectory))
  (check-equal? (ode-trajectory-solver time-trajectory) solver)
  (check-false (ode-trajectory-step-size time-trajectory))
  (check-false (ode-trajectory-checkpoint-every time-trajectory))
  (check-vec2-close (ode-trajectory-position time-trajectory 3) (vec2 9/2 0))
  (check-vec2-close (ode-trajectory-position time-trajectory -3/2)
                    (vec2 9/8 0))

  ;; A smooth autonomous field remains accurate and positions are completely
  ;; field-free after preparation, which preserves renderer-worker safety.
  (define calls (box 0))
  (define (rotation-field x y)
    (set-box! calls (add1 (unbox calls)))
    (vec2 (- y) x))
  (define rotation-trajectory
    (prepare-ode-trajectory
     rotation-field (vec2 1 0) #:time-range (cons 0 pi) #:solver solver))
  (set-box! calls 0)
  (check-vec2-close (ode-trajectory-position rotation-trajectory (/ pi 2))
                    (vec2 0 1) 1e-6)
  (check-equal? (unbox calls) 0)
  (define diagnostics (ode-trajectory-diagnostics rotation-trajectory))
  (check-true (ode-trajectory-diagnostics? diagnostics))
  (check-equal? (ode-trajectory-diagnostics-solver diagnostics) 'adaptive-rk45)
  (check-true (positive? (ode-trajectory-diagnostics-accepted-steps diagnostics)))
  (check-equal? (ode-trajectory-diagnostics-termination-reason diagnostics)
                'time-range)

  ;; A terminal scalar event ends the prepared range at a dense interpolated
  ;; root, rather than only at the next accepted adaptive step boundary.
  (define constant-field (lambda (_x _y) (vec2 1 0)))
  (define hit-x=2
    (ode-event (lambda (x _y) (- x 2))
               #:direction 'increasing #:name 'hit-x=2))
  (define stopped
    (prepare-ode-trajectory
     constant-field origin #:time-range (cons 0 5)
     #:solver solver #:event hit-x=2))
  (define stopped-time (cdr (ode-trajectory-time-range stopped)))
  (check-= stopped-time 2 1e-8)
  (check-vec2-close (ode-trajectory-position stopped stopped-time)
                    (vec2 2 0) 1e-8)
  (check-equal? (ode-trajectory-diagnostics-termination-reason
                 (ode-trajectory-diagnostics stopped))
                'hit-x=2)

  ;; Flow particles read the adaptive dense output during the renderer's serial
  ;; preparation pass. Once the trajectory exists, even a render performs no
  ;; further calls to the author field.
  (define axes0
    (axes #:id 'axes
          #:x-range (axis-range -1 3 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 4 #:y-length 2))
  (define render-calls (box 0))
  (define (counted-field _x _y)
    (set-box! render-calls (add1 (unbox render-calls)))
    (vec2 1 0))
  (define adaptive-particle-trajectory
    (prepare-ode-trajectory
     counted-field origin #:time-range (cons 0 1) #:solver solver))
  (set-box! render-calls 0)
  (define phase (parameter 'phase 0))
  (define scene
    (scene-play
     (scene-add (scene-set-value (make-scene) phase)
                axes0
                (flow-particle axes0 adaptive-particle-trajectory phase
                               #:id 'particle))
     (value-to phase 1)
     #:duration 1))
  (define frames (make-temporary-file "animate-adaptive-ode~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (check-true (is-a? (scene-frame->bitmap scene 1 #:fps 2) bitmap%))
     (render-frames! scene frames #:fps 2)
     ;; Supersampling preserves the world view while multiplying just the
     ;; raster dimensions. This is used by the SCENE-DN movie before Lanczos
     ;; downsampling, so a curved trajectory has clean antialiased edges.
     (define supersampled
       (scene-frame->bitmap scene 1 #:fps 2 #:supersample 2))
     (check-equal? (send supersampled get-width) 2560)
     (check-equal? (send supersampled get-height) 1440)
     (define supersampled-paths
       (render-frames! scene frames #:fps 2 #:supersample 2))
     (define saved-supersampled
       (read-bitmap (car supersampled-paths)))
     (check-equal? (send saved-supersampled get-width) 2560)
     (check-equal? (send saved-supersampled get-height) 1440)
     (check-equal? (unbox render-calls) 0))
   (lambda () (delete-directory/files frames))))
