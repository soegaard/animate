#lang racket/base

;;;
;;; Combinatorial and Polar Polyhedral Duals
;;;

;; A combinatorial dual and a polar dual are deliberately separate operations.
;; The first changes incidence and uses face centroids as a diagram-friendly
;; embedding. The second is geometric and therefore rejects anything that is
;; not a convex, consistently outward, closed polyhedron around its centre.

(require racket/list
         "../geometry.rkt"
         "mesh3d.rkt"
         "mesh-topology3d.rkt"
         "polyhedral-complex3d.rkt"
         "vec3.rkt")

(provide (struct-out dual-polyhedron-face3d)
         (struct-out dual-polyhedron3d-result)
         combinatorial-dual3d
         polar-dual3d)


;;;
;;; Public results
;;;

;; A render mesh triangulates each dual polygon. This record preserves the
;; mathematical dual face to which those render triangles belong.
(struct dual-polyhedron-face3d
  (index primal-vertex triangle-indices boundary-vertex-indices)
  #:transparent)

(struct dual-polyhedron3d-result
  (mesh primal-face->dual-vertex primal-edge->dual-edge primal-vertex->dual-face diagnostics)
  #:transparent)


;;;
;;; Construction entry points
;;;

; combinatorial-dual3d : polyhedral-complex3d? [#:id symbol?] -> dual-polyhedron3d-result?
;; Uses each primal polygonal face centroid as its dual vertex. It requires a
;; closed orientable manifold with simple planar source faces, but it does not
;; claim that the centroid embedding is convex or regular.
(define (combinatorial-dual3d complex #:id [id 'combinatorial-dual])
  (check-id 'combinatorial-dual3d id)
  (validate-dual-complex 'combinatorial-dual3d complex)
  (define faces (polyhedral-complex3d-faces complex))
  (build-dual-result
   id complex
   (vector->immutable-vector
    (for/vector ([face (in-vector faces)]) (polyhedral-face3d-centroid face)))
   (hasheq 'kind 'combinatorial
           'vertex-placement 'primal-face-centroids
           'convexity-checked? #f)))

; polar-dual3d : polyhedral-complex3d?
;   [#:center vec3?] [#:scale positive-finite-real?]
;   [#:tolerance nonnegative-finite-real?] [#:id symbol?]
;   -> dual-polyhedron3d-result?
;; Forms c + n/d * s for every outward primal face plane n . (x-c) = d.
;; Centre containment and every primal point/plane relation are checked before
;; producing the mesh; the operation never silently polarizes a nonconvex or
;; boundary-touching input.
(define (polar-dual3d complex
                      #:center [center origin3]
                      #:scale [scale 1]
                      #:tolerance [tolerance 1e-9]
                      #:id [id 'polar-dual])
  (check-id 'polar-dual3d id)
  (unless (vec3-finite? center)
    (raise-argument-error 'polar-dual3d "vec3 with finite coordinates" center))
  (unless (and (finite-real? scale) (positive? scale))
    (raise-argument-error 'polar-dual3d "positive finite real?" scale))
  (unless (and (finite-real? tolerance) (>= tolerance 0))
    (raise-argument-error 'polar-dual3d "nonnegative finite real?" tolerance))
  (validate-dual-complex 'polar-dual3d complex)
  (define faces (polyhedral-complex3d-faces complex))
  ;; Dual construction is defined in the canonical, world-space analysis mesh.
  (define mesh (polyhedral-complex3d-analysis-mesh complex))
  (define vertices (mesh3d-vertices mesh))
  (define distances
    (for/vector ([face (in-vector faces)])
      (define plane (polyhedral-face3d-plane face))
      (define normal (polyhedral-plane3d-normal plane))
      (define distance (- (polyhedral-plane3d-offset plane) (vec3-dot normal center)))
      (unless (> distance tolerance)
        (raise-arguments-error
         'polar-dual3d
         "a centre strictly inside every outward supporting face plane"
         "face-id" (polyhedral-face3d-id face)
         "signed-distance" distance
         "tolerance" tolerance))
      (for ([vertex (in-vector vertices)])
        (when (> (- (vec3-dot normal vertex) (polyhedral-plane3d-offset plane)) tolerance)
          (raise-arguments-error
           'polar-dual3d
           "a convex polyhedron with every vertex inside every outward supporting plane"
           "face-id" (polyhedral-face3d-id face)
           "outside-vertex" vertex
           "signed-excess" (- (vec3-dot normal vertex) (polyhedral-plane3d-offset plane))
           "tolerance" tolerance)))
      distance))
  (build-dual-result
   id complex
   (vector->immutable-vector
    (for/vector ([face (in-vector faces)] [distance (in-vector distances)])
      (define normal (polyhedral-plane3d-normal (polyhedral-face3d-plane face)))
      (vec3+ center (vec3-scale (/ scale distance) normal))))
   (hasheq 'kind 'polar
           'center center
           'scale scale
           'tolerance tolerance
           'convexity-checked? #t
           'vertex-placement 'polar-face-planes)))


;;;
;;; Shared dual construction
;;;

(define (build-dual-result id complex dual-vertices base-diagnostics)
  (define topology (polyhedral-complex3d-topology complex))
  (define primal-mesh (polyhedral-complex3d-analysis-mesh complex))
  (define primal-centre (mesh-centroid primal-mesh))
  (define face-count (vector-length (polyhedral-complex3d-faces complex)))
  ;; Polygonal face positions have the same indexes as their output dual
  ;; vertices. This vector makes that correspondence explicit and stable.
  (define primal-face->dual-vertex
    (vector->immutable-vector (for/vector ([index (in-range face-count)]) index)))
  (define face-rings
    (for/vector ([vertex-index (in-range (vector-length (mesh3d-vertices primal-mesh)))])
      (ordered-incident-face-ring complex vertex-index)))
  (define-values (triangles dual-face-records rejected-render-faces)
    (triangulate-dual-faces face-rings dual-vertices primal-mesh primal-centre))
  (define dual-mesh
    (mesh3d #:id id #:vertices dual-vertices
            #:triangles (vector->immutable-vector (list->vector triangles))))
  (define dual-topology (mesh3d-topology dual-mesh))
  (define dual-edge-by-pair
    (for/hash ([edge (in-vector (mesh-topology3d-edges dual-topology))])
      (define endpoints (mesh-edge-topology3d-vertices edge))
      (values (edge-key (vector-ref endpoints 0) (vector-ref endpoints 1))
              (mesh-edge-topology3d-index edge))))
  (define primal-edge->dual-edge
    (vector->immutable-vector
     (for/vector ([incident-faces (in-vector (polyhedral-complex3d-edge-to-faces complex))])
       (cond [(= (vector-length incident-faces) 2)
              (hash-ref dual-edge-by-pair
                        (edge-key (vector-ref incident-faces 0)
                                  (vector-ref incident-faces 1))
                        #f)]
             ;; A render diagonal within one grouped mathematical face has no
             ;; dual edge. Keeping #f prevents a false polyhedral incidence.
             [else #f]))))
  (dual-polyhedron3d-result
   dual-mesh primal-face->dual-vertex primal-edge->dual-edge
   (vector->immutable-vector (list->vector dual-face-records))
   (hash-set
    (hash-set base-diagnostics
              'primal-render-diagonal-count
              (for/sum ([mapping (in-vector primal-edge->dual-edge)])
                (if mapping 0 1)))
    'rejected-render-faces rejected-render-faces)))

;; Each face surrounding one primal vertex has exactly two neighbours in the
;; face ring. The topology, rather than a camera-dependent angular sort,
;; determines its canonical order.
(define (ordered-incident-face-ring complex vertex-index)
  (define topology (polyhedral-complex3d-topology complex))
  (define incident
    (vector->list (vector-ref (polyhedral-complex3d-vertex-to-faces complex) vertex-index)))
  (unless (>= (length incident) 3)
    (raise-arguments-error 'combinatorial-dual3d
                           "a closed polyhedral vertex incident to at least three faces"
                           "vertex-index" vertex-index
                           "incident-face-indexes" incident))
  (define neighbours (make-hash))
  (for ([face-index (in-list incident)]) (hash-set! neighbours face-index '()))
  (for ([edge-index (in-vector (mesh-topology3d-incident-edges topology vertex-index))])
    (define faces-on-edge (vector-ref (polyhedral-complex3d-edge-to-faces complex) edge-index))
    (when (= (vector-length faces-on-edge) 2)
      (define first (vector-ref faces-on-edge 0))
      (define second (vector-ref faces-on-edge 1))
      (when (and (hash-has-key? neighbours first) (hash-has-key? neighbours second))
        (hash-set! neighbours first (cons second (hash-ref neighbours first)))
        (hash-set! neighbours second (cons first (hash-ref neighbours second))))))
  (for ([face-index (in-list incident)])
    (define local (sort (remove-duplicates (hash-ref neighbours face-index)) <))
    (unless (= (length local) 2)
      (raise-arguments-error 'combinatorial-dual3d
                             "a simple cyclic polygonal-face ring around every primal vertex"
                             "vertex-index" vertex-index
                             "face-index" face-index
                             "neighbours" local))
    (hash-set! neighbours face-index local))
  (define start (apply min incident))
  (define first-next (car (hash-ref neighbours start)))
  (let walk ([previous start] [current first-next] [collected (list start)])
    (cond [(= current start)
           (if (= (length collected) (length incident)) collected
               (raise-arguments-error 'combinatorial-dual3d
                                      "one cyclic ring containing every incident face"
                                      "vertex-index" vertex-index
                                      "ring" collected
                                      "incident-face-indexes" incident))]
          [(member current collected)
           (raise-arguments-error 'combinatorial-dual3d
                                  "a nonrepeating cyclic face ring"
                                  "vertex-index" vertex-index
                                  "ring" collected)]
          [else
           (define options (remove previous (hash-ref neighbours current)))
           (unless (= (length options) 1)
             (raise-arguments-error 'combinatorial-dual3d
                                    "one next face in a cyclic ring"
                                    "vertex-index" vertex-index
                                    "face-index" current
                                    "options" options))
           (walk current (car options) (append collected (list current)))])))

(define (triangulate-dual-faces face-rings dual-vertices primal-mesh primal-centre)
  (define triangles '())
  (define records '())
  (define rejected '())
  (for ([ring (in-vector face-rings)] [primal-vertex-index (in-naturals)])
    (define triangulation
      (validated-dual-face-triangulation
       ring dual-vertices
       (vec3- (vector-ref (mesh3d-vertices primal-mesh) primal-vertex-index)
              primal-centre)))
    (define oriented-ring (if triangulation (car triangulation) ring))
    (define start-index (length triangles))
    (define face-triangles (if triangulation (cdr triangulation) '()))
    (set! triangles (append triangles face-triangles))
    (set! records
          (append records
                  (list
                   (dual-polyhedron-face3d
                    primal-vertex-index primal-vertex-index
                    (vector->immutable-vector
                     (list->vector
                      (build-list (length face-triangles)
                                  (lambda (offset) (+ start-index offset)))))
                    (vector->immutable-vector (list->vector oriented-ring))))))
    (unless triangulation
      (set! rejected
            (append rejected
                    (list
                     (hasheq 'primal-vertex-index primal-vertex-index
                             'reason 'invalid-projected-dual-polygon
                             'boundary-vertex-indices
                             (vector->immutable-vector (list->vector ring))))))))
  (values triangles records
          (vector->immutable-vector (list->vector rejected))))

;; The cyclic face ring is mathematical dual topology. Rendering it is a
;; distinct operation: project through a stable tangent basis, reject a
;; collapsed or self-crossing projection, and use deterministic ear clipping.
;; The dual result remains useful when a centroid embedding is not drawable.
(define (validated-dual-face-triangulation ring dual-vertices desired-normal)
  (define points (map (lambda (index) (vector-ref dual-vertices index)) ring))
  (cond [(< (length points) 3) #f]
        [else
         (define normal
           (cond [(positive? (vec3-length desired-normal))
                  (vec3-normalize desired-normal)]
                 [else (ring-normal points)]))
         (cond [(not normal) #f]
               [else
                (define scale
                  (max 1
                       (for*/fold ([largest 0]) ([first (in-list points)]
                                                   [second (in-list points)])
                         (max largest (vec3-distance first second)))))
                (define tolerance (* 1e-10 scale scale))
                (define origin (car points))
                (define seed
                  (argmin (lambda (axis) (abs (vec3-dot normal axis)))
                          (list x-axis3 y-axis3 z-axis3)))
                (define u (vec3-normalize (vec3-cross seed normal)))
                (define v (vec3-cross normal u))
                (define projected
                  (for/list ([point (in-list points)])
                    (define offset (vec3- point origin))
                    (vector (vec3-dot offset u) (vec3-dot offset v))))
                (define signed-area (polygon-signed-area projected))
                (cond [(or (<= (abs signed-area) tolerance)
                           (projected-adjacent-duplicates? projected tolerance)
                           (projected-self-intersecting? projected tolerance))
                       #f]
                      [else
                       (define-values (oriented-ring oriented-projected)
                         (if (negative? signed-area)
                             (values (cons (car ring) (reverse (cdr ring)))
                                     (cons (car projected) (reverse (cdr projected))))
                             (values ring projected)))
                       (define triangle-indexes
                         (projected-ear-triangulation oriented-projected tolerance))
                       (cond [(not triangle-indexes) #f]
                             [else
                              (define face-triangles
                                (for/list ([triangle (in-list triangle-indexes)])
                                  (vector-immutable
                                   (list-ref oriented-ring (first triangle))
                                   (list-ref oriented-ring (second triangle))
                                   (list-ref oriented-ring (third triangle)))))
                              ;; Projection alone is insufficient if the face
                              ;; folds in world space. Every render triangle
                              ;; must retain the chosen face orientation.
                              (and (for/and ([triangle (in-list face-triangles)])
                                     (define first-point (vector-ref dual-vertices (vector-ref triangle 0)))
                                     (define second-point (vector-ref dual-vertices (vector-ref triangle 1)))
                                     (define third-point (vector-ref dual-vertices (vector-ref triangle 2)))
                                     (> (vec3-dot (vec3-cross (vec3- second-point first-point)
                                                              (vec3- third-point first-point))
                                                  normal)
                                        tolerance))
                                   (cons oriented-ring face-triangles))])])])]))

(define (ring-normal points)
  (define raw
    (for/fold ([sum origin3]) ([point (in-list points)]
                              [next (in-list (append (cdr points) (list (car points))))])
      (vec3+ sum (vec3-cross point next))))
  (and (positive? (vec3-length raw)) (vec3-normalize raw)))

(define (projected-ear-triangulation points tolerance)
  (let loop ([remaining (build-list (length points) values)] [triangles '()])
    (cond [(= (length remaining) 3) (reverse (cons remaining triangles))]
          [else
           (define ear
             (for/first ([position (in-range (length remaining))]
                         #:when (projected-ear? points remaining position tolerance))
               position))
           (and ear
                (let ([previous (list-ref remaining (modulo (sub1 ear) (length remaining)))]
                      [current (list-ref remaining ear)]
                      [next (list-ref remaining (modulo (add1 ear) (length remaining)))])
                  (loop (append (take remaining ear) (drop remaining (add1 ear)))
                        (cons (list previous current next) triangles))))])))

(define (projected-ear? points indexes position tolerance)
  (define count (length indexes))
  (define previous (list-ref indexes (modulo (sub1 position) count)))
  (define current (list-ref indexes position))
  (define next (list-ref indexes (modulo (add1 position) count)))
  (define first-point (list-ref points previous))
  (define second-point (list-ref points current))
  (define third-point (list-ref points next))
  (and (> (cross2 first-point second-point third-point) tolerance)
       (for/and ([index (in-list indexes)]
                 #:unless (memv index (list previous current next)))
         (not (point-in-projected-triangle? (list-ref points index)
                                            first-point second-point third-point tolerance)))))

(define (point-in-projected-triangle? point first second third tolerance)
  (and (>= (cross2 first second point) (- tolerance))
       (>= (cross2 second third point) (- tolerance))
       (>= (cross2 third first point) (- tolerance))))

(define (projected-adjacent-duplicates? points tolerance)
  (for/or ([point (in-list points)]
           [next (in-list (append (cdr points) (list (car points))))])
    (<= (squared-distance2 point next) (* tolerance tolerance))))

(define (projected-self-intersecting? points tolerance)
  (define count (length points))
  (for/or ([index (in-range count)])
    (for/or ([other (in-range (add1 index) count)]
             #:unless (or (= other (add1 index))
                          (and (zero? index) (= other (sub1 count)))))
      (proper-projected-segment-crossing?
       (list-ref points index) (list-ref points (modulo (add1 index) count))
       (list-ref points other) (list-ref points (modulo (add1 other) count))
       tolerance))))

(define (proper-projected-segment-crossing? first-a second-a first-b second-b tolerance)
  (define a-first (cross2 first-a second-a first-b))
  (define a-second (cross2 first-a second-a second-b))
  (define b-first (cross2 first-b second-b first-a))
  (define b-second (cross2 first-b second-b second-a))
  (and (< (* a-first a-second) 0) (< (* b-first b-second) 0)
       (> (abs a-first) tolerance) (> (abs a-second) tolerance)
       (> (abs b-first) tolerance) (> (abs b-second) tolerance)))

(define (polygon-signed-area points)
  (/ (for/sum ([point (in-list points)]
               [next (in-list (append (cdr points) (list (car points))))])
       (- (* (vector-ref point 0) (vector-ref next 1))
          (* (vector-ref point 1) (vector-ref next 0))))
     2))

(define (squared-distance2 first second)
  (define dx (- (vector-ref first 0) (vector-ref second 0)))
  (define dy (- (vector-ref first 1) (vector-ref second 1)))
  (+ (* dx dx) (* dy dy)))

(define (cross2 first second third)
  (- (* (- (vector-ref second 0) (vector-ref first 0))
        (- (vector-ref third 1) (vector-ref first 1)))
     (* (- (vector-ref second 1) (vector-ref first 1))
        (- (vector-ref third 0) (vector-ref first 0)))))

(define (argmin score values)
  (for/fold ([best (car values)]) ([value (in-list (cdr values))])
    (if (< (score value) (score best)) value best)))


;;;
;;; Validation and small helpers
;;;

(define (validate-dual-complex who complex)
  (unless (polyhedral-complex3d? complex)
    (raise-argument-error who "polyhedral-complex3d?" complex))
  (define topology (polyhedral-complex3d-topology complex))
  (unless (and (mesh-topology3d-manifold? topology)
               (mesh-topology3d-closed? topology)
               (mesh-topology3d-orientable? topology))
    (raise-arguments-error who
                           "a closed orientable manifold polyhedral complex"
                           "topology-diagnostics" (mesh-topology3d-diagnostics topology)))
  (for ([face (in-vector (polyhedral-complex3d-faces complex))] [index (in-naturals)])
    (unless (and (polyhedral-face3d-plane face)
                 (polyhedral-face3d-centroid face)
                 (polyhedral-face3d-boundary-vertex-indices face))
      (raise-arguments-error who
                             "simple planar polygonal primal faces"
                             "face-index" index
                             "face-id" (polyhedral-face3d-id face))))
  (void))

(define (mesh-centroid mesh)
  (define vertices (mesh3d-vertices mesh))
  (vec3-scale (/ 1 (vector-length vertices))
              (for/fold ([sum origin3]) ([vertex (in-vector vertices)])
                (vec3+ sum vertex))))

(define (edge-key first second)
  (cons (min first second) (max first second)))

(define (check-id who id)
  (unless (symbol? id) (raise-argument-error who "symbol?" id)))
