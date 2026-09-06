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

(provide trim-expression3d?
         trim-field3d
         trim-field3d?
         trim-and3d
         trim-or3d
         trim-not3d
         surface-trim
         surface-trim?
         surface-trim-field
         surface-trim-keep
         surface-trim-id
         surface-trim-tolerance
         trimmed-parametric-surface3d)

(struct trim-field3d-value (field keep id tolerance identity) #:transparent)
(struct trim-combination3d-value (operator operands identity) #:transparent)

(define (trim-expression3d? value)
  (or (trim-field3d-value? value) (trim-combination3d-value? value)))
(define trim-field3d? trim-field3d-value?)
(define surface-trim? trim-field3d-value?)
(define surface-trim-field trim-field3d-value-field)
(define surface-trim-keep trim-field3d-value-keep)
(define surface-trim-id trim-field3d-value-id)
(define surface-trim-tolerance trim-field3d-value-tolerance)

; surface-trim : procedure? [#:keep 'positive] #:id symbol? ... -> surface-trim?
;; A trim field retains its non-negative side.  `surface-trim` is the older
;; spelling and additionally exposes #:keep for one signed-field complement.
;; Compound values below combine signed fields with min/max, so a Boolean trim
;; still has one exact, cacheable boundary function for adaptive refinement.
(define (trim-field3d field #:keep [keep 'positive] #:id [id 'trim-0]
                      #:tolerance [tolerance 1e-8])
  (unless (procedure? field) (raise-argument-error 'trim-field3d "procedure?" field))
  (unless (memq keep '(positive negative))
    (raise-argument-error 'trim-field3d "(or/c 'positive 'negative)" keep))
  (unless (symbol? id) (raise-argument-error 'trim-field3d "symbol?" id))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'trim-field3d "positive finite tolerance" tolerance))
  ;; The private declaration identity is part of every generated edge key.
  ;; Public IDs remain useful provenance names, but cannot accidentally alias
  ;; distinct trim functions if a malformed value reaches this layer.
  (trim-field3d-value field keep id tolerance (gensym 'trim-field3d)))

(define (surface-trim field #:keep [keep 'positive] #:id [id 'trim-0]
                      #:tolerance [tolerance 1e-8])
  (trim-field3d field #:keep keep #:id id #:tolerance tolerance))

(define (make-trim-combination who operator operands)
  (unless (and (pair? operands) (andmap trim-expression3d? operands))
    (raise-argument-error who "a nonempty list of trim-expression3d? values" operands))
  (trim-combination3d-value operator operands (gensym operator)))

(define (trim-and3d . operands) (make-trim-combination 'trim-and3d 'and operands))
(define (trim-or3d . operands) (make-trim-combination 'trim-or3d 'or operands))
(define (trim-not3d operand)
  (unless (trim-expression3d? operand)
    (raise-argument-error 'trim-not3d "trim-expression3d?" operand))
  (trim-combination3d-value 'not (list operand) (gensym 'not)))

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
  (define trim-expression (trims->expression trims))
  (define trim-fields
    (if trim-expression (trim-expression-fields trim-expression) '()))
  (define duplicate-id (check-duplicates (map surface-trim-id trim-fields)))
  (when duplicate-id
    (raise-arguments-error 'trimmed-parametric-surface3d
                           "trims with distinct public #:id values"
                           "duplicate-id" duplicate-id))
  (define base
    (adaptive-parametric-surface3d
     procedure #:u-range u-range #:v-range v-range #:id id
     #:derivative-u derivative-u #:derivative-v derivative-v
     #:position-tolerance position-tolerance
     #:normal-angle-tolerance normal-angle-tolerance
     #:maximum-edge-length maximum-edge-length
     ;; A trim supplies its own conservative dyadic refinement predicate.
     ;; This is intentionally not a fixed minimum-depth lattice: a planar
     ;; surface need not pay for four global levels merely because it is
     ;; trimmed, while a centre/edge sample inconsistent with its corners
     ;; still forces discovery of a local boundary or hole.
     #:minimum-depth minimum-depth
     #:maximum-depth maximum-depth
     #:refine-cell?
     (and trim-expression
          (lambda (u0 u1 v0 v1 _depth)
            (trim-cell-needs-refinement? trim-expression u0 u1 v0 v1)))
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
      (if trim-expression
          (clip-uv-polygon polygon trim-expression)
          polygon))
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
    (or (not trim-expression)
        (trim-expression-inside? trim-expression u v)))
  (define diagnostics
    (hasheq 'kind 'trimmed-parametric
            'base (surface3d-diagnostics base)
            'trim-count (length trim-fields)
            'trim-expression (and trim-expression
                                  (trim-expression-provenance trim-expression))
            'retained-triangle-count (vector-length final-triangles)
            'domain-contains? inside?))
  (define topology-key
    (vector 'trimmed-parametric (surface-mesh3d-topology-key source)
            final-triangles final-provenance final-triangle-provenance
            (and trim-expression (trim-expression-provenance trim-expression))))
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

;; A legacy list means conjunction.  A compound value is already one signed
;; expression.  Keeping this normalization at the boundary makes all later
;; clipping, root finding, and provenance logic independent of surface syntax.
(define (trims->expression trims)
  (cond [(trim-expression3d? trims) trims]
        [(and (list? trims) (andmap trim-expression3d? trims))
         (and (pair? trims) (make-trim-combination
                              'trimmed-parametric-surface3d 'and trims))]
        [else
         (raise-argument-error
          'trimmed-parametric-surface3d
          "a trim-expression3d? or a list of trim-expression3d? values"
          trims)]))

(define (trim-expression-identity expression)
  (cond [(trim-field3d-value? expression) (trim-field3d-value-identity expression)]
        [else (trim-combination3d-value-identity expression)]))

(define (trim-expression-fields expression)
  (cond [(trim-field3d-value? expression) (list expression)]
        [else (append-map trim-expression-fields
                           (trim-combination3d-value-operands expression))]))

(define (trim-expression-tolerance expression)
  (apply min (map surface-trim-tolerance (trim-expression-fields expression))))

;; All trim expressions use one inside convention: non-negative is retained.
;; Conjunction/intersection is min; union is max; complement negates.  Those
;; identities make a compound boundary root a genuine signed-field root.
(define (trim-expression-value expression u v)
  (cond
    [(trim-field3d-value? expression)
     (define raw ((trim-field3d-value-field expression) u v))
     (unless (finite-real? raw)
       (raise-arguments-error 'trimmed-parametric-surface3d
                              "a finite signed trim-field value"
                              "trim" (trim-field3d-value-id expression)
                              "u" u "v" v "result" raw))
     (if (eq? (trim-field3d-value-keep expression) 'positive) raw (- raw))]
    [else
     (define values
       (map (lambda (operand) (trim-expression-value operand u v))
            (trim-combination3d-value-operands expression)))
     (case (trim-combination3d-value-operator expression)
       [(and) (apply min values)]
       [(or) (apply max values)]
       [(not) (- (car values))]
       [else (error 'trimmed-parametric-surface3d "unknown trim operator")])]))

(define (trim-expression-inside? expression u v)
  (>= (trim-expression-value expression u v)
      (- (trim-expression-tolerance expression))))

;; The provenance name identifies the declaration that actually supplied the
;; signed boundary. Ties are declaration-order stable, which keeps compound
;; corners deterministic without inventing a fresh public ID for an operator.
(define (trim-expression-boundary-id expression u v)
  (define fields (trim-expression-fields expression))
  (define-values (best _distance)
    (for/fold ([candidate (car fields)]
               [candidate-distance +inf.0])
              ([field (in-list fields)])
      (define value (trim-expression-value field u v))
      (define distance (abs value))
      (if (< distance candidate-distance)
          (values field distance)
          (values candidate candidate-distance))))
  (surface-trim-id best))

(define (trim-expression-provenance expression)
  (cond [(trim-field3d-value? expression)
         (vector 'field (surface-trim-id expression) (surface-trim-keep expression))]
        [else
         (vector (trim-combination3d-value-operator expression)
                 (for/vector ([operand (in-list (trim-combination3d-value-operands expression))])
                   (trim-expression-provenance operand)))]))

;; Nine exact dyadic samples give the adaptive tree a topology signal even for
;; an otherwise planar surface.  It is deliberately conservative: signs on a
;; side, a zero/tolerance hit, a saddle, or a centre inconsistent with all four
;; corners requests subdivision.  No finite sampler can discover every
;; arbitrarily tiny off-sample component; that limitation remains documented.
(define (trim-cell-needs-refinement? expression u0 u1 v0 v1)
  (define um (/ (+ u0 u1) 2))
  (define vm (/ (+ v0 v1) 2))
  (define coordinates
    (list (cons u0 v0) (cons u1 v0) (cons u1 v1) (cons u0 v1)
          (cons um v0) (cons u1 vm) (cons um v1) (cons u0 vm) (cons um vm)))
  (define tolerance (trim-expression-tolerance expression))
  (define (sign-at coordinate)
    (define value (trim-expression-value expression (car coordinate) (cdr coordinate)))
    (cond [(> value tolerance) 'positive]
          [(< value (- tolerance)) 'negative]
          [else 'zero]))
  (define signs (map sign-at coordinates))
  (define corner-signs (take signs 4))
  (define centre-sign (list-ref signs 8))
  (define corner-set (remove-duplicates corner-signs))
  (define saddle?
    (and (= (length corner-set) 2)
         (eq? (first corner-signs) (third corner-signs))
         (eq? (second corner-signs) (fourth corner-signs))
         (not (eq? (first corner-signs) (second corner-signs)))))
  (or (not (not (member 'zero signs)))
      (> (length (remove-duplicates signs)) 1)
      saddle?
      (not (member centre-sign corner-set))))

(define (clip-uv-polygon polygon trim-expression)
  (cond [(null? polygon) '()]
        [else
         (define reversed '())
         (define previous (last polygon))
         (define previous-value (trim-value trim-expression previous))
         (for ([current (in-list polygon)])
           (define current-value (trim-value trim-expression current))
           (define previous-inside? (trim-inside? trim-expression previous-value))
           (define current-inside? (trim-inside? trim-expression current-value))
           (cond [(and previous-inside? current-inside?)
                  (set! reversed (cons current reversed))]
                 [(and previous-inside? (not current-inside?))
                  (set! reversed
                        (cons (trim-intersection trim-expression previous current previous-value current-value)
                              reversed))]
                 [(and (not previous-inside?) current-inside?)
                  (set! reversed
                        (cons current
                              (cons (trim-intersection trim-expression previous current previous-value current-value)
                                    reversed)))])
           (set! previous current)
           (set! previous-value current-value))
         (reverse reversed)]))

(define (trim-value trim-expression vertex)
  (define value
    (trim-expression-value trim-expression
                           (trimmed-vertex-u vertex) (trimmed-vertex-v vertex)))
  (unless (finite-real? value)
    (raise-arguments-error 'trimmed-parametric-surface3d
                           "a finite signed trim-field value"
                           "trim" (trim-expression-provenance trim-expression)
                           "u" (trimmed-vertex-u vertex) "v" (trimmed-vertex-v vertex)
                           "result" value))
  value)

(define (trim-inside? trim-expression value)
  (>= value (- (trim-expression-tolerance trim-expression))))

(define (trim-intersection trim-expression first second first-value second-value)
  (define progress (refine-trim-root trim-expression first second first-value second-value))
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
   (list 'trim-edge (trim-expression-identity trim-expression)
         (ordered-uv (trimmed-vertex-u first) (trimmed-vertex-v first)
                     (trimmed-vertex-u second) (trimmed-vertex-v second)))
   (trim-expression-boundary-id trim-expression u v)))

;; Bisection makes trim tolerance a root-quality guarantee rather than merely
;; an inside threshold. The parameter interval test supplies a deterministic
;; termination bound when a field is very flat near the zero set.
(define (refine-trim-root trim-expression first second first-value second-value)
  (define tolerance (trim-expression-tolerance trim-expression))
  (define (value-at progress)
    (define u (+ (trimmed-vertex-u first)
                 (* progress (- (trimmed-vertex-u second) (trimmed-vertex-u first)))))
    (define v (+ (trimmed-vertex-v first)
                 (* progress (- (trimmed-vertex-v second) (trimmed-vertex-v first)))))
    (define value (trim-expression-value trim-expression u v))
    (unless (finite-real? value)
      (raise-arguments-error 'trimmed-parametric-surface3d
                             "a finite signed trim-field value while refining a boundary"
                             "trim" (trim-expression-provenance trim-expression)
                             "u" u "v" v "result" value))
    value)
  (cond [(<= (abs first-value) tolerance) 0]
        [(<= (abs second-value) tolerance) 1]
        ;; Clipping can cross the tolerance band without bracketing zero. Its
        ;; linear fallback remains deterministic, while true sign crossings
        ;; take the root-accurate path below.
        [(positive? (* first-value second-value))
         (let ([denominator (- first-value second-value)])
           (if (zero? denominator) 1/2 (max 0 (min 1 (/ first-value denominator)))))]
        [else
         (let loop ([low 0] [high 1] [low-value first-value] [high-value second-value]
                    [remaining 64])
           (define middle (/ (+ low high) 2))
           (define middle-value (value-at middle))
           (cond [(or (<= (abs middle-value) tolerance)
                      (<= (- high low) tolerance)
                      (zero? remaining))
                  middle]
                 [(negative? (* low-value middle-value))
                  (loop low middle low-value middle-value (sub1 remaining))]
                 [else
                  (loop middle high middle-value high-value (sub1 remaining))]))]))

(define (ordered-uv first-u first-v second-u second-v)
  (if (or (< first-u second-u) (and (= first-u second-u) (<= first-v second-v)))
      (list first-u first-v second-u second-v)
      (list second-u second-v first-u first-v)))

(define (trimmed-vertex-key vertex)
  (or (trimmed-vertex-cache-key vertex)
      (list 'uv (trimmed-vertex-u vertex) (trimmed-vertex-v vertex))))
