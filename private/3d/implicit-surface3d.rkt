#lang racket/base

;;;
;;; Deterministic Implicit-Surface Extraction
;;;

;; The extractor deliberately uses a fixed marching-tetrahedra decomposition
;; rather than a backend-dependent isosurface helper.  Grid vertices, cube
;; order, tetrahedron order, and shared edge keys are all deterministic.

(require racket/list
         (only-in "../color-token.rkt" theme-surface theme-surface-edge)
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
  (resolution cube-count vertex-count triangle-count boundary-contact?
              invalid-sample-count warnings)
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
                            #:material [material (material3d #:color theme-surface #:shading 'smooth)]
                            #:transform [transform identity-transform3]
                            #:opacity [opacity 1]
                            #:wireframe-color [wireframe-color theme-surface-edge]
                            #:wireframe-width [wireframe-width 1]
                            #:normal-step [normal-step #f]
                            #:gradient [gradient #f]
                            #:iso-tolerance [iso-tolerance 1e-12]
                            #:invalid-subdivision-depth [invalid-subdivision-depth 2]
                            #:on-invalid [on-invalid 'error])
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
  (unless (or (not gradient) (procedure? gradient))
    (raise-argument-error 'implicit-surface3d "(or/c #f procedure?) as #:gradient" gradient))
  (unless (and (finite-real? iso-tolerance) (positive? iso-tolerance))
    (raise-argument-error 'implicit-surface3d "positive finite #:iso-tolerance" iso-tolerance))
  (unless (memq on-invalid '(error skip-cell subdivide))
    (raise-argument-error 'implicit-surface3d
                          "(or/c 'error 'skip-cell 'subdivide) as #:on-invalid" on-invalid))
  (unless (exact-nonnegative-integer? invalid-subdivision-depth)
    (raise-argument-error 'implicit-surface3d
                          "exact-nonnegative-integer? as #:invalid-subdivision-depth"
                          invalid-subdivision-depth))
  (define xmin (first bounds)) (define xmax (second bounds))
  (define ymin (third bounds)) (define ymax (fourth bounds))
  (define zmin (fifth bounds)) (define zmax (sixth bounds))
  (define h (or normal-step
                (/ (min (- xmax xmin) (- ymax ymin) (- zmax zmin))
                   (* 16 resolution))))
  (unless (and (finite-real? h) (positive? h))
    (raise-argument-error 'implicit-surface3d "positive finite #:normal-step" h))
  (define cache (make-hash))
  (define invalid-sample-count 0)
  (define invalid-warning? #f)
  (define invalid-subdivision-count 0)
  (define unresolved-invalid-cell-count 0)
  (define (invalid-sample point reason)
    (case on-invalid
      [(error)
       (raise-arguments-error 'implicit-surface3d "a total finite scalar field"
                              "point" point "reason" reason)]
      [else
       (set! invalid-sample-count (add1 invalid-sample-count))
       (set! invalid-warning? #t)
       (implicit-sample point #f)]))
  ;; Grid coordinates are exact rationals in [0,resolution].  Base cells use
  ;; integers; locally subdivided invalid cells use dyadics.  One coordinate
  ;; representation and cache therefore keeps an interface edge identical on
  ;; either side of a subdivision boundary.
  (define (sample index)
    (hash-ref! cache index
               (lambda ()
                 (define point
                   (vec3 (+ xmin (* (/ (vector-ref index 0) resolution) (- xmax xmin)))
                         (+ ymin (* (/ (vector-ref index 1) resolution) (- ymax ymin)))
                         (+ zmin (* (/ (vector-ref index 2) resolution) (- zmax zmin)))))
                 (define value
                   (with-handlers ([exn:fail?
                                    (lambda (exception)
                                      (invalid-sample point (exn-message exception)))])
                     (field point)))
                 (cond [(implicit-sample? value) value]
                       [(finite-real? value) (implicit-sample point (- value level))]
                       [else (invalid-sample point value)]))))
  (define vertices '())
  (define normals '())
  ;; O(1) lookup tables used while ordering one tetrahedron's intersections.
  ;; The output builders below remain append-only lists frozen at the end.
  (define point-by-id (make-hash))
  (define normal-by-id (make-hash))
  (define vertex-provenance '())
  (define triangles '())
  (define triangle-provenance '())
  (define vertex-ids (make-hash))
  (define next-id 0)
  (define boundary-contact? #f)
  (define (valid-sample? entry) (finite-real? (implicit-sample-value entry)))
  (define (exact-iso? entry)
    (and (valid-sample? entry)
         (<= (abs (implicit-sample-value entry)) iso-tolerance)))
  ;; A zero lattice sample belongs deterministically to one sign class. The
  ;; parity rule is independent of tetrahedron order and removes ambiguous
  ;; exact-iso cases without perturbing the reported field value.
  (define (sample-negative? entry index)
    (cond [(not (valid-sample? entry)) #f]
          [(exact-iso? entry)
           ;; Exact coordinates can be integers or reduced dyadics after an
           ;; invalid-cell subdivision.  Their numerators give one canonical,
           ;; traversal-independent symbolic side assignment.
           (even? (+ (numerator (vector-ref index 0))
                     (numerator (vector-ref index 1))
                     (numerator (vector-ref index 2))))]
          [else (negative? (implicit-sample-value entry))]))
  (define (boundary-grid-edge? first-index second-index)
    (or (and (= (vector-ref first-index 0) 0) (= (vector-ref second-index 0) 0))
        (and (= (vector-ref first-index 0) resolution)
             (= (vector-ref second-index 0) resolution))
        (and (= (vector-ref first-index 1) 0) (= (vector-ref second-index 1) 0))
        (and (= (vector-ref first-index 1) resolution)
             (= (vector-ref second-index 1) resolution))
        (and (= (vector-ref first-index 2) 0) (= (vector-ref second-index 2) 0))
        (and (= (vector-ref first-index 2) resolution)
             (= (vector-ref second-index 2) resolution))))
  (define (checked-field-value point)
    (define result
      (with-handlers ([exn:fail? (lambda (_exception) #f)]) (field point)))
    (if (finite-real? result)
        result
        (case on-invalid
          [(error)
           (raise-arguments-error 'implicit-surface3d "a finite field value while computing a normal"
                                  "point" point "result" result)]
          [else #f])))
  (define (normal-at-point point)
    (define candidate
      (cond [gradient
             (define supplied
               (with-handlers ([exn:fail? (lambda (_exception) #f)])
                 (gradient point)))
             (unless (and (vec3? supplied) (vec3-finite? supplied))
               (raise-arguments-error 'implicit-surface3d
                                      "a finite vec3 result from #:gradient"
                                      "point" point "result" supplied))
             supplied]
            [else
             ;; Use central differences in the interior and bounded one-sided
             ;; differences at a box face. No normal probe may escape the
             ;; declared extraction bounds.
             (define centre (checked-field-value point))
             (define (axis-difference coordinate low high delta)
               (define forward (min h (- high coordinate)))
               (define backward (min h (- coordinate low)))
               (define (at amount) (checked-field-value (vec3+ point (vec3-scale amount delta))))
               (cond [(and (positive? forward) (positive? backward))
                      (define plus (at forward))
                      (define minus (at (- backward)))
                      (and plus minus (/ (- plus minus) (+ forward backward)))]
                     [(positive? forward)
                      (define plus (at forward))
                      (and centre plus (/ (- plus centre) forward))]
                     [(positive? backward)
                      (define minus (at (- backward)))
                      (and centre minus (/ (- centre minus) backward))]
                     [else 0]))
             (vec3 (or (axis-difference (vec3-x point) xmin xmax x-axis3) 0)
                   (or (axis-difference (vec3-y point) ymin ymax y-axis3) 0)
                   (or (axis-difference (vec3-z point) zmin zmax z-axis3) 0))]))
    (if (zero? (vec3-length candidate)) z-axis3 (vec3-normalize candidate)))
  (define (add-intersection first-index first second-index second cube-index tetra-index)
    (define edge-key
      (cond [(exact-iso? first) (vector 'grid-vertex first-index)]
            [(exact-iso? second) (vector 'grid-vertex second-index)]
            [else (ordered-index-edge first-index second-index)]))
    (hash-ref! vertex-ids edge-key
               (lambda ()
                 (define a (implicit-sample-value first))
                 (define b (implicit-sample-value second))
                 (define fraction
                   (cond [(exact-iso? first) 0]
                         [(exact-iso? second) 1]
                         [else
                          (let ([denominator (- a b)])
                            (if (zero? denominator) 1/2
                                (max 0 (min 1 (/ a denominator)))))]))
                 (define point (vec3-lerp (implicit-sample-point first)
                                          (implicit-sample-point second) fraction))
                 (define index next-id)
                 (set! next-id (add1 next-id))
                 (define normal (normal-at-point point))
                 (set! vertices (cons point vertices))
                 (set! normals (cons normal normals))
                 (hash-set! point-by-id index point)
                 (hash-set! normal-by-id index normal)
                 (set! vertex-provenance
                       (cons (hasheq 'kind 'implicit-edge
                                     'grid-edge edge-key
                                     'fraction fraction
                                     'cube cube-index
                                     'tetrahedron tetra-index)
                             vertex-provenance))
                 (when (boundary-grid-edge? first-index second-index)
                   (set! boundary-contact? #t))
                 index)))
  (define (cube-from-bounds x0 x1 y0 y1 z0 z1)
    (vector (vector x0 y0 z0) (vector x1 y0 z0)
            (vector x0 y1 z0) (vector x1 y1 z0)
            (vector x0 y0 z1) (vector x1 y0 z1)
            (vector x0 y1 z1) (vector x1 y1 z1)))
  (define (cube-values cube-indices)
    (for/vector ([index (in-vector cube-indices)]) (sample index)))
  (define (emit-cube cube-indices cube-samples cube-label)
    (for ([tetra (in-list marching-tetrahedra)] [tetra-index (in-naturals)])
      (define local-indices
        (for/list ([corner (in-list tetra)]) (vector-ref cube-indices corner)))
      (define local-samples
        (for/list ([corner (in-list tetra)]) (vector-ref cube-samples corner)))
      (define signs (map sample-negative? local-samples local-indices))
      (unless (or (andmap values signs) (andmap not signs))
        (define intersections '())
        (for ([pair (in-list tetra-edges)])
          (define first-local (first pair))
          (define second-local (second pair))
          (define first-sample (list-ref local-samples first-local))
          (define second-sample (list-ref local-samples second-local))
          (unless (eq? (sample-negative? first-sample (list-ref local-indices first-local))
                       (sample-negative? second-sample (list-ref local-indices second-local)))
            (set! intersections
                  (cons (add-intersection (list-ref local-indices first-local) first-sample
                                          (list-ref local-indices second-local) second-sample
                                          cube-label tetra-index)
                        intersections))))
        (define polygon (sort (remove-duplicates intersections) <))
        (when (>= (length polygon) 3)
          (define ordered (order-polygon polygon point-by-id normal-by-id))
          (for ([second (in-list (drop-right (rest ordered) 1))]
                [third (in-list (drop (rest ordered) 1))]
                [fan-index (in-naturals)])
            (define triangle (orient-triangle (vector (first ordered) second third)
                                             point-by-id normal-by-id))
            (unless (degenerate-triangle? triangle point-by-id)
              (set! triangles (cons triangle triangles))
              (set! triangle-provenance
                    (cons (hasheq 'kind 'implicit-tetrahedron
                                  'cube cube-label 'tetrahedron tetra-index
                                  'fan-index fan-index)
                          triangle-provenance))))))))
  (define (process-cube cube-indices depth)
    (define values (cube-values cube-indices))
    (cond [(andmap valid-sample? (vector->list values))
           (emit-cube cube-indices values
                      (vector 'implicit-cell depth (vector-ref cube-indices 0)
                              (vector-ref cube-indices 7)))]
          [(and (eq? on-invalid 'subdivide)
                (< depth invalid-subdivision-depth))
           (set! invalid-subdivision-count (add1 invalid-subdivision-count))
           (define first-index (vector-ref cube-indices 0))
           (define last-index (vector-ref cube-indices 7))
           (define x0 (vector-ref first-index 0))
           (define y0 (vector-ref first-index 1))
           (define z0 (vector-ref first-index 2))
           (define x1 (vector-ref last-index 0))
           (define y1 (vector-ref last-index 1))
           (define z1 (vector-ref last-index 2))
           (define xm (/ (+ x0 x1) 2))
           (define ym (/ (+ y0 y1) 2))
           (define zm (/ (+ z0 z1) 2))
           (for* ([x-pair (in-list (list (cons x0 xm) (cons xm x1)))]
                  [y-pair (in-list (list (cons y0 ym) (cons ym y1)))]
                  [z-pair (in-list (list (cons z0 zm) (cons zm z1)))])
             (process-cube
              (cube-from-bounds (car x-pair) (cdr x-pair)
                                (car y-pair) (cdr y-pair)
                                (car z-pair) (cdr z-pair))
              (add1 depth)))]
          [else
           (set! unresolved-invalid-cell-count
                 (add1 unresolved-invalid-cell-count))]))
  (for* ([i (in-range resolution)] [j (in-range resolution)] [k (in-range resolution)])
    (process-cube
     (cube-from-bounds i (add1 i) j (add1 j) k (add1 k))
     0))
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
                                  invalid-sample-count
                                  (append (if boundary-contact?
                                              '(surface touches extraction boundary)
                                              '())
                                          (if invalid-warning?
                                              (if (eq? on-invalid 'subdivide)
                                                  '(invalid field samples subdivided)
                                                  '(invalid field samples skipped))
                                              '())
                                          (if (positive? unresolved-invalid-cell-count)
                                              '(invalid cells remained after bounded subdivision)
                                              '()))))
  (define diagnostics
    (hasheq 'kind 'implicit
            'implicit diagnostics-value
            'boundary-contact? boundary-contact?
            'invalid-sample-count invalid-sample-count
            'invalid-subdivision-count invalid-subdivision-count
            'unresolved-invalid-cell-count unresolved-invalid-cell-count
            'invalid-subdivision-depth invalid-subdivision-depth
            'on-invalid on-invalid
            'iso-tolerance iso-tolerance))
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

;; Orders an intersection polygon around its centre using the averaged gradient
;; as a stable local normal.  The tetrahedron contains at most four points.
(define (order-polygon indices point-by-id normal-by-id)
  (define (point-at index) (hash-ref point-by-id index))
  (define (normal-at index) (hash-ref normal-by-id index))
  (define points (map point-at indices))
  (define centre (vec3-scale (/ 1 (length points))
                             (for/fold ([sum origin3]) ([point (in-list points)])
                               (vec3+ sum point))))
  (define normal
    (let ([sum (for/fold ([value origin3]) ([index (in-list indices)])
                 (vec3+ value (normal-at index)))])
      (if (zero? (vec3-length sum)) z-axis3 (vec3-normalize sum))))
  (define axis
    (let ([candidate (vec3-cross normal x-axis3)])
      (if (< (vec3-length candidate) 1e-8)
          (vec3-normalize (vec3-cross normal y-axis3))
          (vec3-normalize candidate))))
  (define perpendicular (vec3-cross normal axis))
  (sort indices < #:key
        (lambda (index)
          (define offset (vec3- (point-at index) centre))
          (define y (vec3-dot offset perpendicular))
          (define x (vec3-dot offset axis))
          ;; A field passing exactly through a grid vertex can make two edge
          ;; intersections coincident.  It will be removed as a degenerate
          ;; triangle later; give its angular sort a deterministic value here.
          (if (and (zero? x) (zero? y)) 0 (atan y x)))))

(define (orient-triangle triangle point-by-id normal-by-id)
  (define (point-at index) (hash-ref point-by-id index))
  (define (normal-at index) (hash-ref normal-by-id index))
  (define first (point-at (vector-ref triangle 0)))
  (define second (point-at (vector-ref triangle 1)))
  (define third (point-at (vector-ref triangle 2)))
  (define face (vec3-cross (vec3- second first) (vec3- third first)))
  (define average
    (vec3+ (normal-at (vector-ref triangle 0))
           (vec3+ (normal-at (vector-ref triangle 1))
                  (normal-at (vector-ref triangle 2)))))
  (if (negative? (vec3-dot face average))
      (vector (vector-ref triangle 0) (vector-ref triangle 2) (vector-ref triangle 1))
      triangle))

(define (degenerate-triangle? triangle point-by-id)
  (define first (hash-ref point-by-id (vector-ref triangle 0)))
  (define second (hash-ref point-by-id (vector-ref triangle 1)))
  (define third (hash-ref point-by-id (vector-ref triangle 2)))
  (< (vec3-length (vec3-cross (vec3- second first) (vec3- third first))) 1e-10))
