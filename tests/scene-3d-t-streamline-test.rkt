#lang racket/base

;;; SCENE-3D-T3: immutable adaptive streamline preparation and resampling.

(require rackunit
         "../3d.rkt")

(define (largest-chord samples)
  (for/fold ([largest 0]) ([index (in-range 1 (vector-length samples))])
    (max largest
         (vec3-distance (vector-ref samples (sub1 index))
                        (vector-ref samples index)))))

(module+ test
  ;; Time parameterization keeps the ODE's natural speed.  Display samples are
  ;; generated from frozen dense data and respect the world-space chord cap.
  (define line-policy
    (streamline-sample-policy3d #:maximum-chord-error 0
                                #:maximum-turn-angle 0
                                #:maximum-segment-length 1/4
                                #:minimum-segment-length 1/10000))
  (define time-line
    (prepare-streamline3d
     (lambda (_x _y _z) (vec3 2 0 0)) origin3
     #:solver (fixed-rk4-solver3d #:step-size 1/2)
     #:termination (trajectory-termination3d #:time-limit 1)
     #:sample-policy line-policy))
  (check-equal? (prepared-streamline3d-direction time-line) 'forward)
  (check-equal? (prepared-streamline3d-parameterization time-line) 'time)
  (check-equal? (ode-trajectory3d-time-range
                 (prepared-streamline3d-trajectory time-line))
                (cons 0 1))
  (define time-samples (prepared-streamline3d-curve-samples time-line))
  (check-equal? (vector-ref time-samples 0) origin3)
  (check-equal? (vector-ref time-samples (sub1 (vector-length time-samples)))
                (vec3 2 0 0))
  (check-true (<= (largest-chord time-samples) 1/4))
  (check-equal? (streamline-diagnostics3d-termination-reasons
                 (prepared-streamline3d-diagnostics time-line))
                '(time-limit))
  (check-true (curve3d?
               (adaptive-streamline3d time-line #:id 'time-line
                                      #:style (stroke3d #:width 2))))

  ;; Arc-length parameterization normalizes an autonomous field explicitly.
  ;; The same time budget therefore moves half as far as the time path above.
  (define arc-line
    (prepare-streamline3d
     (lambda (_x _y _z) (vec3 2 0 0)) origin3
     #:parameterization 'arc-length
     #:solver (fixed-rk4-solver3d #:step-size 1/2)
     #:termination (trajectory-termination3d #:time-limit 1)
     #:sample-policy line-policy))
  (define arc-samples (prepared-streamline3d-curve-samples arc-line))
  (check-equal? (vector-ref arc-samples (sub1 (vector-length arc-samples)))
                (vec3 1 0 0))
  (check-exn exn:fail:contract?
             (lambda ()
               (prepare-streamline3d
                (ode-field3d (lambda (_time _x _y _z) x-axis3)
                             #:autonomous? #f)
                origin3 #:parameterization 'arc-length)))
  ;; At an equilibrium an arc-length direction is undefined. Preparation
  ;; installs the documented zero-speed policy rather than fabricating a line.
  (define equilibrium
    (prepare-streamline3d
     (lambda (_x _y _z) origin3) origin3 #:parameterization 'arc-length
     #:termination (trajectory-termination3d #:time-limit 1)))
  (check-equal? (vector-length (prepared-streamline3d-curve-samples equilibrium)) 1)
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination
                              (prepared-streamline3d-trajectory equilibrium))
                             0))
                'minimum-speed)

  ;; A bidirectional stream joins its two independently prepared directions in
  ;; physical-time order and retains exactly one copy of the seed.
  (define both-line
    (prepare-streamline3d
     (lambda (_x _y _z) x-axis3) origin3 #:direction 'both
     #:solver (fixed-rk4-solver3d #:step-size 1/2)
     #:termination (trajectory-termination3d #:time-limit 1)
     #:sample-policy line-policy))
  (define both-samples (prepared-streamline3d-curve-samples both-line))
  (define seed-index (prepared-streamline3d-seed-index both-line))
  (check-equal? (vector-ref both-samples seed-index) origin3)
  (check-equal? (for/sum ([point (in-vector both-samples)])
                  (if (equal? point origin3) 1 0))
                1)
  (define both-diagnostics (prepared-streamline3d-diagnostics both-line))
  (check-true (streamline-branch-diagnostics3d?
               (streamline-diagnostics3d-forward both-diagnostics)))
  (check-true (streamline-branch-diagnostics3d?
               (streamline-diagnostics3d-backward both-diagnostics)))

  ;; A T2 termination policy passes straight through the streamline layer, and
  ;; no later curve query or visual construction calls the author field.
  (define calls (box 0))
  (define bounded
    (prepare-streamline3d
     (lambda (_x _y _z)
       (set-box! calls (add1 (unbox calls)))
       x-axis3)
     origin3 #:solver (fixed-rk4-solver3d #:step-size 1/2)
     #:termination
     (trajectory-termination3d
      #:time-limit 4
      #:bounds (aabb3 (vec3 -1 -1 -1) (vec3 1 1 1)))))
  (define count-after-preparation (unbox calls))
  (define bounded-trajectory (prepared-streamline3d-trajectory bounded))
  (void (ode-trajectory3d-position bounded-trajectory 1))
  (void (adaptive-streamline3d bounded #:id 'bounded))
  (check-equal? (unbox calls) count-after-preparation)
  (check-equal? (trajectory-termination-hit3d-reason
                 (vector-ref (ode-trajectory3d-termination bounded-trajectory) 0))
                'bounds-exit)

  ;; The established shorthand is still a direct visual constructor, but now
  ;; uses the immutable prepared path instead of reintegrating during render.
  (check-true
   (curve3d?
    (streamline3d (lambda (_x _y _z) x-axis3) origin3
                  #:id 'legacy #:direction 'forward #:step-size 1/4 #:steps 4))))
