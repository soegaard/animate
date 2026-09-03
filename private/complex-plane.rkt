#lang racket/base

;;;
;;; Complex-Plane Builders and Maps
;;;

;; Keeps complex arithmetic in Racket's ordinary numeric domain while using
;; vec2 at the drawing boundary. Complex animations are a thin specialization
;; of apply-pointwise rather than a second scene representation.

(require "axes-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "linear-algebra.rkt"
         "text-visual.rkt"
         "visual-model.rkt"
         "animation.rkt")

(provide complex->point
         point->complex
         complex-plane
         apply-complex-function)

;; complex->point : complex? -> vec2?
;; Maps a + bi to the usual Cartesian point (a,b).
(define (complex->point value)
  (unless (complex? value)
    (raise-argument-error 'complex->point "complex?" value))
  (define real (real-part value))
  (define imaginary (imag-part value))
  (unless (and (finite-real? real) (finite-real? imaginary))
    (raise-arguments-error
     'complex->point
     "a complex number with finite real and imaginary parts"
     "value" value))
  (vec2 real imaginary))

;; point->complex : vec2? -> complex?
;; Maps a Cartesian point (x,y) to x + yi.
(define (point->complex point)
  (unless (vec2? point)
    (raise-argument-error 'point->complex "vec2?" point))
  (make-rectangular (vec2-x point) (vec2-y point)))

;; complex-plane : #:id symbol? ... -> group-visual?
;; Builds a Cartesian grid with conventional Re/Im labels. Numeric tick labels
;; are delegated to number-plane, keeping their scale and range consistent with
;; the existing linear-algebra API.
(define (complex-plane #:id id
                       #:x-range [x-range (axis-range -4 4 1)]
                       #:y-range [y-range (axis-range -3 3 1)]
                       #:x-length [x-length 8]
                       #:y-length [y-length 6]
                       #:center [center origin]
                       #:rotation [rotation 0]
                       #:scale [scale 1]
                       #:grid? [grid? #t]
                       #:labels? [labels? #t]
                       #:grid-stroke [grid-stroke "lightsteelblue"]
                       #:grid-stroke-width [grid-stroke-width 1]
                       #:axes-stroke [axes-stroke "navy"]
                       #:axes-stroke-width [axes-stroke-width 2]
                       #:label-font-size [label-font-size 1/4]
                       #:label-color [label-color "navy"])
  (unless (symbol? id)
    (raise-argument-error 'complex-plane "symbol?" id))
  (unless (axis-range? x-range)
    (raise-argument-error 'complex-plane "axis-range?" x-range))
  (unless (axis-range? y-range)
    (raise-argument-error 'complex-plane "axis-range?" y-range))
  (unless (and (finite-real? x-length) (positive? x-length))
    (raise-argument-error 'complex-plane "positive finite x length" x-length))
  (unless (and (finite-real? y-length) (positive? y-length))
    (raise-argument-error 'complex-plane "positive finite y length" y-length))
  (unless (boolean? labels?)
    (raise-argument-error 'complex-plane "boolean?" labels?))
  (define plane
    (number-plane
     #:id 'coordinates
     #:x-range x-range #:y-range y-range
     #:x-length x-length #:y-length y-length
     #:grid? grid? #:labels? labels?
     #:grid-stroke grid-stroke #:grid-stroke-width grid-stroke-width
     #:axes-stroke axes-stroke #:axes-stroke-width axes-stroke-width
     #:label-font-size label-font-size #:label-color label-color))
  (define semantic-axis-labels
    (if labels?
        (list
         (plain-text "Re" #:id 'real-axis
                     #:center (vec2 (+ (/ x-length 2) 3/10) 1/5)
                     #:font-size label-font-size #:font-family 'swiss
                     #:font-weight 'bold #:color label-color)
         (plain-text "Im" #:id 'imaginary-axis
                     #:center (vec2 1/5 (+ (/ y-length 2) 3/10))
                     #:font-size label-font-size #:font-family 'swiss
                     #:font-weight 'bold #:color label-color))
        '()))
  (group (append (list plane) semantic-axis-labels)
         #:id id #:center center #:rotation rotation #:scale scale))

;; apply-complex-function : target (-> complex? complex?) ...
;; Applies f to every sampled world point interpreted as a complex number.
(define (apply-complex-function target function #:samples [samples 24])
  (unless (and (procedure? function)
               (procedure-arity-includes? function 1))
    (raise-argument-error
     'apply-complex-function "(procedure-arity-includes/c 1)" function))
  (apply-pointwise
   target
   (lambda (point)
     (define result (function (point->complex point)))
     (unless (complex? result)
       (raise-arguments-error
        'apply-complex-function
        "the complex function must return a complex number"
        "point" point
        "result" result))
     (complex->point result))
   #:samples samples))
