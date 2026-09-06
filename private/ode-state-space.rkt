#lang racket/base

;;;
;;; Finite ODE State Spaces and Generic Integrators
;;;

;; This module is deliberately numerical and headless.  It owns the algebra
;; shared by Animate's fixed RK4 and adaptive Dormand--Prince 5(4) solvers;
;; callers supply field invocation so they can retain their own public field
;; arities and diagnostics.  A state space never contains integration history.


;;;
;;; Imports and Exports

(require "geometry.rkt"
         "3d/vec3.rkt")

(provide (struct-out ode-state-space)
         real-ode-state-space
         vec2-ode-state-space
         vec3-ode-state-space
         numeric-vector-ode-state-space
         ode-state-space-check-state
         ode-state-space-weighted-sum
         ode-state-space-rk4-step
         ode-state-space-dormand-prince-step
         ode-state-space-embedded-error-ratio
         ode-state-space-hermite-interpolate)


;;;
;;; State-Space Values

;; `dimension` is a positive exact component count.  Numeric vector spaces
;; are therefore constructed for one explicit dimension rather than allowing
;; an accidental dimension change halfway through an integration.
(struct ode-state-space
  (dimension add subtract scale norm interpolate finite?)
  #:transparent
  #:guard
  (lambda (dimension add subtract scale norm interpolate finite? who)
    (unless (exact-positive-integer? dimension)
      (raise-argument-error who "exact-positive-integer? dimension" dimension))
    (for ([procedure (in-list (list add subtract scale norm interpolate finite?))]
          [name (in-list '(add subtract scale norm interpolate finite?))])
      (unless (procedure? procedure)
        (raise-arguments-error who "procedure fields" "field" name "value" procedure)))
    (values dimension add subtract scale norm interpolate finite?)))

;; A `finite?` predicate is part of every state space rather than being
;; inferred from its representation.  That keeps generic solver validation
;; correct for custom numeric-vector dimensions and rejects accidental NaNs at
;; the same boundary as a field result.
(define (ode-state-space-check-state who space value)
  (unless (ode-state-space? space)
    (raise-argument-error who "ode-state-space?" space))
  (unless ((ode-state-space-finite? space) value)
    (raise-arguments-error who
                           "a finite state in the supplied ODE state space"
                           "state-space-dimension" (ode-state-space-dimension space)
                           "value" value))
  value)


;;;
;;; Built-In Spaces

(define real-ode-state-space
  (ode-state-space
   1
   (lambda (first second) (+ first second))
   (lambda (first second) (- first second))
   (lambda (scalar value) (* scalar value))
   abs
   real-lerp
   finite-real?))

(define vec2-ode-state-space
  (ode-state-space
   2
   vec2+
   vec2-
   vec2-scale
   (lambda (value)
     (unless (vec2? value) (raise-argument-error 'vec2-ode-state-space "vec2?" value))
     (sqrt (+ (* (vec2-x value) (vec2-x value))
              (* (vec2-y value) (vec2-y value)))))
   vec2-lerp
   vec2?))

(define vec3-ode-state-space
  (ode-state-space
   3
   vec3+
   vec3-
   vec3-scale
   vec3-length
   vec3-lerp
   vec3-finite?))

; numeric-vector-ode-state-space : exact-positive-integer? -> ode-state-space?
;; Builds an immutable numeric-vector space with one fixed component count.
;; Requiring immutable inputs prevents a caller from changing a prepared
;; trajectory's seed through a retained mutable vector.
(define (numeric-vector-ode-state-space dimension)
  (unless (exact-positive-integer? dimension)
    (raise-argument-error 'numeric-vector-ode-state-space
                          "exact-positive-integer?" dimension))
  (define (finite-vector? value)
    (and (vector? value)
         (immutable? value)
         (= (vector-length value) dimension)
         (for/and ([component (in-vector value)]) (finite-real? component))))
  (define (check who value)
    (unless (finite-vector? value)
      (raise-arguments-error who
                             "immutable vector of finite reals with the state-space dimension"
                             "dimension" dimension
                             "value" value)))
  (define (combine who operation first second)
    (check who first)
    (check who second)
    (vector->immutable-vector
     (for/vector ([left (in-vector first)] [right (in-vector second)])
       (operation left right))))
  (define (scale scalar value)
    (unless (finite-real? scalar)
      (raise-argument-error 'numeric-vector-ode-state-space "finite real?" scalar))
    (check 'numeric-vector-ode-state-space value)
    (vector->immutable-vector
     (for/vector ([component (in-vector value)]) (* scalar component))))
  (define (interpolate first second progress)
    (unless (finite-real? progress)
      (raise-argument-error 'numeric-vector-ode-state-space "finite real?" progress))
    (combine 'numeric-vector-ode-state-space
             (lambda (left right) (real-lerp left right progress)) first second))
  (ode-state-space
   dimension
   (lambda (first second) (combine 'numeric-vector-ode-state-space + first second))
   (lambda (first second) (combine 'numeric-vector-ode-state-space - first second))
   scale
   (lambda (value)
     (check 'numeric-vector-ode-state-space value)
     (sqrt (for/sum ([component (in-vector value)]) (* component component))))
   interpolate
   finite-vector?))


;;;
;;; Generic Numerical Operations

; ode-state-space-weighted-sum : ode-state-space? (nonempty-listof pair?) -> state
;; Produces Σ coefficient × state without needing a distinguished zero-state
;; field in ode-state-space.  RK methods always have at least one derivative.
(define (ode-state-space-weighted-sum space terms)
  (unless (ode-state-space? space)
    (raise-argument-error 'ode-state-space-weighted-sum "ode-state-space?" space))
  (unless (and (pair? terms) (list? terms))
    (raise-argument-error 'ode-state-space-weighted-sum "nonempty list?" terms))
  (define first-term (car terms))
  (unless (and (pair? first-term) (finite-real? (car first-term)))
    (raise-argument-error 'ode-state-space-weighted-sum
                          "pairs of finite coefficients and states" first-term))
  (ode-state-space-check-state 'ode-state-space-weighted-sum space (cdr first-term))
  (for/fold ([sum ((ode-state-space-scale space) (car first-term) (cdr first-term))])
            ([term (in-list (cdr terms))])
    (unless (and (pair? term) (finite-real? (car term)))
      (raise-argument-error 'ode-state-space-weighted-sum
                            "pairs of finite coefficients and states" term))
    (ode-state-space-check-state 'ode-state-space-weighted-sum space (cdr term))
    ((ode-state-space-add space)
     sum
     ((ode-state-space-scale space) (car term) (cdr term)))))

(define (check-numerical-call who space call-field time state step)
  (unless (ode-state-space? space)
    (raise-argument-error who "ode-state-space?" space))
  (unless (and (procedure? call-field) (procedure-arity-includes? call-field 2))
    (raise-argument-error who "procedure accepting time and state" call-field))
  (unless (finite-real? time) (raise-argument-error who "finite real? time" time))
  (ode-state-space-check-state who space state)
  (unless (finite-real? step) (raise-argument-error who "finite real? step" step)))

(define (call-derivative who space call-field time state)
  (define derivative (call-field time state))
  (ode-state-space-check-state who space derivative)
  derivative)

; ode-state-space-rk4-step : ode-state-space? (time state -> state)
;                            finite-real? state finite-real? -> state
(define (ode-state-space-rk4-step space call-field time state step)
  (check-numerical-call 'ode-state-space-rk4-step space call-field time state step)
  (define add (ode-state-space-add space))
  (define scale (ode-state-space-scale space))
  (define half-step (/ step 2))
  (define k1 (call-derivative 'ode-state-space-rk4-step space call-field time state))
  (define k2 (call-derivative 'ode-state-space-rk4-step space call-field
                              (+ time half-step) (add state (scale half-step k1))))
  (define k3 (call-derivative 'ode-state-space-rk4-step space call-field
                              (+ time half-step) (add state (scale half-step k2))))
  (define k4 (call-derivative 'ode-state-space-rk4-step space call-field
                              (+ time step) (add state (scale step k3))))
  (add state
       (scale (/ step 6)
              (ode-state-space-weighted-sum
               space (list (cons 1 k1) (cons 2 k2) (cons 2 k3) (cons 1 k4))))))

; ode-state-space-embedded-error-ratio : ode-state-space? state state state
;                                        positive-finite-real? positive-finite-real?
;                                        -> nonnegative-finite-real?
;; A norm-relative embedded error works for every declared space.  The norm is
;; evaluated only on finite states, and the denominator has a positive absolute
;; tolerance, so the result is deterministic even at the origin.
(define (ode-state-space-embedded-error-ratio space previous fifth fourth
                                              relative-tolerance absolute-tolerance)
  (unless (ode-state-space? space)
    (raise-argument-error 'ode-state-space-embedded-error-ratio "ode-state-space?" space))
  (for ([value (in-list (list previous fifth fourth))])
    (ode-state-space-check-state 'ode-state-space-embedded-error-ratio space value))
  (for ([value (in-list (list relative-tolerance absolute-tolerance))]
        [name (in-list '(relative-tolerance absolute-tolerance))])
    (unless (and (finite-real? value) (positive? value))
      (raise-arguments-error 'ode-state-space-embedded-error-ratio
                             "positive finite tolerances" "tolerance" name "value" value)))
  (define norm (ode-state-space-norm space))
  (/ (norm ((ode-state-space-subtract space) fifth fourth))
     (+ absolute-tolerance
        (* relative-tolerance (max (norm previous) (norm fifth))))))

; ode-state-space-dormand-prince-step : ode-state-space? (time state -> state)
;                                        finite-real? state finite-real?
;                                        positive-finite-real? positive-finite-real?
;                                        -> (values state state nonnegative-finite-real?)
;; Performs one Dormand--Prince 5(4) trial.  It leaves acceptance policy and
;; adaptive-step selection to the caller, keeping those decisions transparent
;; to both the 2D and 3D trajectory wrappers.
(define (ode-state-space-dormand-prince-step space call-field time state step
                                              relative-tolerance absolute-tolerance)
  (check-numerical-call 'ode-state-space-dormand-prince-step space call-field time state step)
  (for ([value (in-list (list relative-tolerance absolute-tolerance))])
    (unless (and (finite-real? value) (positive? value))
      (raise-argument-error 'ode-state-space-dormand-prince-step
                            "positive finite tolerance" value)))
  (define add (ode-state-space-add space))
  (define scale (ode-state-space-scale space))
  (define (at offset terms)
    (call-derivative
     'ode-state-space-dormand-prince-step space call-field (+ time (* offset step))
     (add state (scale step (ode-state-space-weighted-sum space terms)))))
  (define k1 (call-derivative 'ode-state-space-dormand-prince-step space call-field time state))
  (define k2 (at 1/5 (list (cons 1/5 k1))))
  (define k3 (at 3/10 (list (cons 3/40 k1) (cons 9/40 k2))))
  (define k4 (at 4/5 (list (cons 44/45 k1) (cons -56/15 k2) (cons 32/9 k3))))
  (define k5 (at 8/9 (list (cons 19372/6561 k1) (cons -25360/2187 k2)
                            (cons 64448/6561 k3) (cons -212/729 k4))))
  (define k6 (at 1 (list (cons 9017/3168 k1) (cons -355/33 k2)
                          (cons 46732/5247 k3) (cons 49/176 k4)
                          (cons -5103/18656 k5))))
  (define fifth-order
    (add state (scale step
                      (ode-state-space-weighted-sum
                       space (list (cons 35/384 k1) (cons 500/1113 k3)
                                   (cons 125/192 k4) (cons -2187/6784 k5)
                                   (cons 11/84 k6))))))
  (define k7 (call-derivative 'ode-state-space-dormand-prince-step space call-field
                              (+ time step) fifth-order))
  (define fourth-order
    (add state (scale step
                      (ode-state-space-weighted-sum
                       space (list (cons 5179/57600 k1) (cons 7571/16695 k3)
                                   (cons 393/640 k4) (cons -92097/339200 k5)
                                   (cons 187/2100 k6) (cons 1/40 k7))))))
  (values fifth-order k7
          (ode-state-space-embedded-error-ratio
           space state fifth-order fourth-order relative-tolerance absolute-tolerance)))

; ode-state-space-hermite-interpolate : ode-state-space? state state state
;                                      state finite-real? finite-real? -> state
;; Cubic Hermite dense output for values and time derivatives stored at the
;; endpoints of one accepted integration interval.
(define (ode-state-space-hermite-interpolate space first-position first-derivative
                                              second-position second-derivative
                                              step progress)
  (unless (ode-state-space? space)
    (raise-argument-error 'ode-state-space-hermite-interpolate "ode-state-space?" space))
  (for ([value (in-list (list first-position first-derivative
                              second-position second-derivative))])
    (ode-state-space-check-state 'ode-state-space-hermite-interpolate space value))
  (for ([value (in-list (list step progress))])
    (unless (finite-real? value)
      (raise-argument-error 'ode-state-space-hermite-interpolate "finite real?" value)))
  (define h00 (+ (* 2 progress progress progress) (* -3 progress progress) 1))
  (define h10 (+ (* progress progress progress) (* -2 progress progress) progress))
  (define h01 (+ (* -2 progress progress progress) (* 3 progress progress)))
  (define h11 (+ (* progress progress progress) (* -1 progress progress)))
  (ode-state-space-weighted-sum
   space
   (list (cons h00 first-position)
         (cons (* h10 step) first-derivative)
         (cons h01 second-position)
         (cons (* h11 step) second-derivative))))
