#lang racket/base

;;;
;;; Point-Marker Visuals
;;;

;; Defines immutable semantic point markers with a small closed set of marker
;; shapes. Rendering remains in the Pict adapter through conversion to existing
;; circle, rectangle, and path Visuals.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide point-marker-shape?
         point-marker
         point-marker-visual?
         point-marker-visual-shape
         point-marker-visual-size
         point-marker-visual-fill
         point-marker-visual-stroke
         point-marker-visual-stroke-width
         point-marker-visual->visual)


;;;
;;; Marker Shapes
;;;

; point-marker-shape? : any/c -> boolean?
;;   Reports whether value names one of the supported point-marker shapes.
(define (point-marker-shape? value)
  (and (symbol? value)
       (memq value
             '(circle square diamond triangle-up triangle-down))
       #t))


;;;
;;; Data Representation
;;;

(struct point-marker-visual
  (identifier transform opacity shape size fill stroke stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (point-marker-visual-identifier visual))

   (define (visual-position visual)
     (affine-transform-translation
      (point-marker-visual-transform visual)))

   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error
        'visual-with-position
        "vec2?"
        position))
     (struct-copy
      point-marker-visual
      visual
      [transform
       (affine-transform-with-translation
        (point-marker-visual-transform visual)
        position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (point-marker-visual-transform visual))

   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy point-marker-visual visual
                  [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (point-marker-visual-opacity visual))

   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "opacity?"
        opacity))
     (struct-copy point-marker-visual visual
                  [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width visual)
     (point-marker-visual-stroke-width visual))

   (define (visual-with-stroke-width visual stroke-width)
     (unless (stroke-width? stroke-width)
       (raise-argument-error
        'visual-with-stroke-width
        "stroke-width?"
        stroke-width))
     (struct-copy point-marker-visual visual
                  [stroke-width stroke-width]))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color visual)
     (point-marker-visual-fill visual))
   (define (visual-with-fill-color visual color)
     (unless (color-spec? color)
       (raise-argument-error 'visual-with-fill-color "color-spec?" color))
     (struct-copy point-marker-visual visual [fill color]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color visual)
     (point-marker-visual-stroke visual))
   (define (visual-with-stroke-color visual color)
     (unless (color-spec? color)
       (raise-argument-error 'visual-with-stroke-color "color-spec?" color))
     (struct-copy point-marker-visual visual [stroke color]))])

;; point-marker-visual represents one semantic point marker.
;;  - identifier    symbol?                    stable Visual identity.
;;  - transform     affine-transform?          placement and local deformation.
;;  - opacity       opacity?                   global semantic opacity.
;;  - shape         point-marker-shape?         closed marker shape.
;;  - size          positive finite real?      full local marker extent.
;;  - fill          any/c                      adapter-specific fill style.
;;  - stroke        any/c                      adapter-specific stroke style.
;;  - stroke-width  nonnegative finite real?   cosmetic stroke width.
;;
;; The circle diameter, square side, diamond width and height, and triangle
;; width and height are all equal to size before affine scale is applied.


;;;
;;; Construction
;;;

; point-marker : #:id symbol?
;                [#:center vec2?]
;                [#:rotation finite-real?]
;                [#:scale scale-factor?]
;                [#:opacity opacity?]
;                [#:shape point-marker-shape?]
;                [#:size positive-finite-real?]
;                [#:fill any/c]
;                [#:stroke any/c]
;                [#:stroke-width nonnegative-finite-real?]
;                -> point-marker-visual?
;;   Constructs one semantic point marker with explicit identity.
(define (point-marker #:id identifier
                      #:center [center origin]
                      #:rotation [rotation 0]
                      #:scale [scale-factor 1]
                      #:opacity [opacity 1]
                      #:shape [shape 'circle]
                      #:size [size 1/5]
                      #:fill [fill "royalblue"]
                      #:stroke [stroke "black"]
                      #:stroke-width [stroke-width 1])
  (unless (symbol? identifier)
    (raise-argument-error 'point-marker "symbol?" identifier))
  (unless (vec2? center)
    (raise-argument-error 'point-marker "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'point-marker "finite-real?" rotation))
  (unless (scale-factor? scale-factor)
    (raise-argument-error 'point-marker "scale-factor?" scale-factor))
  (unless (opacity? opacity)
    (raise-argument-error 'point-marker "opacity?" opacity))
  (unless (point-marker-shape? shape)
    (raise-argument-error
     'point-marker
     "point-marker-shape?"
     shape))
  (unless (and (finite-real? size)
               (positive? size))
    (raise-argument-error
     'point-marker
     "positive finite real?"
     size))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error
     'point-marker
     "nonnegative finite real?"
     stroke-width))
  (point-marker-visual
   identifier
   (make-affine-transform #:translation center
                          #:rotation rotation
                          #:scale scale-factor)
   opacity
   shape
   size
   fill
   stroke
   stroke-width))


;;;
;;; Semantic Primitive Conversion
;;;

; point-marker-visual->visual : point-marker-visual? -> affine-visual?
;;   Converts a marker to an existing primitive for default Pict rendering.
(define (point-marker-visual->visual visual)
  (unless (point-marker-visual? visual)
    (raise-argument-error
     'point-marker-visual->visual
     "point-marker-visual?"
     visual))
  (case (point-marker-visual-shape visual)
    [(circle)
     (point-marker->circle visual)]
    [(square)
     (point-marker->square visual)]
    [(diamond triangle-up triangle-down)
     (point-marker->path visual)]
    [else
     (raise-argument-error
      'point-marker-visual->visual
      "point-marker-shape?"
      (point-marker-visual-shape visual))]))

; point-marker->circle : point-marker-visual? -> circle-visual?
;;   Converts a circular marker to an equivalent circle Visual.
(define (point-marker->circle visual)
  (circle #:id (visual-id visual)
          #:center (visual-position visual)
          #:rotation (visual-rotation visual)
          #:scale (visual-scale visual)
          #:opacity 1
          #:radius (/ (point-marker-visual-size visual) 2)
          #:fill (point-marker-visual-fill visual)
          #:stroke (point-marker-visual-stroke visual)
          #:stroke-width
          (point-marker-visual-stroke-width visual)))

; point-marker->square : point-marker-visual? -> rectangle-visual?
;;   Converts a square marker to an equivalent rectangle Visual.
(define (point-marker->square visual)
  (define size
    (point-marker-visual-size visual))
  (rectangle #:id (visual-id visual)
             #:center (visual-position visual)
             #:rotation (visual-rotation visual)
             #:scale (visual-scale visual)
             #:opacity 1
             #:width size
             #:height size
             #:fill (point-marker-visual-fill visual)
             #:stroke (point-marker-visual-stroke visual)
             #:stroke-width
             (point-marker-visual-stroke-width visual)))

; point-marker->path : point-marker-visual? -> path-visual?
;;   Converts a polygonal marker to an equivalent path Visual.
(define (point-marker->path visual)
  (make-path-visual
   (polygon-path
    (point-marker-local-points
     (point-marker-visual-shape visual)
     (point-marker-visual-size visual)))
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity 1
   #:fill (point-marker-visual-fill visual)
   #:stroke (point-marker-visual-stroke visual)
   #:stroke-width
   (point-marker-visual-stroke-width visual)))

; point-marker-local-points : point-marker-shape? positive-real?
;                             -> (listof vec2?)
;;   Returns polygon vertices in significant traversal order.
(define (point-marker-local-points shape size)
  (define half-size
    (/ size 2))
  (case shape
    [(diamond)
     (list (vec2 0 half-size)
           (vec2 half-size 0)
           (vec2 0 (- half-size))
           (vec2 (- half-size) 0))]
    [(triangle-up)
     (list (vec2 0 half-size)
           (vec2 (- half-size) (- half-size))
           (vec2 half-size (- half-size)))]
    [(triangle-down)
     (list (vec2 0 (- half-size))
           (vec2 half-size half-size)
           (vec2 (- half-size) half-size))]
    [else
     (raise-argument-error
      'point-marker-local-points
      "polygonal point-marker shape"
      shape)]))
