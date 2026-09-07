#lang racket/base

;;;
;;; Immutable attenuation and spotlight falloff values
;;;

;; This module is deliberately renderer neutral.  It defines the named
;; attenuation models that V5's reference lighting and the later OpenGL pass
;; will evaluate; accepting a value here never implies that an older renderer
;; silently approximates a point or spot light.

(require (only-in racket/math pi sqr)
         "../geometry.rkt")

(provide (struct-out light-attenuation3d)
         constant-attenuation3d
         inverse-square-attenuation3d
         polynomial-attenuation3d
         light-attenuation3d-factor
         spot-smoothstep3d
         spot-cone-factor3d)

;; `parameters` is an immutable hash with a mode-specific explicit schema.
;; This preserves an inspectable, extensible semantic record without exposing
;; anonymous coefficient triples as the sole public interface.
(struct light-attenuation3d (mode parameters)
  #:transparent
  #:guard
  (lambda (mode parameters who)
    (unless (memq mode '(constant inverse-square polynomial))
      (raise-argument-error who
                            "(or/c 'constant 'inverse-square 'polynomial)"
                            mode))
    (unless (and (hash? parameters) (immutable? parameters))
      (raise-argument-error who "immutable hash? attenuation parameters" parameters))
    (validate-parameters who mode parameters)
    (values mode parameters)))

; constant-attenuation3d : [#:factor nonnegative-finite-real?] -> light-attenuation3d?
;; A constant multiplier is mostly useful for explicit didactic comparisons;
;; ordinary authored light strength belongs in `#:intensity`.
(define (constant-attenuation3d #:factor [factor 1])
  (check-nonnegative 'constant-attenuation3d factor 'factor)
  (light-attenuation3d 'constant (hasheq 'factor factor)))

; inverse-square-attenuation3d : [#:reference-distance positive-finite-real?]
;                                [#:cutoff (or/c #f positive-finite-real?)]
;                                -> light-attenuation3d?
;; The factor is `(reference-distance / max(distance, reference-distance))^2`.
;; Hence the singularity is explicitly clamped at the named reference distance.
(define (inverse-square-attenuation3d #:reference-distance [reference-distance 1]
                                      #:cutoff [cutoff #f])
  (check-positive 'inverse-square-attenuation3d reference-distance 'reference-distance)
  (check-cutoff 'inverse-square-attenuation3d cutoff)
  (light-attenuation3d
   'inverse-square
   (hasheq 'reference-distance reference-distance 'cutoff cutoff)))

; polynomial-attenuation3d : [#:constant nonnegative-finite-real?]
;                             [#:linear nonnegative-finite-real?]
;                             [#:quadratic nonnegative-finite-real?]
;                             [#:cutoff (or/c #f positive-finite-real?)]
;                             -> light-attenuation3d?
;; The named coefficients form `1/(constant + linear*d + quadratic*d^2)`.
;; At least one must be positive, making every accepted value total at d = 0.
(define (polynomial-attenuation3d #:constant [constant 1]
                                  #:linear [linear 0]
                                  #:quadratic [quadratic 0]
                                  #:cutoff [cutoff #f])
  (for ([value (in-list (list constant linear quadratic))]
        [name (in-list '(constant linear quadratic))])
    (check-nonnegative 'polynomial-attenuation3d value name))
  (when (and (zero? constant) (zero? linear) (zero? quadratic))
    (raise-arguments-error 'polynomial-attenuation3d
                           "at least one positive named coefficient"
                           "constant" constant "linear" linear "quadratic" quadratic))
  (check-cutoff 'polynomial-attenuation3d cutoff)
  (light-attenuation3d
   'polynomial
   (hasheq 'constant constant 'linear linear 'quadratic quadratic 'cutoff cutoff)))

; light-attenuation3d-factor : light-attenuation3d? nonnegative-finite-real? -> nonnegative-real?
;; Shared pure evaluation used by the later CPU/GPU lighting implementations.
(define (light-attenuation3d-factor attenuation distance)
  (unless (light-attenuation3d? attenuation)
    (raise-argument-error 'light-attenuation3d-factor "light-attenuation3d?" attenuation))
  (check-nonnegative 'light-attenuation3d-factor distance 'distance)
  (define parameters (light-attenuation3d-parameters attenuation))
  (define cutoff (hash-ref parameters 'cutoff #f))
  (cond [(and cutoff (> distance cutoff)) 0]
        [else
         (case (light-attenuation3d-mode attenuation)
           [(constant) (hash-ref parameters 'factor)]
           [(inverse-square)
            (define reference-distance (hash-ref parameters 'reference-distance))
            (sqr (/ reference-distance (max distance reference-distance)))]
           [(polynomial)
            (define denominator
              (+ (hash-ref parameters 'constant)
                 (* (hash-ref parameters 'linear) distance)
                 (* (hash-ref parameters 'quadratic) distance distance)))
            (/ 1 denominator)])]))

; spot-smoothstep3d : finite-real? -> real in [0,1]
;; The fixed C1 polynomial selected for the spot transition interval.
(define (spot-smoothstep3d progress)
  (unless (finite-real? progress)
    (raise-argument-error 'spot-smoothstep3d "finite-real?" progress))
  (define t (min 1 (max 0 progress)))
  (* t t (- 3 (* 2 t))))

; spot-cone-factor3d : inner-angle outer-angle angle -> real in [0,1]
;; Angles are radians from the spot's outward direction.  The inner cone is
;; fully illuminated, the outer cone and beyond are dark, and the interval is
;; the fixed smoothstep transition specified for V3.
(define (spot-cone-factor3d inner-angle outer-angle angle)
  (check-cone-angles 'spot-cone-factor3d inner-angle outer-angle)
  (unless (and (finite-real? angle) (>= angle 0))
    (raise-argument-error 'spot-cone-factor3d "nonnegative finite angle" angle))
  (cond [(<= angle inner-angle) 1]
        [(>= angle outer-angle) 0]
        [(= inner-angle outer-angle) 0]
        [else (spot-smoothstep3d (/ (- outer-angle angle)
                                    (- outer-angle inner-angle)))]))

(define (validate-parameters who mode parameters)
  (case mode
    [(constant)
     (check-exact-keys who parameters '(factor))
     (check-nonnegative who (hash-ref parameters 'factor) 'factor)]
    [(inverse-square)
     (check-exact-keys who parameters '(reference-distance cutoff))
     (check-positive who (hash-ref parameters 'reference-distance) 'reference-distance)
     (check-cutoff who (hash-ref parameters 'cutoff))]
    [(polynomial)
     (check-exact-keys who parameters '(constant linear quadratic cutoff))
     (for ([name (in-list '(constant linear quadratic))])
       (check-nonnegative who (hash-ref parameters name) name))
     (when (and (zero? (hash-ref parameters 'constant))
                (zero? (hash-ref parameters 'linear))
                (zero? (hash-ref parameters 'quadratic)))
       (raise-arguments-error who "at least one positive polynomial coefficient"
                              "parameters" parameters))
     (check-cutoff who (hash-ref parameters 'cutoff))]))

(define (check-exact-keys who parameters expected)
  (unless (and (= (hash-count parameters) (length expected))
               (for/and ([key (in-list expected)]) (hash-has-key? parameters key)))
    (raise-arguments-error who "the expected immutable attenuation parameter keys"
                           "parameters" parameters "expected-keys" expected)))

(define (check-nonnegative who value name)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who "nonnegative finite real" "field" name "value" value)))

(define (check-positive who value name)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real" "field" name "value" value)))

(define (check-cutoff who cutoff)
  (unless (or (not cutoff) (and (finite-real? cutoff) (positive? cutoff)))
    (raise-arguments-error who "#f or positive finite cutoff" "cutoff" cutoff)))

(define (check-cone-angles who inner-angle outer-angle)
  (unless (and (finite-real? inner-angle) (>= inner-angle 0))
    (raise-arguments-error who "nonnegative finite inner angle" inner-angle))
  (unless (and (finite-real? outer-angle) (positive? outer-angle) (<= outer-angle pi))
    (raise-arguments-error who "finite outer angle in (0, pi]" outer-angle))
  (unless (<= inner-angle outer-angle)
    (raise-arguments-error who "inner angle no larger than outer angle"
                           "inner-angle" inner-angle "outer-angle" outer-angle)))
