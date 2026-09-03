#lang racket/base

;;;
;;; Pointwise World-Space Maps
;;;

;; Turns geometric leaves of an ordinary Visual tree into sampled paths in
;; world coordinates, then applies a point map to every sample. Sampling before
;; mapping is intentional: mapping only Bézier control points would leave a
;; straight grid line straight under, for example, z -> z^2.

(require racket/list
         "affine-transform.rkt"
         "arrow-visual.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide pointwise-map-visual)

;; pointwise-map-visual : visual? (-> vec2? vec2?) finite-real?
;;                        [#:samples exact-positive-integer?] -> visual?
;; Produces an ordinary world-coordinate Visual tree. Path, circle, and
;; rectangle leaves are sampled and point-mapped; other affine leaves remain
;; legible and retain their original world placement. Progress is an explicit
;; straight-line blend between each source point and its mapped point.
(define (pointwise-map-visual visual map-point progress
                              #:samples [samples 24])
  (unless (visual? visual)
    (raise-argument-error 'pointwise-map-visual "visual?" visual))
  (check-point-map 'pointwise-map-visual map-point)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'pointwise-map-visual
                          "finite real in the closed interval [0, 1]"
                          progress))
  (unless (and (exact-integer? samples) (positive? samples))
    (raise-argument-error 'pointwise-map-visual "positive exact integer" samples))
  (map-visual-tree visual map-point progress samples identity-affine-transform 1))

(define (map-visual-tree visual map-point progress samples parent-transform
                         parent-opacity)
  (unless (affine-visual? visual)
    (raise-arguments-error 'apply-pointwise "an affine Visual tree" "visual" visual))
  (define world-transform
    (compose-world-transform parent-transform (visual-transform visual)))
  (define world-opacity
    (if (opacity-visual? visual)
        (* parent-opacity (visual-opacity visual))
        parent-opacity))
  (cond
    [(group-visual? visual)
     ;; Preserve hierarchy and identities, while folding placement into leaves.
     ;; This keeps visual paths addressable after a world-space map.
     (group
      (for/list ([child (in-list (group-visual-children visual))])
        (map-visual-tree child map-point progress samples
                         world-transform world-opacity))
      #:id (visual-id visual))]
    [(path-visual? visual)
     (mapped-path-leaf visual (path-visual-path visual)
                       map-point progress samples world-transform world-opacity)]
    [(axes-visual? visual)
     (mapped-styled-path-leaf
      (visual-id visual)
      (axes-visual-path-geometry visual)
      #f (axes-visual-stroke visual) (axes-visual-stroke-width visual)
      map-point progress samples world-transform world-opacity)]
    [(arrow-visual? visual)
     (mapped-styled-path-leaf
      (visual-id visual)
      (arrow-visual-path-geometry visual)
      #f (arrow-visual-stroke visual) (arrow-visual-stroke-width visual)
      map-point progress samples world-transform world-opacity)]
    [(circle-visual? visual)
     (mapped-path-leaf visual (circle-path (circle-visual-radius visual))
                       map-point progress samples world-transform world-opacity)]
    [(rectangle-visual? visual)
     (mapped-path-leaf visual
                       (rectangle-path (rectangle-visual-width visual)
                                       (rectangle-visual-height visual))
                       map-point progress samples world-transform world-opacity)]
    [else
     ;; Text, images, and custom affine leaves have no exposed vector outline.
     ;; Keep them legible at their original world placement instead of silently
     ;; dropping them or pretending they were geometrically deformed.
     (world-place-visual visual world-transform world-opacity)]))

(define (world-place-visual visual transform opacity)
  (define transformed (visual-with-transform visual transform))
  (if (opacity-visual? transformed)
      (visual-with-opacity transformed opacity)
      transformed))

(define (mapped-path-leaf visual geometry map-point progress samples
                          world-transform world-opacity)
  (mapped-styled-path-leaf
   (visual-id visual) geometry
   (visual-fill-color visual) (visual-stroke-color visual)
   (visual-stroke-width visual)
   map-point progress samples world-transform world-opacity))

(define (mapped-styled-path-leaf id geometry fill stroke stroke-width
                                 map-point progress samples
                                 world-transform world-opacity)
  (define world-geometry
    (path-geometry-map-points
     geometry
     (lambda (point)
       (affine-transform-apply-point world-transform point))))
  (define sampled-geometry
    (sample-path-geometry world-geometry samples))
  (define blended-geometry
    (path-geometry-map-points
     sampled-geometry
     (lambda (point)
       (vec2-lerp point
                  (checked-map-result 'apply-pointwise map-point point)
                  progress))))
  (make-path-visual blended-geometry
                    #:id id
                    #:opacity world-opacity
                    #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; Combines transforms where `local` is expressed in `parent` coordinates.
(define (compose-world-transform parent local)
  (make-affine-transform
   #:translation
   (affine-transform-apply-point parent (affine-transform-translation local))
   #:rotation
   (+ (affine-transform-rotation parent) (affine-transform-rotation local))
   #:scale
   (vec2* (affine-transform-scale parent) (affine-transform-scale local))))

;; Converts every original segment to `samples` straight pieces. It preserves
;; separate subpaths and closure, which keeps fills and holes meaningful.
(define (sample-path-geometry geometry samples)
  (path-geometry
   (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
     (sample-subpath subpath samples))))

(define (sample-subpath subpath samples)
  (define start (path-subpath-start subpath))
  (define-values (points ignored-final)
    (for/fold ([collected (list start)] [segment-start start])
              ([segment (in-list (path-subpath-segments subpath))])
      (define end (path-segment-end segment))
      (values
       (append collected
               (for/list ([index (in-range 1 (add1 samples))])
                 (path-segment-point segment segment-start (/ index samples))))
       end)))
  ;; A closed path can contain an explicit final return to its start. The
  ;; `closed?` flag already supplies that edge, so omit the duplicate endpoint.
  (define normalized-points
    (if (and (path-subpath-closed? subpath)
             (pair? (cdr points))
             (vec2=? (last points) start))
        (drop-right points 1)
        points))
  (path-subpath
   (car normalized-points)
   (for/list ([point (in-list (cdr normalized-points))])
     (line-path-segment point))
   (path-subpath-closed? subpath)))

(define (path-segment-end segment)
  (cond
    [(line-path-segment? segment) (line-path-segment-end segment)]
    [(cubic-bezier-path-segment? segment) (cubic-bezier-path-segment-end segment)]
    [else (raise-argument-error 'sample-path-geometry "path segment" segment)]))

(define (path-segment-point segment start t)
  (cond
    [(line-path-segment? segment)
     (vec2-lerp start (line-path-segment-end segment) t)]
    [(cubic-bezier-path-segment? segment)
     (define one-minus-t (- 1 t))
     (define control1 (cubic-bezier-path-segment-control1 segment))
     (define control2 (cubic-bezier-path-segment-control2 segment))
     (define end (cubic-bezier-path-segment-end segment))
     (vec2+
      (vec2+
       (vec2-scale (* one-minus-t one-minus-t one-minus-t) start)
       (vec2-scale (* 3 one-minus-t one-minus-t t) control1))
      (vec2+
       (vec2-scale (* 3 one-minus-t t t) control2)
       (vec2-scale (* t t t) end)))]
    [else (raise-argument-error 'sample-path-geometry "path segment" segment)]))

;; Four cubic arcs, converted to straight samples immediately before mapping.
(define (circle-path radius)
  (define k (* radius 0.5522847498307936))
  (path-geometry
   (list
    (path-subpath
     (vec2 radius 0)
     (list
      (cubic-bezier-path-segment (vec2 radius k) (vec2 k radius) (vec2 0 radius))
      (cubic-bezier-path-segment (vec2 (- k) radius) (vec2 (- radius) k)
                                 (vec2 (- radius) 0))
      (cubic-bezier-path-segment (vec2 (- radius) (- k)) (vec2 (- k) (- radius))
                                 (vec2 0 (- radius)))
      (cubic-bezier-path-segment (vec2 k (- radius)) (vec2 radius (- k))
                                 (vec2 radius 0)))
     #t))))

(define (rectangle-path width height)
  (define half-width (/ width 2))
  (define half-height (/ height 2))
  (polygon-path
   (list (vec2 (- half-width) (- half-height))
         (vec2 half-width (- half-height))
         (vec2 half-width half-height)
         (vec2 (- half-width) half-height))))

(define (check-point-map who map-point)
  (unless (and (procedure? map-point) (procedure-arity-includes? map-point 1))
    (raise-argument-error who "(procedure-arity-includes/c 1)" map-point)))

(define (checked-map-result who map-point point)
  (define result (map-point point))
  (unless (vec2? result)
    (raise-arguments-error who "the point map must return a vec2"
                           "point" point "result" result))
  result)

(define (vec2=? left right)
  (and (= (vec2-x left) (vec2-x right))
       (= (vec2-y left) (vec2-y right))))
