#lang racket/base

;;;
;;; Screen and World Marker Semantics
;;;

;; Marker values are camera-independent author values.  Screen sizing is
;; resolved only while preparing a frame, never by inflating a marker into a
;; world-space mesh.  This gives points and arrowheads the same legibility as
;; mathematical pen strokes during an orbit or dolly.

(require "../color-style.rkt"
         "../geometry.rkt"
         "bounds3.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide point-style3d
         point-style3d?
         point-style3d-size
         point-style3d-size-mode
         point-style3d-color
         point-style3d-opacity
         point-style3d-depth-mode
         point-style3d-depth-bias
         point-style3d-with-color
         point-style3d-with-opacity
         arrow-style3d
         arrow-style3d?
         arrow-style3d-length
         arrow-style3d-length-mode
         arrow-style3d-width
         arrow-style3d-color
         arrow-style3d-opacity
         arrow-style3d-depth-mode
         arrow-style3d-depth-bias
         arrow-style3d-with-color
         arrow-style3d-with-opacity
         point-marker3d
         point-marker3d?
         point-marker3d-position
         point-marker3d-style
         arrow-marker3d
         arrow-marker3d?
         arrow-marker3d-from
         arrow-marker3d-to
         arrow-marker3d-style)

(struct point-style3d-value (size size-mode color opacity depth-mode depth-bias)
  #:transparent)

(define point-style3d? point-style3d-value?)
(define point-style3d-size point-style3d-value-size)
(define point-style3d-size-mode point-style3d-value-size-mode)
(define point-style3d-color point-style3d-value-color)
(define point-style3d-opacity point-style3d-value-opacity)
(define point-style3d-depth-mode point-style3d-value-depth-mode)
(define point-style3d-depth-bias point-style3d-value-depth-bias)

(define (point-style3d #:size [size 8]
                       #:size-mode [size-mode 'screen]
                       #:color [color "cornflowerblue"]
                       #:opacity [opacity 1]
                       #:depth-mode [depth-mode 'test]
                       #:depth-bias [depth-bias 1e-5])
  (check-style-arguments 'point-style3d size size-mode color opacity depth-mode depth-bias)
  (point-style3d-value size size-mode color opacity depth-mode depth-bias))

(define (point-style3d-with-color style color)
  (unless (point-style3d? style)
    (raise-argument-error 'point-style3d-with-color "point-style3d?" style))
  (unless (color-spec? color)
    (raise-argument-error 'point-style3d-with-color "color-spec?" color))
  (struct-copy point-style3d-value style [color color]))

(define (point-style3d-with-opacity style opacity)
  (unless (point-style3d? style)
    (raise-argument-error 'point-style3d-with-opacity "point-style3d?" style))
  (check-opacity 'point-style3d-with-opacity opacity)
  (struct-copy point-style3d-value style [opacity opacity]))

(struct arrow-style3d-value (length length-mode width color opacity depth-mode depth-bias)
  #:transparent)

(define arrow-style3d? arrow-style3d-value?)
(define arrow-style3d-length arrow-style3d-value-length)
(define arrow-style3d-length-mode arrow-style3d-value-length-mode)
(define arrow-style3d-width arrow-style3d-value-width)
(define arrow-style3d-color arrow-style3d-value-color)
(define arrow-style3d-opacity arrow-style3d-value-opacity)
(define arrow-style3d-depth-mode arrow-style3d-value-depth-mode)
(define arrow-style3d-depth-bias arrow-style3d-value-depth-bias)

(define (arrow-style3d #:length [length 12]
                       #:length-mode [length-mode 'screen]
                       #:width [width #f]
                       #:color [color "tomato"]
                       #:opacity [opacity 1]
                       #:depth-mode [depth-mode 'test]
                       #:depth-bias [depth-bias 1e-5])
  (check-style-arguments 'arrow-style3d length length-mode color opacity depth-mode depth-bias)
  (define resolved-width (or width (/ length 3/2)))
  (unless (and (finite-real? resolved-width) (positive? resolved-width))
    (raise-argument-error 'arrow-style3d "positive finite arrowhead width" resolved-width))
  (arrow-style3d-value length length-mode resolved-width color opacity depth-mode depth-bias))

(define (arrow-style3d-with-color style color)
  (unless (arrow-style3d? style)
    (raise-argument-error 'arrow-style3d-with-color "arrow-style3d?" style))
  (unless (color-spec? color)
    (raise-argument-error 'arrow-style3d-with-color "color-spec?" color))
  (struct-copy arrow-style3d-value style [color color]))

(define (arrow-style3d-with-opacity style opacity)
  (unless (arrow-style3d? style)
    (raise-argument-error 'arrow-style3d-with-opacity "arrow-style3d?" style))
  (check-opacity 'arrow-style3d-with-opacity opacity)
  (struct-copy arrow-style3d-value style [opacity opacity]))

(struct point-marker3d-value (id transform opacity position style local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id value) (point-marker3d-value-id value))
   (define (spatial-transform value) (point-marker3d-value-transform value))
   (define (spatial-with-transform value transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy point-marker3d-value value [transform transform]))
   (define (spatial-opacity value) (point-marker3d-value-opacity value))
   (define (spatial-with-opacity value opacity)
     (check-opacity 'spatial-with-opacity opacity)
     (struct-copy point-marker3d-value value [opacity opacity]))
   (define (spatial-local-bounds value) (point-marker3d-value-local-bounds value))])

(define point-marker3d? point-marker3d-value?)
(define point-marker3d-position point-marker3d-value-position)
(define point-marker3d-style point-marker3d-value-style)

(define (point-marker3d position #:id id #:style [style (point-style3d)]
                        #:transform [transform identity-transform3]
                        #:opacity [opacity 1])
  (unless (vec3? position) (raise-argument-error 'point-marker3d "vec3?" position))
  (unless (symbol? id) (raise-argument-error 'point-marker3d "symbol?" id))
  (unless (point-style3d? style)
    (raise-argument-error 'point-marker3d "point-style3d?" style))
  (unless (transform3? transform)
    (raise-argument-error 'point-marker3d "transform3?" transform))
  (check-opacity 'point-marker3d opacity)
  ;; A screen marker has no physical extent. A one-point AABB is deliberate:
  ;; it gives transforms and relations a truthful world anchor without making
  ;; a camera-dependent authoring bound.
  (point-marker3d-value id transform opacity position style
                        (aabb3-from-points (list position))))

(struct arrow-marker3d-value (id transform opacity from to style local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id value) (arrow-marker3d-value-id value))
   (define (spatial-transform value) (arrow-marker3d-value-transform value))
   (define (spatial-with-transform value transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy arrow-marker3d-value value [transform transform]))
   (define (spatial-opacity value) (arrow-marker3d-value-opacity value))
   (define (spatial-with-opacity value opacity)
     (check-opacity 'spatial-with-opacity opacity)
     (struct-copy arrow-marker3d-value value [opacity opacity]))
   (define (spatial-local-bounds value) (arrow-marker3d-value-local-bounds value))])

(define arrow-marker3d? arrow-marker3d-value?)
(define arrow-marker3d-from arrow-marker3d-value-from)
(define arrow-marker3d-to arrow-marker3d-value-to)
(define arrow-marker3d-style arrow-marker3d-value-style)

(define (arrow-marker3d from to #:id id #:style [style (arrow-style3d)]
                        #:transform [transform identity-transform3]
                        #:opacity [opacity 1])
  (unless (vec3? from) (raise-argument-error 'arrow-marker3d "vec3?" from))
  (unless (vec3? to) (raise-argument-error 'arrow-marker3d "vec3?" to))
  (when (zero? (vec3-distance from to))
    (raise-arguments-error 'arrow-marker3d "distinct endpoint positions"
                           "from" from "to" to))
  (unless (symbol? id) (raise-argument-error 'arrow-marker3d "symbol?" id))
  (unless (arrow-style3d? style)
    (raise-argument-error 'arrow-marker3d "arrow-style3d?" style))
  (unless (transform3? transform)
    (raise-argument-error 'arrow-marker3d "transform3?" transform))
  (check-opacity 'arrow-marker3d opacity)
  (arrow-marker3d-value id transform opacity from to style
                        (aabb3-from-points (list from to))))

(define (check-style-arguments who size mode color opacity depth-mode depth-bias)
  (unless (and (finite-real? size) (positive? size))
    (raise-argument-error who "positive finite size" size))
  (unless (memq mode '(screen world))
    (raise-argument-error who "one of 'screen or 'world" mode))
  (unless (color-spec? color)
    (raise-argument-error who "color-spec?" color))
  (check-opacity who opacity)
  (unless (memq depth-mode '(test always hidden))
    (raise-argument-error who "one of 'test, 'always, or 'hidden" depth-mode))
  (unless (and (finite-real? depth-bias) (>= depth-bias 0))
    (raise-argument-error who "nonnegative finite depth bias" depth-bias)))

(define (check-opacity who opacity)
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error who "finite real in [0, 1] as opacity" opacity)))
