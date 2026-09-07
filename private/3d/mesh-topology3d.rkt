#lang racket/base

;;;
;;; Deterministic Indexed-Mesh Topological Complex
;;;

;; This module is deliberately separate from render compilation. It turns a
;; valid indexed triangle container into immutable, navigable topology without
;; repairing, welding, or otherwise changing its authored geometry. The shared
;; cache retains only source-index structure; semantic IDs are attached afresh
;; for the requested mesh, so equally shaped meshes never borrow one another's
;; author-visible part names.

(require racket/list
         "edge-adjacency3d.rkt"
         "geometry-fingerprint3d.rkt"
         "mesh-analysis3d.rkt"
         "mesh3d.rkt")

(provide (struct-out mesh-vertex-topology3d)
         (struct-out mesh-halfedge3d)
         (struct-out mesh-edge-topology3d)
         (struct-out mesh-triangle-topology3d)
         (struct-out mesh-boundary-component3d)
         (struct-out mesh-component-topology3d)
         (struct-out mesh-topology3d)
         (struct-out mesh3d-component-invariants3d)
         (struct-out mesh3d-genus-report)
         mesh3d-topology
         mesh-topology3d-vertex-neighbours
         mesh-topology3d-incident-edges
         mesh-topology3d-incident-faces
         mesh-topology3d-face-neighbours
         mesh-topology3d-boundary-components
         mesh-topology3d-connected-components
         mesh-topology3d-manifold?
         mesh-topology3d-closed?
         mesh-topology3d-orientable?
         mesh3d-euler-characteristic
         mesh3d-boundary-count
         mesh3d-component-invariants
         mesh3d-genus)


;;;
;;; Immutable records
;;;

(struct mesh-vertex-topology3d (index id outgoing-halfedges boundary? component)
  #:transparent)

;; `opposite` is #f on a boundary, one half-edge index on a two-incidence edge,
;; and an immutable vector of all other incident half-edges on a nonmanifold
;; edge. It never pretends that a nonmanifold edge has one arbitrary twin.
(struct mesh-halfedge3d (index from to triangle next previous opposite edge)
  #:transparent)

(struct mesh-edge-topology3d (index id vertices halfedges boundary? nonmanifold?)
  #:transparent)

(struct mesh-triangle-topology3d (index id vertices halfedges component)
  #:transparent)

;; Boundary records are connected components of boundary edges. `vertices` and
;; `halfedges` retain source encounter order; `closed?` is false for branching
;; or open boundary graphs, which is diagnostic rather than an invented loop.
(struct mesh-boundary-component3d (index edges vertices halfedges component closed?)
  #:transparent)

;; A component contains edge-connected triangle faces. Isolated vertices are
;; represented as explicit zero-face components, keeping Euler accounting and
;; diagnostics honest instead of silently losing source vertices.
(struct mesh-component-topology3d
  (index triangles vertices edges boundary-components manifold? orientable?)
  #:transparent)

(struct mesh-topology3d
  (vertices halfedges edges triangles components boundaries diagnostics)
  #:transparent)

(struct mesh3d-component-invariants3d
  (component vertex-count edge-count face-count euler-characteristic
             boundary-count manifold? orientable? genus reason)
  #:transparent)

(struct mesh3d-genus-report (components valid? reason) #:transparent)


;;;
;;; Structural topology cache
;;;

;; The cache key excludes U-0 semantic labels. A cached value uses numeric
;; source IDs; `annotate-topology` replaces precisely those three ID fields for
;; a requesting mesh. Weak keys make this an acceleration, not retained scene
;; or renderer state.
(define topology-cache (make-weak-hash))

; mesh3d-topology : mesh3d? -> mesh-topology3d?
;; Builds or returns deterministic immutable topological structure for a mesh.
(define (mesh3d-topology mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-topology "mesh3d?" mesh))
  (define key (mesh3d-geometry-key mesh))
  (define skeleton
    (hash-ref! topology-cache key (lambda () (build-topology-skeleton mesh))))
  (annotate-topology mesh skeleton))

(define (annotate-topology mesh topology)
  (define semantic-edge-ids (mesh-semantic-edge-id-table mesh))
  (struct-copy mesh-topology3d topology
               [vertices
                (vector->immutable-vector
                 (for/vector ([vertex (in-vector (mesh-topology3d-vertices topology))])
                   (struct-copy mesh-vertex-topology3d vertex
                                [id (mesh3d-vertex-id mesh
                                                     (mesh-vertex-topology3d-index vertex))])))]
               [edges
                (vector->immutable-vector
                 (for/vector ([edge (in-vector (mesh-topology3d-edges topology))])
                   (define vertices (mesh-edge-topology3d-vertices edge))
                   (struct-copy mesh-edge-topology3d edge
                                [id (hash-ref semantic-edge-ids
                                              (cons (vector-ref vertices 0)
                                                    (vector-ref vertices 1))
                                              (mesh-edge-topology3d-index edge))])))]
               [triangles
                (vector->immutable-vector
                 (for/vector ([triangle (in-vector (mesh-topology3d-triangles topology))])
                   (struct-copy mesh-triangle-topology3d triangle
                                [id (mesh3d-face-id mesh
                                                   (mesh-triangle-topology3d-index triangle))])))]))

;; Explicit mesh edge IDs align with the mesh's optional render-edge vector;
;; topological edges align with triangle incidences. Only an unambiguous equal
;; vertex pair transfers a semantic ID. A custom vector that omits or repeats a
;; triangle edge therefore falls back to its stable topology index.
(define (mesh-semantic-edge-id-table mesh)
  (define table (make-hash))
  (define ambiguous (make-hash))
  (for ([edge (in-vector (mesh3d-edges mesh))]
        [index (in-naturals)])
    (define key (cons (min (vector-ref edge 0) (vector-ref edge 1))
                      (max (vector-ref edge 0) (vector-ref edge 1))))
    (when (mesh3d-edge-ids mesh)
      (cond [(hash-has-key? table key)
             (hash-set! ambiguous key #t)
             (hash-remove! table key)]
            [(not (hash-has-key? ambiguous key))
             (hash-set! table key (mesh3d-edge-id mesh index))])))
  table)


;;;
;;; Construction
;;;

(define (build-topology-skeleton mesh)
  (define triangles (mesh3d-triangles mesh))
  (define vertex-count (vector-length (mesh3d-vertices mesh)))
  (define adjacency (mesh3d-edge-adjacency mesh))
  (define edge-index-by-pair
    (for/hash ([entry (in-vector adjacency)] [edge-index (in-naturals)])
      (define edge (edge-adjacency3d-edge entry))
      (values (cons (vector-ref edge 0) (vector-ref edge 1)) edge-index)))
  (define triangle-components (face-components triangles adjacency))
  (define triangle->component
    (component-index-vector (vector-length triangles) triangle-components))
  (define halfedges
    (build-halfedges triangles adjacency edge-index-by-pair))
  (define edges
    (build-edges adjacency))
  (define boundaries
    (build-boundaries edges halfedges triangle->component vertex-count))
  (define components
    (build-components triangle-components triangle->component edges boundaries
                      halfedges vertex-count))
  (define vertices
    (build-vertices vertex-count halfedges boundaries components triangle->component))
  (define triangle-records
    (vector->immutable-vector
     (for/vector ([triangle (in-vector triangles)] [index (in-naturals)])
       (mesh-triangle-topology3d index index triangle
                                 (vector-immutable (* 3 index)
                                                   (add1 (* 3 index))
                                                   (+ (* 3 index) 2))
                                 (vector-ref triangle->component index)))))
  (define-values (_parities orientation-conflict?)
    (mesh3d-orientation-parities mesh adjacency))
  ;; The current relation solver reports one conflict bit for the complete
  ;; topology. Until U-2 introduces a polygonal-face relation graph, marking
  ;; each face component nonorientable when that bit is set is conservative and
  ;; prevents a component record from contradicting the mesh-level query.
  (define oriented-components
    (vector->immutable-vector
     (for/vector ([component (in-vector components)])
       (struct-copy mesh-component-topology3d component
                    [orientable? (not orientation-conflict?)]))))
  (define analysis (analyze-mesh3d mesh))
  (mesh-topology3d
   vertices halfedges edges triangle-records oriented-components boundaries
   (hasheq 'nonmanifold-edge-indices
           (vector->immutable-vector
            (for/vector ([edge (in-vector edges)] #:when (mesh-edge-topology3d-nonmanifold? edge))
              (mesh-edge-topology3d-index edge)))
           'boundary-edge-count (for/sum ([edge (in-vector edges)]
                                           #:when (mesh-edge-topology3d-boundary? edge)) 1)
           'isolated-vertex-indices (mesh3d-analysis-isolated-vertices analysis)
           'orientation-conflict? orientation-conflict?
           'cache-policy 'geometry-key-structural-skeleton)))

(define (build-halfedges triangles adjacency edge-index-by-pair)
  (vector->immutable-vector
   (for/vector ([halfedge-index (in-range (* 3 (vector-length triangles)))])
     (define triangle-index (quotient halfedge-index 3))
     (define local-index (remainder halfedge-index 3))
     (define triangle (vector-ref triangles triangle-index))
     (define from (vector-ref triangle local-index))
     (define to (vector-ref triangle (modulo (add1 local-index) 3)))
     (define edge-key (cons (min from to) (max from to)))
     (define edge-index (hash-ref edge-index-by-pair edge-key))
     (define incidences
       (edge-adjacency3d-incidences (vector-ref adjacency edge-index)))
     (define incident-halfedges
       (for/list ([incidence (in-vector incidences)])
         (+ (* 3 (edge-incidence3d-triangle-index incidence))
            (edge-incidence3d-local-edge-index incidence))))
     (define opposite
       (cond [(= (length incident-halfedges) 1) #f]
             [(= (length incident-halfedges) 2)
              (if (= halfedge-index (first incident-halfedges))
                  (second incident-halfedges)
                  (first incident-halfedges))]
             [else
              (vector->immutable-vector
               (list->vector
                (filter (lambda (index) (not (= index halfedge-index)))
                        incident-halfedges)))]))
     (mesh-halfedge3d halfedge-index from to triangle-index
                      (+ (* 3 triangle-index) (modulo (add1 local-index) 3))
                      (+ (* 3 triangle-index) (modulo (+ local-index 2) 3))
                      opposite edge-index))))

(define (build-edges adjacency)
  (vector->immutable-vector
   (for/vector ([entry (in-vector adjacency)] [index (in-naturals)])
     (define incidences (edge-adjacency3d-incidences entry))
     (mesh-edge-topology3d
      index index (edge-adjacency3d-edge entry)
      (vector->immutable-vector
       (for/vector ([incidence (in-vector incidences)])
         (+ (* 3 (edge-incidence3d-triangle-index incidence))
            (edge-incidence3d-local-edge-index incidence))))
      (= (vector-length incidences) 1)
      (> (vector-length incidences) 2)))))

;; Face components are based on shared edges, not merely a touching vertex.
;; That is the appropriate adjacency relation for triangle topology and keeps a
;; bow-tie vertex diagnostic rather than claiming a fabricated surface fan.
(define (face-components triangles adjacency)
  (define count (vector-length triangles))
  (define neighbours (make-vector count '()))
  (for ([entry (in-vector adjacency)]
        #:when (>= (vector-length (edge-adjacency3d-incidences entry)) 2))
    (define face-indices
      (for/list ([incidence (in-vector (edge-adjacency3d-incidences entry))])
        (edge-incidence3d-triangle-index incidence)))
    (for ([first-index (in-list face-indices)])
      (for ([second-index (in-list face-indices)] #:unless (= first-index second-index))
        (vector-set! neighbours first-index
                     (append (vector-ref neighbours first-index) (list second-index))))))
  (define seen (make-vector count #f))
  (define components '())
  (for ([root (in-range count)])
    (unless (vector-ref seen root)
      (vector-set! seen root #t)
      (define component
        (let visit ([pending (list root)] [reversed '()])
          (cond [(null? pending) (sort reversed <)]
                [else
                 (define current (car pending))
                 (define remaining
                   (for/fold ([queue (cdr pending)])
                             ([next (in-list (vector-ref neighbours current))])
                     (if (vector-ref seen next)
                         queue
                         (begin (vector-set! seen next #t)
                                (append queue (list next))))))
                 (visit remaining (cons current reversed))])))
      (set! components (append components (list component)))))
  (vector->immutable-vector
   (list->vector
    (sort components < #:key car))))

(define (component-index-vector triangle-count components)
  (define indices (make-vector triangle-count #f))
  (for ([component (in-vector components)] [component-index (in-naturals)])
    (for ([triangle-index (in-list component)])
      (vector-set! indices triangle-index component-index)))
  (vector->immutable-vector indices))

;; Boundary components use connectivity of boundary edges. A valid manifold
;; boundary will have degree two at every boundary vertex; the `closed?` flag
;; exposes any other graph instead of guessing a cyclic ordering.
(define (build-boundaries edges halfedges triangle->component vertex-count)
  (define boundary-edge-indices
    (for/list ([edge (in-vector edges)] #:when (mesh-edge-topology3d-boundary? edge))
      (mesh-edge-topology3d-index edge)))
  (define edges-at-vertex (make-vector vertex-count '()))
  (for ([edge-index (in-list boundary-edge-indices)])
    (define endpoints (mesh-edge-topology3d-vertices (vector-ref edges edge-index)))
    (for ([vertex-index (in-vector endpoints)])
      (vector-set! edges-at-vertex vertex-index
                   (append (vector-ref edges-at-vertex vertex-index) (list edge-index)))))
  (define seen (make-vector (vector-length edges) #f))
  (define reversed '())
  (for ([root (in-list boundary-edge-indices)])
    (unless (vector-ref seen root)
      (vector-set! seen root #t)
      (define component-edges
        (let visit ([pending (list root)] [collected '()])
          (cond [(null? pending) (sort collected <)]
                [else
                 (define current (car pending))
                 (define endpoints (mesh-edge-topology3d-vertices (vector-ref edges current)))
                 (define following
                   (for/fold ([queue (cdr pending)]) ([vertex-index (in-vector endpoints)])
                     (for/fold ([next-queue queue])
                               ([edge-index (in-list (vector-ref edges-at-vertex vertex-index))])
                       (if (vector-ref seen edge-index)
                           next-queue
                           (begin (vector-set! seen edge-index #t)
                                  (append next-queue (list edge-index)))))))
                 (visit following (cons current collected))])))
      (define component-vertices
        (sort (remove-duplicates
               (apply append
                      (for/list ([edge-index (in-list component-edges)])
                        (vector->list
                         (mesh-edge-topology3d-vertices (vector-ref edges edge-index))))))
              <))
      (define incident-components
        (remove-duplicates
         (apply append
                (for/list ([edge-index (in-list component-edges)])
                  (for/list ([halfedge-index
                              (in-vector (mesh-edge-topology3d-halfedges
                                          (vector-ref edges edge-index)))])
                    (vector-ref triangle->component
                                (mesh-halfedge3d-triangle
                                 (vector-ref halfedges halfedge-index))))))))
      (define component-index
        (and (= (length incident-components) 1) (car incident-components)))
      (define closed?
        (and (pair? component-edges)
             (for/and ([vertex-index (in-list component-vertices)])
               (= (length (vector-ref edges-at-vertex vertex-index)) 2))))
      (set! reversed
            (cons (mesh-boundary-component3d
                   0
                   (vector->immutable-vector (list->vector component-edges))
                   (vector->immutable-vector (list->vector component-vertices))
                   (vector->immutable-vector
                    (list->vector
                     (apply append
                            (for/list ([edge-index (in-list component-edges)])
                              (vector->list (mesh-edge-topology3d-halfedges
                                             (vector-ref edges edge-index)))))))
                   component-index closed?)
                  reversed))))
  (vector->immutable-vector
   (for/vector ([boundary (in-list (reverse reversed))] [index (in-naturals)])
     (struct-copy mesh-boundary-component3d boundary [index index]))))

(define (build-components face-components triangle->component edges boundaries halfedges vertex-count)
  (define base-components
    (for/list ([triangle-indices (in-vector face-components)] [component-index (in-naturals)])
      (define component-vertices
        (sort (remove-duplicates
               (apply append
                      (for/list ([triangle-index (in-list triangle-indices)])
                        (vector->list
                         (mesh-triangle-vertices-from-halfedges halfedges triangle-index)))))
              <))
      (define component-edges
        (for/list ([edge (in-vector edges)]
                   #:when (for/or ([halfedge-index (in-vector (mesh-edge-topology3d-halfedges edge))])
                            (= (vector-ref triangle->component
                                           (mesh-halfedge3d-triangle
                                            (vector-ref halfedges halfedge-index)))
                               component-index)))
          (mesh-edge-topology3d-index edge)))
      (define component-boundaries
        (for/list ([boundary (in-vector boundaries)]
                   #:when (equal? (mesh-boundary-component3d-component boundary)
                                  component-index))
          (mesh-boundary-component3d-index boundary)))
      (define manifold?
        (for/and ([edge-index (in-list component-edges)])
          (not (mesh-edge-topology3d-nonmanifold? (vector-ref edges edge-index)))))
      (mesh-component-topology3d
       component-index
       (vector->immutable-vector (list->vector triangle-indices))
       (vector->immutable-vector (list->vector component-vertices))
       (vector->immutable-vector (list->vector component-edges))
       (vector->immutable-vector (list->vector component-boundaries))
       manifold? #t)))
  (define used-vertices
    (for/fold ([used (make-hash)]) ([component (in-list base-components)])
      (for ([vertex-index (in-vector (mesh-component-topology3d-vertices component))])
        (hash-set! used vertex-index #t))
      used))
  (define isolated-components
    (for/list ([vertex-index (in-range vertex-count)]
               #:unless (hash-has-key? used-vertices vertex-index))
      (mesh-component-topology3d 0 #() (vector-immutable vertex-index) #() #() #t #t)))
  (vector->immutable-vector
   (for/vector ([component (in-list (append base-components isolated-components))]
                [component-index (in-naturals)])
     (struct-copy mesh-component-topology3d component [index component-index]))))

(define (mesh-triangle-vertices-from-halfedges halfedges triangle-index)
  (vector-immutable
   (mesh-halfedge3d-from (vector-ref halfedges (* 3 triangle-index)))
   (mesh-halfedge3d-from (vector-ref halfedges (add1 (* 3 triangle-index))))
   (mesh-halfedge3d-from (vector-ref halfedges (+ (* 3 triangle-index) 2)))))

(define (build-vertices vertex-count halfedges boundaries components triangle->component)
  (define boundary? (make-vector vertex-count #f))
  (for ([boundary (in-vector boundaries)])
    (for ([vertex-index (in-vector (mesh-boundary-component3d-vertices boundary))])
      (vector-set! boundary? vertex-index #t)))
  (define outgoing (make-vector vertex-count '()))
  (for ([halfedge (in-vector halfedges)])
    (define from (mesh-halfedge3d-from halfedge))
    (vector-set! outgoing from
                 (append (vector-ref outgoing from)
                         (list (mesh-halfedge3d-index halfedge)))))
  (vector->immutable-vector
   (for/vector ([vertex-index (in-range vertex-count)])
     (define incident-components
       (remove-duplicates
        (for/list ([halfedge-index (in-list (vector-ref outgoing vertex-index))])
          (vector-ref triangle->component
                      (mesh-halfedge3d-triangle (vector-ref halfedges halfedge-index))))))
     (define component
       (cond [(pair? incident-components) (car incident-components)]
             [else
              (for/first ([candidate (in-vector components)]
                          #:when (member vertex-index
                                         (vector->list (mesh-component-topology3d-vertices candidate))))
                (mesh-component-topology3d-index candidate))]))
     (mesh-vertex-topology3d
      vertex-index vertex-index
      (vector->immutable-vector (list->vector (vector-ref outgoing vertex-index)) )
      (vector-ref boundary? vertex-index) component))))


;;;
;;; Queries
;;;

(define (check-topology who topology)
  (unless (mesh-topology3d? topology)
    (raise-argument-error who "mesh-topology3d?" topology)))

(define (check-vertex-index who topology vertex-index)
  (unless (and (exact-nonnegative-integer? vertex-index)
               (< vertex-index (vector-length (mesh-topology3d-vertices topology))))
    (raise-arguments-error who "an in-range exact nonnegative vertex index"
                           "vertex-index" vertex-index
                           "vertex-count" (vector-length (mesh-topology3d-vertices topology)))))

(define (check-face-index who topology face-index)
  (unless (and (exact-nonnegative-integer? face-index)
               (< face-index (vector-length (mesh-topology3d-triangles topology))))
    (raise-arguments-error who "an in-range exact nonnegative face index"
                           "face-index" face-index
                           "face-count" (vector-length (mesh-topology3d-triangles topology)))))

(define (mesh-topology3d-vertex-neighbours topology vertex-index)
  (check-topology 'mesh-topology3d-vertex-neighbours topology)
  (check-vertex-index 'mesh-topology3d-vertex-neighbours topology vertex-index)
  (vector->immutable-vector
   (list->vector
    (for/fold ([neighbours '()]) ([edge (in-vector (mesh-topology3d-edges topology))])
      (define endpoints (mesh-edge-topology3d-vertices edge))
      (cond [(= vertex-index (vector-ref endpoints 0))
             (append neighbours (list (vector-ref endpoints 1)))]
            [(= vertex-index (vector-ref endpoints 1))
             (append neighbours (list (vector-ref endpoints 0)))]
            [else neighbours])))))

(define (mesh-topology3d-incident-edges topology vertex-index)
  (check-topology 'mesh-topology3d-incident-edges topology)
  (check-vertex-index 'mesh-topology3d-incident-edges topology vertex-index)
  (vector->immutable-vector
   (for/vector ([edge (in-vector (mesh-topology3d-edges topology))]
                #:when (let ([endpoints (mesh-edge-topology3d-vertices edge)])
                         (or (= vertex-index (vector-ref endpoints 0))
                             (= vertex-index (vector-ref endpoints 1)))))
     (mesh-edge-topology3d-index edge))))

(define (mesh-topology3d-incident-faces topology vertex-index)
  (check-topology 'mesh-topology3d-incident-faces topology)
  (check-vertex-index 'mesh-topology3d-incident-faces topology vertex-index)
  (vector->immutable-vector
   (for/vector ([face (in-vector (mesh-topology3d-triangles topology))]
                #:when (member vertex-index
                               (vector->list (mesh-triangle-topology3d-vertices face))) )
     (mesh-triangle-topology3d-index face))))

(define (mesh-topology3d-face-neighbours topology face-index)
  (check-topology 'mesh-topology3d-face-neighbours topology)
  (check-face-index 'mesh-topology3d-face-neighbours topology face-index)
  (define face (vector-ref (mesh-topology3d-triangles topology) face-index))
  (define seen (make-hash))
  (define reversed '())
  (for ([halfedge-index (in-vector (mesh-triangle-topology3d-halfedges face))])
    (define halfedge (vector-ref (mesh-topology3d-halfedges topology) halfedge-index))
    (define edge (vector-ref (mesh-topology3d-edges topology) (mesh-halfedge3d-edge halfedge)))
    (for ([other-halfedge-index (in-vector (mesh-edge-topology3d-halfedges edge))]
          #:unless (= other-halfedge-index halfedge-index))
      (define other-face
        (mesh-halfedge3d-triangle
         (vector-ref (mesh-topology3d-halfedges topology) other-halfedge-index)))
      (unless (hash-has-key? seen other-face)
        (hash-set! seen other-face #t)
        (set! reversed (cons other-face reversed)))))
  (vector->immutable-vector (list->vector (reverse reversed))))

(define (mesh-topology3d-boundary-components topology)
  (check-topology 'mesh-topology3d-boundary-components topology)
  (mesh-topology3d-boundaries topology))

(define (mesh-topology3d-connected-components topology)
  (check-topology 'mesh-topology3d-connected-components topology)
  (mesh-topology3d-components topology))

(define (mesh-topology3d-manifold? topology)
  (check-topology 'mesh-topology3d-manifold? topology)
  (and (for/and ([edge (in-vector (mesh-topology3d-edges topology))])
         (not (mesh-edge-topology3d-nonmanifold? edge)))
       ;; A pinched vertex has half-edges from more than one edge-connected
       ;; face component. It is not a 2-manifold even if each edge has at most
       ;; two incident faces.
       (for/and ([vertex (in-vector (mesh-topology3d-vertices topology))])
         (let ([components
                (remove-duplicates
                 (for/list ([halfedge-index
                             (in-vector (mesh-vertex-topology3d-outgoing-halfedges vertex))])
                   (mesh-triangle-topology3d-component
                    (vector-ref (mesh-topology3d-triangles topology)
                                (mesh-halfedge3d-triangle
                                 (vector-ref (mesh-topology3d-halfedges topology)
                                             halfedge-index))))))])
           (<= (length components) 1)))))

(define (mesh-topology3d-closed? topology)
  (check-topology 'mesh-topology3d-closed? topology)
  (and (positive? (vector-length (mesh-topology3d-triangles topology)))
       (mesh-topology3d-manifold? topology)
       (zero? (vector-length (mesh-topology3d-boundaries topology)))))

(define (mesh-topology3d-orientable? topology)
  (check-topology 'mesh-topology3d-orientable? topology)
  (not (hash-ref (mesh-topology3d-diagnostics topology) 'orientation-conflict? #f)))


;;;
;;; Combinatorial invariants
;;;

(define (mesh3d-euler-characteristic mesh-or-topology)
  (define topology (as-topology 'mesh3d-euler-characteristic mesh-or-topology))
  (- (+ (vector-length (mesh-topology3d-vertices topology))
        (vector-length (mesh-topology3d-triangles topology)))
     (vector-length (mesh-topology3d-edges topology))))

(define (mesh3d-boundary-count mesh-or-topology)
  (define topology (as-topology 'mesh3d-boundary-count mesh-or-topology))
  (vector-length (mesh-topology3d-boundaries topology)))

(define (mesh3d-component-invariants mesh-or-topology)
  (define topology (as-topology 'mesh3d-component-invariants mesh-or-topology))
  (vector->immutable-vector
   (for/vector ([component (in-vector (mesh-topology3d-components topology))])
     (define vertex-count (vector-length (mesh-component-topology3d-vertices component)))
     (define edge-count (vector-length (mesh-component-topology3d-edges component)))
     (define face-count (vector-length (mesh-component-topology3d-triangles component)))
     (define chi (- (+ vertex-count face-count) edge-count))
     (define boundary-count (vector-length (mesh-component-topology3d-boundary-components component)))
     (define manifold? (and (mesh-component-topology3d-manifold? component)
                            (mesh-topology3d-manifold? topology)))
     (define orientable? (and (mesh-component-topology3d-orientable? component)
                              (mesh-topology3d-orientable? topology)))
     (define numerator (- 2 boundary-count chi))
     (define genus
       (and manifold? orientable? (positive? face-count)
            (even? numerator) (>= numerator 0) (/ numerator 2)))
     (define reason
       (cond [(zero? face-count) 'no-faces]
             [(not manifold?) 'nonmanifold]
             [(not orientable?) 'nonorientable]
             [(not (even? numerator)) 'nonintegral-genus]
             [(negative? numerator) 'negative-genus]
             [else #f]))
     (mesh3d-component-invariants3d
      (mesh-component-topology3d-index component)
      vertex-count edge-count face-count chi boundary-count manifold? orientable?
      genus reason))))

(define (mesh3d-genus mesh-or-topology)
  (define invariants (mesh3d-component-invariants mesh-or-topology))
  (define invalid
    (for/first ([invariant (in-vector invariants)]
                #:when (mesh3d-component-invariants3d-reason invariant))
      (mesh3d-component-invariants3d-reason invariant)))
  (mesh3d-genus-report invariants (not invalid) invalid))

(define (as-topology who value)
  (cond [(mesh-topology3d? value) value]
        [(mesh3d? value) (mesh3d-topology value)]
        [else (raise-argument-error who "(or/c mesh3d? mesh-topology3d?)" value)]))
