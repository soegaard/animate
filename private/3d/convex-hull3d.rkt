#lang racket/base

;;;
;;; Deterministic Convex Hulls
;;;

;; This is a pure, source-index preserving hull preparation layer.  It keeps
;; lower-dimensional input honest: a point, a segment, or a planar polygon is
;; returned as such instead of being perturbed into a fictitious volume.

(require racket/list
         racket/math
         "../geometry.rkt"
         "mesh3d.rkt"
         "polyhedral-complex3d.rkt"
         "vec3.rkt")

(provide (struct-out convex-hull3d-result)
         (struct-out convex-hull3d-coplanar-group3d)
         convex-hull3d)


;;;
;;; Public values
;;;

(struct convex-hull3d-result
  (dimension mesh source-point-indices coplanar-groups interior-indices diagnostics)
  #:transparent)

;; A merged supporting face records both the generated polygonal face and all
;; input source points that lie on its supporting plane.  Source triangle
;; indexes refer to the returned hull mesh.
(struct convex-hull3d-coplanar-group3d
  (face-id triangle-indices boundary-vertex-indices source-point-indices)
  #:transparent)


;;;
;;; Internal source-point and face records
;;;

(struct hull-source-point3d (position source-indices) #:transparent)
(struct hull-face3d (a b c) #:transparent)

(define (hull-source-point3d-primary point)
  (car (hull-source-point3d-source-indices point)))

(define (hull-source-point3d<? first second)
  (define first-position (hull-source-point3d-position first))
  (define second-position (hull-source-point3d-position second))
  (or (< (vec3-x first-position) (vec3-x second-position))
      (and (= (vec3-x first-position) (vec3-x second-position))
           (or (< (vec3-y first-position) (vec3-y second-position))
               (and (= (vec3-y first-position) (vec3-y second-position))
                    (or (< (vec3-z first-position) (vec3-z second-position))
                        (and (= (vec3-z first-position) (vec3-z second-position))
                             (< (hull-source-point3d-primary first)
                                (hull-source-point3d-primary second)))))))))


;;;
;;; Public construction
;;;

; convex-hull3d : (or/c list? vector?)
;   [#:id symbol?]
;   [#:tolerance (or/c 'automatic nonnegative-finite-real?)]
;   [#:merge-tolerance (or/c #f nonnegative-finite-real?)]
;   [#:orientation-tolerance (or/c #f nonnegative-finite-real?)]
;   [#:coplanar-tolerance (or/c #f nonnegative-finite-real?)]
;   [#:coplanar (or/c 'merge 'triangulate)]
;   [#:on-degenerate (or/c 'report 'error)]
;   -> convex-hull3d-result?
;;
;; The incremental selection always chooses the farthest currently outside
;; source point (lexicographic/source-index tie break). This makes face order
;; and provenance deterministic without depending on hash iteration or thread
;; timing. Exact inputs use exact orientation determinants; inexact inputs use
;; the reported scale-aware orientation tolerance. `#:tolerance` remains the
;; legacy shorthand for supplying all three explicit tolerances.
(define (convex-hull3d points
                       #:id [id 'hull]
                       #:tolerance [tolerance 'automatic]
                       #:merge-tolerance [merge-tolerance #f]
                       #:orientation-tolerance [orientation-tolerance #f]
                       #:coplanar-tolerance [coplanar-tolerance #f]
                       #:coplanar [coplanar 'merge]
                       #:on-degenerate [on-degenerate 'report])
  (unless (symbol? id)
    (raise-argument-error 'convex-hull3d "symbol?" id))
  (unless (or (eq? tolerance 'automatic)
              (and (finite-real? tolerance) (>= tolerance 0)))
    (raise-argument-error 'convex-hull3d
                          "'automatic or a nonnegative finite real tolerance"
                          tolerance))
  (define (check-optional-tolerance keyword value)
    (unless (or (not value)
                (and (finite-real? value) (>= value 0)))
      (raise-argument-error 'convex-hull3d
                            (format "#f or a nonnegative finite real for ~a" keyword)
                            value)))
  (check-optional-tolerance '#:merge-tolerance merge-tolerance)
  (check-optional-tolerance '#:orientation-tolerance orientation-tolerance)
  (check-optional-tolerance '#:coplanar-tolerance coplanar-tolerance)
  (unless (memq coplanar '(merge triangulate))
    (raise-argument-error 'convex-hull3d "(or/c 'merge 'triangulate)" coplanar))
  (unless (memq on-degenerate '(report error))
    (raise-argument-error 'convex-hull3d "(or/c 'report 'error)" on-degenerate))
  ;; A numeric legacy tolerance means exactly what it used to mean: use it for
  ;; all three policies.  Explicit policy keywords override just their stage.
  (define effective-merge-tolerance
    (cond [merge-tolerance merge-tolerance]
          [(eq? tolerance 'automatic) 0]
          [else tolerance]))
  (define requested-orientation-tolerance
    (cond [orientation-tolerance orientation-tolerance]
          [else tolerance]))
  (define-values (unique-points duplicate-count)
    (normalize-points points effective-merge-tolerance))
  (define tolerance-data
    (derive-tolerances unique-points requested-orientation-tolerance))
  (define effective-orientation-tolerance (first tolerance-data))
  (define volume-tolerance (second tolerance-data))
  (define exact-input? (third tolerance-data))
  (define effective-coplanar-tolerance
    (cond [coplanar-tolerance coplanar-tolerance]
          [(eq? tolerance 'automatic) effective-orientation-tolerance]
          [else tolerance]))
  (define uncertain-count (box 0))
  (define (classify-volume value)
    (cond [(positive? value)
           (if (> value volume-tolerance) 1
               (begin (unless exact-input? (set-box! uncertain-count (add1 (unbox uncertain-count)))) 0))]
          [(negative? value)
           (if (< value (- volume-tolerance)) -1
               (begin (unless exact-input? (set-box! uncertain-count (add1 (unbox uncertain-count)))) 0))]
          [else 0]))
  (define dimension-data
    (affine-dimension unique-points effective-orientation-tolerance classify-volume))
  (define dimension (first dimension-data))
  (define anchors (second dimension-data))
  (when (and (< dimension 3) (eq? on-degenerate 'error))
    (raise-arguments-error 'convex-hull3d
                           "a full-dimensional point set under the requested tolerance"
                           "dimension" dimension
                           "tolerance" effective-orientation-tolerance))
  (define common-diagnostics
    (hasheq 'algorithm 'deterministic-incremental-quickhull
            'input-point-count (input-point-count points)
            'unique-point-count (length unique-points)
            'duplicate-point-count duplicate-count
            'merge-tolerance effective-merge-tolerance
            'orientation-tolerance effective-orientation-tolerance
            'volume-tolerance volume-tolerance
            'orientation-policy (if exact-input?
                                    'exact-determinants
                                    'scale-aware-tolerance)
            'uncertain-orientation-count (unbox uncertain-count)
            'coplanar-tolerance effective-coplanar-tolerance
            'coplanar-policy coplanar))
  (cond [(zero? dimension)
         (degenerate-result id 0 unique-points anchors common-diagnostics)]
        [(= dimension 1)
         (degenerate-result id 1 unique-points anchors common-diagnostics)]
        [(= dimension 2)
         (planar-result id unique-points anchors effective-orientation-tolerance common-diagnostics)]
        [else
         (solid-result id unique-points anchors volume-tolerance effective-coplanar-tolerance
                       classify-volume coplanar common-diagnostics uncertain-count)]))


;;;
;;; Input normalization and affine dimension
;;;

(define (input-point-list points)
  (define result
    (cond [(vector? points) (vector->list points)]
          [(list? points) points]
          [else (raise-argument-error 'convex-hull3d "a vector or list of vec3? values" points)]))
  (when (null? result)
    (raise-arguments-error 'convex-hull3d "a nonempty point collection" "points" points))
  (for ([point (in-list result)])
    (unless (vec3-finite? point)
      (raise-argument-error 'convex-hull3d "vec3 with finite coordinates" point)))
  result)

(define (input-point-count points) (length (input-point-list points)))

(define (normalize-points points merge-tolerance)
  ;; Mergeability is transitive: if a is close to b and b is close to c, all
  ;; three belong to one cluster even if a and c are farther apart.  Work in
  ;; canonical geometry/source-index order and union by lowest index, which
  ;; makes the representative and its provenance independent of input order.
  (define ordered
    (list->vector
     (sort (for/list ([point (in-list (input-point-list points))] [index (in-naturals)])
             (hull-source-point3d point (list index)))
           hull-source-point3d<?)))
  (define count (vector-length ordered))
  (define parents (build-vector count values))
  (define (find-root index)
    (define parent (vector-ref parents index))
    (cond [(= parent index) index]
          [else
           (define root (find-root parent))
           (vector-set! parents index root)
           root]))
  (define (union! first second)
    (define first-root (find-root first))
    (define second-root (find-root second))
    (unless (= first-root second-root)
      (if (< first-root second-root)
          (vector-set! parents second-root first-root)
          (vector-set! parents first-root second-root))))
  (define (mergeable? first second)
    (define first-position
      (hull-source-point3d-position (vector-ref ordered first)))
    (define second-position
      (hull-source-point3d-position (vector-ref ordered second)))
    (or (equal? first-position second-position)
        (and (positive? merge-tolerance)
             (<= (vec3-distance first-position second-position) merge-tolerance))))
  (for* ([first (in-range count)]
         [second (in-range (add1 first) count)]
         #:when (mergeable? first second))
    (union! first second))
  (define member-indices-by-root (make-hash))
  (for ([index (in-range count)])
    (hash-update! member-indices-by-root (find-root index)
                  (lambda (members) (cons index members))
                  '()))
  (define clusters
    (for/list ([root (in-list (sort (hash-keys member-indices-by-root) <))])
      (define source-indices
        (sort
         (apply append
                (for/list ([member (in-list (hash-ref member-indices-by-root root))])
                  (hull-source-point3d-source-indices (vector-ref ordered member))))
         <))
      (hull-source-point3d
       (hull-source-point3d-position (vector-ref ordered root))
       source-indices)))
  (values clusters (- count (length clusters))))

(define (derive-tolerances points requested-tolerance)
  (define positions (map hull-source-point3d-position points))
  (define xs (map vec3-x positions))
  (define ys (map vec3-y positions))
  (define zs (map vec3-z positions))
  (define scale
    (max 1
         (- (apply max xs) (apply min xs))
         (- (apply max ys) (apply min ys))
         (- (apply max zs) (apply min zs))))
  (define exact-input?
    (for/and ([position (in-list positions)])
      (and (exact? (vec3-x position))
           (exact? (vec3-y position))
           (exact? (vec3-z position)))))
  (define linear
    (cond [(not (eq? requested-tolerance 'automatic)) requested-tolerance]
          [exact-input? 0]
          [else (* 1e-10 (exact->inexact scale))]))
  (list linear (* linear scale scale) exact-input?))

;; Returns `(dimension anchors)`, where anchors are p0, p1, p2, and (for a
;; full solid) p3. The first point is lexicographically least, and every later
;; anchor maximizes the appropriate distance with the same stable tie break.
(define (affine-dimension points linear-tolerance classify-volume)
  (define first-point (car points))
  (define-values (second-point _second-distance)
    (farthest-point points
                    (lambda (point)
                      (vec3-dot (vec3- (hull-source-point3d-position point)
                                      (hull-source-point3d-position first-point))
                                (vec3- (hull-source-point3d-position point)
                                      (hull-source-point3d-position first-point))))))
  (cond [(or (not second-point)
             (<= (vec3-distance (hull-source-point3d-position first-point)
                                 (hull-source-point3d-position second-point))
                 linear-tolerance))
         (list 0 (list first-point))]
        [else
         (define line-vector
           (vec3- (hull-source-point3d-position second-point)
                  (hull-source-point3d-position first-point)))
         (define line-length (vec3-length line-vector))
         (define-values (third-point _third-distance)
           (farthest-point
            points
            (lambda (point)
              (/ (vec3-length
                  (vec3-cross line-vector
                              (vec3- (hull-source-point3d-position point)
                                     (hull-source-point3d-position first-point))))
                 line-length))))
         (cond [(or (not third-point)
                    (<= (/ (vec3-length
                            (vec3-cross line-vector
                                        (vec3- (hull-source-point3d-position third-point)
                                               (hull-source-point3d-position first-point))))
                           line-length)
                        linear-tolerance))
                (list 1 (sort (list first-point second-point) hull-source-point3d<?))]
               [else
                (define raw-normal
                  (vec3-cross line-vector
                              (vec3- (hull-source-point3d-position third-point)
                                     (hull-source-point3d-position first-point))))
                (define normal-length (vec3-length raw-normal))
                (define-values (fourth-point _fourth-distance)
                  (farthest-point
                   points
                   (lambda (point)
                     (abs (/ (signed-volume6 (hull-source-point3d-position first-point)
                                             (hull-source-point3d-position second-point)
                                             (hull-source-point3d-position third-point)
                                             (hull-source-point3d-position point))
                             normal-length)))))
                (cond [(or (not fourth-point)
                           (zero? (classify-volume
                                   (signed-volume6 (hull-source-point3d-position first-point)
                                                   (hull-source-point3d-position second-point)
                                                   (hull-source-point3d-position third-point)
                                                   (hull-source-point3d-position fourth-point)))))
                       (list 2 (list first-point second-point third-point))]
                      [else (list 3 (list first-point second-point third-point fourth-point))])])]))

(define (farthest-point points measure)
  (for/fold ([best #f] [best-value #f]) ([point (in-list points)])
    (define value (measure point))
    (cond [(or (not best)
               (> value best-value)
               (and (= value best-value) (hull-source-point3d<? point best)))
           (values point value)]
          [else (values best best-value)])))


;;;
;;; Lower-dimensional output
;;;

(define (degenerate-result id dimension all-points anchors diagnostics)
  (define vertices
    (case dimension
      [(0) anchors]
      [(1) anchors]
      [else (error 'degenerate-result "internal dimension error")]))
  (define mesh
    (mesh3d #:id id
            #:vertices (vector->immutable-vector (list->vector (map hull-source-point3d-position vertices)))
            #:triangles #()
            #:edges (if (= dimension 1) '#(#(0 1)) #())))
  (convex-hull3d-result
   dimension mesh (source-index-vector vertices) #()
   (interior-index-vector all-points vertices)
   (hash-set diagnostics 'dimension dimension)))

(define (planar-result id all-points anchors tolerance diagnostics)
  (define first-point (first anchors))
  (define second-point (second anchors))
  (define third-point (third anchors))
  (define raw-normal
    (vec3-cross (vec3- (hull-source-point3d-position second-point)
                       (hull-source-point3d-position first-point))
                (vec3- (hull-source-point3d-position third-point)
                       (hull-source-point3d-position first-point))))
  (define polygon (planar-convex-hull all-points raw-normal tolerance))
  (define vertex-count (length polygon))
  (define triangles
    (vector->immutable-vector
     (for/vector ([index (in-range 1 (sub1 vertex-count))])
       (vector-immutable 0 index (add1 index)))))
  (define edges
    (vector->immutable-vector
     (for/vector ([index (in-range vertex-count)])
       (vector-immutable index (modulo (add1 index) vertex-count)))))
  (define mesh
    (mesh3d #:id id
            #:vertices (vector->immutable-vector
                        (list->vector (map hull-source-point3d-position polygon)))
            #:triangles triangles #:edges edges))
  (convex-hull3d-result
   2 mesh (source-index-vector polygon) #()
   (interior-index-vector all-points polygon)
   (hash-set diagnostics 'dimension 2)))

;; Monotone-chain hull after a normal-aligned 2D projection. Equal/collinear
;; points on an edge are deliberately omitted from the polygon and remain in
;; provenance as non-vertex source points.
(define (planar-convex-hull points normal tolerance)
  (define dominant
    (let ([x (abs (vec3-x normal))] [y (abs (vec3-y normal))] [z (abs (vec3-z normal))])
      (cond [(and (>= x y) (>= x z)) 'x]
            [(>= y z) 'y]
            [else 'z])))
  (define (coordinates point)
    (define position (hull-source-point3d-position point))
    (case dominant
      [(x) (cons (vec3-y position) (vec3-z position))]
      [(y) (cons (vec3-z position) (vec3-x position))]
      [else (cons (vec3-x position) (vec3-y position))]))
  (define projected
    (sort points
          (lambda (first second)
            (define first-coordinates (coordinates first))
            (define second-coordinates (coordinates second))
            (or (< (car first-coordinates) (car second-coordinates))
                (and (= (car first-coordinates) (car second-coordinates))
                     (or (< (cdr first-coordinates) (cdr second-coordinates))
                         (and (= (cdr first-coordinates) (cdr second-coordinates))
                              (hull-source-point3d<? first second))))))))
  (define (turn first second third)
    (define a (coordinates first))
    (define b (coordinates second))
    (define c (coordinates third))
    (- (* (- (car b) (car a)) (- (cdr c) (cdr a)))
       (* (- (cdr b) (cdr a)) (- (car c) (car a)))))
  (define projected-tolerance (* tolerance tolerance))
  (define (build-half sequence)
    (reverse
     (for/fold ([stack '()]) ([point (in-list sequence)])
       (let trim ([current stack])
         (if (and (pair? current) (pair? (cdr current))
                  (<= (turn (second current) (first current) point) projected-tolerance))
             (trim (cdr current))
             (cons point current))))))
  (define lower (build-half projected))
  (define upper (build-half (reverse projected)))
  (define polygon (append (drop-right lower 1) (drop-right upper 1)))
  ;; The chosen coordinate pairs produce a positive cross product along the
  ;; positive dominant axis. Reverse if the input plane normal points opposite.
  (if (negative? (case dominant
                   [(x) (vec3-x normal)] [(y) (vec3-y normal)] [else (vec3-z normal)]))
      (reverse polygon)
      polygon))


;;;
;;; Three-dimensional incremental hull
;;;

(define (solid-result id all-points anchors volume-tolerance coplanar-tolerance
                      classify-volume coplanar diagnostics uncertain-count)
  (define point-vector (vector->immutable-vector (list->vector all-points)))
  (define (point-at index) (hull-source-point3d-position (vector-ref point-vector index)))
  (define anchor-indices
    (for/list ([anchor (in-list anchors)])
      (for/first ([point (in-list all-points)] [index (in-naturals)] #:when (eq? point anchor)) index)))
  (define inside
    (centroid3 (map point-at anchor-indices)))
  (define initial-faces
    (let ([a (first anchor-indices)] [b (second anchor-indices)]
          [c (third anchor-indices)] [d (fourth anchor-indices)])
      (list (outward-face a b c point-at inside)
            (outward-face a d b point-at inside)
            (outward-face a c d point-at inside)
            (outward-face b d c point-at inside))))
  (define remaining
    (for/list ([index (in-range (vector-length point-vector))]
               #:unless (member index anchor-indices))
      index))
  (define final-faces
    (let build ([faces initial-faces] [candidates remaining])
      (define next (farthest-outside-point candidates faces point-at classify-volume))
      (cond [(not next) faces]
            [else
             (define point-index (car next))
             (define visible (cdr next))
             (define horizon (horizon-edges visible))
             (define retained (filter (lambda (face) (not (member face visible))) faces))
             (define created
               (for/list ([edge (in-list horizon)])
                 (outward-face (car edge) (cdr edge) point-index point-at inside)))
             (build (append retained created) (remove point-index candidates))])))
  (define-values (mesh hull-points)
    (faces->mesh id point-vector final-faces))
  (define groups
    (if (eq? coplanar 'merge)
        (coplanar-groups mesh all-points coplanar-tolerance)
        #()))
  (convex-hull3d-result
   3 mesh (source-index-vector hull-points) groups
   (interior-index-vector all-points hull-points)
   (hash-set (hash-set diagnostics 'dimension 3)
             'uncertain-orientation-count (unbox uncertain-count))))

(define (farthest-outside-point candidates faces point-at classify-volume)
  ;; Return `(point-index . visible-faces)` for the point whose greatest
  ;; positive face distance is maximal; exact source-index/geometry ordering is
  ;; already encoded in `candidates` through the normalized point vector.
  (define best-index #f)
  (define best-distance #f)
  (define best-visible #f)
  (for ([point-index (in-list candidates)])
    (define visible
      (filter (lambda (face)
                (positive? (classify-volume
                            (face-signed-volume face (point-at point-index) point-at))))
              faces))
    (when (pair? visible)
      (define distance
        (apply max (map (lambda (face)
                          (face-signed-volume face (point-at point-index) point-at))
                        visible)))
      (when (or (not best-index) (> distance best-distance)
                (and (= distance best-distance) (< point-index best-index)))
        (set! best-index point-index)
        (set! best-distance distance)
        (set! best-visible visible))))
  (and best-index (cons best-index best-visible)))

(define (outward-face a b c point-at inside)
  (if (positive? (signed-volume6 (point-at a) (point-at b) (point-at c) inside))
      (hull-face3d a c b)
      (hull-face3d a b c)))

(define (face-signed-volume face point point-at)
  (signed-volume6 (point-at (hull-face3d-a face))
                  (point-at (hull-face3d-b face))
                  (point-at (hull-face3d-c face))
                  point))

;; A directed edge occurring twice within the visible set is internal.  The
;; surviving directed edges are sorted by their undirected key before new faces
;; are made, avoiding traversal-order dependence at a multi-face horizon.
(define (horizon-edges visible-faces)
  (define counts (make-hash))
  (for ([face (in-list visible-faces)])
    (for ([edge (in-list (face-directed-edges face))])
      (define key (cons (min (car edge) (cdr edge)) (max (car edge) (cdr edge))))
      (hash-update! counts key (lambda (edges) (cons edge edges)) '())))
  (sort (for/list ([(key edges) (in-hash counts)] #:when (= (length edges) 1))
          (car edges))
        (lambda (first second)
          (or (< (min (car first) (cdr first)) (min (car second) (cdr second)))
              (and (= (min (car first) (cdr first)) (min (car second) (cdr second)))
                   (< (max (car first) (cdr first)) (max (car second) (cdr second))))))))

(define (face-directed-edges face)
  (list (cons (hull-face3d-a face) (hull-face3d-b face))
        (cons (hull-face3d-b face) (hull-face3d-c face))
        (cons (hull-face3d-c face) (hull-face3d-a face))))

(define (faces->mesh id point-vector faces)
  (define used-indices
    (sort (remove-duplicates
           (apply append
                  (for/list ([face (in-list faces)])
                    (list (hull-face3d-a face) (hull-face3d-b face) (hull-face3d-c face)))))
          (lambda (first second)
            (hull-source-point3d<? (vector-ref point-vector first)
                                    (vector-ref point-vector second)))))
  (define index-map (make-hash))
  (for ([old-index (in-list used-indices)] [new-index (in-naturals)])
    (hash-set! index-map old-index new-index))
  (define triangles
    (sort
     (for/list ([face (in-list faces)])
       (canonical-triangle
        (hash-ref index-map (hull-face3d-a face))
        (hash-ref index-map (hull-face3d-b face))
        (hash-ref index-map (hull-face3d-c face))))
     triangle<?))
  (values
   (mesh3d #:id id
           #:vertices (vector->immutable-vector
                       (list->vector
                        (for/list ([index (in-list used-indices)])
                          (hull-source-point3d-position (vector-ref point-vector index)))))
           #:triangles (vector->immutable-vector (list->vector (map list->vector-immutable triangles))))
   (for/list ([index (in-list used-indices)]) (vector-ref point-vector index))))

(define (canonical-triangle a b c)
  (cond [(and (<= a b) (<= a c)) (list a b c)]
        [(and (<= b a) (<= b c)) (list b c a)]
        [else (list c a b)]))

(define (triangle<? left right)
  (or (< (first left) (first right))
      (and (= (first left) (first right))
           (or (< (second left) (second right))
               (and (= (second left) (second right))
                    (< (third left) (third right)))))))


;;;
;;; Provenance and helpers
;;;

(define (coplanar-groups mesh input-points tolerance)
  (define complex
    (polyhedral-complex3d mesh #:faces 'coplanar #:plane-distance tolerance))
  (vector->immutable-vector
   (for/vector ([face (in-vector (polyhedral-complex3d-faces complex))])
     (define plane (polyhedral-face3d-plane face))
     (convex-hull3d-coplanar-group3d
      (polyhedral-face3d-id face)
      (polyhedral-face3d-triangle-indices face)
      (polyhedral-face3d-boundary-vertex-indices face)
      (vector->immutable-vector
       (list->vector
        (sort
         (apply append
                (for/list ([point (in-list input-points)]
                           #:when (and plane
                                       (<= (abs (- (vec3-dot (polyhedral-plane3d-normal plane)
                                                             (hull-source-point3d-position point))
                                                   (polyhedral-plane3d-offset plane)))
                                           tolerance)))
                  (hull-source-point3d-source-indices point)))
         <)))))))

(define (source-index-vector points)
  (vector->immutable-vector
   (list->vector (map hull-source-point3d-primary points))))

(define (interior-index-vector all-points selected-points)
  (define selected (make-hasheq))
  (for ([point (in-list selected-points)]) (hash-set! selected point #t))
  (vector->immutable-vector
   (list->vector
    (sort
     (apply append
            (for/list ([point (in-list all-points)])
              (if (hash-has-key? selected point)
                  (cdr (hull-source-point3d-source-indices point))
                  (hull-source-point3d-source-indices point))))
     <))))

(define (centroid3 points)
  (vec3-scale (/ 1 (length points))
              (for/fold ([sum origin3]) ([point (in-list points)]) (vec3+ sum point))))

(define (signed-volume6 first second third fourth)
  (vec3-dot (vec3-cross (vec3- second first) (vec3- third first))
            (vec3- fourth first)))

(define (list->vector-immutable values)
  (vector->immutable-vector (list->vector values)))
