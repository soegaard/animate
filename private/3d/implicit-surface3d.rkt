#lang racket/base

;;;
;;; Deterministic Implicit-Surface Extraction
;;;

;; The extractor deliberately uses a fixed marching-tetrahedra decomposition
;; rather than a backend-dependent isosurface helper.  Grid vertices, cube
;; order, tetrahedron order, and shared edge keys are all deterministic.

(require racket/list
         "../geometry.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "surface-mesh3d.rkt"
         "surface-provenance3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide implicit-surface3d
         (struct-out implicit-surface-diagnostics))

(struct implicit-surface-diagnostics
  (resolution cube-count vertex-count triangle-count boundary-contact? warnings)
  #:transparent)

; implicit-surface3d : (vec3? -> finite-real?) -> surface3d?
;; Extracts field(position) = level inside the declared axis-aligned box.
;; The returned surface keeps every extraction decision in immutable mesh
;; provenance, so the same field and inputs produce the same topology.
(define (implicit-surface3d field
                            #:bounds [bounds '(-1 1 -1 1 -1 1)]
                            #:resolution [resolution 24]
                            #:level [level 0]
                            #:id id
                            #:material [material (material3d #:color "mediumpurple" #:shading 'smooth)]
                            #:transform [transform identity-transform3]
                            #:opacity [opacity 1]
                            #:wireframe-color [wireframe-color "mediumpurple"]
                            #:wireframe-width [wireframe-width 1]
                            #:normal-step [normal-step #f])
  (unless (procedure? field)
    (raise-argument-error 'implicit-surface3d "procedure?" field))
  (unless (symbol? id)
    (raise-argument-error 'implicit-surface3d "symbol?" id))
  (unless (and (list? bounds) (= (length bounds) 6)
               (andmap finite-real? bounds)
               (< (first bounds) (second bounds))
               (< (third bounds) (fourth bounds))
               (< (fifth bounds) (sixth bounds)))
    (raise-argument-error 'implicit-surface3d
                          "(list xmin xmax ymin ymax zmin zmax), with increasing finite bounds"
                          bounds))
  (unless (and (exact-positive-integer? resolution) (>= resolution 2))
    (raise-argument-error 'implicit-surface3d "exact integer at least 2" resolution))
  (unless (finite-real? level)
    (raise-argument-error 'implicit-surface3d "finite real?" level))
  (unless (material3d? material)
    (raise-argument-error 'implicit-surface3d "material3d?" material))
  (unless (transform3? transform)
    (raise-argument-error 'implicit-surface3d "transform3?" transform))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'implicit-surface3d "finite real in [0, 1]" opacity))
  (unless (and (finite-real? wireframe-width) (positive? wireframe-width))
    (raise-argument-error 'implicit-surface3d "positive finite real?" wireframe-width))
  (define xmin (first bounds)) (define xmax (second bounds))
  (define ymin (third bounds)) (define ymax (fourth bounds))
  (define zmin (fifth bounds)) (define zmax (sixth bounds))
  (define h (or normal-step
                (/ (min (- xmax xmin) (- ymax ymin) (- zmax zmin))
                   (* 16 resolution))))
  (unless (and (finite-real? h) (positive? h))
    (raise-argument-error 'implicit-surface3d "positive finite #:normal-step" h))
  (define cache (make-hash))
  (define (sample i j k)
    (hash-ref! cache (vector i j k)
               (lambda ()
                 (define point
                   (vec3 (+ xmin (* (/ i resolution) (- xmax xmin)))
                         (+ ymin (* (/ j resolution) (- ymax ymin)))
                         (+ zmin (* (/ k resolution) (- zmax zmin)))))
                 (define value
                   (with-handlers ([exn:fail?
                                    (lambda (exception)
                                      (raise-arguments-error
                                       'implicit-surface3d "a total finite scalar field"
                                       "point" point "exception" (exn-message exception)))])
                     (field point)))
                 (unless (finite-real? value)
                   (raise-arguments-error 'implicit-surface3d
                                          "a finite scalar field result"
                                          "point" point "result" value))
                 (implicit-sample point (- value level)))))
  (define vertices '())
  (define normals '())
  (define vertex-provenance '())
  (define triangles '())
  (define triangle-provenance '())
  (define vertex-ids (make-hash))
  (define next-id 0)
  (define (gradient point)
    (define (value-at delta)
      (define result (field (vec3+ point delta)))
      (if (finite-real? result) result level))
    (define candidate
      (vec3 (- (value-at (vec3 h 0 0)) (value-at (vec3 (- h) 0 0)))
            (- (value-at (vec3 0 h 0)) (value-at (vec3 0 (- h) 0)))
            (- (value-at (vec3 0 0 h)) (value-at (vec3 0 0 (- h))))))
    (if (zero? (vec3-length candidate)) z-axis3 (vec3-normalize candidate)))
  (define (add-intersection first-index first second-index second cube-index tetra-index)
    (define edge-key (ordered-index-edge first-index second-index))
    (hash-ref! vertex-ids edge-key
               (lambda ()
                 (define a (implicit-sample-value first))
                 (define b (implicit-sample-value second))
                 (define fraction
                   (let ([denominator (- a b)])
                     (if (zero? denominator) 1/2 (max 0 (min 1 (/ a denominator))))))
                 (define point (vec3-lerp (implicit-sample-point first)
                                          (implicit-sample-point second) fraction))
                 (define index next-id)
                 (set! next-id (add1 next-id))
                 (set! vertices (cons point vertices))
                 (set! normals (cons (gradient point) normals))
                 (set! vertex-provenance
                       (cons (hasheq 'kind 'implicit-edge
                                     'grid-edge edge-key
                                     'fraction fraction
                                     'cube cube-index
                                     'tetrahedron tetra-index)
                             vertex-provenance))
                 index)))
  (define boundary-contact? #f)
  (for* ([i (in-range resolution)] [j (in-range resolution)] [k (in-range resolution)])
    (define cube-indices
      (vector (vector i j k) (vector (add1 i) j k)
              (vector i (add1 j) k) (vector (add1 i) (add1 j) k)
              (vector i j (add1 k)) (vector (add1 i) j (add1 k))
              (vector i (add1 j) (add1 k)) (vector (add1 i) (add1 j) (add1 k))))
    (define cube-samples
      (for/vector ([index (in-vector cube-indices)])
        (sample (vector-ref index 0) (vector-ref index 1) (vector-ref index 2))))
    (for ([tetra (in-list marching-tetrahedra)] [tetra-index (in-naturals)])
      (define local-indices (for/list ([corner (in-list tetra)])
                              (vector-ref cube-indices corner)))
      (define local-samples (for/list ([corner (in-list tetra)])
                              (vector-ref cube-samples corner)))
      (define signs (map (lambda (entry) (<= (implicit-sample-value entry) 0)) local-samples))
      (unless (or (andmap values signs) (andmap not signs))
        (define intersections '())
        (for ([pair (in-list tetra-edges)])
          (define first-local (first pair))
          (define second-local (second pair))
          (define first-sample (list-ref local-samples first-local))
          (define second-sample (list-ref local-samples second-local))
          (unless (eq? (<= (implicit-sample-value first-sample) 0)
                       (<= (implicit-sample-value second-sample) 0))
            (set! intersections
                  (cons (add-intersection (list-ref local-indices first-local) first-sample
                                          (list-ref local-indices second-local) second-sample
                                          (vector i j k) tetra-index)
                        intersections))))
        (define polygon (sort (remove-duplicates intersections) <))
        (when (>= (length polygon) 3)
          (define ordered (order-polygon polygon vertices normals))
          (for ([second (in-list (drop-right (rest ordered) 1))]
                [third (in-list (drop (rest ordered) 1))]
                [fan-index (in-naturals)])
            (define triangle (orient-triangle (vector (first ordered) second third) vertices normals))
            (unless (degenerate-triangle? triangle vertices)
              (set! triangles (cons triangle triangles))
              (set! triangle-provenance
                    (cons (hasheq 'kind 'implicit-tetrahedron
                                  'cube (vector i j k) 'tetrahedron tetra-index
                                  'fan-index fan-index)
                          triangle-provenance))))))))
  (for ([entry (in-hash-values cache)])
    (define point (implicit-sample-point entry))
    (when (and (or (= (vec3-x point) xmin) (= (vec3-x point) xmax)
                   (= (vec3-y point) ymin) (= (vec3-y point) ymax)
                   (= (vec3-z point) zmin) (= (vec3-z point) zmax))
               (<= (abs (implicit-sample-value entry)) 1e-9))
      (set! boundary-contact? #t)))
  (define final-vertices (vector->immutable-vector (list->vector (reverse vertices))))
  (define final-normals (vector->immutable-vector (list->vector (reverse normals))))
  (define final-triangles (vector->immutable-vector (list->vector (reverse triangles))))
  (define final-vertex-provenance
    (vector->immutable-vector (list->vector (reverse vertex-provenance))))
  (define final-triangle-provenance
    (vector->immutable-vector (list->vector (reverse triangle-provenance))))
  (define diagnostics-value
    (implicit-surface-diagnostics resolution (* resolution resolution resolution)
                                  (vector-length final-vertices)
                                  (vector-length final-triangles)
                                  boundary-contact?
                                  (if boundary-contact?
                                      '(surface touches extraction boundary)
                                      '())))
  (define diagnostics
    (hasheq 'kind 'implicit
            'implicit diagnostics-value
            'boundary-contact? boundary-contact?))
  (define mesh
    (mesh3d #:id id #:vertices final-vertices #:triangles final-triangles
            #:normals final-normals #:material material
            #:wireframe-color wireframe-color #:wireframe-width wireframe-width))
  (define surface-mesh
    (surface-mesh3d mesh final-vertex-provenance final-triangle-provenance
                    (vector 'implicit bounds resolution level final-triangles)
                    diagnostics))
  (surface3d-from-generated-mesh
   'implicit id surface-mesh #:transform transform #:opacity opacity #:material material
   #:wireframe-color wireframe-color #:wireframe-width wireframe-width
   #:diagnostics diagnostics #:provenance surface-mesh))

(struct implicit-sample (point value) #:transparent)

;; A consistent six-tetrahedra decomposition of every lattice cube.
(define marching-tetrahedra
  '((0 1 3 7) (0 3 2 7) (0 2 6 7) (0 6 4 7) (0 4 5 7) (0 5 1 7)))
(define tetra-edges '((0 1) (0 2) (0 3) (1 2) (1 3) (2 3)))

(define (ordered-index-edge first second)
  (if (index-vector<? first second) (vector first second) (vector second first)))
(define (index-vector<? first second)
  (or (< (vector-ref first 0) (vector-ref second 0))
      (and (= (vector-ref first 0) (vector-ref second 0))
           (or (< (vector-ref first 1) (vector-ref second 1))
               (and (= (vector-ref first 1) (vector-ref second 1))
                    (< (vector-ref first 2) (vector-ref second 2)))))))

(define (vertex-at vertices index)
  ;; vertices are accumulated in reverse ID order.
  (list-ref vertices (- (length vertices) 1 index)))
(define (normal-at normals index)
  (list-ref normals (- (length normals) 1 index)))

;; Orders an intersection polygon around its centre using the averaged gradient
;; as a stable local normal.  The tetrahedron contains at most four points.
(define (order-polygon indices vertices normals)
  (define points (map (lambda (index) (vertex-at vertices index)) indices))
  (define centre (vec3-scale (/ 1 (length points))
                             (for/fold ([sum origin3]) ([point (in-list points)])
                               (vec3+ sum point))))
  (define normal
    (let ([sum (for/fold ([value origin3]) ([index (in-list indices)])
                 (vec3+ value (normal-at normals index)))])
      (if (zero? (vec3-length sum)) z-axis3 (vec3-normalize sum))))
  (define axis
    (let ([candidate (vec3-cross normal x-axis3)])
      (if (< (vec3-length candidate) 1e-8)
          (vec3-normalize (vec3-cross normal y-axis3))
          (vec3-normalize candidate))))
  (define perpendicular (vec3-cross normal axis))
  (sort indices < #:key
        (lambda (index)
          (define offset (vec3- (vertex-at vertices index) centre))
          (define y (vec3-dot offset perpendicular))
          (define x (vec3-dot offset axis))
          ;; A field passing exactly through a grid vertex can make two edge
          ;; intersections coincident.  It will be removed as a degenerate
          ;; triangle later; give its angular sort a deterministic value here.
          (if (and (zero? x) (zero? y)) 0 (atan y x)))))

(define (orient-triangle triangle vertices normals)
  (define first (vertex-at vertices (vector-ref triangle 0)))
  (define second (vertex-at vertices (vector-ref triangle 1)))
  (define third (vertex-at vertices (vector-ref triangle 2)))
  (define face (vec3-cross (vec3- second first) (vec3- third first)))
  (define average
    (vec3+ (normal-at normals (vector-ref triangle 0))
           (vec3+ (normal-at normals (vector-ref triangle 1))
                  (normal-at normals (vector-ref triangle 2)))))
  (if (negative? (vec3-dot face average))
      (vector (vector-ref triangle 0) (vector-ref triangle 2) (vector-ref triangle 1))
      triangle))

(define (degenerate-triangle? triangle vertices)
  (define first (vertex-at vertices (vector-ref triangle 0)))
  (define second (vertex-at vertices (vector-ref triangle 1)))
  (define third (vertex-at vertices (vector-ref triangle 2)))
  (< (vec3-length (vec3-cross (vec3- second first) (vec3- third first))) 1e-10))
