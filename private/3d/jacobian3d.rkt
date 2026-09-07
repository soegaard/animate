#lang racket/base

;;;
;;; Deterministic Jacobians for Three-Dimensional ODE Fields
;;;

;; This module deliberately keeps numerical differentiation separate from ODE
;; preparation.  A Jacobian is a local, immutable mathematical result: it does
;; not retain the author supplied field or derivative procedure.

(require "../geometry.rkt"
         "linear3.rkt"
         "ode-flow3d.rkt"
         "vec3.rkt")

(provide jacobian3d
         (struct-out jacobian3d-result))


;;; Results

(struct jacobian3d-result
  (matrix method step evaluations error-estimate diagnostics)
  #:transparent)


;;; Public API

;; jacobian3d : (or/c ode-field3d? field-procedure?) finite-vec3?
;;              #:time finite-real?
;;              #:derivative (or/c #f field-procedure?)
;;              #:step (or/c #f positive-finite-real?)
;;              #:domain (or/c #f (finite-vec3? -> boolean?))
;;              -> jacobian3d-result?
;;
;; A field and its analytic derivative both use the established ODE convention:
;; `(x y z)` or `(time x y z)`.  The derivative returns a `linear3`.  The
;; optional domain predicate is intentionally the only authority for taking a
;; one-sided finite difference; absent a declared domain every axis is sampled
;; symmetrically.
(define (jacobian3d field point
                    #:time [time 0]
                    #:derivative [derivative #f]
                    #:step [step #f]
                    #:domain [domain #f])
  (check-field 'jacobian3d field)
  (check-point 'jacobian3d point)
  (unless (finite-real? time)
    (raise-argument-error 'jacobian3d "finite real? as #:time" time))
  (when derivative (check-derivative 'jacobian3d derivative))
  (when step
    (unless (and (finite-real? step) (positive? step))
      (raise-argument-error 'jacobian3d "#f or positive finite real as #:step" step)))
  (when domain
    (unless (and (procedure? domain) (procedure-arity-includes? domain 1))
      (raise-argument-error 'jacobian3d
                            "#f or procedure accepting a finite vec3 as #:domain"
                            domain))
    (unless (in-domain? 'jacobian3d domain point)
      (raise-arguments-error 'jacobian3d "point is outside the declared domain"
                             "point" point)))
  (cond
    [derivative
     (define matrix (call-derivative 'jacobian3d derivative time point))
     (jacobian3d-result
      matrix 'analytic #f 1 #f
      (hasheq 'derivative-source 'analytic
              'domain-restricted? (and domain #t)))]
    [else
     (finite-difference-jacobian field point time step domain)]))


;;; Finite differences

;; sqrt(machine epsilon) is the standard scale for a first derivative of an
;; ordinary double-precision field.  The per-coordinate scale prevents a small
;; step from disappearing beside a very large coordinate, without introducing
;; process-global numerical settings.
(define automatic-step-scale 1.4901161193847656e-8)

(define (finite-difference-jacobian field point time explicit-step domain)
  (define steps
    (vec3 (coordinate-step (vec3-x point) explicit-step)
          (coordinate-step (vec3-y point) explicit-step)
          (coordinate-step (vec3-z point) explicit-step)))
  (define evaluations 0)
  (define (evaluate candidate)
    (set! evaluations (add1 evaluations))
    (call-field 'jacobian3d field time candidate))
  ;; A central difference's error indicator compares it with a first-order
  ;; forward estimate using the same samples.  It is an indicator, rather than
  ;; a bound, and is #f for a one-sided fallback.
  (define base (evaluate point))
  (define methods '())
  (define fallback-axes '())
  (define error-indicators '())
  (define columns
    (for/list ([axis (in-range 3)])
      (define h (vec3-ref steps axis))
      (define plus (point-offset point axis h))
      (define minus (point-offset point axis (- h)))
      (define plus-valid? (or (not domain) (in-domain? 'jacobian3d domain plus)))
      (define minus-valid? (or (not domain) (in-domain? 'jacobian3d domain minus)))
      (cond
        [(and plus-valid? minus-valid?)
         (define forward (evaluate plus))
         (define backward (evaluate minus))
         (define central (vec3-scale (/ 1 (* 2 h)) (vec3- forward backward)))
         (define first-order (vec3-scale (/ 1 h) (vec3- forward base)))
         (set! methods (cons 'central methods))
         (set! error-indicators
               (cons (vec3-length (vec3- central first-order)) error-indicators))
         central]
        [plus-valid?
         (set! methods (cons 'forward methods))
         (set! fallback-axes (cons axis fallback-axes))
         (vec3-scale (/ 1 h) (vec3- (evaluate plus) base))]
        [minus-valid?
         (set! methods (cons 'backward methods))
         (set! fallback-axes (cons axis fallback-axes))
         (vec3-scale (/ 1 h) (vec3- base (evaluate minus)))]
        [else
         (raise-arguments-error
          'jacobian3d
          "neither finite-difference neighbour is inside the declared domain"
          "axis" axis "point" point "step" h)])))
  (define dx (car columns))
  (define dy (cadr columns))
  (define dz (caddr columns))
  (define matrix
    (linear3 (vec3-x dx) (vec3-x dy) (vec3-x dz)
             (vec3-y dx) (vec3-y dy) (vec3-y dz)
             (vec3-z dx) (vec3-z dy) (vec3-z dz)))
  (define any-fallback? (pair? fallback-axes))
  (jacobian3d-result
   matrix
   (if any-fallback? 'one-sided 'central)
   steps
   evaluations
   (and (not any-fallback?) (apply max error-indicators))
   (hasheq 'derivative-source 'finite-difference
           'coordinate-methods
           (vector->immutable-vector (list->vector (reverse methods)))
           'one-sided-axes
           (vector->immutable-vector (list->vector (reverse fallback-axes)))
           'domain-restricted? (and domain #t)
           'automatic-step? (not explicit-step))))

(define (coordinate-step coordinate explicit-step)
  (or explicit-step (* automatic-step-scale (max 1.0 (abs coordinate)))))

(define (vec3-ref value index)
  (case index
    [(0) (vec3-x value)]
    [(1) (vec3-y value)]
    [(2) (vec3-z value)]
    [else (error 'jacobian3d "invalid coordinate index: ~e" index)]))

(define (point-offset point axis amount)
  (case axis
    [(0) (vec3 (+ (vec3-x point) amount) (vec3-y point) (vec3-z point))]
    [(1) (vec3 (vec3-x point) (+ (vec3-y point) amount) (vec3-z point))]
    [(2) (vec3 (vec3-x point) (vec3-y point) (+ (vec3-z point) amount))]
    [else (error 'jacobian3d "invalid coordinate index: ~e" axis)]))


;;; Validation and calls

(define (check-field who field)
  (unless (or (ode-field3d? field)
              (and (procedure? field)
                   (or (procedure-arity-includes? field 3)
                       (procedure-arity-includes? field 4))))
    (raise-argument-error who
                          "ode-field3d? or procedure accepting (x y z) or (time x y z)"
                          field)))

(define (check-derivative who derivative)
  (unless (and (procedure? derivative)
               (or (procedure-arity-includes? derivative 3)
                   (procedure-arity-includes? derivative 4)))
    (raise-argument-error who
                          "procedure accepting (x y z) or (time x y z) as #:derivative"
                          derivative)))

(define (check-point who point)
  (unless (vec3-finite? point)
    (raise-argument-error who "finite vec3?" point)))

(define (field-procedure field)
  (if (ode-field3d? field) (ode-field3d-procedure field) field))

(define (field-arity field)
  (if (ode-field3d? field)
      (ode-field3d-arity field)
      (if (procedure-arity-includes? field 4) 4 3)))

(define (call-field who field time point)
  (define procedure (field-procedure field))
  (define value
    (if (= (field-arity field) 4)
        (procedure time (vec3-x point) (vec3-y point) (vec3-z point))
        (procedure (vec3-x point) (vec3-y point) (vec3-z point))))
  (unless (vec3-finite? value)
    (raise-arguments-error who "field did not return a finite vec3"
                           "time" time "point" point "result" value))
  value)

(define (call-derivative who derivative time point)
  (define value
    (if (procedure-arity-includes? derivative 4)
        (derivative time (vec3-x point) (vec3-y point) (vec3-z point))
        (derivative (vec3-x point) (vec3-y point) (vec3-z point))))
  (unless (linear3? value)
    (raise-arguments-error who "analytic derivative did not return a linear3"
                           "time" time "point" point "result" value))
  value)

(define (in-domain? who domain point)
  (define result (domain point))
  (unless (boolean? result)
    (raise-arguments-error who "domain predicate did not return a boolean"
                           "point" point "result" result))
  result)
