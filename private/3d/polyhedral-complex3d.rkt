#lang racket/base

;;;
;;; Polygonal Faces over an Indexed Triangle Mesh
;;;

;; A `mesh3d` is deliberately still a renderer-friendly triangle container.
;; This module adds the separate mathematical layer needed by polyhedra: one
;; polygonal face may own a connected coplanar region of render triangles.  It
;; never welds, reorders, or repairs the mesh.  In particular, a bad boundary
;; remains a diagnosed bad boundary rather than an invented polygon.

(require racket/list
         racket/math
         "../geometry.rkt"
         "affine3.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "mesh-topology3d.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide (struct-out polyhedral-plane3d)
         (struct-out polyhedral-source-face-id3d)
         (struct-out polyhedral-face-declaration3d)
         (struct-out polyhedral-face3d)
         polyhedral-complex3d?
         polyhedral-complex3d-source-mesh
         polyhedral-complex3d-analysis-mesh
         polyhedral-complex3d-source-transform
         polyhedral-complex3d-mesh
         polyhedral-complex3d-topology
         polyhedral-complex3d-faces
         polyhedral-complex3d-edge-to-faces
         polyhedral-complex3d-vertex-to-faces
         polyhedral-complex3d-diagnostics
         polyhedral-complex3d)


;;;
;;; Immutable values
;;;

;; The signed plane equation is n . x = offset.  `normal` is a unit vector in
;; the mesh's transformed/world coordinates, so its tolerance is meaningful
;; even if an authored mesh carries a non-uniform scale.
(struct polyhedral-plane3d (normal offset) #:transparent)

;; Generated face identities deliberately expose their source instead of
;; hiding it in a geometry hash string.  An explicit declaration supplies a
;; symbol; an automatically grouped region gets its least source triangle.
(struct polyhedral-source-face-id3d (triangle-index) #:transparent)

;; An explicit partition entry.  `triangle-indices` names a nonempty group of
;; source triangles and `id` is its author-visible polygonal-face identity.
(struct polyhedral-face-declaration3d (id triangle-indices) #:transparent)

;; `boundary-vertex-indices` is an immutable cyclic vertex vector for a simple
;; region boundary, or #f when the source region has holes/branches/repeated
;; vertices.  The complete diagnostic remains on the enclosing complex.
(struct polyhedral-face3d
  (id triangle-indices boundary-vertex-indices normal plane centroid area provenance)
  #:transparent)

;; The public operation and the mathematical value intentionally have the same
;; natural name in the roadmap.  Racket reserves a structure name at expansion
;; time, so the value has this private representation name and exposes the
;; documented predicate/accessors below; authors still construct it with
;; `(polyhedral-complex3d mesh ...)`.
(struct polyhedral-complex3d-value
  (source-mesh analysis-mesh topology faces edge-to-faces vertex-to-faces diagnostics)
  #:transparent)

(define polyhedral-complex3d? polyhedral-complex3d-value?)
(define polyhedral-complex3d-source-mesh polyhedral-complex3d-value-source-mesh)
(define polyhedral-complex3d-analysis-mesh polyhedral-complex3d-value-analysis-mesh)
(define (polyhedral-complex3d-source-transform complex)
  (unless (polyhedral-complex3d? complex)
    (raise-argument-error 'polyhedral-complex3d-source-transform "polyhedral-complex3d?" complex))
  (spatial-transform (polyhedral-complex3d-source-mesh complex)))
;; Compatibility alias.  New code must choose source or analysis explicitly;
;; the mathematical operations below intentionally use analysis/world space.
(define polyhedral-complex3d-mesh polyhedral-complex3d-analysis-mesh)
(define polyhedral-complex3d-topology polyhedral-complex3d-value-topology)
(define polyhedral-complex3d-faces polyhedral-complex3d-value-faces)
(define polyhedral-complex3d-edge-to-faces polyhedral-complex3d-value-edge-to-faces)
(define polyhedral-complex3d-vertex-to-faces polyhedral-complex3d-value-vertex-to-faces)
(define polyhedral-complex3d-diagnostics polyhedral-complex3d-value-diagnostics)


;;;
;;; Construction
;;;

; polyhedral-complex3d : mesh3d?
;   [#:faces (or/c #f 'coplanar 'triangles explicit-face-partition?)]
;   [#:coplanar-angle nonnegative-finite-real?]
;   [#:plane-distance nonnegative-finite-real?]
;   -> polyhedral-complex3d?
;;
;; `#:faces #f` (the default) and 'coplanar merge edge-connected, consistently
;; oriented triangles whose transformed planes agree.  'triangles keeps every
;; render triangle distinct.  An explicit partition is a list/vector of
;; `polyhedral-face-declaration3d` values, or concise `(id index ...)` entries;
;; it must partition every source triangle exactly once and always overrides
;; automatic merging.
(define (polyhedral-complex3d mesh
                              #:faces [face-mode #f]
                              #:coplanar-angle [coplanar-angle 1e-7]
                              #:plane-distance [plane-distance 1e-7])
  (unless (mesh3d? mesh)
    (raise-argument-error 'polyhedral-complex3d "mesh3d?" mesh))
  (check-nonnegative-finite 'polyhedral-complex3d "coplanar-angle" coplanar-angle)
  (when (> coplanar-angle pi)
    (raise-arguments-error 'polyhedral-complex3d
                           "an angle no greater than pi radians"
                           "coplanar-angle" coplanar-angle))
  (check-nonnegative-finite 'polyhedral-complex3d "plane-distance" plane-distance)
  (define analysis-mesh (mesh3d-analysis-mesh3d mesh))
  (define topology (mesh3d-topology analysis-mesh))
  (define triangle-planes (mesh-triangle-planes analysis-mesh))
  (define-values (mode groups explicit-ids)
    (cond [(or (not face-mode) (eq? face-mode 'coplanar))
           (values 'coplanar
                   (coplanar-triangle-groups topology triangle-planes
                                              coplanar-angle plane-distance)
                   #f)]
          [(eq? face-mode 'triangles)
           (values 'triangles
                   (vector->immutable-vector
                    (for/vector ([triangle-index
                                  (in-range (vector-length (mesh3d-triangles analysis-mesh)))])
                      (list triangle-index)))
                   #f)]
          [else
           (define-values (groups ids) (normalize-explicit-partition analysis-mesh face-mode))
           (values 'explicit groups ids)]))
  (define face-builds
    (for/list ([triangle-group (in-vector groups)] [face-index (in-naturals)])
      (build-polyhedral-face analysis-mesh triangle-planes triangle-group
                             (and explicit-ids (vector-ref explicit-ids face-index))
                             mode coplanar-angle plane-distance)))
  (define faces
    (vector->immutable-vector
     (list->vector (map car face-builds))))
  (define face-diagnostics (map cdr face-builds))
  (define-values (edge-to-faces vertex-to-faces)
    (build-incidence-tables topology groups))
  (define invalid-face-indices
    (for/list ([diagnostic (in-list face-diagnostics)] [index (in-naturals)]
               #:when (not (and (hash-ref diagnostic 'simple-boundary? #f)
                                 (hash-ref diagnostic 'planar? #f))))
      index))
  (polyhedral-complex3d-value
   mesh analysis-mesh topology faces edge-to-faces vertex-to-faces
   (hasheq 'mode mode
           'analysis-space 'world
           'source-transform (spatial-transform mesh)
           'reflection?
           (negative? (linear3-determinant
                       (affine3-linear (transform3->affine3 (spatial-transform mesh)))))
           'coplanar-angle coplanar-angle
           'plane-distance plane-distance
           'invalid-face-indices
           (vector->immutable-vector (list->vector invalid-face-indices))
           'face-boundary-diagnostics
           (vector->immutable-vector (list->vector face-diagnostics))
           'topology-diagnostics (mesh-topology3d-diagnostics topology))))

(define (check-nonnegative-finite who label value)
  (unless (and (finite-real? value) (>= value 0))
    (raise-arguments-error who "a nonnegative finite real"
                           label value)))


;;;
;;; Explicit partitions
;;;

(define (normalize-explicit-partition mesh partition)
  (define entries
    (cond [(vector? partition) (vector->list partition)]
          [(list? partition) partition]
          [else
           (raise-argument-error
            'polyhedral-complex3d
            "a list/vector of polyhedral-face-declaration3d values or (id triangle-index ...) entries"
            partition)]))
  (when (null? entries)
    (raise-arguments-error 'polyhedral-complex3d
                           "a nonempty explicit face partition"
                           "faces" partition))
  (define declarations
    (for/list ([entry (in-list entries)])
      (cond [(polyhedral-face-declaration3d? entry)
             (validate-declaration entry)]
            [(or (list? entry) (vector? entry))
             (define values (if (vector? entry) (vector->list entry) entry))
             (unless (and (pair? values) (symbol? (car values)) (pair? (cdr values)))
               (raise-arguments-error
                'polyhedral-complex3d
                "an explicit entry of the form (symbol triangle-index ...)"
                "entry" entry))
             (validate-declaration
              (polyhedral-face-declaration3d
               (car values)
               (vector->immutable-vector (list->vector (cdr values)))))]
            [else
             (raise-arguments-error
              'polyhedral-complex3d
              "a polyhedral-face-declaration3d value or (symbol triangle-index ...) entry"
              "entry" entry)])))
  (define ids (map polyhedral-face-declaration3d-id declarations))
  (unless (= (length ids) (length (remove-duplicates ids)))
    (raise-arguments-error 'polyhedral-complex3d
                           "explicit polygonal face IDs that are unique"
                           "ids" ids))
  (define triangle-count (vector-length (mesh3d-triangles mesh)))
  (define groups
    (for/list ([declaration (in-list declarations)])
      (define indices (polyhedral-face-declaration3d-triangle-indices declaration))
      (unless (or (vector? indices) (list? indices))
        (raise-arguments-error 'polyhedral-complex3d
                               "a vector or list of triangle indexes"
                               "triangle-indices" indices))
      (define result (if (vector? indices) (vector->list indices) indices))
      (when (null? result)
        (raise-arguments-error 'polyhedral-complex3d
                               "a nonempty group of triangle indexes"
                               "triangle-indices" indices))
      (for ([triangle-index (in-list result)])
        (unless (and (exact-nonnegative-integer? triangle-index)
                     (< triangle-index triangle-count))
          (raise-arguments-error 'polyhedral-complex3d
                                 "an in-range exact nonnegative triangle index"
                                 "triangle-index" triangle-index
                                 "triangle-count" triangle-count)))
      (sort result <)))
  (define all-indices (apply append groups))
  (unless (and (= (length all-indices) triangle-count)
               (= (length (remove-duplicates all-indices)) triangle-count)
               (equal? (sort all-indices <) (build-list triangle-count values)))
    (raise-arguments-error
     'polyhedral-complex3d
     "an explicit partition that names every source triangle exactly once"
     "triangle-groups" groups))
  (values (vector->immutable-vector (list->vector groups))
          (vector->immutable-vector (list->vector ids))))

(define (validate-declaration declaration)
  (unless (symbol? (polyhedral-face-declaration3d-id declaration))
    (raise-arguments-error 'polyhedral-complex3d
                           "an explicit polygonal face ID that is a symbol"
                           "id" (polyhedral-face-declaration3d-id declaration)))
  declaration)


;;;
;;; Coplanar grouping
;;;

;; Each analysis triangle has one world-space plane.  A triangle with zero area
;; cannot participate in a mathematical plane and is left as its own group;
;; the complex records that condition through a non-simple boundary diagnostic.
(define (mesh-triangle-planes mesh)
  (define vertices (mesh3d-vertices mesh))
  (vector->immutable-vector
   (for/vector ([triangle (in-vector (mesh3d-triangles mesh))])
     (define first (vector-ref vertices (vector-ref triangle 0)))
     (define second (vector-ref vertices (vector-ref triangle 1)))
     (define third (vector-ref vertices (vector-ref triangle 2)))
     (define raw-normal (vec3-cross (vec3- second first) (vec3- third first)))
     (define twice-area (vec3-length raw-normal))
     (and (positive? twice-area)
          (let ([normal (vec3-scale (/ 1.0 twice-area) raw-normal)])
            (triangle-plane3d normal (vec3-dot normal first)
                              (vec3-scale (/ 1 3) (vec3+ first (vec3+ second third)))
                              (/ twice-area 2)
                              (vector-immutable first second third)))))))

;; Topological analysis is deliberately performed on one canonical geometry
;; space.  Retaining a transformed plane alongside local vertices used to make
;; downstream dual, Schlegel, and net operations mix coordinate systems.  Bake
;; the author transform once, preserve all stable semantic IDs, and expose the
;; original mesh separately for source-level provenance.  A reflection reverses
;; the analysis winding so geometric face normals stay aligned with transformed
;; authored normals.
(define (mesh3d-analysis-mesh3d source)
  (define map (transform3->affine3 (spatial-transform source)))
  (define reflected?
    (negative? (linear3-determinant (affine3-linear map))))
  (define normals (mesh3d-normals source))
  (define (normalise normal)
    (define length (vec3-length normal))
    (if (zero? length) normal (vec3-scale (/ 1 length) normal)))
  (define analysis-triangles
    (if reflected?
        (for/vector ([triangle (in-vector (mesh3d-triangles source))])
          (vector (vector-ref triangle 0) (vector-ref triangle 2) (vector-ref triangle 1)))
        (mesh3d-triangles source)))
  (mesh3d
   #:id (spatial-id source)
   #:vertices
   (for/vector ([vertex (in-vector (mesh3d-vertices source))])
     (affine3-apply-point map vertex))
   #:triangles analysis-triangles
   #:edges (mesh3d-edges source)
   #:vertex-ids (mesh3d-vertex-ids source)
   #:edge-ids (mesh3d-edge-ids source)
   #:face-ids (mesh3d-face-ids source)
   #:normals
   (and normals
        (for/vector ([normal (in-vector normals)])
          (normalise
           (linear3-apply-vector (affine3-normal-transform map) normal))))
   #:colors (mesh3d-colors source)
   #:material (mesh3d-material source)
   #:opacity (spatial-opacity source)
   #:wireframe-color (mesh3d-wireframe-color source)
   #:wireframe-width (mesh3d-wireframe-width source)))

(struct triangle-plane3d (normal offset centroid area points) #:transparent)

(define (coplanar-triangle-groups topology planes angle-tolerance distance-tolerance)
  (define triangle-count (vector-length (mesh-topology3d-triangles topology)))
  (define neighbours (triangle-neighbour-table topology triangle-count))
  (define seen (make-vector triangle-count #f))
  (define groups '())
  (for ([root (in-range triangle-count)])
    (unless (vector-ref seen root)
      (vector-set! seen root #t)
      (define root-plane (vector-ref planes root))
      (define group
        (let visit ([pending (list root)] [collected '()])
          (cond [(null? pending) (sort collected <)]
                [else
                 (define current (car pending))
                 (define additions
                   (for/list ([candidate (in-list (vector-ref neighbours current))]
                              #:unless (vector-ref seen candidate)
                              #:when (planes-agree? root-plane
                                                    (vector-ref planes candidate)
                                                    angle-tolerance distance-tolerance))
                     candidate))
                 (for ([candidate (in-list additions)])
                   (vector-set! seen candidate #t))
                 (visit (append (cdr pending) additions) (cons current collected))])))
      (set! groups (cons group groups))))
  (vector->immutable-vector (list->vector (reverse groups))))

;; Only two-incidence edges provide automatic adjacency.  A nonmanifold edge
;; cannot be assigned one arbitrary local continuation, so it forms a region
;; boundary and remains visible in the U-1 diagnostics.
(define (triangle-neighbour-table topology triangle-count)
  (define table (make-vector triangle-count '()))
  (for ([edge (in-vector (mesh-topology3d-edges topology))]
        #:when (= (vector-length (mesh-edge-topology3d-halfedges edge)) 2))
    (define halfedges (mesh-edge-topology3d-halfedges edge))
    (define first
      (mesh-halfedge3d-triangle
       (vector-ref (mesh-topology3d-halfedges topology) (vector-ref halfedges 0))))
    (define second
      (mesh-halfedge3d-triangle
       (vector-ref (mesh-topology3d-halfedges topology) (vector-ref halfedges 1))))
    (vector-set! table first (cons second (vector-ref table first)))
    (vector-set! table second (cons first (vector-ref table second))))
  (vector->immutable-vector
   (for/vector ([neighbours (in-vector table)])
     (sort (remove-duplicates neighbours) <))))

(define (planes-agree? first second angle-tolerance distance-tolerance)
  (and first second
       (>= (vec3-dot (triangle-plane3d-normal first) (triangle-plane3d-normal second))
           (cos angle-tolerance))
       (for/and ([point (in-vector (triangle-plane3d-points second))])
         (<= (abs (- (vec3-dot (triangle-plane3d-normal first) point)
                     (triangle-plane3d-offset first)))
             distance-tolerance))))


;;;
;;; Face records and incidence
;;;

(define (build-polyhedral-face mesh planes triangle-group explicit-id mode
                               angle-tolerance distance-tolerance)
  (define triangle-indices
    (vector->immutable-vector (list->vector triangle-group)))
  (define source-planes
    (for/list ([triangle-index (in-list triangle-group)])
      (vector-ref planes triangle-index)))
  (define usable-planes (filter values source-planes))
  (define first-plane (and (pair? usable-planes) (car usable-planes)))
  (define planar?
    (and first-plane
         (= (length usable-planes) (length source-planes))
         (for/and ([source-plane (in-list usable-planes)])
           (planes-agree? first-plane source-plane angle-tolerance distance-tolerance))))
  (define normal (and planar? (triangle-plane3d-normal first-plane)))
  (define plane
    (and planar?
         (polyhedral-plane3d normal (triangle-plane3d-offset first-plane))))
  (define area (for/sum ([source-plane (in-list usable-planes)])
                 (triangle-plane3d-area source-plane)))
  (define centroid
    (and planar? (positive? area)
         (vec3-scale
          (/ 1 area)
          (for/fold ([sum origin3]) ([source-plane (in-list usable-planes)])
            (vec3+ sum (vec3-scale (triangle-plane3d-area source-plane)
                                   (triangle-plane3d-centroid source-plane)))))))
  (define boundary (extract-simple-boundary mesh triangle-group))
  (define diagnostic
    (hash-set
     (hash-set boundary 'planar? (and planar? #t))
     'degenerate-triangle-indices
     (vector->immutable-vector
      (list->vector
       (for/list ([source-plane (in-list source-planes)] [triangle-index (in-list triangle-group)]
                  #:unless source-plane)
         triangle-index)))))
  (define id (or explicit-id (automatic-face-id mesh triangle-group)))
  (define provenance
    (hasheq 'mode mode
            'source-triangle-indices triangle-indices
            'source-triangle-minimum (car triangle-group)))
  (cons
   (polyhedral-face3d id triangle-indices
                       (and (hash-ref diagnostic 'simple-boundary? #f)
                            (hash-ref diagnostic 'planar? #f)
                            (hash-ref diagnostic 'boundary-vertices))
                       normal plane centroid area provenance)
   diagnostic))

(define (automatic-face-id mesh triangle-group)
  (define authored-ids
    (and (mesh3d-face-ids mesh)
         (for/list ([triangle-index (in-list triangle-group)])
           (mesh3d-face-id mesh triangle-index))))
  (cond [(and authored-ids
              (= (length authored-ids) 1))
         (car authored-ids)]
        [(and authored-ids
              (andmap (lambda (id) (equal? id (car authored-ids))) (cdr authored-ids)))
         (car authored-ids)]
        [else (polyhedral-source-face-id3d (car triangle-group))]))

;; A simple face boundary is one directed, non-branching cycle.  The triangle
;; source order determines encounter order; the least boundary vertex fixes
;; its otherwise arbitrary rotation.  We retain diagnostics instead of trying
;; to bridge holes or split pinched regions at this stage.
(define (extract-simple-boundary mesh triangle-group)
  (define triangles (mesh3d-triangles mesh))
  (define directed '())
  (define counts (make-hash))
  (for ([triangle-index (in-list triangle-group)])
    (define triangle (vector-ref triangles triangle-index))
    (for ([local-index (in-range 3)])
      (define from (vector-ref triangle local-index))
      (define to (vector-ref triangle (modulo (add1 local-index) 3)))
      (define undirected (cons (min from to) (max from to)))
      (hash-set! counts undirected (add1 (hash-ref counts undirected 0)))
      (set! directed (append directed (list (cons from to))))))
  (define boundary-edges
    (filter (lambda (edge)
              (= (hash-ref counts (cons (min (car edge) (cdr edge))
                           (max (car edge) (cdr edge))) 0)
                 1))
            directed))
  (define from-table (make-hash))
  (define to-table (make-hash))
  (for ([edge (in-list boundary-edges)])
    (hash-update! from-table (car edge) (lambda (edges) (cons edge edges)) '())
    (hash-update! to-table (cdr edge) (lambda (edges) (cons edge edges)) '()))
  (define vertices
    (sort (remove-duplicates
           (append (map car boundary-edges) (map cdr boundary-edges)))
          <))
  (define degree-valid?
    (and (pair? boundary-edges)
         (for/and ([vertex-index (in-list vertices)])
           (and (= (length (hash-ref from-table vertex-index '())) 1)
                (= (length (hash-ref to-table vertex-index '())) 1)))))
  (define loops
    (and degree-valid? (boundary-loops boundary-edges from-table)))
  (define simple?
    (and degree-valid? (= (length loops) 1)
         (= (length (car loops)) (length (remove-duplicates (car loops))))))
  (hasheq 'simple-boundary? (and simple? #t)
          'boundary-edge-count (length boundary-edges)
          'boundary-loop-count (if loops (length loops) 0)
          'boundary-vertices
          (and simple?
               (vector->immutable-vector
                (list->vector (canonicalize-boundary (car loops)))))))

(define (boundary-loops boundary-edges from-table)
  (define unseen (make-hash))
  (for ([edge (in-list boundary-edges)]) (hash-set! unseen edge #t))
  (define loops '())
  (let loop ()
    (define starts
      (sort (for/list ([(edge _) (in-hash unseen)]) edge)
            < #:key car))
    (unless (null? starts)
      (define start-edge (car starts))
      (define start (car start-edge))
      (define vertices '())
      (let walk ([edge start-edge])
        (hash-remove! unseen edge)
        (set! vertices (append vertices (list (car edge))))
        (define next (car (hash-ref from-table (cdr edge))))
        (unless (= (cdr edge) start)
          (walk next)))
      (set! loops (append loops (list vertices)))
      (loop)))
  loops)

(define (canonicalize-boundary boundary)
  (define smallest (apply min boundary))
  (let rotate ([prefix '()] [remaining boundary])
    (cond [(= (car remaining) smallest) (append remaining prefix)]
          [else (rotate (append prefix (list (car remaining))) (cdr remaining))])))

(define (build-incidence-tables topology groups)
  (define triangle->face (make-vector (vector-length (mesh-topology3d-triangles topology)) #f))
  (for ([group (in-vector groups)] [face-index (in-naturals)])
    (for ([triangle-index (in-list group)])
      (vector-set! triangle->face triangle-index face-index)))
  (define edge-to-faces
    (vector->immutable-vector
     (for/vector ([edge (in-vector (mesh-topology3d-edges topology))])
       (vector->immutable-vector
        (list->vector
         (sort
          (remove-duplicates
           (for/list ([halfedge-index (in-vector (mesh-edge-topology3d-halfedges edge))])
             (define triangle-index
               (mesh-halfedge3d-triangle
                (vector-ref (mesh-topology3d-halfedges topology) halfedge-index)))
             (vector-ref triangle->face triangle-index)))
          <))))))
  (define vertex-to-faces
    (vector->immutable-vector
     (for/vector ([vertex (in-vector (mesh-topology3d-vertices topology))])
       (vector->immutable-vector
        (list->vector
         (sort
          (remove-duplicates
           (for/list ([triangle-index
                       (in-vector (mesh-topology3d-incident-faces
                                   topology
                                   (mesh-vertex-topology3d-index vertex)))])
             (vector-ref triangle->face triangle-index)))
          <))))))
  (values edge-to-faces vertex-to-faces))
