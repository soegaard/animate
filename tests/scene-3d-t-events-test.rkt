#lang racket/base

;;; SCENE-3D-T1: event-aware immutable dense trajectories.

(require rackunit
         racket/list
         (only-in racket/math pi)
         "../3d.rkt")

(define (constant-x-trajectory seed events #:range [time-range (cons 0 4)])
  (prepare-ode-trajectory3d
   (lambda (_x _y _z) (vec3 1 0 0))
   seed
   #:time-range time-range
   #:solver (fixed-rk4-solver3d #:step-size 1/2)
   #:events events))

(define (event-times trajectory)
  (for/list ([hit (in-vector (ode-trajectory3d-event-hits trajectory))])
    (ode-event-hit3d-time hit)))

(module+ test
  ;; A terminal event is located through the stored dense segment and becomes
  ;; a canonical endpoint.  No field lookup occurs after preparation.
  (define field-calls (box 0))
  (define terminal
    (ode-event3d #:id 'x-zero #:function (lambda (point) (vec3-x point))))
  (define trajectory
    (prepare-ode-trajectory3d
     (lambda (_x _y _z)
       (set-box! field-calls (add1 (unbox field-calls)))
       (vec3 1 0 0))
     (vec3 -1 0 0)
     #:time-range (cons 0 4)
     #:solver (fixed-rk4-solver3d #:step-size 1/2)
     #:events (list terminal)))
  (check-equal? (ode-trajectory3d-time-range trajectory) (cons 0 1))
  (check-equal? (event-times trajectory) '(1))
  (define hit (vector-ref (ode-trajectory3d-event-hits trajectory) 0))
  (check-equal? (ode-event-hit3d-event-id hit) 'x-zero)
  (check-equal? (ode-event-hit3d-direction hit) 'increasing)
  (check-equal? (ode-event-hit3d-provenance hit) 'endpoint)
  (check-equal? (ode-trajectory3d-diagnostics-termination-reason
                 (ode-trajectory3d-diagnostics trajectory))
                'terminal-event)
  (check-equal? (ode-trajectory3d-diagnostics-event-count
                 (ode-trajectory3d-diagnostics trajectory))
                1)
  (set-box! field-calls 0)
  (void (ode-trajectory3d-position trajectory 1/4))
  (void (ode-trajectory3d-derivative trajectory 3/4))
  (check-equal? (unbox field-calls) 0)

  ;; Nonterminal crossings remain in a time-ordered hit vector.  A terminal
  ;; root in the same path still selects the earliest point in integration
  ;; direction; equal-time hits keep declaration order.
  (define nonterminal
    (ode-event3d #:id 'first #:terminal? #f
                 #:function (lambda (_time point) (vec3-x point))))
  (define simultaneous
    (ode-event3d #:id 'second #:terminal? #f
                 #:function (lambda (point) (vec3-x point))))
  (define stop
    (ode-event3d #:id 'stop #:function (lambda (point) (- (vec3-x point) 2))))
  (define mixed
    (constant-x-trajectory (vec3 -1 0 0) (list nonterminal simultaneous stop)))
  (check-equal? (ode-trajectory3d-time-range mixed) (cons 0 3))
  (check-equal? (event-times mixed) '(1 1 3))
  (check-equal?
   (for/list ([event-hit (in-vector (ode-trajectory3d-event-hits mixed))])
     (ode-event-hit3d-event-id event-hit))
   '(first second stop))

  ;; Direction is evaluated in increasing physical time, including a backward
  ;; preparation interval.  x(t) = 1 + t crosses zero while increasing.
  (define backward-increasing
    (ode-event3d #:id 'up #:direction 'increasing
                 #:function (lambda (point) (vec3-x point))))
  (define backward-decreasing
    (ode-event3d #:id 'down #:direction 'decreasing #:terminal? #f
                 #:function (lambda (point) (vec3-x point))))
  (define backward
    (constant-x-trajectory (vec3 1 0 0)
                           (list backward-increasing backward-decreasing)
                           #:range (cons -2 0)))
  (check-equal? (ode-trajectory3d-time-range backward) (cons -1 0))
  (check-equal? (event-times backward) '(-1))
  (check-equal?
   (ode-event-hit3d-event-id (vector-ref (ode-trajectory3d-event-hits backward) 0))
   'up)

  ;; An initial zero is one canonical event even though the first segment also
  ;; begins at the root.  A root at an accepted-node boundary is likewise not
  ;; reported by both neighbouring segments.
  (define initial
    (constant-x-trajectory origin3
                           (list (ode-event3d #:id 'initial
                                              #:function (lambda (point) (vec3-x point))))))
  (check-equal? (ode-trajectory3d-time-range initial) (cons 0 0))
  (check-equal? (event-times initial) '(0))
  (define boundary
    (constant-x-trajectory
     (vec3 -1 0 0)
     (list (ode-event3d #:id 'node #:terminal? #f
                        #:function (lambda (point) (vec3-x point))))))
  (check-equal? (event-times boundary) '(1))

  ;; Direction filtering is independent of the solver's traversal direction.
  ;; This is a decreasing physical crossing, so only the matching declaration
  ;; observes it.
  (define decreasing-path
    (prepare-ode-trajectory3d
     (lambda (_x _y _z) (vec3 -1 0 0)) (vec3 1 0 0)
     #:time-range (cons 0 2) #:step-size 1/2
     #:events
     (list (ode-event3d #:id 'down #:direction 'decreasing #:terminal? #f
                        #:function (lambda (point) (vec3-x point)))
           (ode-event3d #:id 'not-up #:direction 'increasing #:terminal? #f
                        #:function (lambda (point) (vec3-x point))))))
  (check-equal? (event-times decreasing-path) '(1))
  (check-equal?
   (ode-event-hit3d-event-id (vector-ref (ode-trajectory3d-event-hits decreasing-path) 0))
   'down)

  ;; Curved analytic trajectories exercise dense, state-based root location.
  ;; Circular motion crosses x=0 twice, while exponential growth crosses the
  ;; radius x=2 once.
  (define circular
    (prepare-ode-trajectory3d
     (lambda (_x y _z) (vec3 (- y) _x 0)) (vec3 1 0 0)
     #:time-range (cons 0 (* 2 pi))
     #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-10
                                    #:absolute-tolerance 1e-12
                                    #:initial-step 1/10 #:maximum-step 1/10)
     #:events (list (ode-event3d #:id 'plane #:terminal? #f
                                  #:function (lambda (point) (vec3-x point))))))
  (check-equal? (vector-length (ode-trajectory3d-event-hits circular)) 2)
  (check-= (first (event-times circular)) (/ pi 2) 1e-6)
  (check-= (second (event-times circular)) (* 3/2 pi) 1e-6)
  (define exponential
    (prepare-ode-trajectory3d
     (lambda (x _y _z) (vec3 x 0 0)) (vec3 1 0 0)
     #:time-range (cons 0 2)
     #:solver (adaptive-rk45-solver3d #:relative-tolerance 1e-10
                                    #:absolute-tolerance 1e-12
                                    #:initial-step 1/10)
     #:events (list (ode-event3d #:id 'radius
                                  #:function (lambda (point) (- (vec3-x point) 2))))))
  (check-= (car (event-times exponential)) (log 2) 1e-6)

  ;; A wholly nonzero sampled event yields no hit. An intentionally shallow
  ;; bisection preserves its isolated-bracket hit and records the explicit
  ;; maximum-iteration warning.
  (define absent
    (constant-x-trajectory origin3
                           (list (ode-event3d #:id 'outside #:terminal? #f
                                              #:function (lambda (point) (+ 100 (vec3-x point)))))))
  (check-equal? (vector-length (ode-trajectory3d-event-hits absent)) 0)
  (define coarse-root
    (constant-x-trajectory
     origin3
     (list (ode-event3d #:id 'coarse #:maximum-iterations 1
                        #:function (lambda (point) (- (vec3-x point) (sqrt 2)))))))
  (check-equal? (ode-event-hit3d-provenance
                 (vector-ref (ode-trajectory3d-event-hits coarse-root) 0))
                'maximum-iterations)
  (check-equal? (ode-trajectory3d-diagnostics-warnings
                 (ode-trajectory3d-diagnostics coarse-root))
                (list (list 'event-maximum-iterations 'coarse 23/16)))

  ;; Bad event behaviour fails deterministically during preparation rather
  ;; than being deferred to a rendering worker.
  (check-exn exn:fail:contract?
             (lambda ()
               (constant-x-trajectory origin3
                                      (list (ode-event3d #:id 'nan
                                                         #:function (lambda (_point) +nan.0))))))
  (check-exn exn:fail:contract?
             (lambda ()
               (constant-x-trajectory origin3
                                      (list (ode-event3d #:id 'boom
                                                         #:function (lambda (_point)
                                                                      (error 'boom "no"))))))))
