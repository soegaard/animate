#lang racket/base

;;; SCENE-3D-T2: explicit dense-trajectory termination policies.

(require rackunit
         "../3d.rkt")

(define (constant-trajectory speed
                             #:range [time-range (cons 0 4)]
                             #:termination [termination (trajectory-termination3d)])
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) (vec3 speed 0 0))
   origin3
   #:time-range time-range
   #:solver (fixed-rk4-solver3d #:step-size 1/2)
   #:termination termination))

(define (only-termination trajectory)
  (define hits (ode-trajectory3d-termination trajectory))
  (check-equal? (vector-length hits) 1)
  (vector-ref hits 0))

(module+ test
  ;; A time budget clips the requested horizon before integration.  It is a
  ;; real prepared endpoint, so subsequent lookup requires no field call.
  (define time-limited
    (constant-trajectory 1
                         #:range (cons 0 5)
                         #:termination (trajectory-termination3d #:time-limit 2)))
  (check-equal? (ode-trajectory3d-time-range time-limited) (cons 0 2))
  (define time-hit (only-termination time-limited))
  (check-equal? (trajectory-termination-hit3d-reason time-hit) 'time-limit)
  (check-equal? (trajectory-termination-hit3d-time time-hit) 2)
  (check-equal? (trajectory-termination-hit3d-position time-hit) (vec3 2 0 0))
  ;; A requested interval completely beyond the budget is represented by the
  ;; singleton budget boundary and still exposes its termination record.
  (define exterior-time-request
    (constant-trajectory 1 #:range (cons 3 5)
                         #:termination (trajectory-termination3d #:time-limit 2)))
  (check-equal? (ode-trajectory3d-time-range exterior-time-request) (cons 2 2))
  (check-equal? (trajectory-termination-hit3d-reason
                 (only-termination exterior-time-request))
                'time-limit)

  ;; Bounds use the same Hermite segments as ordinary trajectory lookup.  The
  ;; result is represented exactly on the face and retains its outward normal.
  (define bounded
    (constant-trajectory
     1 #:range (cons 0 4)
     #:termination
     (trajectory-termination3d
      #:bounds (aabb3 (vec3 -1 -1 -1) (vec3 3/2 1 1)))))
  (define bounds-hit (only-termination bounded))
  (check-equal? (trajectory-termination-hit3d-reason bounds-hit) 'bounds-exit)
  (check-= (trajectory-termination-hit3d-time bounds-hit) 3/2 1e-10)
  (check-equal? (trajectory-termination-hit3d-position bounds-hit) (vec3 3/2 0 0))
  (check-equal? (cadr (trajectory-termination-hit3d-details bounds-hit))
                (vec3 1 0 0))

  ;; Arc length is integrated over the dense Hermite segment and its limit is
  ;; resolved inside the segment, not rounded to a step endpoint.
  (define arc-limited
    (constant-trajectory 2 #:range (cons 0 4)
                         #:termination (trajectory-termination3d #:arc-length-limit 3)))
  (define arc-hit (only-termination arc-limited))
  (check-equal? (trajectory-termination-hit3d-reason arc-hit) 'arc-length-limit)
  (check-= (trajectory-termination-hit3d-time arc-hit) 3/2 1e-10)
  (check-= (vec3-x (trajectory-termination-hit3d-position arc-hit)) 3 1e-10)

  ;; Low-speed termination finds the first dense threshold crossing before the
  ;; zero-speed stationary point at t = 1.
  (define slow
    (prepare-ode-trajectory3d
     (lambda (time _x _y _z) (vec3 (- 1 time) 0 0)) origin3
     #:time-range (cons 0 2) #:step-size 1/2
     #:termination (trajectory-termination3d #:minimum-speed 1/10)))
  (define slow-hit (only-termination slow))
  (check-equal? (trajectory-termination-hit3d-reason slow-hit) 'minimum-speed)
  (check-= (trajectory-termination-hit3d-time slow-hit) 9/10 1e-8)

  ;; A terminal event supplied through the policy participates in the same
  ;; plan as explicit #:events and wins against a coincident bounds exit.
  (define event-at-boundary
    (ode-event3d #:id 'wall #:function (lambda (point) (- (vec3-x point) 3/2))))
  (define event-first
    (constant-trajectory
     1 #:range (cons 0 4)
     #:termination
     (trajectory-termination3d
      #:bounds (aabb3 (vec3 -1 -1 -1) (vec3 3/2 1 1))
      #:events (list event-at-boundary))))
  (define event-hit (only-termination event-first))
  (check-equal? (trajectory-termination-hit3d-reason event-hit) 'terminal-event)
  (check-equal? (trajectory-termination-hit3d-time event-hit) 3/2)
  (check-equal? (ode-event-hit3d-event-id
                 (vector-ref (ode-trajectory3d-event-hits event-first) 0))
                'wall)

  ;; Maximum steps and tolerated field failure stop at the last accepted node;
  ;; the normal policy still propagates author field failures.
  (define step-limited
    (constant-trajectory 1 #:range (cons 0 4)
                         #:termination (trajectory-termination3d #:maximum-steps 2)))
  (define steps-hit (only-termination step-limited))
  (check-equal? (trajectory-termination-hit3d-reason steps-hit) 'maximum-steps)
  (check-equal? (ode-trajectory3d-time-range step-limited) (cons 0 1))
  (define failing-field
    (lambda (time _x _y _z)
      (if (>= time 1) (error 'field "stop") (vec3 1 0 0))))
  (check-exn exn:fail:contract?
             (lambda ()
               (prepare-ode-trajectory3d failing-field origin3
                                         #:time-range (cons 0 2) #:step-size 1/2)))
  (define field-limited
    (prepare-ode-trajectory3d
     failing-field origin3 #:time-range (cons 0 2) #:step-size 1/2
     #:termination (trajectory-termination3d #:on-field-error 'terminate)))
  (define field-hit (only-termination field-limited))
  (check-equal? (trajectory-termination-hit3d-reason field-hit) 'field-error)
  (check-equal? (ode-trajectory3d-time-range field-limited) (cons 0 1/2))

  ;; The policy is symmetric around the seed time.  On a backward branch the
  ;; first physical AABB exit is the lower endpoint, not an integration-order
  ;; artefact.
  (define backward-bounded
    (constant-trajectory
     1 #:range (cons -4 0)
     #:termination
     (trajectory-termination3d
      #:bounds (aabb3 (vec3 -3/2 -1 -1) (vec3 1 1 1)))))
  (define backward-hit (only-termination backward-bounded))
  (check-equal? (trajectory-termination-hit3d-reason backward-hit) 'bounds-exit)
  (check-= (trajectory-termination-hit3d-time backward-hit) -3/2 1e-10)
  (check-equal? (trajectory-termination-hit3d-position backward-hit) (vec3 -3/2 0 0)))
