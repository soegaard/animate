#lang racket/base

;;;
;;; Deterministic ODE Flow and Streamlines
;;;

;; Integrates a two-dimensional autonomous field with fixed-step RK4. The
;; routines retain neither an integration history nor mutable particle state:
;; every requested time is recomputed from the same seed and field.


;;;
;;; Imports and Exports

(require "axes-visual.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "parameter.rkt"
         "path-geometry.rkt"
         "point-marker-visual.rkt"
         "visual-model.rkt")

(provide ode-flow-position
         streamline-points
         streamline
         streamlines
         flow-particle)


;;;
;;; Public Numerical API

;; ode-flow-position : field vec2? finite-real? #:step-size positive-finite-real?
;;                     -> vec2?
;; Returns the fixed-step fourth-order Runge--Kutta solution from time zero.
(define (ode-flow-position field seed time #:step-size [step-size 1/20])
  (check-field 'ode-flow-position field)
  (check-vec2 'ode-flow-position seed)
  (check-finite 'ode-flow-position "time" time)
  (check-positive 'ode-flow-position "step-size" step-size)
  (cond
    [(zero? time) seed]
    [else
     (define direction (if (positive? time) 1 -1))
     (define full-step (* direction step-size))
     (define whole-count (inexact->exact (floor (/ (abs time) step-size))))
     (define state
       (for/fold ([point seed]) ([ignored (in-range whole-count)])
         (rk4-step field point full-step)))
     (define remainder (- time (* whole-count full-step)))
     (if (zero? remainder)
         state
         (rk4-step field state remainder))]))

;; streamline-points : field vec2? #:direction flow-direction?
;;                     #:step-size positive-finite-real? #:steps positive-integer?
;;                     -> (listof vec2?)
;; Produces a stable collection of coordinate-space ODE samples. `both` has one
;; shared seed point in the middle and never duplicates it.
(define (streamline-points field seed
                           #:direction [direction 'both]
                           #:step-size [step-size 1/20]
                           #:steps [steps 120])
  (check-field 'streamline-points field)
  (check-vec2 'streamline-points seed)
  (check-direction 'streamline-points direction)
  (check-positive 'streamline-points "step-size" step-size)
  (check-steps 'streamline-points steps)
  (define (at index)
    (ode-flow-position field seed (* index step-size) #:step-size step-size))
  (case direction
    [(forward)
     (for/list ([index (in-range 0 (add1 steps))])
       (at index))]
    [(backward)
     (for/list ([index (in-range steps -1 -1)])
       (at (- index)))]
    [(both)
     (append
      (for/list ([index (in-range steps 0 -1)])
        (at (- index)))
      (for/list ([index (in-range 0 (add1 steps))])
        (at index)))]))


;;;
;;; Streamline Visuals

;; streamline : axes-visual? field vec2? #:id symbol? ... -> path-visual?
;; Converts fixed numeric-coordinate samples through the supplied axes.
(define (streamline axes field seed
                    #:id id
                    #:direction [direction 'both]
                    #:step-size [step-size 1/20]
                    #:steps [steps 120]
                    #:opacity [opacity 1]
                    #:stroke [stroke "royalblue"]
                    #:stroke-width [stroke-width 2])
  (check-axes 'streamline axes)
  (unless (symbol? id)
    (raise-argument-error 'streamline "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error 'streamline "opacity?" opacity))
  (check-nonnegative 'streamline "stroke-width" stroke-width)
  (define coordinates
    (streamline-points field seed
                       #:direction direction
                       #:step-size step-size
                       #:steps steps))
  (make-world-path-visual
   (map (lambda (point)
          (axes-coordinates->point axes (vec2-x point) (vec2-y point)))
        coordinates)
   id opacity stroke stroke-width))

;; streamlines : axes-visual? field (listof vec2?) #:id symbol? ...
;;               -> group-visual?
;; Builds an ordinary group whose child IDs are deterministic `id-N` symbols.
(define (streamlines axes field seeds
                    #:id id
                    #:direction [direction 'both]
                    #:step-size [step-size 1/20]
                    #:steps [steps 120]
                    #:opacity [opacity 1]
                    #:stroke [stroke "royalblue"]
                    #:stroke-width [stroke-width 2])
  (check-axes 'streamlines axes)
  (check-field 'streamlines field)
  (unless (symbol? id)
    (raise-argument-error 'streamlines "symbol?" id))
  (unless (list? seeds)
    (raise-argument-error 'streamlines "list?" seeds))
  (for ([seed (in-list seeds)])
    (check-vec2 'streamlines seed))
  (check-direction 'streamlines direction)
  (check-positive 'streamlines "step-size" step-size)
  (check-steps 'streamlines steps)
  (unless (opacity? opacity)
    (raise-argument-error 'streamlines "opacity?" opacity))
  (check-nonnegative 'streamlines "stroke-width" stroke-width)
  (group
   (for/list ([seed (in-list seeds)] [index (in-naturals)])
     (streamline axes field seed
                 #:id (streamline-id id index)
                 #:direction direction
                 #:step-size step-size
                 #:steps steps
                 #:opacity opacity
                 #:stroke stroke
                 #:stroke-width stroke-width))
   #:id id))


;;;
;;; Parameter-Driven Flow Particle

;; flow-particle : axes-visual? field vec2? parameter #:id symbol? ...
;;                  -> derived-visual?
;; Uses the current scalar parameter as an absolute ODE time. Its position is
;; recomputed directly from the original seed at each sampled frame.
(define (flow-particle axes field seed phase
                       #:id id
                       #:step-size [step-size 1/20]
                       #:shape [shape 'circle]
                       #:size [size 1/5]
                       #:fill [fill "crimson"]
                       #:stroke [stroke "black"]
                       #:stroke-width [stroke-width 1]
                       #:opacity [opacity 1])
  (check-axes 'flow-particle axes)
  (check-field 'flow-particle field)
  (check-vec2 'flow-particle seed)
  (define phase-id (parameter-target-id phase 'flow-particle))
  (unless (symbol? id)
    (raise-argument-error 'flow-particle "symbol?" id))
  (check-positive 'flow-particle "step-size" step-size)
  (define (make-marker time)
    (define coordinate
      (ode-flow-position field seed time #:step-size step-size))
    (define center
      (axes-coordinates->point axes
                                (vec2-x coordinate)
                                (vec2-y coordinate)))
    (point-marker #:id id #:center center
                  #:shape shape #:size size #:fill fill #:stroke stroke
                  #:stroke-width stroke-width #:opacity opacity))
  (derived-visual
   (make-marker 0)
   (lambda (context _template)
     (define time (derived-context-value-ref context phase-id))
     (unless (finite-real? time)
       (raise-arguments-error
        'flow-particle
        "the phase parameter must hold a finite real ODE time"
        "phase-id" phase-id
        "value" time))
     (make-marker time))))


;;;
;;; Internal Geometry and Validation

;; Creates a path in the containing world coordinate system. Unlike ordinary
;; function graphs, the supplied points have already passed through an axes
;; transform, so the path stores a neutral transform around its own center.
(define (make-world-path-visual points id opacity stroke stroke-width)
  (define geometry (polyline-path points))
  (define center (path-geometry-center geometry))
  (make-path-visual
   (path-geometry-translate geometry (vec2-scale -1 center))
   #:id id #:center center #:opacity opacity #:fill #f
   #:stroke stroke #:stroke-width stroke-width))

(define (rk4-step field point step)
  (define half-step (/ step 2))
  (define k1 (call-field field point))
  (define k2 (call-field field (vec2+ point (vec2-scale half-step k1))))
  (define k3 (call-field field (vec2+ point (vec2-scale half-step k2))))
  (define k4 (call-field field (vec2+ point (vec2-scale step k3))))
  (vec2+
   point
   (vec2-scale
    (/ step 6)
    (vec2+ k1
           (vec2+ (vec2-scale 2 k2)
                  (vec2+ (vec2-scale 2 k3) k4))))))

(define (call-field field point)
  (define result
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'ode-flow-position
             "the ODE field raised an exception"
             "point" point
             "exception message" (exn-message exception)))])
      (call-with-values
       (lambda () (field (vec2-x point) (vec2-y point)))
       list)))
  (unless (= (length result) 1)
    (raise-arguments-error
     'ode-flow-position
     "the ODE field must return exactly one vec2"
     "point" point
     "result count" (length result)))
  (define value (car result))
  (unless (vec2? value)
    (raise-arguments-error
     'ode-flow-position
     "the ODE field must return a finite vec2"
     "point" point
     "result" value))
  value)

(define (streamline-id id index)
  (string->symbol (format "~a-~a" (symbol->string id) index)))

(define (check-field who field)
  (unless (and (procedure? field)
               (procedure-arity-includes? field 2))
    (raise-argument-error who "procedure accepting two numeric arguments" field)))

(define (check-direction who value)
  (unless (memq value '(forward backward both))
    (raise-argument-error who "'forward, 'backward, or 'both" value)))

(define (check-axes who value)
  (unless (axes-visual? value)
    (raise-argument-error who "axes-visual?" value)))

(define (check-vec2 who value)
  (unless (vec2? value)
    (raise-argument-error who "vec2?" value)))

(define (check-finite who name value)
  (unless (finite-real? value)
    (raise-arguments-error who "a finite real value" name value)))

(define (check-positive who name value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "a positive finite real value" name value)))

(define (check-nonnegative who name value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who "a nonnegative finite real value" name value)))

(define (check-steps who value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-argument-error who "positive exact integer?" value)))
