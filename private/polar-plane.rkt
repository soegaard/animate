#lang racket/base

;;;
;;; Polar Coordinates and Polar Graphs
;;;

(require racket/list
         (only-in racket/math pi)
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide polar-coordinate?
         polar-coordinate-radius
         polar-coordinate-angle
         polar->point
         point->polar
         polar-plane
         polar-graph)

;; A normalized polar reading produced by point->polar. Angles use atan's
;; conventional interval [-pi, pi], and the zero point has angle zero.
(struct polar-coordinate (radius angle)
  #:transparent
  #:guard
  (lambda (radius angle who)
    (unless (and (finite-real? radius) (not (negative? radius)))
      (raise-argument-error who "nonnegative finite real radius" radius))
    (unless (finite-real? angle)
      (raise-argument-error who "finite real angle" angle))
    (values radius angle)))

;; polar->point : finite-real? finite-real? -> vec2?
;; Converts the (possibly signed) radial graph value and azimuth to Cartesian
;; coordinates. Signed radii deliberately support standard rose curves.
(define (polar->point radius angle)
  (unless (finite-real? radius)
    (raise-argument-error 'polar->point "finite real radius" radius))
  (unless (finite-real? angle)
    (raise-argument-error 'polar->point "finite real angle" angle))
  (vec2 (* radius (cos angle))
        (* radius (sin angle))))

;; point->polar : vec2? -> polar-coordinate?
(define (point->polar point)
  (unless (vec2? point)
    (raise-argument-error 'point->polar "vec2?" point))
  (define x (vec2-x point))
  (define y (vec2-y point))
  (polar-coordinate (sqrt (+ (* x x) (* y y)))
                    (if (and (zero? x) (zero? y))
                        0
                        (atan y x))))

;; polar-plane : #:id symbol? ... -> group-visual?
;; Creates addressed `rings`, `rays`, and optional `labels` children. The rings
;; are ordinary semantic circles, so they retain their meaning until a caller
;; applies a nonlinear point map.
(define (polar-plane #:id id
                     #:radii [radii '(1 2 3)]
                     #:angles [angles default-polar-angles]
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale 1]
                     #:labels? [labels? #t]
                     #:stroke [stroke "steelblue"]
                     #:stroke-width [stroke-width 2]
                     #:grid-stroke [grid-stroke "lightsteelblue"]
                     #:grid-stroke-width [grid-stroke-width 1]
                     #:label-font-size [label-font-size 1/4]
                     #:label-color [label-color "navy"])
  (unless (symbol? id)
    (raise-argument-error 'polar-plane "symbol?" id))
  (check-positive-number-list 'polar-plane "radii" radii)
  (check-number-list 'polar-plane "angles" angles)
  (unless (vec2? center)
    (raise-argument-error 'polar-plane "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'polar-plane "finite real rotation" rotation))
  (unless (and (finite-real? scale) (positive? scale))
    (raise-argument-error 'polar-plane "positive finite uniform scale" scale))
  (unless (boolean? labels?)
    (raise-argument-error 'polar-plane "boolean?" labels?))
  (unless (and (finite-real? label-font-size) (positive? label-font-size))
    (raise-argument-error 'polar-plane "positive finite label font size" label-font-size))
  (define maximum-radius (apply max radii))
  (define rings
    (group
     (for/list ([radius (in-list radii)] [index (in-naturals)])
       (circle #:id (indexed-id 'ring index)
               #:radius radius #:fill #f
               #:stroke grid-stroke #:stroke-width grid-stroke-width))
     #:id 'rings))
  (define rays
    (group
     (for/list ([angle (in-list angles)] [index (in-naturals)])
       (line origin (polar->point maximum-radius angle)
             #:id (indexed-id 'ray index)
             #:stroke (if (zero? (sin angle)) stroke grid-stroke)
             #:stroke-width (if (zero? (sin angle)) stroke-width grid-stroke-width)))
     #:id 'rays))
  (define labels
    (if labels?
        (group
         (append
          (for/list ([radius (in-list radii)] [index (in-naturals)])
            (plain-text (number->string radius)
                        #:id (indexed-id 'radius index)
                        #:center (vec2 (+ radius 1/8) 1/8)
                        #:font-size label-font-size #:font-family 'swiss
                        #:color label-color))
          (for/list ([angle (in-list angles)] [index (in-naturals)])
            (define position
              (polar->point (+ maximum-radius 3/10) angle))
            (plain-text (angle-label angle)
                        #:id (indexed-id 'angle index)
                        #:center position
                        #:font-size label-font-size #:font-family 'swiss
                        #:color label-color)))
         #:id 'labels)
        #f))
  (group (append (list rings rays) (if labels (list labels) '()))
         #:id id #:center center #:rotation rotation #:scale scale))

;; polar-graph : (-> finite-real? finite-real?) #:id symbol? ... -> path-visual?
;; Samples r(theta) at evenly spaced angles. A signed radius is accepted, as in
;; conventional polar-curve notation; an invalid function result is diagnosed
;; with the corresponding angle.
(define (polar-graph radius-function
                     #:id id
                     #:start [start 0]
                     #:end [end (* 2 pi)]
                     #:samples [samples 240]
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale 1]
                     #:opacity [opacity 1]
                     #:stroke [stroke "crimson"]
                     #:stroke-width [stroke-width 3]
                     #:fill [fill #f])
  (unless (and (procedure? radius-function)
               (procedure-arity-includes? radius-function 1))
    (raise-argument-error
     'polar-graph "(procedure-arity-includes/c 1)" radius-function))
  (unless (symbol? id)
    (raise-argument-error 'polar-graph "symbol?" id))
  (unless (and (finite-real? start) (finite-real? end) (< start end))
    (raise-arguments-error 'polar-graph "finite start < end"
                           "start" start "end" end))
  (unless (and (exact-integer? samples) (>= samples 2))
    (raise-argument-error 'polar-graph "exact integer at least 2" samples))
  (define points
    (for/list ([index (in-range (add1 samples))])
      (define angle (+ start (* (- end start) (/ index samples))))
      (define radius (radius-function angle))
      (unless (finite-real? radius)
        (raise-arguments-error
         'polar-graph "radius function result must be a finite real"
         "angle" angle "result" radius))
      (polar->point radius angle)))
  (make-path-visual
   (polyline-path points)
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:stroke stroke #:stroke-width stroke-width #:fill fill))

(define default-polar-angles
  (list 0 (/ pi 4) (/ pi 2) (* 3 (/ pi 4)) pi
        (* 5 (/ pi 4)) (* 3 (/ pi 2)) (* 7 (/ pi 4))))

(define (indexed-id prefix index)
  (string->symbol (format "~a-~a" prefix index)))

(define (angle-label angle)
  (format "~a°" (inexact->exact (round (* 180 (/ angle pi))))))

(define (check-number-list who field values)
  (unless (and (list? values)
               (pair? values)
               (andmap finite-real? values))
    (raise-arguments-error who "a nonempty list of finite reals"
                           field values)))

(define (check-positive-number-list who field values)
  (check-number-list who field values)
  (unless (andmap positive? values)
    (raise-arguments-error who "a list of positive finite reals"
                           field values)))
