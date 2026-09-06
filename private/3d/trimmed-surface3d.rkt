#lang racket/base

;;;
;;; Deterministic Trimmed Parametric Surfaces
;;;

;; Trims operate in parameter space after camera-independent adaptive sampling.
;; Every shared source edge uses one canonical trim intersection key, avoiding
;; cracks while keeping the evaluator and retained domain explicit.

(require racket/list
         racket/math
         "../geometry.rkt"
         "adaptive-surface3d.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "parametric-surface3d.rkt"
         "surface-mesh3d.rkt"
         "surface-provenance3d.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide surface-trim
         surface-trim?
         surface-trim-field
         surface-trim-keep
         surface-trim-id
         surface-trim-tolerance
         trimmed-parametric-surface3d)

(struct surface-trim-value (field keep id tolerance) #:transparent)
(define surface-trim? surface-trim-value?)
(define surface-trim-field surface-trim-value-field)
(define surface-trim-keep surface-trim-value-keep)
(define surface-trim-id surface-trim-value-id)
(define surface-trim-tolerance surface-trim-value-tolerance)

; surface-trim : procedure? [#:keep 'positive] #:id symbol? ... -> surface-trim?
;; Describes one signed parameter-space boundary; retained values have the
;; requested sign. Boolean trims are intentionally not implicit here because
;; their boundary cannot be shared exactly.
(define (surface-trim field #:keep [keep 'positive] #:id [id 'trim-0]
                      #:tolerance [tolerance 1e-8])
  (unless (procedure? field) (raise-argument-error 'surface-trim "procedure?" field))
  (unless (memq keep '(positive negative))
    (raise-argument-error 'surface-trim "(or/c 'positive 'negative)" keep))
  (unless (symbol? id) (raise-argument-error 'surface-trim "symbol?" id))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'surface-trim "positive finite tolerance" tolerance))
  (surface-trim-value field keep id tolerance))

; trimmed-parametric-surface3d : procedure? #:trims (listof surface-trim?) ... -> surface3d?
;; Builds an adaptive mesh and clips every retained cell deterministically in UV.
(define (trimmed-parametric-surface3d procedure
                                      #:u-range [u-range (list -1 1)]
                                      #:v-range [v-range (list -1 1)]
                                      #:trims trims
                                      #:id id
                                      #:derivative-u [derivative-u #f]
                                      #:derivative-v [derivative-v #f]
                                      #:position-tolerance [position-tolerance 1e-3]
                                      #:normal-angle-tolerance [normal-angle-tolerance (/ pi 18)]
                                      #:maximum-edge-length [maximum-edge-length +inf.0]
                                      #:minimum-depth [minimum-depth 0]
                                      #:maximum-depth [maximum-depth 8]
                                      #:on-invalid [on-invalid 'split]
                                      #:material [material (material3d #:color "steelblue" #:shading 'smooth)]
                                      #:transform [transform identity-transform3]
                                      #:opacity [opacity 1]
                                      #:wireframe-color [wireframe-color "steelblue"]
                                      #:wireframe-width [wireframe-width 1])
  (unless (and (list? trims) (andmap surface-trim? trims))
    (raise-argument-error 'trimmed-parametric-surface3d "(listof surface-trim?)" trims))
  (define base
    (adaptive-parametric-surface3d
     procedure #:u-range u-range #:v-range v-range #:id id
     #:derivative-u derivative-u #:derivative-v derivative-v
     #:position-tolerance position-tolerance
     #:normal-angle-tolerance normal-angle-tolerance
     #:maximum-edge-length maximum-edge-length
     ;; Trim boundaries are independent of geometric curvature. A small
     ;; deterministic base lattice ensures a boundary can be discovered even
     ;; on an otherwise perfectly planar parameterization.
     #:minimum-depth (max minimum-depth (min 4 maximum-depth))
     #:maximum-depth maximum-depth
     #:on-invalid on-invalid #:material material #:transform transform #:opacity opacity
     #:wireframe-color wireframe-color #:wireframe-width wireframe-width))
  (define source (surface3d-mesh base))
  (define source-mesh (surface-mesh3d-mesh source))
  (define vertices '())
  (define normals '())
  (define vertex-provenance '())
  (define triangles '())
  (define triangle-provenance '())
  (define vertex-ids (make-hash))
  (define next-id 0)
  (define (add-vertex vertex)
    (hash-ref! vertex-ids (trimmed-vertex-key vertex)
               (lambda ()
                 (define id next-id)
                 (set! next-id (add1 next-id))
                 (set! vertices (cons (trimmed-vertex-position vertex) vertices))
                 (set! normals (cons (or (trimmed-vertex-normal vertex) z-axis3) normals))
                 (set! vertex-provenance
                       (cons (hasheq 'u (trimmed-vertex-u vertex)
                                     'v (trimmed-vertex-v vertex)
                                     'trim-boundary (trimmed-vertex-boundary vertex))
                             vertex-provenance))
                 id)))
  (for ([triangle (in-vector (mesh3d-triangles source-mesh))]
        [triangle-index (in-naturals)])
    (define polygon
      (for/list ([index (in-vector triangle)])
        (source-index->trimmed-vertex source-mesh source index u-range v-range)))
    (define clipped
      (for/fold ([current polygon]) ([trim (in-list trims)])
        (clip-uv-polygon current trim)))
    (when (>= (length clipped) 3)
      (define first-id (add-vertex (first clipped)))
      (for ([second (in-list (drop-right (rest clipped) 1))]
            [third (in-list (drop (rest clipped) 1))]
            [fan-index (in-naturals)])
        (define second-id (add-vertex second))
        (define third-id (add-vertex third))
        (unless (or (= first-id second-id) (= second-id third-id) (= third-id first-id))
          (set! triangles (cons (vector first-id second-id third-id) triangles))
          (set! triangle-provenance
                (cons (hasheq 'source-triangle triangle-index
                              'fan-index fan-index
                              'trim-boundaries
                              (remove-duplicates
                               (filter (lambda (boundary) boundary)
                                       (map trimmed-vertex-boundary
                                            (list (first clipped) second third)))))
                      triangle-provenance))))))
  (define final-vertices (vector->immutable-vector (list->vector (reverse vertices))))
  (define final-triangles (vector->immutable-vector (list->vector (reverse triangles))))
  (define final-normals (vector->immutable-vector (list->vector (reverse normals))))
  (define final-provenance
    (vector->immutable-vector (list->vector (reverse vertex-provenance))))
  (define final-triangle-provenance
    (vector->immutable-vector (list->vector (reverse triangle-provenance))))
  (define mesh
    (mesh3d #:id id #:vertices final-vertices #:triangles final-triangles
            #:normals final-normals #:material material
            #:wireframe-color wireframe-color #:wireframe-width wireframe-width))
  (define (inside? u v)
    (for/and ([trim (in-list trims)])
      (define value ((surface-trim-field trim) u v))
      (and (finite-real? value)
           (if (eq? (surface-trim-keep trim) 'positive)
               (>= value (- (surface-trim-tolerance trim)))
               (<= value (surface-trim-tolerance trim))))))
  (define diagnostics
    (hasheq 'kind 'trimmed-parametric
            'base (surface3d-diagnostics base)
            'trim-count (length trims)
            'retained-triangle-count (vector-length final-triangles)
            'domain-contains? inside?))
  (define topology-key
    (vector 'trimmed-parametric (surface-mesh3d-topology-key source)
            final-triangles final-provenance final-triangle-provenance
            (for/vector ([trim (in-list trims)])
              (vector (surface-trim-id trim) (surface-trim-keep trim)))))
  (surface3d-from-generated-mesh
   'trimmed-parametric id
   (surface-mesh3d mesh final-provenance final-triangle-provenance topology-key diagnostics)
   #:transform transform #:opacity opacity #:material material
   #:wireframe-color wireframe-color #:wireframe-width wireframe-width
   #:evaluator procedure #:u-range u-range #:v-range v-range #:diagnostics diagnostics))

(struct trimmed-vertex (position normal u v cache-key boundary) #:transparent)

(define (source-index->trimmed-vertex mesh source index u-range v-range)
  (define sample (vector-ref (surface-mesh3d-vertex-provenance source) index))
  (define uv (parametric-sample3d-uv sample))
  (define normalized-u (/ (dyadic-coordinate-numerator (uv-key-u uv))
                          (expt 2 (dyadic-coordinate-level (uv-key-u uv))))
  )
  (define normalized-v (/ (dyadic-coordinate-numerator (uv-key-v uv))
                          (expt 2 (dyadic-coordinate-level (uv-key-v uv))))
  )
  (trimmed-vertex
   (vector-ref (mesh3d-vertices mesh) index)
   (and (mesh3d-normals mesh) (vector-ref (mesh3d-normals mesh) index))
   (+ (first u-range) (* normalized-u (- (second u-range) (first u-range))))
   (+ (first v-range) (* normalized-v (- (second v-range) (first v-range))))
   (list 'source (parametric-sample3d-uv sample))
   #f))

(define (clip-uv-polygon polygon trim)
  (cond [(null? polygon) '()]
        [else
         (define reversed '())
         (define previous (last polygon))
         (define previous-value (trim-value trim previous))
         (for ([current (in-list polygon)])
           (define current-value (trim-value trim current))
           (define previous-inside? (trim-inside? trim previous-value))
           (define current-inside? (trim-inside? trim current-value))
           (cond [(and previous-inside? current-inside?)
                  (set! reversed (cons current reversed))]
                 [(and previous-inside? (not current-inside?))
                  (set! reversed
                        (cons (trim-intersection trim previous current previous-value current-value)
                              reversed))]
                 [(and (not previous-inside?) current-inside?)
                  (set! reversed
                        (cons current
                              (cons (trim-intersection trim previous current previous-value current-value)
                                    reversed)))])
           (set! previous current)
           (set! previous-value current-value))
         (reverse reversed)]))

(define (trim-value trim vertex)
  (define value ((surface-trim-field trim) (trimmed-vertex-u vertex) (trimmed-vertex-v vertex)))
  (unless (finite-real? value)
    (raise-arguments-error 'trimmed-parametric-surface3d
                           "a finite signed trim-field value"
                           "trim" (surface-trim-id trim)
                           "u" (trimmed-vertex-u vertex) "v" (trimmed-vertex-v vertex)
                           "result" value))
  value)

(define (trim-inside? trim value)
  (if (eq? (surface-trim-keep trim) 'positive)
      (>= value (- (surface-trim-tolerance trim)))
      (<= value (surface-trim-tolerance trim))))

(define (trim-intersection trim first second first-value second-value)
  (define denominator (- first-value second-value))
  (define progress
    (if (zero? denominator) 1/2
        (max 0 (min 1 (/ first-value denominator)))))
  (define u (+ (trimmed-vertex-u first)
               (* progress (- (trimmed-vertex-u second) (trimmed-vertex-u first)))))
  (define v (+ (trimmed-vertex-v first)
               (* progress (- (trimmed-vertex-v second) (trimmed-vertex-v first)))))
  (trimmed-vertex
   (vec3-lerp (trimmed-vertex-position first) (trimmed-vertex-position second) progress)
   (and (trimmed-vertex-normal first) (trimmed-vertex-normal second)
        (let ([normal (vec3-lerp (trimmed-vertex-normal first)
                                 (trimmed-vertex-normal second) progress)])
          (and (positive? (vec3-length normal)) (vec3-normalize normal))))
   u v
   (list 'trim-edge (surface-trim-id trim)
         (ordered-uv (trimmed-vertex-u first) (trimmed-vertex-v first)
                     (trimmed-vertex-u second) (trimmed-vertex-v second)))
   (surface-trim-id trim)))

(define (ordered-uv first-u first-v second-u second-v)
  (if (or (< first-u second-u) (and (= first-u second-u) (<= first-v second-v)))
      (list first-u first-v second-u second-v)
      (list second-u second-v first-u first-v)))

(define (trimmed-vertex-key vertex)
  (or (trimmed-vertex-cache-key vertex)
      (list 'uv (trimmed-vertex-u vertex) (trimmed-vertex-v vertex))))
