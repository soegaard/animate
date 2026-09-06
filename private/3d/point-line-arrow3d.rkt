#lang racket/base

;;;
;;; Spatial Points, Lines, and Arrows
;;;

;; Provides the elementary finite geometry used by diagrams.  Every width is a
;; physical radius in world coordinates, so a changing camera retains the
;; expected perspective behaviour.


;;;
;;; Imports and Exports
;;;

(require (only-in racket/math pi)
         "../geometry.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "rotation3.rkt"
         "spatial-group.rkt"
         "transform3.rkt"
         "curve3d.rkt"
         "vec3.rkt")

(provide point3d
         line3d
         segment3d
         arrow3d
         double-arrow3d)


;;;
;;; Points and Segments
;;;

; point3d : vec3? #:id symbol? [#:radius positive-finite-real?] ... -> mesh3d?
;;   Creates an octahedral spatial point centred at position.
(define (point3d position
                 #:id id
                 #:radius [radius 1/10]
                 #:color [color "cornflowerblue"]
                 #:transform [transform identity-transform3]
                 #:opacity [opacity 1])
  (unless (vec3? position) (raise-argument-error 'point3d "vec3?" position))
  (unless (symbol? id) (raise-argument-error 'point3d "symbol?" id))
  (unless (and (finite-real? radius) (positive? radius))
    (raise-argument-error 'point3d "positive finite radius" radius))
  (define point-transform
    (make-transform3
     #:translation (vec3+ position (transform3-translation transform))
     #:rotation (transform3-rotation transform)
     #:scale (transform3-scale transform)))
  (mesh3d
   #:id id
   #:vertices (vector (vec3 radius 0 0) (vec3 (- radius) 0 0)
                      (vec3 0 radius 0) (vec3 0 (- radius) 0)
                      (vec3 0 0 radius) (vec3 0 0 (- radius)))
   #:triangles (vector (vector 0 2 4) (vector 2 1 4)
                      (vector 1 3 4) (vector 3 0 4)
                      (vector 2 0 5) (vector 1 2 5)
                      (vector 3 1 5) (vector 0 3 5))
   #:material (material3d #:color color #:shading 'flat #:double-sided? #t)
   #:transform point-transform #:opacity opacity
   #:wireframe-color color #:wireframe-width 2))

; line3d : vec3? vec3? #:id symbol? ... -> curve3d?
;;   Creates a finite straight spatial line segment.  It is named `line3d` to
;; match diagram vocabulary; an infinite Euclidean line has no finite render.
(define (line3d from to
                #:id id
                #:radius [radius 1/20]
                #:sides [sides 8]
                #:color [color "steelblue"]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1]
                #:width-mode [width-mode 'world])
  (check-distinct-endpoints 'line3d from to)
  (polyline3d (list from to) #:id id #:radius radius #:sides sides #:color color
              #:transform transform #:opacity opacity #:width-mode width-mode))

; segment3d : vec3? vec3? #:id symbol? ... -> curve3d?
;;   Alias for `line3d`, provided when an endpoint-bounded segment is clearer.
(define segment3d line3d)


;;;
;;; Arrow Geometry
;;;

; arrow3d : vec3? vec3? #:id symbol? ... -> group3d?
;;   Creates a shaft and one conical tip, both with fixed descendant paths
;;   `shaft` and `tip` below the supplied arrow identity.
(define (arrow3d from to
                 #:id id
                 #:radius [radius 1/20]
                 #:tip-length [tip-length (* 5 radius)]
                 #:tip-radius [tip-radius (* 2 radius)]
                 #:sides [sides 8]
                 #:color [color "tomato"]
                 #:transform [transform identity-transform3]
                 #:opacity [opacity 1]
                 #:width-mode [width-mode 'world])
  (check-arrow-arguments 'arrow3d from to id radius tip-length tip-radius sides width-mode)
  (define direction (vec3-normalize (vec3- to from)))
  (define length (vec3-distance from to))
  (when (>= tip-length length)
    (raise-arguments-error 'arrow3d "a tip shorter than the arrow"
                           "tip-length" tip-length "arrow-length" length))
  (define base (vec3- to (vec3-scale tip-length direction)))
  (group3d
   (list (line3d from base #:id 'shaft #:radius radius #:sides sides #:color color
                 #:width-mode width-mode)
         (cone3d 'tip base direction tip-length tip-radius sides color))
   #:id id #:transform transform #:opacity opacity))

; double-arrow3d : vec3? vec3? #:id symbol? ... -> group3d?
;;   Creates a shaft and one conical tip at each endpoint.
(define (double-arrow3d from to
                        #:id id
                        #:radius [radius 1/20]
                        #:tip-length [tip-length (* 5 radius)]
                        #:tip-radius [tip-radius (* 2 radius)]
                        #:sides [sides 8]
                        #:color [color "tomato"]
                        #:transform [transform identity-transform3]
                        #:opacity [opacity 1]
                        #:width-mode [width-mode 'world])
  (check-arrow-arguments 'double-arrow3d from to id radius tip-length tip-radius sides width-mode)
  (define direction (vec3-normalize (vec3- to from)))
  (define length (vec3-distance from to))
  (when (>= (* 2 tip-length) length)
    (raise-arguments-error 'double-arrow3d "two tips shorter than the arrow"
                           "tip-length" tip-length "arrow-length" length))
  (define shaft-start (vec3+ from (vec3-scale tip-length direction)))
  (define shaft-end (vec3- to (vec3-scale tip-length direction)))
  (group3d
   (list (line3d shaft-start shaft-end #:id 'shaft #:radius radius #:sides sides
                 #:color color #:width-mode width-mode)
         (cone3d 'start-tip shaft-start (vec3-scale -1 direction)
                 tip-length tip-radius sides color)
         (cone3d 'end-tip shaft-end direction tip-length tip-radius sides color))
   #:id id #:transform transform #:opacity opacity))


;;;
;;; Local Helpers
;;;

(define (cone3d id base direction length radius sides color)
  (define rotation (rotation3-from-to z-axis3 direction))
  (define vertices
    (list->vector
     (append
      (for/list ([side (in-range sides)])
        (define angle (* 2 pi (/ side sides)))
        (vec3 (* radius (cos angle)) (* radius (sin angle)) 0))
      (list (vec3 0 0 length) origin3))))
  (define tip-index sides)
  (define centre-index (add1 sides))
  (mesh3d
   #:id id #:vertices vertices
   #:triangles
   (list->vector
    (append
     (for/list ([side (in-range sides)])
       (vector side (modulo (add1 side) sides) tip-index))
     (for/list ([side (in-range sides)])
       (vector centre-index (modulo (add1 side) sides) side))))
   #:edges
   (list->vector
    (append
     (for/list ([side (in-range sides)])
       (vector side (modulo (add1 side) sides)))
     (for/list ([side (in-range sides)]) (vector side tip-index))))
   #:material (material3d #:color color #:shading 'flat #:double-sided? #t)
   #:transform (make-transform3 #:translation base #:rotation rotation)
   #:wireframe-color color #:wireframe-width 2))

(define (check-distinct-endpoints who from to)
  (unless (vec3? from) (raise-argument-error who "vec3?" from))
  (unless (vec3? to) (raise-argument-error who "vec3?" to))
  (when (zero? (vec3-distance from to))
    (raise-arguments-error who "distinct endpoint positions" "from" from "to" to)))

(define (check-arrow-arguments who from to id radius tip-length tip-radius sides width-mode)
  (check-distinct-endpoints who from to)
  (unless (symbol? id) (raise-argument-error who "symbol?" id))
  (for ([value (in-list (list radius tip-length tip-radius))])
    (unless (and (finite-real? value) (positive? value))
      (raise-argument-error who "positive finite arrow dimensions" value)))
  (unless (and (exact-integer? sides) (>= sides 3))
    (raise-argument-error who "exact integer at least 3" sides))
  (unless (eq? width-mode 'world)
    (raise-arguments-error who
                           "a physical `world` width; screen widths are deferred"
                           "width-mode" width-mode)))
