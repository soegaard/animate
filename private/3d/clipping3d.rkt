#lang racket/base

;;;
;;; Semantic Mesh Slicing and Render Clips
;;;

;; This module keeps two deliberately distinct operations.  `clip3d` is a
;; viewport instruction: it retains its child geometry and only constrains the
;; triangles sent to a renderer.  `slice-mesh3d` instead returns newly cut
;; indexed geometry, while `section-by-plane3d` retains the exact section
;; topology needed for annotations and curves.

(require racket/list
         racket/match
         "../geometry.rkt"
         "affine3.rkt"
         "bounds3.rkt"
         "curve3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "ray-plane.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide clip-plane3d
         clip-plane3d?
         clip-plane3d-plane
         clip-plane3d-keep
         clip-plane3d-world
         clip3d
         clip3d?
         clip3d-content
         clip3d-plane
         slice-mesh3d
         section3d?
         section3d-loops
         section3d-chains
         section-by-plane3d
         section-curve3d
         plane-signed-distance
         clip-triangle-by-plane3d)


;;;
;;; Plane and Render-clip Values
;;;

(struct clip-plane3d-value (plane keep) #:transparent)

(define clip-plane3d? clip-plane3d-value?)
(define clip-plane3d-plane clip-plane3d-value-plane)
(define clip-plane3d-keep clip-plane3d-value-keep)

; clip-plane3d : plane3? [#:keep (or/c 'positive 'negative)] -> clip-plane3d?
;; Describes the retained half-space of a local clipping plane.
(define (clip-plane3d plane #:keep [keep 'positive])
  (unless (plane3? plane)
    (raise-argument-error 'clip-plane3d "plane3?" plane))
  (check-keep 'clip-plane3d keep)
  (clip-plane3d-value plane keep))

; clip-plane3d-world : clip-plane3d? affine3? -> clip-plane3d?
;; Moves a local plane into world coordinates without changing its half-space.
(define (clip-plane3d-world clip transform)
  (unless (clip-plane3d? clip)
    (raise-argument-error 'clip-plane3d-world "clip-plane3d?" clip))
  (unless (affine3? transform)
    (raise-argument-error 'clip-plane3d-world "affine3?" transform))
  (clip-plane3d
   (plane3
    (affine3-apply-point transform (plane3-point (clip-plane3d-plane clip)))
    (linear3-apply-vector
     (affine3-normal-transform transform)
     (plane3-normal (clip-plane3d-plane clip))))
   #:keep (clip-plane3d-keep clip)))

(struct clip3d-value (id transform opacity content plane)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id value) (clip3d-value-id value))
   (define (spatial-transform value) (clip3d-value-transform value))
   (define (spatial-with-transform value transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy clip3d-value value [transform transform]))
   (define (spatial-opacity value) (clip3d-value-opacity value))
   (define (spatial-with-opacity value opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error 'spatial-with-opacity
                             "finite real in the closed unit interval" opacity))
     (struct-copy clip3d-value value [opacity opacity]))
   (define (spatial-local-bounds value)
     (aabb3-transform
      (spatial-local-bounds (clip3d-value-content value))
      (transform3->affine3
       (spatial-transform (clip3d-value-content value)))))]
  #:methods gen:spatial-container
  [(define (spatial-child-entries value)
     (list (spatial-child (spatial-id (clip3d-value-content value))
                          (clip3d-value-content value))))
   (define (spatial-container-with-children value children)
     (unless (and (list? children) (= (length children) 1)
                  (spatial-visual? (car children)))
       (raise-argument-error 'spatial-container-with-children
                             "a one-element list of spatial-visual?" children))
     (struct-copy clip3d-value value [content (car children)]))])

(define clip3d? clip3d-value?)
(define clip3d-content clip3d-value-content)
(define clip3d-plane clip3d-value-plane)

; clip3d : spatial-visual? (or/c plane3? clip-plane3d?) #:id symbol? ... -> clip3d?
;; Wraps one spatial subtree with render-only local half-space clipping.
(define (clip3d content clip
                #:id [id (string->symbol (format "~a-clip" (spatial-id content)))]
                #:transform [transform identity-transform3]
                #:opacity [opacity 1])
  (unless (spatial-visual? content)
    (raise-argument-error 'clip3d "spatial-visual?" content))
  (unless (symbol? id) (raise-argument-error 'clip3d "symbol? as #:id" id))
  (unless (transform3? transform)
    (raise-argument-error 'clip3d "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'clip3d "finite real in the closed unit interval" opacity))
  (clip3d-value id transform opacity content (->clip-plane 'clip3d clip)))


;;;
;;; Actual Geometry Slicing
;;;

;; `section3d` deliberately exposes topology rather than pretending a section
;; is always one closed curve.  Loops and chains are ordered deterministically
;; in the plane's coordinate system.
(struct section3d (loops chains) #:transparent)

(define epsilon 1e-8)

; plane-signed-distance : plane3? vec3? -> finite-real?
;; Positive values lie on the normal-facing side of the plane.
(define (plane-signed-distance plane point)
  (unless (plane3? plane) (raise-argument-error 'plane-signed-distance "plane3?" plane))
  (unless (vec3? point) (raise-argument-error 'plane-signed-distance "vec3?" point))
  (vec3-dot (vec3- point (plane3-point plane)) (plane3-normal plane)))

; clip-triangle-by-plane3d : (listof vec3?) clip-plane3d? -> (listof vec3?)
;; Clips one CCW triangle in the plane's local coordinate system.
(define (clip-triangle-by-plane3d triangle clip)
  (unless (and (list? triangle) (= (length triangle) 3) (andmap vec3? triangle))
    (raise-argument-error 'clip-triangle-by-plane3d "list of three vec3?" triangle))
  (unless (clip-plane3d? clip)
    (raise-argument-error 'clip-triangle-by-plane3d "clip-plane3d?" clip))
  (clip-polygon-by-plane triangle clip))

; slice-mesh3d : mesh3d? (or/c plane3? clip-plane3d?) ... -> mesh3d?
;; Produces the requested local half of a mesh.  It does not manufacture a cap;
;; call `section-by-plane3d` for the truthful intersection geometry.
(define (slice-mesh3d mesh clip
                      #:id [id (spatial-id mesh)]
                      #:keep [keep #f])
  (unless (mesh3d? mesh) (raise-argument-error 'slice-mesh3d "mesh3d?" mesh))
  (unless (symbol? id) (raise-argument-error 'slice-mesh3d "symbol? as #:id" id))
  (define actual-clip
    (if keep
        (begin (check-keep 'slice-mesh3d keep)
               (clip-plane3d (->plane 'slice-mesh3d clip) #:keep keep))
        (->clip-plane 'slice-mesh3d clip)))
  (define output-vertices '())
  (define output-triangles '())
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define polygon
      (clip-polygon-by-plane
       (for/list ([index (in-vector triangle)])
         (vector-ref (mesh3d-vertices mesh) index))
       actual-clip))
    (when (>= (length polygon) 3)
      (define start (length output-vertices))
      (set! output-vertices (append output-vertices polygon))
      (for ([index (in-range 1 (sub1 (length polygon)))])
        (set! output-triangles
              (append output-triangles
                      (list (vector start (+ start index) (+ start index 1))))))))
  (define result
    (mesh3d #:id id
            #:vertices (list->vector output-vertices)
            #:triangles (list->vector output-triangles)
            #:material (mesh3d-material mesh)
            #:transform (spatial-transform mesh)
            #:opacity (spatial-opacity mesh)
            #:wireframe-color (mesh3d-wireframe-color mesh)
            #:wireframe-width (mesh3d-wireframe-width mesh)))
  (with-flat-normals result))

; section-by-plane3d : mesh3d? (or/c plane3? clip-plane3d?) -> section3d?
;; Returns deterministically joined plane/mesh section loops and open chains.
(define (section-by-plane3d mesh clip)
  (unless (mesh3d? mesh)
    (raise-argument-error 'section-by-plane3d "mesh3d?" mesh))
  (define plane (->plane 'section-by-plane3d clip))
  (define segments
    (for/fold ([segments '()]) ([triangle (in-vector (mesh3d-triangles mesh))])
      (define points
        (for/list ([index (in-vector triangle)])
          (vector-ref (mesh3d-vertices mesh) index)))
      (define intersection (triangle-section-segment points plane))
      (if intersection (cons intersection segments) segments)))
  (define-values (loops chains) (join-section-segments (reverse segments) plane))
  ;; Racket pairs are immutable, and these lists are freshly allocated above.
  (section3d loops chains))

; section-curve3d : mesh3d? (or/c plane3? clip-plane3d?) ... -> group3d?
;; Converts all sections to independently addressable tube curves.  A group is
;; returned even for one loop, because a nonmanifold input may truthfully yield
;; more than one component.
(define (section-curve3d mesh clip
                         #:id [id 'section]
                         #:color [color "gold"]
                         #:radius [radius 1/24]
                         #:sides [sides 8])
  (unless (symbol? id) (raise-argument-error 'section-curve3d "symbol? as #:id" id))
  (define section (section-by-plane3d mesh clip))
  (define loops (section3d-loops section))
  (define chains (section3d-chains section))
  (define curves
    (append
     (for/list ([loop (in-list loops)] [index (in-naturals)])
       (polyline3d loop #:id (string->symbol (format "~a-loop-~a" id index))
                   #:radius radius #:sides sides #:closed? #t #:color color))
     (for/list ([chain (in-list chains)] [index (in-naturals)])
       (polyline3d chain #:id (string->symbol (format "~a-chain-~a" id index))
                   #:radius radius #:sides sides #:closed? #f #:color color))))
  ;; Section points live in the source mesh's local coordinates, so preserve
  ;; its authored envelope on the returned group rather than silently drawing
  ;; the curve at the world origin.
  (group3d curves #:id id #:transform (spatial-transform mesh)
           #:opacity (spatial-opacity mesh)))


;;;
;;; Polygon and Section Helpers
;;;

(define (->plane who value)
  (cond [(plane3? value) value]
        [(clip-plane3d? value) (clip-plane3d-plane value)]
        [else (raise-argument-error who "(or/c plane3? clip-plane3d?)" value)]))

(define (->clip-plane who value)
  (cond [(clip-plane3d? value) value]
        [(plane3? value) (clip-plane3d value)]
        [else (raise-argument-error who "(or/c plane3? clip-plane3d?)" value)]))

(define (check-keep who value)
  (unless (memq value '(positive negative))
    (raise-argument-error who "(or/c 'positive 'negative)" value)))

(define (clip-polygon-by-plane polygon clip)
  (define plane (clip-plane3d-plane clip))
  (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
  (cond [(null? polygon) '()]
        [else
         (define reversed '())
         (define previous (last polygon))
         (define previous-distance (* sign (plane-signed-distance plane previous)))
         (for ([current (in-list polygon)])
           (define current-distance (* sign (plane-signed-distance plane current)))
           (define previous-inside? (>= previous-distance (- epsilon)))
           (define current-inside? (>= current-distance (- epsilon)))
           (cond
             [(and previous-inside? current-inside?)
              (set! reversed (cons current reversed))]
             [(and previous-inside? (not current-inside?))
              (set! reversed
                    (cons (edge-plane-intersection previous current previous-distance current-distance)
                          reversed))]
             [(and (not previous-inside?) current-inside?)
              (set! reversed
                    (cons current
                          (cons (edge-plane-intersection previous current previous-distance current-distance)
                                reversed)))])
           (set! previous current)
           (set! previous-distance current-distance))
         (reverse (deduplicate-consecutive (reverse reversed)))]))

(define (edge-plane-intersection first second first-distance second-distance)
  (define denominator (- first-distance second-distance))
  (if (zero? denominator)
      first
      (vec3-lerp first second (/ first-distance denominator))))

(define (triangle-section-segment points plane)
  (define intersections '())
  (for ([first-point (in-list points)]
        [second-point (in-list (append (cdr points) (list (car points))))])
    (define first-distance (plane-signed-distance plane first-point))
    (define second-distance (plane-signed-distance plane second-point))
    (cond
      [(<= (abs first-distance) epsilon)
       (set! intersections (cons first-point intersections))]
      [(< (* first-distance second-distance) 0)
       (set! intersections
             (cons (vec3-lerp first-point second-point
                               (/ first-distance (- first-distance second-distance)))
                   intersections))]))
  (define unique (deduplicate-points (reverse intersections)))
  (and (>= (length unique) 2)
       (list (first unique) (second unique))))

(define (deduplicate-consecutive points)
  (cond [(null? points) '()]
        [else
         (define reversed (list (car points)))
         (for ([point (in-list (cdr points))])
           (unless (point≈? point (car reversed))
             (set! reversed (cons point reversed))))
         (define result (reverse reversed))
         (if (and (> (length result) 1) (point≈? (car result) (last result)))
             (drop-right result 1)
             result)]))

(define (deduplicate-points points)
  (for/fold ([result '()]) ([point (in-list points)])
    (if (ormap (lambda (candidate) (point≈? point candidate)) result)
        result
        (append result (list point)))))

(define (point≈? first-point second-point)
  (<= (vec3-distance first-point second-point) epsilon))

(define (point-key point)
  (list (inexact->exact (round (/ (vec3-x point) epsilon)))
        (inexact->exact (round (/ (vec3-y point) epsilon)))
        (inexact->exact (round (/ (vec3-z point) epsilon)))))

(define (key<? first-key second-key)
  (cond [(< (first first-key) (first second-key)) #t]
        [(> (first first-key) (first second-key)) #f]
        [(< (second first-key) (second second-key)) #t]
        [(> (second first-key) (second second-key)) #f]
        [else (< (third first-key) (third second-key))]))

(define (edge-key first-key second-key)
  (if (key<? second-key first-key)
      (cons second-key first-key)
      (cons first-key second-key)))

;; Joins exactly matching sections from triangulated faces.  It intentionally
;; leaves a nonmanifold branch as deterministic open chains rather than
;; inventing a topological repair.
(define (join-section-segments segments plane)
  (define points (make-hash))
  (define edges (make-hash))
  (for ([segment (in-list segments)])
    (define first-point (first segment))
    (define second-point (second segment))
    (define first-key (point-key first-point))
    (define second-key (point-key second-point))
    (unless (equal? first-key second-key)
      (hash-set! points first-key first-point)
      (hash-set! points second-key second-point)
      (hash-set! edges (edge-key first-key second-key) #t)))
  (define adjacency (make-hash))
  (for ([(edge _value) (in-hash edges)])
    (define first-key (car edge))
    (define second-key (cdr edge))
    (hash-set! adjacency first-key (cons second-key (hash-ref adjacency first-key '())))
    (hash-set! adjacency second-key (cons first-key (hash-ref adjacency second-key '()))))
  (for ([(key neighbours) (in-hash adjacency)])
    (hash-set! adjacency key (sort neighbours key<?)))
  (define unused (make-hash))
  (for ([(edge _value) (in-hash edges)]) (hash-set! unused edge #t))
  (define loops '())
  (define chains '())
  (define (edge-unused? first-key second-key)
    (hash-has-key? unused (edge-key first-key second-key)))
  (define (consume! first-key second-key)
    (hash-remove! unused (edge-key first-key second-key)))
  (define (walk start-key first-next)
    (define reversed (list start-key))
    (define previous start-key)
    (define current first-next)
    (consume! start-key first-next)
    (let loop ()
      (set! reversed (cons current reversed))
      (define next
        (for/first ([candidate (in-list (hash-ref adjacency current '()))]
                    #:when (and (not (equal? candidate previous))
                                (edge-unused? current candidate)))
          candidate))
      (cond [next
             (set! previous current)
             (set! current next)
             (consume! previous current)
             (loop)]
            [else (reverse reversed)])))
  ;; Start branch/end paths first, which keeps ordinary open chains canonical.
  (for ([start-key (in-list (sort (hash-keys adjacency) key<?))]
        #:when (not (= (length (hash-ref adjacency start-key)) 2)))
    (for ([next-key (in-list (hash-ref adjacency start-key))]
          #:when (edge-unused? start-key next-key))
      (set! chains (append chains (list (keys->points (walk start-key next-key) points))))))
  ;; Remaining edges have degree two and therefore form loops.
  (let loop ()
    (define edge
      (for/first ([candidate (in-list (sort (hash-keys unused)
                                        (lambda (a b) (key<? (car a) (car b)))))])
        candidate))
    (when edge
      (define path (walk (car edge) (cdr edge)))
      (define closed? (and (> (length path) 2) (equal? (car path) (last path))))
      (define normalized (if closed? (drop-right path 1) path))
      (if closed?
          (set! loops (append loops (list (orient-loop (keys->points normalized points) plane))))
          (set! chains (append chains (list (keys->points normalized points)))))
      (loop)))
  (values loops chains))

(define (keys->points keys points)
  (for/list ([key (in-list keys)]) (hash-ref points key)))

(define (orient-loop points plane)
  (define normal
    (for/fold ([sum origin3]) ([first-point (in-list points)]
                               [second-point (in-list (append (cdr points) (list (car points))))])
      (vec3+ sum (vec3-cross first-point second-point))))
  (if (negative? (vec3-dot normal (plane3-normal plane)))
      (reverse points)
      points))

(define (with-flat-normals mesh)
  (define vertices (mesh3d-vertices mesh))
  (define normals (make-vector (vector-length vertices) z-axis3))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define first-point (vector-ref vertices (vector-ref triangle 0)))
    (define second-point (vector-ref vertices (vector-ref triangle 1)))
    (define third-point (vector-ref vertices (vector-ref triangle 2)))
    (define normal (vec3-normalize
                    (vec3-cross (vec3- second-point first-point)
                                (vec3- third-point first-point))))
    (for ([index (in-vector triangle)]) (vector-set! normals index normal)))
  (mesh3d #:id (spatial-id mesh) #:vertices vertices #:triangles (mesh3d-triangles mesh)
          #:normals normals #:material (mesh3d-material mesh)
          #:transform (spatial-transform mesh) #:opacity (spatial-opacity mesh)
          #:wireframe-color (mesh3d-wireframe-color mesh)
          #:wireframe-width (mesh3d-wireframe-width mesh)))
