#lang racket/base

;;;
;;; Surface Calculus Geometry
;;;

;; Builds ordinary spatial Visuals from an immutable surface's direct sampled
;; calculus data.  None of these helpers uses a renderer callback or a prior
;; animation frame.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../geometry.rkt"
         "curve3d.rkt"
         "marker3d.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "point-line-arrow3d.rkt"
         "spatial-group.rkt"
         "surface-grid.rkt"
         "stroke3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide surface-point
         surface-tangent-u
         surface-tangent-v
         surface-normal
         surface-tangent-plane
         surface-coordinate-curve
         surface-gradient-arrow
         surface-level-curve)


;;;
;;; Pointwise Geometry
;;;

; surface-point : surface3d? finite-real? finite-real? #:id symbol? ... -> point3d?
;;   Creates a labelled-by-path point at an exact surface parameter position.
(define (surface-point surface u v #:id id
                       #:style [style (point-style3d #:size 10 #:color "gold")])
  (point3d (surface3d-position-at surface u v) #:id id #:style style))

; surface-tangent-u : surface3d? finite-real? finite-real? #:id symbol? ... -> group3d?
;;   Draws an arrow from the surface point in its u tangent direction.
(define (surface-tangent-u surface u v #:id id #:length [length 1]
                           #:shaft-style [shaft-style (stroke3d #:color "tomato")]
                           #:tip-style [tip-style (arrow-style3d #:color "tomato")])
  (tangent-arrow 'surface-tangent-u surface u v id length shaft-style tip-style
                 (surface3d-tangent-u-at surface u v)))

; surface-tangent-v : surface3d? finite-real? finite-real? #:id symbol? ... -> group3d?
;;   Draws an arrow from the surface point in its v tangent direction.
(define (surface-tangent-v surface u v #:id id #:length [length 1]
                           #:shaft-style [shaft-style (stroke3d #:color "forestgreen")]
                           #:tip-style [tip-style (arrow-style3d #:color "forestgreen")])
  (tangent-arrow 'surface-tangent-v surface u v id length shaft-style tip-style
                 (surface3d-tangent-v-at surface u v)))

; surface-normal : surface3d? finite-real? finite-real? #:id symbol? ... -> group3d?
;;   Draws an arrow in the direct u-cross-v normal direction.
(define (surface-normal surface u v #:id id #:length [length 1]
                        #:shaft-style [shaft-style (stroke3d #:color "midnightblue")]
                        #:tip-style [tip-style (arrow-style3d #:color "midnightblue")])
  (tangent-arrow 'surface-normal surface u v id length shaft-style tip-style
                 (surface3d-normal-at surface u v)))

; surface-tangent-plane : surface3d? finite-real? finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a finite double-sided parallelogram spanned by normalized tangents.
(define (surface-tangent-plane surface u v #:id id #:size [size 1]
                               #:color [color "lightsteelblue"])
  (unless (symbol? id) (raise-argument-error 'surface-tangent-plane "symbol?" id))
  (unless (and (finite-real? size) (positive? size))
    (raise-argument-error 'surface-tangent-plane "positive finite size" size))
  (define point (surface3d-position-at surface u v))
  (define u-direction (safe-unit 'surface-tangent-plane (surface3d-tangent-u-at surface u v)))
  (define v-direction (safe-unit 'surface-tangent-plane (surface3d-tangent-v-at surface u v)))
  (define u-offset (vec3-scale size u-direction))
  (define v-offset (vec3-scale size v-direction))
  (mesh3d
   #:id id
   #:vertices (vector (vec3- (vec3- point u-offset) v-offset)
                      (vec3+ (vec3- point v-offset) u-offset)
                      (vec3+ (vec3+ point u-offset) v-offset)
                      (vec3+ (vec3- point u-offset) v-offset))
   #:triangles (vector (vector 0 1 2) (vector 0 2 3))
   #:material (material3d #:color color #:shading 'unlit #:double-sided? #t)
   #:wireframe-color color #:wireframe-width 1))


;;;
;;; Curves and Function-Surface Helpers
;;;

; surface-coordinate-curve : surface3d? [#:u (or/c #f finite-real?)]
;                            [#:v (or/c #f finite-real?)] #:id symbol? ... -> curve3d?
;;   Samples one fixed-u or fixed-v parameter curve at deterministic locations.
(define (surface-coordinate-curve surface
                                  #:u [fixed-u #f]
                                  #:v [fixed-v #f]
                                  #:id id
                                  #:samples [samples 64]
                                  #:style [style (stroke3d #:color "gold" #:width 2)])
  (unless (surface3d? surface)
    (raise-argument-error 'surface-coordinate-curve "surface3d?" surface))
  (unless (not (eq? (not fixed-u) (not fixed-v)))
    (raise-arguments-error 'surface-coordinate-curve
                           "exactly one of #:u or #:v"
                           "u" fixed-u "v" fixed-v))
  (unless (and (exact-integer? samples) (>= samples 2))
    (raise-argument-error 'surface-coordinate-curve "exact integer at least 2" samples))
  (define range (if fixed-u (surface3d-v-range surface) (surface3d-u-range surface)))
  (polyline3d
   (for/list ([index (in-range samples)])
     (define parameter (+ (first range) (* (/ index (sub1 samples))
                                           (- (second range) (first range)))))
     (if fixed-u (surface3d-position-at surface fixed-u parameter)
         (surface3d-position-at surface parameter fixed-v)))
   #:id id #:style style))

; surface-gradient-arrow : surface3d? finite-real? finite-real? #:id symbol? ... -> group3d?
;;   Draws the xy gradient of a declared function surface at one (x,y) point.
(define (surface-gradient-arrow surface x y #:id id #:length [length 1]
                                #:shaft-style [shaft-style (stroke3d #:color "purple")]
                                #:tip-style [tip-style (arrow-style3d #:color "purple")])
  (define function (surface3d-scalar-function surface))
  (unless function
    (raise-arguments-error 'surface-gradient-arrow "a function-surface3d value"
                           "surface" surface))
  (define derivative-x (surface3d-scalar-derivative-x surface))
  (define derivative-y (surface3d-scalar-derivative-y surface))
  (define gradient
    (vec3 (if derivative-x (derivative-x x y)
              (scalar-finite-derivative surface x y 'x))
          (if derivative-y (derivative-y x y)
              (scalar-finite-derivative surface x y 'y))
          0))
  (tangent-arrow 'surface-gradient-arrow surface x y id length shaft-style tip-style gradient))

; surface-level-curve : surface3d? finite-real? #:id symbol? ... -> group3d?
;;   Produces deterministic triangle-wise level-set segments for a function surface.
(define (surface-level-curve surface level #:id id
                             #:style [style (stroke3d #:color "purple" #:width 2)])
  (unless (surface3d? surface) (raise-argument-error 'surface-level-curve "surface3d?" surface))
  (unless (finite-real? level) (raise-argument-error 'surface-level-curve "finite-real?" level))
  (define height (surface3d-scalar-function surface))
  (unless height
    (raise-arguments-error 'surface-level-curve "a function-surface3d value"
                           "surface" surface))
  (define grid (surface3d-grid surface))
  (define segments
    (apply append
           (for*/list ([u-index (in-range (sub1 (surface-grid-u-count grid)))]
                       [v-index (in-range (sub1 (surface-grid-v-count grid)))])
             (define points
               (list (surface-grid-ref grid u-index v-index)
                     (surface-grid-ref grid (add1 u-index) v-index)
                     (surface-grid-ref grid (add1 u-index) (add1 v-index))
                     (surface-grid-ref grid u-index (add1 v-index))))
             (define heights (map vec3-z points))
             (append (triangle-level-segment (list (first points) (second points) (third points))
                                             (list (first heights) (second heights) (third heights)) level)
                     (triangle-level-segment (list (first points) (third points) (fourth points))
                                             (list (first heights) (third heights) (fourth heights)) level)))))
  (group3d
   (for/list ([segment (in-list segments)] [index (in-naturals)])
     (line3d (first segment) (second segment)
             #:id (string->symbol (format "segment~a" index))
             #:style style))
   #:id id))


;;;
;;; Local Helpers
;;;

(define (tangent-arrow who surface u v id length shaft-style tip-style direction)
  (unless (symbol? id) (raise-argument-error who "symbol?" id))
  (unless (and (finite-real? length) (positive? length))
    (raise-argument-error who "positive finite length" length))
  (define unit (safe-unit who direction))
  (define point (surface3d-position-at surface u v))
  (arrow3d point (vec3+ point (vec3-scale length unit))
           #:id id #:shaft-style shaft-style #:tip-style tip-style))

(define (safe-unit who vector)
  (unless (and (vec3? vector) (not (zero? (vec3-length vector))))
    (raise-arguments-error who "a nonzero tangent or normal" "vector" vector))
  (vec3-normalize vector))

(define (scalar-finite-derivative surface x y axis)
  (define range (if (eq? axis 'x) (surface3d-u-range surface) (surface3d-v-range surface)))
  (define count (if (eq? axis 'x) (first (surface3d-resolution surface))
                    (second (surface3d-resolution surface))))
  (define step (/ (- (second range) (first range)) (sub1 count)))
  (define input (if (eq? axis 'x) x y))
  (define low (max (first range) (- input step)))
  (define high (min (second range) (+ input step)))
  (define function (surface3d-scalar-function surface))
  (define low-value (if (eq? axis 'x) (function low y) (function x low)))
  (define high-value (if (eq? axis 'x) (function high y) (function x high)))
  (/ (- high-value low-value) (- high low)))

(define (triangle-level-segment points scalar-values level)
  (define intersections
    (filter values
            (for/list ([first-point (in-list points)]
                       [second-point (in-list (append (cdr points) (list (car points))))]
                       [first-value (in-list scalar-values)]
                       [second-value (in-list (append (cdr scalar-values) (list (car scalar-values))))])
              (and (< (* (- first-value level) (- second-value level)) 0)
                   (vec3-lerp first-point second-point
                              (/ (- level first-value) (- second-value first-value)))))))
  (if (= (length intersections) 2) (list intersections) '()))
