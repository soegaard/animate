#lang racket/base

;;;
;;; Spatial Points, Lines, and Arrows
;;;

;; Provides the elementary finite geometry used by diagrams. Mathematical
;; points, shafts, and arrowheads are semantic screen-space primitives by
;; default; use explicit mesh or tube constructors for physical 3D solids.


;;;
;;; Imports and Exports
;;;

(require "../geometry.rkt"
         "marker3d.rkt"
         "spatial-group.rkt"
         "transform3.rkt"
         "curve3d.rkt"
         "stroke3d.rkt"
         "vec3.rkt")

(provide point3d
         line3d
         segment3d
         arrow3d
         double-arrow3d)


;;;
;;; Points and Segments
;;;

; point3d : vec3? #:id symbol? [#:style point-style3d?] ... -> point-marker3d?
;;   Creates a screen-sized point marker centred at position.
(define (point3d position
                 #:id id
                 #:style [style (point-style3d)]
                 #:transform [transform identity-transform3]
                 #:opacity [opacity 1])
  (point-marker3d position #:id id #:style style
                  #:transform transform #:opacity opacity))

; line3d : vec3? vec3? #:id symbol? ... -> curve3d?
;;   Creates a finite straight spatial line segment.  It is named `line3d` to
;; match diagram vocabulary; an infinite Euclidean line has no finite render.
(define (line3d from to
                #:id id
                #:style [style (stroke3d)]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1])
  (check-distinct-endpoints 'line3d from to)
  (polyline3d (list from to) #:id id #:style style
              #:transform transform #:opacity opacity))

; segment3d : vec3? vec3? #:id symbol? ... -> curve3d?
;;   Alias for `line3d`, provided when an endpoint-bounded segment is clearer.
(define segment3d line3d)


;;;
;;; Arrow Geometry
;;;

; arrow3d : vec3? vec3? #:id symbol? ... -> group3d?
;;   Creates a shaft and one screen-sized tip, both with fixed descendant paths
;;   `shaft` and `tip` below the supplied arrow identity.
(define (arrow3d from to
                 #:id id
                 #:shaft-style [shaft-style (stroke3d #:color "tomato")]
                 #:tip-style [tip-style (arrow-style3d #:color "tomato")]
                 #:transform [transform identity-transform3]
                 #:opacity [opacity 1])
  (check-arrow-arguments 'arrow3d from to id shaft-style tip-style)
  (group3d
   (list (line3d from to #:id 'shaft #:style shaft-style)
         (arrow-marker3d from to #:id 'tip #:style tip-style))
   #:id id #:transform transform #:opacity opacity))

; double-arrow3d : vec3? vec3? #:id symbol? ... -> group3d?
;;   Creates a shaft and one conical tip at each endpoint.
(define (double-arrow3d from to
                        #:id id
                        #:shaft-style [shaft-style (stroke3d #:color "tomato")]
                        #:tip-style [tip-style (arrow-style3d #:color "tomato")]
                        #:transform [transform identity-transform3]
                        #:opacity [opacity 1])
  (check-arrow-arguments 'double-arrow3d from to id shaft-style tip-style)
  (group3d
   (list (line3d from to #:id 'shaft #:style shaft-style)
         (arrow-marker3d to from #:id 'start-tip #:style tip-style)
         (arrow-marker3d from to #:id 'end-tip #:style tip-style))
   #:id id #:transform transform #:opacity opacity))


;;;
;;; Local Helpers
;;;

(define (check-distinct-endpoints who from to)
  (unless (vec3? from) (raise-argument-error who "vec3?" from))
  (unless (vec3? to) (raise-argument-error who "vec3?" to))
  (when (zero? (vec3-distance from to))
    (raise-arguments-error who "distinct endpoint positions" "from" from "to" to)))

(define (check-arrow-arguments who from to id shaft-style tip-style)
  (check-distinct-endpoints who from to)
  (unless (symbol? id) (raise-argument-error who "symbol?" id))
  (unless (stroke3d? shaft-style)
    (raise-argument-error who "stroke3d? as #:shaft-style" shaft-style))
  (unless (arrow-style3d? tip-style)
    (raise-argument-error who "arrow-style3d? as #:tip-style" tip-style)))
