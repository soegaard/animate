#lang racket/base

;;;
;;; Deterministic Adaptive Parametric Surfaces
;;;

;; Sampling is camera-independent. Exact dyadic coordinates, fixed traversal,
;; 2:1-balanced leaves, and transition triangulation make repeated construction
;; produce the same indexed mesh and provenance regardless of hash iteration
;; order.  In particular, one detailed area no longer forces an entire connected
;; surface to its maximum depth merely to remove T-junctions.

(require racket/list
         racket/math
         "../geometry.rkt"
         "dyadic2.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "surface-mesh3d.rkt"
         "surface-provenance3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide (struct-out adaptive-surface-diagnostics)
         adaptive-parametric-surface3d
         adaptive-function-surface3d)

(struct adaptive-surface-diagnostics
  (sample-count cache-hits leaf-count maximum-depth-reached omitted-cell-count
                invalid-samples position-error-maximum normal-error-maximum
                conformity-refinements)
  #:transparent)

(struct adaptive-cell (u0 u1 v0 v1 depth) #:transparent)

; adaptive-parametric-surface3d : procedure? #:id symbol? ... -> surface3d?
;; Constructs a camera-independent adaptive indexed parametric surface.
(define (adaptive-parametric-surface3d procedure
                                       #:u-range [u-range (list -1 1)]
                                       #:v-range [v-range (list -1 1)]
                                       #:id id
                                       #:derivative-u [derivative-u #f]
                                       #:derivative-v [derivative-v #f]
                                       #:position-tolerance [position-tolerance 1e-3]
                                       #:normal-angle-tolerance [normal-angle-tolerance (/ pi 18)]
                                       #:maximum-edge-length [maximum-edge-length +inf.0]
                                       #:minimum-depth [minimum-depth 0]
                                       #:maximum-depth [maximum-depth 8]
                                       #:refine-cell? [refine-cell? #f]
                                       #:on-invalid [on-invalid 'split]
                                       #:material [material (material3d #:color "steelblue" #:shading 'smooth)]
                                       #:transform [transform identity-transform3]
                                       #:opacity [opacity 1]
                                       #:wireframe-color [wireframe-color "steelblue"]
                                       #:wireframe-width [wireframe-width 1])
  (check-constructor-inputs 'adaptive-parametric-surface3d procedure u-range v-range id
                            derivative-u derivative-v position-tolerance
                            normal-angle-tolerance maximum-edge-length
                            minimum-depth maximum-depth refine-cell? on-invalid material transform opacity)
  (define samples (make-hash))
  (define sample-count 0)
  (define cache-hits 0)
  (define invalid-samples '())
  (define position-error-maximum 0.0)
  (define normal-error-maximum 0.0)
  (define max-depth-reached 0)
  (define (parameter coordinate range)
    (+ (first range)
       (* (dyadic-coordinate->real coordinate)
          (- (second range) (first range)))))
  (define (sample-at key)
    (define found (hash-ref samples key #f))
    (cond [found (set! cache-hits (add1 cache-hits)) found]
          [else
           (set! sample-count (add1 sample-count))
           (define u (parameter (uv-key-u key) u-range))
           (define v (parameter (uv-key-v key) v-range))
           (define result
             (with-handlers
                 ([exn? (lambda (exception)
                           (parametric-sample3d key #f #f #f #f 'exception
                                                (exn-message exception)))])
               (define point (procedure u v))
               (cond [(not (and (vec3? point) (vec3-finite? point)))
                      (parametric-sample3d key #f #f #f #f 'non-finite point)]
                     [else
                      (define tangent-u (and derivative-u (derivative-u u v)))
                      (define tangent-v (and derivative-v (derivative-v u v)))
                      (define normal
                        (and (vec3? tangent-u) (vec3? tangent-v)
                             (vec3-finite? tangent-u) (vec3-finite? tangent-v)
                             (let ([cross (vec3-cross tangent-u tangent-v)])
                               (and (positive? (vec3-length cross))
                                    (vec3-normalize cross)))))
                      (parametric-sample3d key point tangent-u tangent-v normal
                                           (if normal 'valid 'degenerate-normal) #f)])))
           (unless (memq (parametric-sample3d-status result) '(valid degenerate-normal))
             (set! invalid-samples (cons result invalid-samples)))
           (hash-set! samples key result)
           result]))
  (define (cell-keys cell)
    (define u0 (adaptive-cell-u0 cell))
    (define u1 (adaptive-cell-u1 cell))
    (define v0 (adaptive-cell-v0 cell))
    (define v1 (adaptive-cell-v1 cell))
    (define um (dyadic-coordinate-midpoint u0 u1))
    (define vm (dyadic-coordinate-midpoint v0 v1))
    (list (uv-key u0 v0) (uv-key u1 v0) (uv-key u1 v1) (uv-key u0 v1)
          (uv-key um v0) (uv-key u1 vm) (uv-key um v1) (uv-key u0 vm)
          (uv-key um vm)))
  (define (cell-samples cell) (for/list ([key (in-list (cell-keys cell))]) (sample-at key)))
  (define (cell-invalid? cell)
    (for/or ([sample (in-list (cell-samples cell))])
      (not (memq (parametric-sample3d-status sample) '(valid degenerate-normal)))))
  (define (cell-error? cell)
    (define samples-list (cell-samples cell))
    (define corners (take samples-list 4))
    (define edge-midpoints (take (drop samples-list 4) 4))
    (define centre (list-ref samples-list 8))
    (define (point sample) (parametric-sample3d-position sample))
    (cond [(ormap (lambda (sample) (not (point sample))) samples-list) #t]
          [else
           (define p00 (point (list-ref corners 0)))
           (define p10 (point (list-ref corners 1)))
           (define p11 (point (list-ref corners 2)))
           (define p01 (point (list-ref corners 3)))
           (define expected
             (list (vec3-lerp p00 p10 1/2)
                   (vec3-lerp p10 p11 1/2)
                   (vec3-lerp p01 p11 1/2)
                   (vec3-lerp p00 p01 1/2)
                   (vec3-lerp (vec3-lerp p00 p10 1/2)
                              (vec3-lerp p01 p11 1/2) 1/2)))
           (define observed (append (map point edge-midpoints) (list (point centre))))
           (define position-error
             (for/fold ([largest 0.0]) ([actual (in-list observed)]
                                         [estimate (in-list expected)])
               (max largest (vec3-distance actual estimate))))
           (set! position-error-maximum (max position-error-maximum position-error))
           (define edge-length
             (apply max (map vec3-distance
                             (list p00 p10 p11 p01)
                             (list p10 p11 p01 p00))))
           (define normals (filter (lambda (normal) normal)
                                   (map parametric-sample3d-normal samples-list)))
           (define normal-error
             (if (< (length normals) 2) 0.0
                 (for*/fold ([largest 0.0]) ([first (in-list normals)]
                                              [second (in-list normals)])
                   (max largest
                        (acos (max -1.0 (min 1.0 (vec3-dot first second))))))))
           (set! normal-error-maximum (max normal-error-maximum normal-error))
           (or (> position-error position-tolerance)
               (> normal-error normal-angle-tolerance)
               (> edge-length maximum-edge-length))]))
  (define (children cell)
    (define um (dyadic-coordinate-midpoint (adaptive-cell-u0 cell) (adaptive-cell-u1 cell)))
    (define vm (dyadic-coordinate-midpoint (adaptive-cell-v0 cell) (adaptive-cell-v1 cell)))
    (define depth (add1 (adaptive-cell-depth cell)))
    ;; Canonical SW, SE, NW, NE order.
    (list (adaptive-cell (adaptive-cell-u0 cell) um (adaptive-cell-v0 cell) vm depth)
          (adaptive-cell um (adaptive-cell-u1 cell) (adaptive-cell-v0 cell) vm depth)
          (adaptive-cell (adaptive-cell-u0 cell) um vm (adaptive-cell-v1 cell) depth)
          (adaptive-cell um (adaptive-cell-u1 cell) vm (adaptive-cell-v1 cell) depth)))
  ;; A producer with topology constraints (currently the trim producer) may
  ;; request a split from its own camera-independent cell samples.  Keeping
  ;; this hook here lets that producer share the exact dyadic tree, balancing,
  ;; and transition-triangle machinery instead of growing a second lattice.
  ;; Its five arguments are the real parameter bounds and the current depth.
  (define (requested-refinement? cell)
    (and refine-cell?
         (let ([answer
                (refine-cell?
                 (parameter (adaptive-cell-u0 cell) u-range)
                 (parameter (adaptive-cell-u1 cell) u-range)
                 (parameter (adaptive-cell-v0 cell) v-range)
                 (parameter (adaptive-cell-v1 cell) v-range)
                 (adaptive-cell-depth cell))])
           (unless (boolean? answer)
             (raise-arguments-error
              'adaptive-parametric-surface3d
              "a boolean from #:refine-cell?"
              "cell" cell
              "result" answer))
           answer)))
  (define omitted '())
  (define (refine cell)
    (set! max-depth-reached (max max-depth-reached (adaptive-cell-depth cell)))
    (cond [(cell-invalid? cell)
           (case on-invalid
             [(error)
              (define bad
                (for/first ([sample (in-list (cell-samples cell))]
                            #:unless (memq (parametric-sample3d-status sample)
                                           '(valid degenerate-normal)))
                  sample))
              (raise-arguments-error 'adaptive-parametric-surface3d
                                     "a finite parameterization sample"
                                     "uv" (and bad (parametric-sample3d-uv bad))
                                     "diagnostic" (and bad (parametric-sample3d-diagnostic bad)))]
             [(omit)
              (set! omitted (cons cell omitted))
              '()]
             [else
              (if (< (adaptive-cell-depth cell) maximum-depth)
                  (append-map refine (children cell))
                  (begin (set! omitted (cons cell omitted)) '()))])]
          [(or (< (adaptive-cell-depth cell) minimum-depth)
               (and (< (adaptive-cell-depth cell) maximum-depth)
                    (or (cell-error? cell) (requested-refinement? cell))))
           (append-map refine (children cell))]
          [else (list cell)]))
  (define root
    (adaptive-cell (dyadic-coordinate 0 0) (dyadic-coordinate 1 0)
                   (dyadic-coordinate 0 0) (dyadic-coordinate 1 0) 0))
  (define initial-leaves (refine root))
  ;; Balance only violations greater than one level.  A side-indexed lookup
  ;; avoids the old all-leaf-pairs scan, and the later transition fan fills the
  ;; resulting one-level T-junctions without globally over-refining.
  (define-values (leaves conformity-refinements)
    (balance-2:1-leaves initial-leaves children))
  (for ([leaf (in-list leaves)])
    (set! max-depth-reached (max max-depth-reached (adaptive-cell-depth leaf))))
  (define-values (vertices triangles vertex-provenance triangle-provenance)
    (leaves->mesh-data leaves sample-at))
  (define mesh-without-normals
    (mesh3d #:id id #:vertices vertices #:triangles triangles #:material material
            #:wireframe-color wireframe-color #:wireframe-width wireframe-width))
  (define final-mesh
    (mesh3d #:id id #:vertices vertices #:triangles triangles
            #:normals (mesh-vertex-normals mesh-without-normals)
            #:material material #:wireframe-color wireframe-color
            #:wireframe-width wireframe-width))
  (define diagnostics
    (adaptive-surface-diagnostics
     sample-count cache-hits (length leaves) max-depth-reached (length omitted)
     (vector->immutable-vector (list->vector (reverse invalid-samples)))
     position-error-maximum normal-error-maximum conformity-refinements))
  (define topology-key
    (vector 'adaptive-parametric
            (for/vector ([cell (in-list leaves)]) cell)
            triangles vertex-provenance triangle-provenance))
  (surface3d-from-generated-mesh
   'adaptive-parametric id
   (surface-mesh3d final-mesh vertex-provenance triangle-provenance topology-key diagnostics)
   #:transform transform #:opacity opacity #:material material
   #:wireframe-color wireframe-color #:wireframe-width wireframe-width
   #:evaluator procedure #:u-range u-range #:v-range v-range
   #:diagnostics diagnostics))

; adaptive-function-surface3d : procedure? #:id symbol? ... -> surface3d?
;; Convenience graph-surface spelling retaining the same adaptive semantics.
(define (adaptive-function-surface3d function
                                     #:x-range [x-range (list -1 1)]
                                     #:y-range [y-range (list -1 1)]
                                     #:id id
                                     #:derivative-x [derivative-x #f]
                                     #:derivative-y [derivative-y #f]
                                     #:position-tolerance [position-tolerance 1e-3]
                                     #:normal-angle-tolerance [normal-angle-tolerance (/ pi 18)]
                                     #:maximum-edge-length [maximum-edge-length +inf.0]
                                     #:minimum-depth [minimum-depth 0]
                                     #:maximum-depth [maximum-depth 8]
                                     #:refine-cell? [refine-cell? #f]
                                     #:on-invalid [on-invalid 'split]
                                     #:material [material (material3d #:color "steelblue" #:shading 'smooth)]
                                     #:transform [transform identity-transform3]
                                     #:opacity [opacity 1]
                                     #:wireframe-color [wireframe-color "steelblue"]
                                     #:wireframe-width [wireframe-width 1])
  (unless (procedure? function)
    (raise-argument-error 'adaptive-function-surface3d "procedure?" function))
  (adaptive-parametric-surface3d
   (lambda (x y)
     (define z (function x y))
     (unless (finite-real? z)
       (raise-arguments-error 'adaptive-function-surface3d "a finite height"
                              "x" x "y" y "result" z))
     (vec3 x y z))
   #:u-range x-range #:v-range y-range #:id id
   #:derivative-u (and derivative-x (lambda (x y) (vec3 1 0 (derivative-x x y))))
   #:derivative-v (and derivative-y (lambda (x y) (vec3 0 1 (derivative-y x y))))
   #:position-tolerance position-tolerance
   #:normal-angle-tolerance normal-angle-tolerance
   #:maximum-edge-length maximum-edge-length
   #:minimum-depth minimum-depth #:maximum-depth maximum-depth
   #:refine-cell? refine-cell?
   #:on-invalid on-invalid #:material material #:transform transform #:opacity opacity
   #:wireframe-color wireframe-color #:wireframe-width wireframe-width))

(define (check-constructor-inputs who procedure u-range v-range id derivative-u derivative-v
                                  position-tolerance normal-angle-tolerance maximum-edge-length
                                  minimum-depth maximum-depth refine-cell? on-invalid material transform opacity)
  (unless (procedure? procedure) (raise-argument-error who "procedure?" procedure))
  (unless (symbol? id) (raise-argument-error who "symbol?" id))
  (for ([range (in-list (list u-range v-range))])
    (unless (and (list? range) (= (length range) 2) (andmap finite-real? range)
                 (< (first range) (second range)))
      (raise-argument-error who "ascending two-finite-real range" range)))
  (for ([value (in-list (list derivative-u derivative-v))])
    (unless (or (not value) (procedure? value))
      (raise-argument-error who "(or/c #f procedure?)" value)))
  (unless (and (finite-real? position-tolerance) (positive? position-tolerance))
    (raise-argument-error who "positive finite position tolerance" position-tolerance))
  (unless (and (finite-real? normal-angle-tolerance) (positive? normal-angle-tolerance))
    (raise-argument-error who "positive finite normal angle tolerance" normal-angle-tolerance))
  (unless (and (real? maximum-edge-length) (positive? maximum-edge-length))
    (raise-argument-error who "positive real maximum edge length" maximum-edge-length))
  (unless (and (exact-nonnegative-integer? minimum-depth)
               (exact-nonnegative-integer? maximum-depth)
               (<= minimum-depth maximum-depth))
    (raise-argument-error who "ordered exact nonnegative depths"
                          (list minimum-depth maximum-depth)))
  (unless (or (not refine-cell?) (procedure-arity-includes? refine-cell? 5))
    (raise-argument-error who "(or/c #f (procedure-arity-includes/c 5))" refine-cell?))
  (unless (memq on-invalid '(error omit split))
    (raise-argument-error who "(or/c 'error 'omit 'split)" on-invalid))
  (unless (material3d? material) (raise-argument-error who "material3d?" material))
  (unless (transform3? transform) (raise-argument-error who "transform3?" transform))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error who "finite opacity in [0, 1]" opacity)))

;; The side index is deliberately keyed by exact dyadic line coordinates.  A
;; lookup inspects only leaves meeting one line, not every leaf in the surface.
(define (cells->side-index cells)
  (define index (make-hash))
  (define (add! orientation coordinate cell)
    (hash-update! index
                  (list orientation (dyadic-coordinate->real coordinate))
                  (lambda (previous) (cons cell previous))
                  '()))
  (for ([cell (in-list cells)])
    (add! 'vertical (adaptive-cell-u0 cell) cell)
    (add! 'vertical (adaptive-cell-u1 cell) cell)
    (add! 'horizontal (adaptive-cell-v0 cell) cell)
    (add! 'horizontal (adaptive-cell-v1 cell) cell))
  index)

(define (cell-side-neighbours cell orientation coordinate side-index)
  (filter (lambda (candidate)
            (and (not (eq? cell candidate))
                 (cells-share-side? cell candidate)))
          (hash-ref side-index
                    (list orientation (dyadic-coordinate->real coordinate))
                    '())))

(define (first-unbalanced-pair cells side-index)
  (for*/first
      ([cell (in-list cells)]
       [candidate (in-list
                   (append
                    (cell-side-neighbours cell 'vertical (adaptive-cell-u0 cell) side-index)
                    (cell-side-neighbours cell 'vertical (adaptive-cell-u1 cell) side-index)
                    (cell-side-neighbours cell 'horizontal (adaptive-cell-v0 cell) side-index)
                    (cell-side-neighbours cell 'horizontal (adaptive-cell-v1 cell) side-index)))]
       #:when (> (abs (- (adaptive-cell-depth cell) (adaptive-cell-depth candidate))) 1))
    (cons cell candidate)))

(define (balance-2:1-leaves cells children)
  ;; Split every currently-visible coarse violation in one deterministic
  ;; round. The earlier one-pair-at-a-time loop was correct but made a long
  ;; trim boundary rebuild the side index hundreds of times at depth 8.
  ;; A round may reveal the next one-ring violation, so repeat to a fixed
  ;; point; each round still preserves source traversal order.
  (let loop ([current cells] [refinements 0])
    (define side-index (cells->side-index current))
    (define coarser-set (make-hash))
    (for ([cell (in-list current)])
      (for ([candidate (in-list
                       (append
                        (cell-side-neighbours cell 'vertical (adaptive-cell-u0 cell) side-index)
                        (cell-side-neighbours cell 'vertical (adaptive-cell-u1 cell) side-index)
                        (cell-side-neighbours cell 'horizontal (adaptive-cell-v0 cell) side-index)
                        (cell-side-neighbours cell 'horizontal (adaptive-cell-v1 cell) side-index)))])
        (when (> (abs (- (adaptive-cell-depth cell) (adaptive-cell-depth candidate))) 1)
          (hash-set! coarser-set
                     (if (< (adaptive-cell-depth cell) (adaptive-cell-depth candidate))
                         cell candidate)
                     #t))))
    (if (zero? (hash-count coarser-set))
        (values current refinements)
        (loop
         (append-map (lambda (cell)
                       (if (hash-has-key? coarser-set cell)
                           (children cell)
                           (list cell)))
                     current)
         (+ refinements (hash-count coarser-set))))))

(define (cells-share-side? first second)
  (define (same coordinate-a coordinate-b)
    (zero? (dyadic-coordinate-compare coordinate-a coordinate-b)))
  (define (overlap? low-a high-a low-b high-b)
    (< (max (dyadic-coordinate->real low-a) (dyadic-coordinate->real low-b))
       (min (dyadic-coordinate->real high-a) (dyadic-coordinate->real high-b))))
  (or (and (or (same (adaptive-cell-u1 first) (adaptive-cell-u0 second))
               (same (adaptive-cell-u0 first) (adaptive-cell-u1 second)))
           (overlap? (adaptive-cell-v0 first) (adaptive-cell-v1 first)
                     (adaptive-cell-v0 second) (adaptive-cell-v1 second)))
      (and (or (same (adaptive-cell-v1 first) (adaptive-cell-v0 second))
               (same (adaptive-cell-v0 first) (adaptive-cell-v1 second)))
           (overlap? (adaptive-cell-u0 first) (adaptive-cell-u1 first)
                     (adaptive-cell-u0 second) (adaptive-cell-u1 second)))))

(define (leaves->mesh-data leaves sample-at)
  (define side-index (cells->side-index leaves))
  (define ids (make-hash))
  (define vertices '())
  (define provenance '())
  (define triangles '())
  (define triangle-provenance '())
  (define next-id 0)
  (define (vertex-id key)
    (hash-ref! ids key
               (lambda ()
                 (define sample (sample-at key))
                 (unless (parametric-sample3d-position sample)
                   (error 'adaptive-parametric-surface3d
                          "a conforming leaf retained an invalid corner sample"))
                 (define result next-id)
                 (set! next-id (add1 next-id))
                 (set! vertices (cons (parametric-sample3d-position sample) vertices))
                 (set! provenance (cons sample provenance))
                 result)))
  (for ([cell (in-list leaves)])
    (define u0 (adaptive-cell-u0 cell))
    (define u1 (adaptive-cell-u1 cell))
    (define v0 (adaptive-cell-v0 cell))
    (define v1 (adaptive-cell-v1 cell))
    (define um (dyadic-coordinate-midpoint u0 u1))
    (define vm (dyadic-coordinate-midpoint v0 v1))
    (define (finer? orientation coordinate)
      (for/or ([neighbour (in-list (cell-side-neighbours
                                    cell orientation coordinate side-index))])
        (> (adaptive-cell-depth neighbour) (adaptive-cell-depth cell))))
    (define split-bottom? (finer? 'horizontal v0))
    (define split-right? (finer? 'vertical u1))
    (define split-top? (finer? 'horizontal v1))
    (define split-left? (finer? 'vertical u0))
    (define corner-keys
      (list (uv-key u0 v0) (uv-key u1 v0) (uv-key u1 v1) (uv-key u0 v1)))
    (define indices (map vertex-id corner-keys))
    (cond
      [(or split-bottom? split-right? split-top? split-left?)
       ;; Traverse the cell boundary counter-clockwise. A one-level-finer
       ;; neighbour contributes exactly the dyadic midpoint on the shared
       ;; side; a centre fan is a small deterministic transition template for
       ;; every possible subset of split sides.
       (define boundary-keys
         (append (list (first corner-keys))
                 (if split-bottom? (list (uv-key um v0)) '())
                 (list (second corner-keys))
                 (if split-right? (list (uv-key u1 vm)) '())
                 (list (third corner-keys))
                 (if split-top? (list (uv-key um v1)) '())
                 (list (fourth corner-keys))
                 (if split-left? (list (uv-key u0 vm)) '())))
       (define boundary (map vertex-id boundary-keys))
       (define centre (vertex-id (uv-key um vm)))
       (for ([first (in-list boundary)]
             [second (in-list (append (rest boundary) (list (first boundary))))]
             [fan-index (in-naturals)])
         (set! triangles (cons (vector centre first second) triangles))
         (set! triangle-provenance
               (cons (hasheq 'cell cell
                             'transition-sides
                             (list split-bottom? split-right? split-top? split-left?)
                             'triangle-in-cell fan-index)
                     triangle-provenance)))]
      [else
       (define parity
         (modulo (+ (dyadic-coordinate-numerator u0)
                    (dyadic-coordinate-numerator v0)
                    (adaptive-cell-depth cell))
                 2))
       (define local-triangles
         (if (zero? parity)
             (list (vector (first indices) (second indices) (third indices))
                   (vector (first indices) (third indices) (fourth indices)))
             (list (vector (first indices) (second indices) (fourth indices))
                   (vector (second indices) (third indices) (fourth indices)))))
       (for ([triangle (in-list local-triangles)] [diagonal-index (in-naturals)])
         (set! triangles (cons triangle triangles))
         (set! triangle-provenance
               (cons (hasheq 'cell cell 'diagonal parity 'triangle-in-cell diagonal-index)
                     triangle-provenance)))]))
  (values (vector->immutable-vector (list->vector (reverse vertices)))
          (vector->immutable-vector (list->vector (reverse triangles)))
          (vector->immutable-vector (list->vector (reverse provenance)))
          (vector->immutable-vector (list->vector (reverse triangle-provenance)))))

(define (mesh-vertex-normals mesh)
  (define sums (make-vector (vector-length (mesh3d-vertices mesh)) origin3))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define first (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 0)))
    (define second (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 1)))
    (define third (vector-ref (mesh3d-vertices mesh) (vector-ref triangle 2)))
    (define normal (vec3-cross (vec3- second first) (vec3- third first)))
    (for ([index (in-vector triangle)])
      (vector-set! sums index (vec3+ (vector-ref sums index) normal))))
  (vector->immutable-vector
   (for/vector ([normal (in-vector sums)])
     (if (zero? (vec3-length normal)) z-axis3 (vec3-normalize normal)))))
