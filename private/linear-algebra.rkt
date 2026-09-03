#lang racket/base

;;;
;;; Linear-Algebra Diagram Builders
;;;

;; Defines ordinary immutable group trees for number planes, vectors, basis
;; arrows, and a canonical linear-transformation diagram. No special Scene
;; subclass or mutable updater is introduced: callers animate the returned
;; top-level group with apply-matrix/apply-affine.


;;;
;;; Imports and Exports

(require "arrow-visual.rkt"
         "axes-visual.rkt"
         "coordinate-decoration.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide number-plane
         number-plane-grid-path
         number-plane-axes-path
         number-plane-labels-path
         vector-arrow
         vector-coordinates
         vector-label
         basis-vectors
         linear-transformation-diagram)


;;;
;;; Number Planes

;; number-plane : #:id symbol? ... -> group-visual?
;; Builds one regular group with addressable grid, axes, and optional labels.
(define (number-plane #:id id
                      #:x-range [x-range (axis-range -4 4 1)]
                      #:y-range [y-range (axis-range -3 3 1)]
                      #:x-length [x-length 8]
                      #:y-length [y-length 6]
                      #:center [center origin]
                      #:rotation [rotation 0]
                      #:scale [scale 1]
                      #:grid? [grid? #t]
                      #:labels? [labels? #f]
                      #:grid-stroke [grid-stroke "lightsteelblue"]
                      #:grid-stroke-width [grid-stroke-width 1]
                      #:axes-stroke [axes-stroke "navy"]
                      #:axes-stroke-width [axes-stroke-width 2]
                      #:label-font-size [label-font-size 1/4]
                      #:label-color [label-color "navy"])
  (unless (symbol? id)
    (raise-argument-error 'number-plane "symbol?" id))
  (unless (axis-range? x-range)
    (raise-argument-error 'number-plane "axis-range?" x-range))
  (unless (axis-range? y-range)
    (raise-argument-error 'number-plane "axis-range?" y-range))
  (unless (and (finite-real? x-length) (positive? x-length))
    (raise-argument-error 'number-plane "positive finite x length" x-length))
  (unless (and (finite-real? y-length) (positive? y-length))
    (raise-argument-error 'number-plane "positive finite y length" y-length))
  (unless (boolean? grid?)
    (raise-argument-error 'number-plane "boolean?" grid?))
  (unless (boolean? labels?)
    (raise-argument-error 'number-plane "boolean?" labels?))
  (unless (and (finite-real? label-font-size) (positive? label-font-size))
    (raise-argument-error 'number-plane "positive finite label font size" label-font-size))
  (define plane-axes
    (axes #:id 'axes
          #:x-range x-range #:y-range y-range
          #:x-length x-length #:y-length y-length
          #:stroke axes-stroke #:stroke-width axes-stroke-width))
  (define children
    (append
     (if grid?
         (list (axes-grid-lines plane-axes
                                #:id 'grid
                                #:stroke grid-stroke
                                #:stroke-width grid-stroke-width))
         '())
     (list plane-axes)
     (if labels?
         (list
          (group
           (axes-number-labels plane-axes
                               #:id-prefix 'tick
                               #:font-size label-font-size
                               #:color label-color)
           #:id 'labels))
         '())))
  (group children
         #:id id #:center center #:rotation rotation #:scale scale))

;; number-plane-grid-path : symbol? -> visual-path?
(define (number-plane-grid-path plane-id)
  (number-plane-child-path 'number-plane-grid-path plane-id 'grid))

;; number-plane-axes-path : symbol? -> visual-path?
(define (number-plane-axes-path plane-id)
  (number-plane-child-path 'number-plane-axes-path plane-id 'axes))

;; number-plane-labels-path : symbol? -> visual-path?
(define (number-plane-labels-path plane-id)
  (number-plane-child-path 'number-plane-labels-path plane-id 'labels))

(define (number-plane-child-path who plane-id child-id)
  (unless (symbol? plane-id)
    (raise-argument-error who "symbol?" plane-id))
  (list plane-id child-id))


;;;
;;; Vector Arrows and Labels

;; vector-arrow avoids shadowing racket/base's vector constructor.
;; vector-arrow : vec2? #:start vec2? #:id symbol? ... -> arrow-visual?
(define (vector-arrow endpoint
                      #:start [start origin]
                      #:id id
                      #:stroke [stroke "darkorchid"]
                      #:stroke-width [stroke-width 3]
                      #:tip-length [tip-length 3/10]
                      #:tip-width [tip-width 1/4])
  (unless (vec2? endpoint)
    (raise-argument-error 'vector-arrow "vec2?" endpoint))
  (unless (vec2? start)
    (raise-argument-error 'vector-arrow "vec2?" start))
  (arrow start endpoint
         #:id id #:stroke stroke #:stroke-width stroke-width
         #:tip-length tip-length #:tip-width tip-width))

;; vector-coordinates : arrow-visual? -> vec2?
;; Returns endpoint minus start in the containing coordinate system.
(define (vector-coordinates vector)
  (unless (arrow-visual? vector)
    (raise-argument-error 'vector-coordinates "arrow-visual?" vector))
  (vec2- (arrow-visual-end vector)
         (arrow-visual-start vector)))

;; vector-label : arrow-visual? #:id symbol? ... -> text-visual?
;; Places a static label at the vector's endpoint. SCENE-DE will add live
;; layout relationships for labels that follow a separately animated vector.
(define (vector-label vector
                      #:id id
                      #:text [text #f]
                      #:offset [offset (vec2 1/5 1/5)]
                      #:font-size [font-size 1/4]
                      #:color [color "darkorchid"])
  (unless (arrow-visual? vector)
    (raise-argument-error 'vector-label "arrow-visual?" vector))
  (unless (symbol? id)
    (raise-argument-error 'vector-label "symbol?" id))
  (unless (or (not text) (string? text))
    (raise-argument-error 'vector-label "(or/c false/c string?)" text))
  (unless (vec2? offset)
    (raise-argument-error 'vector-label "vec2?" offset))
  (unless (and (finite-real? font-size) (positive? font-size))
    (raise-argument-error 'vector-label "positive finite font size" font-size))
  (plain-text
   (or text (coordinates->string (vector-coordinates vector)))
   #:id id
   #:center (vec2+ (arrow-visual-end vector) offset)
   #:font-size font-size
   #:color color))

;; basis-vectors : #:id symbol? ... -> group-visual?
;; Creates conventional e1/e2 arrows with direct, stable child identities.
(define (basis-vectors #:id id
                       #:origin [start origin]
                       #:e1 [e1 (vec2 1 0)]
                       #:e2 [e2 (vec2 0 1)]
                       #:e1-color [e1-color "crimson"]
                       #:e2-color [e2-color "forestgreen"]
                       #:stroke-width [stroke-width 3])
  (unless (symbol? id)
    (raise-argument-error 'basis-vectors "symbol?" id))
  (unless (vec2? start)
    (raise-argument-error 'basis-vectors "vec2?" start))
  (unless (vec2? e1)
    (raise-argument-error 'basis-vectors "vec2?" e1))
  (unless (vec2? e2)
    (raise-argument-error 'basis-vectors "vec2?" e2))
  (group
   (list
    (vector-arrow e1 #:start start #:id 'e1
                  #:stroke e1-color #:stroke-width stroke-width)
    (vector-arrow e2 #:start start #:id 'e2
                  #:stroke e2-color #:stroke-width stroke-width))
   #:id id))


;;;
;;; Canonical Diagram

;; linear-transformation-diagram : #:id symbol? ... -> group-visual?
;; Produces an ordinary nested tree intended for apply-matrix/apply-affine.
(define (linear-transformation-diagram
         #:id id
         #:x-range [x-range (axis-range -4 4 1)]
         #:y-range [y-range (axis-range -3 3 1)]
         #:vector-end [vector-end (vec2 3 2)]
         #:unit-square? [unit-square? #t]
         #:grid? [grid? #t])
  (unless (symbol? id)
    (raise-argument-error 'linear-transformation-diagram "symbol?" id))
  (unless (vec2? vector-end)
    (raise-argument-error 'linear-transformation-diagram "vec2?" vector-end))
  (unless (boolean? unit-square?)
    (raise-argument-error 'linear-transformation-diagram "boolean?" unit-square?))
  (unless (boolean? grid?)
    (raise-argument-error 'linear-transformation-diagram "boolean?" grid?))
  (define plane
    (number-plane #:id 'plane #:x-range x-range #:y-range y-range
                  #:grid? grid?))
  (define basis
    (basis-vectors #:id 'basis))
  (define arbitrary-vector
    (vector-arrow vector-end #:id 'vector
                  #:stroke "darkorchid" #:stroke-width 4))
  (define square
    (polygon (list origin
                   (vec2 1 0)
                   (vec2 1 1)
                   (vec2 0 1))
             #:id 'unit-square
             #:fill "gold" #:stroke "goldenrod" #:stroke-width 2))
  (group
   ;; The unit square is diagram background geometry.  Keep the basis and
   ;; arbitrary vector above it, so their shafts and tips remain visible when
   ;; the square is filled or passes through a thin reflection midpoint.
   (append (list plane)
           (if unit-square? (list square) '())
           (list basis arbitrary-vector))
   #:id id))


;;;
;;; Formatting

(define (coordinates->string point)
  (format "(~a, ~a)"
          (number->string (vec2-x point))
          (number->string (vec2-y point))))
