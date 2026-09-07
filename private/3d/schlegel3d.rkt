#lang racket/base

(require racket/list
         "mesh3d.rkt" "mesh-topology3d.rkt" "plane-basis3d.rkt" "polyhedral-complex3d.rkt"
         "ray-plane.rkt" "spatial-group.rkt" "point-line-arrow3d.rkt" "stroke3d.rkt"
         "vec3.rkt")

(provide (struct-out schlegel-diagram3d-data)
         prepare-schlegel-diagram3d schlegel-diagram3d)

(struct schlegel-diagram3d-data
  (outer-face viewpoint plane vertex-positions edges face-polygons mappings diagnostics)
  #:transparent)

(define (prepare-schlegel-diagram3d complex
                                    #:outer-face [selector #f]
                                    #:viewpoint-distance [distance 3]
                                    #:margin [margin 1/20]
                                    #:tolerance [tolerance 1e-8])
  (unless (polyhedral-complex3d? complex) (raise-argument-error 'prepare-schlegel-diagram3d "polyhedral-complex3d?" complex))
  (unless (and (real? distance) (positive? distance)) (raise-argument-error 'prepare-schlegel-diagram3d "positive real?" distance))
  (unless (and (real? margin) (>= margin 0)) (raise-argument-error 'prepare-schlegel-diagram3d "nonnegative real?" margin))
  (define faces (polyhedral-complex3d-faces complex))
  (define outer-index
    (cond [(not selector) 0]
          [(and (exact-nonnegative-integer? selector) (< selector (vector-length faces))) selector]
          [else (or (for/first ([face (in-vector faces)] [i (in-naturals)] #:when (equal? selector (polyhedral-face3d-id face))) i)
                    (raise-arguments-error 'prepare-schlegel-diagram3d "an in-range face index or face ID" "outer-face" selector))]))
  (define outer (vector-ref faces outer-index))
  (unless (and (polyhedral-face3d-plane outer) (polyhedral-face3d-boundary-vertex-indices outer))
    (raise-arguments-error 'prepare-schlegel-diagram3d "a simple planar outer face" "outer-face" (polyhedral-face3d-id outer)))
  (define normal (polyhedral-plane3d-normal (polyhedral-face3d-plane outer)))
  (define centroid (polyhedral-face3d-centroid outer))
  (define viewpoint (vec3+ centroid (vec3-scale distance normal)))
  (define target (plane3 (vec3- centroid (vec3-scale margin normal)) normal))
  (define vertices (mesh3d-vertices (polyhedral-complex3d-mesh complex)))
  (define projected
    (vector->immutable-vector
     (for/vector ([vertex (in-vector vertices)])
       (define direction (vec3- vertex viewpoint))
       (define denominator (vec3-dot normal direction))
       (when (zero? denominator)
         (raise-arguments-error 'prepare-schlegel-diagram3d "a viewpoint not coplanar with a projection ray" "vertex" vertex))
       (vec3+ viewpoint (vec3-scale (/ (vec3-dot normal (vec3- (plane3-point target) viewpoint)) denominator) direction)))))
  (define boundary (polyhedral-face3d-boundary-vertex-indices outer))
  (define basis (plane3d-basis target))
  (define boundary-2d (for/list ([i (in-vector boundary)]) (plane-basis3d-project basis (vector-ref projected i))))
  (for ([point (in-vector projected)] [i (in-naturals)] #:unless (member i (vector->list boundary)))
    (unless (inside-convex? (plane-basis3d-project basis point) boundary-2d tolerance)
      (raise-arguments-error 'prepare-schlegel-diagram3d "a valid Schlegel projection with all inner vertices inside the outer face" "vertex-index" i)))
  (define topology (polyhedral-complex3d-topology complex))
  (define edges
    (vector->immutable-vector
     (for/vector ([edge (in-vector (mesh-topology3d-edges topology))]
                  #:when (= (vector-length (vector-ref (polyhedral-complex3d-edge-to-faces complex) (mesh-edge-topology3d-index edge))) 2))
       (mesh-edge-topology3d-vertices edge))))
  (schlegel-diagram3d-data
   (polyhedral-face3d-id outer) viewpoint target projected edges
   (vector->immutable-vector (for/vector ([face (in-vector faces)]) (polyhedral-face3d-boundary-vertex-indices face)))
   (hasheq 'vertex-ids (for/vector ([i (in-range (vector-length vertices))]) i)
           'edge-count (vector-length edges)
           'face-ids (for/vector ([face (in-vector faces)]) (polyhedral-face3d-id face)))
   (hasheq 'outer-face-index outer-index 'margin margin 'viewpoint-distance distance 'basis basis)))

(define (inside-convex? point polygon tolerance)
  (define signs
    (for/list ([a (in-list polygon)] [b (in-list (append (cdr polygon) (list (car polygon))))])
      (- (* (- (vector-ref b 0) (vector-ref a 0)) (- (vector-ref point 1) (vector-ref a 1)))
         (* (- (vector-ref b 1) (vector-ref a 1)) (- (vector-ref point 0) (vector-ref a 0))))))
  (or (andmap (lambda (x) (>= x (- tolerance))) signs)
      (andmap (lambda (x) (<= x tolerance)) signs)))

(define (schlegel-diagram3d data #:id [id 'schlegel] #:color [color "slateblue"] #:width [width 2])
  (unless (schlegel-diagram3d-data? data) (raise-argument-error 'schlegel-diagram3d "schlegel-diagram3d-data?" data))
  (define points (schlegel-diagram3d-data-vertex-positions data))
  (group3d
   (for/list ([edge (in-vector (schlegel-diagram3d-data-edges data))] [i (in-naturals)])
     (line3d (vector-ref points (vector-ref edge 0)) (vector-ref points (vector-ref edge 1))
             #:id (string->symbol (format "edge-~a" i)) #:style (stroke3d #:color color #:width width)))
   #:id id))
