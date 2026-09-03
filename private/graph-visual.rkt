#lang racket/base

;;;
;;; Mathematical Graph and Network Visuals
;;;

;; Graphs are regular immutable group trees. Vertices are ordinary groups that
;; can be targeted and animated at `(graph-id vertices vertex-id)`. Edges are
;; pure derived children under `(graph-id edges edge-id)`, so their concrete
;; geometry is rebuilt from the sampled endpoint vertices rather than from
;; mutable updater state or previous rendered frames.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/math
         "affine-transform.rkt"
         "arrow-visual.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "point-marker-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide graph-vertex
         graph-vertex?
         graph-vertex-name
         graph-vertex-position
         graph-vertex-label
         graph-vertex-partition
         graph-edge
         graph-edge?
         graph-edge-source
         graph-edge-target
         graph-edge-id
         graph-edge-label
         graph-edge-weight
         graph-edge-curvature
         graph-edge-stroke
         graph-edge-stroke-width
         graph-layout?
         graph
         digraph
         graph-vertices-path
         graph-edges-path
         graph-vertex-path
         graph-edge-path
         graph-bfs
         graph-dfs
         graph-shortest-path)


;;;
;;; Author-Facing Specifications
;;;

(struct graph-vertex-spec (name position label partition)
  #:transparent)

;; graph-vertex : symbol? [#:position (or/c vec2? false/c)]
;;                [#:label (or/c string? false/c)] -> graph-vertex?
;; A position is required by the manual layout and intentionally ignored by the
;; circle/tree layouts, which calculate it deterministically from list order.
(define (graph-vertex name
                      #:position [position #f]
                      #:label [label #f]
                      #:partition [partition #f])
  (unless (symbol? name)
    (raise-argument-error 'graph-vertex "symbol?" name))
  (unless (or (not position) (vec2? position))
    (raise-argument-error 'graph-vertex "(or/c vec2? false/c)" position))
  (unless (or (not label) (string? label))
    (raise-argument-error 'graph-vertex "(or/c string? false/c)" label))
  (unless (or (not partition) (symbol? partition))
    (raise-argument-error 'graph-vertex "(or/c symbol? false/c)" partition))
  (graph-vertex-spec name position label partition))

(define graph-vertex? graph-vertex-spec?)
(define graph-vertex-name graph-vertex-spec-name)
(define graph-vertex-position graph-vertex-spec-position)
(define graph-vertex-label graph-vertex-spec-label)
(define graph-vertex-partition graph-vertex-spec-partition)

(struct graph-edge-spec (source target id label weight curvature stroke stroke-width)
  #:transparent)

;; graph-edge : symbol? symbol? [#:id symbol?] [#:label (or/c string? false/c)]
;;               -> graph-edge?
;; An omitted ID is stable and readable, for example `A->B`.
(define (graph-edge source target
                    #:id [id #f]
                    #:label [label #f]
                    #:weight [weight 1]
                    #:curvature [curvature #f]
                    #:stroke [stroke #f]
                    #:stroke-width [stroke-width #f])
  (unless (symbol? source)
    (raise-argument-error 'graph-edge "symbol?" source))
  (unless (symbol? target)
    (raise-argument-error 'graph-edge "symbol?" target))
  (unless (or (not id) (symbol? id))
    (raise-argument-error 'graph-edge "(or/c symbol? false/c)" id))
  (unless (or (not label) (string? label))
    (raise-argument-error 'graph-edge "(or/c string? false/c)" label))
  (unless (and (finite-real? weight) (positive? weight))
    (raise-argument-error 'graph-edge "positive finite real?" weight))
  (unless (or (not curvature) (finite-real? curvature))
    (raise-argument-error 'graph-edge "(or/c finite-real? false/c)" curvature))
  (unless (or (not stroke-width)
              (and (finite-real? stroke-width) (not (negative? stroke-width))))
    (raise-argument-error
     'graph-edge
     "(or/c nonnegative-finite-real? false/c)"
     stroke-width))
  (graph-edge-spec source target
                   (or id (default-edge-id source target))
                   label weight curvature stroke stroke-width))

(define graph-edge? graph-edge-spec?)
(define graph-edge-source graph-edge-spec-source)
(define graph-edge-target graph-edge-spec-target)
(define graph-edge-id graph-edge-spec-id)
(define graph-edge-label graph-edge-spec-label)
(define graph-edge-weight graph-edge-spec-weight)
(define graph-edge-curvature graph-edge-spec-curvature)
(define graph-edge-stroke graph-edge-spec-stroke)
(define graph-edge-stroke-width graph-edge-spec-stroke-width)

(define (default-edge-id source target)
  (string->symbol
   (string-append (symbol->string source)
                  "->"
                  (symbol->string target))))

(define (graph-layout? value)
  (and (symbol? value)
       (memq value '(manual circle tree spring layered partite planar))
       #t))


;;;
;;; Stable Paths
;;;

;; The returned graph is an ordinary root group with two ordinary named child
;; groups. These helpers centralize the public tree vocabulary.

(define (graph-vertices-path graph-id)
  (check-symbol 'graph-vertices-path graph-id)
  (list graph-id 'vertices))

(define (graph-edges-path graph-id)
  (check-symbol 'graph-edges-path graph-id)
  (list graph-id 'edges))

(define (graph-vertex-path graph-id vertex-id)
  (check-symbol 'graph-vertex-path graph-id)
  (check-symbol 'graph-vertex-path vertex-id)
  (list graph-id 'vertices vertex-id))

(define (graph-edge-path graph-id edge-or-id)
  (check-symbol 'graph-edge-path graph-id)
  (define edge-id
    (if (graph-edge? edge-or-id)
        (graph-edge-id edge-or-id)
        edge-or-id))
  (check-symbol 'graph-edge-path edge-id)
  (list graph-id 'edges edge-id))


;;;
;;; Graph Construction
;;;

;; graph : (listof graph-vertex?) (listof graph-edge?)
;;         #:id symbol?
;;         [#:layout graph-layout?]
;;         [#:layout-center vec2?]
;;         [#:layout-radius positive-finite-real?]
;;         [#:tree-root (or/c symbol? false/c)]
;;         [#:tree-x-spacing positive-finite-real?]
;;         [#:tree-y-spacing positive-finite-real?]
;;         [#:partite-order (or/c (listof symbol?) false/c)]
;;         [#:spring-iterations exact-positive-integer?]
;;         [#:spring-attraction positive-finite-real?]
;;         [#:spring-repulsion positive-finite-real?]
;;         [#:vertex-shape point-marker-shape?]
;;         [#:vertex-size positive-finite-real?]
;;         [#:vertex-fill any/c] [#:vertex-stroke any/c]
;;         [#:vertex-stroke-width nonnegative-finite-real?]
;;         [#:vertex-label-offset vec2?] [#:vertex-label-size positive-finite-real?]
;;         [#:vertex-label-color any/c]
;;         [#:edge-stroke any/c] [#:edge-stroke-width nonnegative-finite-real?]
;;         [#:edge-curvature finite-real?]
;;         [#:parallel-edge-separation nonnegative-finite-real?]
;;         [#:self-loop-radius positive-finite-real?]
;;         [#:edge-label-offset vec2?] [#:edge-label-size positive-finite-real?]
;;         [#:edge-label-color any/c]
;;         -> group-visual?
;; Constructs an undirected graph. The root is deliberately an identity
;; namespace; animate the named vertices, not the complete root group, so edge
;; derivations remain in the same coordinate system as their endpoints.
(define (graph vertices edges
               #:id id
               #:layout [layout 'manual]
               #:layout-center [layout-center origin]
               #:layout-radius [layout-radius 3]
               #:tree-root [tree-root #f]
               #:tree-x-spacing [tree-x-spacing 3/2]
               #:tree-y-spacing [tree-y-spacing 3/2]
               #:partite-order [partite-order #f]
               #:spring-iterations [spring-iterations 60]
               #:spring-attraction [spring-attraction 1]
               #:spring-repulsion [spring-repulsion 1]
               #:vertex-shape [vertex-shape 'circle]
               #:vertex-size [vertex-size 1/2]
               #:vertex-fill [vertex-fill "aliceblue"]
               #:vertex-stroke [vertex-stroke "navy"]
               #:vertex-stroke-width [vertex-stroke-width 2]
               #:vertex-label-offset [vertex-label-offset (vec2 0 -2/5)]
               #:vertex-label-size [vertex-label-size 1/5]
               #:vertex-label-color [vertex-label-color "midnightblue"]
               #:edge-stroke [edge-stroke "slategray"]
               #:edge-stroke-width [edge-stroke-width 2]
               #:edge-curvature [edge-curvature 0]
               #:parallel-edge-separation [parallel-edge-separation 1/3]
               #:self-loop-radius [self-loop-radius 4/5]
               #:edge-label-offset [edge-label-offset (vec2 0 1/5)]
               #:edge-label-size [edge-label-size 1/5]
               #:edge-label-color [edge-label-color "darkslategray"])
  (make-graph
   #f vertices edges id layout layout-center layout-radius tree-root
   tree-x-spacing tree-y-spacing partite-order spring-iterations
   spring-attraction spring-repulsion vertex-shape vertex-size vertex-fill
   vertex-stroke vertex-stroke-width vertex-label-offset vertex-label-size
   vertex-label-color edge-stroke edge-stroke-width edge-curvature
   parallel-edge-separation self-loop-radius edge-label-offset
   edge-label-size edge-label-color 'graph))

;; digraph accepts the same keywords and produces arrow-headed edges whose
;; direction is the declared source-to-target order.
(define (digraph vertices edges
                 #:id id
                 #:layout [layout 'manual]
                 #:layout-center [layout-center origin]
                 #:layout-radius [layout-radius 3]
                 #:tree-root [tree-root #f]
                 #:tree-x-spacing [tree-x-spacing 3/2]
                 #:tree-y-spacing [tree-y-spacing 3/2]
                 #:partite-order [partite-order #f]
                 #:spring-iterations [spring-iterations 60]
                 #:spring-attraction [spring-attraction 1]
                 #:spring-repulsion [spring-repulsion 1]
                 #:vertex-shape [vertex-shape 'circle]
                 #:vertex-size [vertex-size 1/2]
                 #:vertex-fill [vertex-fill "aliceblue"]
                 #:vertex-stroke [vertex-stroke "navy"]
                 #:vertex-stroke-width [vertex-stroke-width 2]
                 #:vertex-label-offset [vertex-label-offset (vec2 0 -2/5)]
                 #:vertex-label-size [vertex-label-size 1/5]
                 #:vertex-label-color [vertex-label-color "midnightblue"]
                 #:edge-stroke [edge-stroke "slategray"]
                 #:edge-stroke-width [edge-stroke-width 2]
                 #:edge-curvature [edge-curvature 0]
                 #:parallel-edge-separation [parallel-edge-separation 1/3]
                 #:self-loop-radius [self-loop-radius 4/5]
                 #:edge-label-offset [edge-label-offset (vec2 0 1/5)]
                 #:edge-label-size [edge-label-size 1/5]
                 #:edge-label-color [edge-label-color "darkslategray"])
  (make-graph
   #t vertices edges id layout layout-center layout-radius tree-root
   tree-x-spacing tree-y-spacing partite-order spring-iterations
   spring-attraction spring-repulsion vertex-shape vertex-size vertex-fill
   vertex-stroke vertex-stroke-width vertex-label-offset vertex-label-size
   vertex-label-color edge-stroke edge-stroke-width edge-curvature
   parallel-edge-separation self-loop-radius edge-label-offset
   edge-label-size edge-label-color 'digraph))

(define (make-graph directed? vertices edges id layout layout-center layout-radius
                    tree-root tree-x-spacing tree-y-spacing partite-order
                    spring-iterations spring-attraction spring-repulsion
                    vertex-shape vertex-size vertex-fill vertex-stroke
                    vertex-stroke-width vertex-label-offset vertex-label-size
                    vertex-label-color edge-stroke edge-stroke-width edge-curvature
                    parallel-edge-separation self-loop-radius edge-label-offset
                    edge-label-size edge-label-color who)
  (check-symbol who id)
  (unless (and (list? vertices) (pair? vertices)
               (andmap graph-vertex? vertices))
    (raise-argument-error who "nonempty list of graph-vertex? values" vertices))
  (unless (and (list? edges) (andmap graph-edge? edges))
    (raise-argument-error who "list of graph-edge? values" edges))
  (unless (graph-layout? layout)
    (raise-argument-error who "graph-layout?" layout))
  (unless (vec2? layout-center)
    (raise-argument-error who "vec2?" layout-center))
  (check-positive who "layout radius" layout-radius)
  (unless (or (not tree-root) (symbol? tree-root))
    (raise-argument-error who "(or/c symbol? false/c)" tree-root))
  (check-positive who "tree x spacing" tree-x-spacing)
  (check-positive who "tree y spacing" tree-y-spacing)
  (check-optional-symbol-list who "partite order" partite-order)
  (unless (exact-positive-integer? spring-iterations)
    (raise-arguments-error who "a positive exact integer"
                           "spring iterations" spring-iterations))
  (check-positive who "spring attraction" spring-attraction)
  (check-positive who "spring repulsion" spring-repulsion)
  (unless (point-marker-shape? vertex-shape)
    (raise-argument-error who "point-marker-shape?" vertex-shape))
  (check-positive who "vertex size" vertex-size)
  (check-nonnegative who "vertex stroke width" vertex-stroke-width)
  (unless (vec2? vertex-label-offset)
    (raise-argument-error who "vec2?" vertex-label-offset))
  (check-positive who "vertex label size" vertex-label-size)
  (check-nonnegative who "edge stroke width" edge-stroke-width)
  (unless (vec2? edge-label-offset)
    (raise-argument-error who "vec2?" edge-label-offset))
  (check-positive who "edge label size" edge-label-size)
  (unless (finite-real? edge-curvature)
    (raise-arguments-error who "a finite real"
                           "edge curvature" edge-curvature))
  (check-nonnegative who "parallel edge separation" parallel-edge-separation)
  (check-positive who "self loop radius" self-loop-radius)
  (check-graph-identities who id vertices edges)
  (check-graph-endpoints who vertices edges)
  (define positioned-vertices
    (install-layout directed? vertices edges layout layout-center layout-radius tree-root
                    tree-x-spacing tree-y-spacing partite-order spring-iterations
                    spring-attraction spring-repulsion who))
  (define vertex-group
    (group
     (for/list ([vertex (in-list positioned-vertices)])
       (make-vertex-group vertex vertex-shape vertex-size vertex-fill
                          vertex-stroke vertex-stroke-width vertex-label-offset
                          vertex-label-size vertex-label-color))
     #:id 'vertices))
  (define edge-group
    (group
     (for/list ([edge (in-list edges)])
       (make-edge-group id edge directed? vertex-size edge-stroke
                        edge-stroke-width edge-label-offset edge-label-size
                        edge-label-color
                        (edge-routing edge edges edge-curvature
                                      parallel-edge-separation self-loop-radius)))
     #:id 'edges))
  ;; Keep the graph root at the coordinate origin. Edge definitions query the
  ;; sampled world positions of their endpoint groups, while graph children are
  ;; rendered in root-local coordinates. Vertex-level motion is therefore the
  ;; stable supported way to rearrange a graph.
  (group (list edge-group vertex-group) #:id id))


;;;
;;; Layout and Validation
;;;

(define (check-graph-identities who graph-id vertices edges)
  (define vertex-names (map graph-vertex-name vertices))
  (define edge-names (map graph-edge-id edges))
  (check-unique who vertex-names "vertex name")
  (check-unique who edge-names "edge ID")
  (for ([name (in-list vertex-names)])
    (when (memq name '(vertices edges body label line))
      (raise-arguments-error
       who "a vertex name outside graph-reserved path names"
       "vertex name" name)))
  (for ([name (in-list edge-names)])
    (when (memq name '(vertices edges body label line))
      (raise-arguments-error
       who "an edge ID outside graph-reserved path names"
       "edge ID" name)))
  (when (or (memq graph-id '(vertices edges body label line))
            (member graph-id vertex-names)
            (member graph-id edge-names))
    (raise-arguments-error
     who "a graph ID distinct from all reserved and nested names"
     "graph ID" graph-id)))

(define (check-graph-endpoints who vertices edges)
  (define names (map graph-vertex-name vertices))
  (for ([edge (in-list edges)])
    (unless (member (graph-edge-source edge) names)
      (raise-arguments-error
       who "edge source naming a declared vertex"
       "edge ID" (graph-edge-id edge)
       "source" (graph-edge-source edge)))
    (unless (member (graph-edge-target edge) names)
      (raise-arguments-error
       who "edge target naming a declared vertex"
       "edge ID" (graph-edge-id edge)
       "target" (graph-edge-target edge)))
    (void)))

(define (install-layout directed? vertices edges layout center radius tree-root
                        tree-x-spacing tree-y-spacing partite-order
                        spring-iterations spring-attraction spring-repulsion who)
  (case layout
    [(manual)
     (for ([vertex (in-list vertices)])
       (unless (vec2? (graph-vertex-position vertex))
         (raise-arguments-error
          who "a #:position for every vertex in a manual layout"
          "vertex" (graph-vertex-name vertex))))
     vertices]
    [(circle)
     (define count (length vertices))
     (for/list ([vertex (in-list vertices)] [index (in-naturals)])
       (graph-vertex-spec
        (graph-vertex-name vertex)
        (vec2+ center
               (vec2 (* radius (cos (* 2 pi (/ index count))))
                     (* radius (sin (* 2 pi (/ index count))))))
        (graph-vertex-label vertex)
        (graph-vertex-partition vertex)))]
    [(tree)
     (install-tree-layout vertices edges center tree-root tree-x-spacing
                          tree-y-spacing who)]
    [(spring)
     (install-spring-layout vertices edges center radius spring-iterations
                            spring-attraction spring-repulsion)]
    [(layered)
     (unless directed?
       (raise-arguments-error who "a directed graph for the layered layout"
                              "layout" layout))
     (install-layered-layout vertices edges center tree-x-spacing tree-y-spacing who)]
    [(partite)
     (install-partite-layout vertices center tree-x-spacing tree-y-spacing
                             partite-order who)]
    [(planar)
     (install-planar-layout vertices edges center radius who)]))

(define (install-tree-layout vertices edges center requested-root x-spacing
                             y-spacing who)
  (define names (map graph-vertex-name vertices))
  (define children-by-parent
    (for/fold ([children (hash)]) ([edge (in-list edges)])
      (hash-update children
                   (graph-edge-source edge)
                   (lambda (old)
                     (append old (list (graph-edge-target edge))))
                   '())))
  (define incoming-counts
    (for/fold ([counts (for/hash ([name (in-list names)]) (values name 0))])
              ([edge (in-list edges)])
      (hash-update counts (graph-edge-target edge) add1)))
  (unless (= (length edges) (sub1 (length vertices)))
    (raise-arguments-error
     who "a tree layout needs exactly one fewer edge than vertices"
     "vertex-count" (length vertices)
     "edge-count" (length edges)))
  (define inferred-roots
    (filter (lambda (name) (zero? (hash-ref incoming-counts name))) names))
  (define root
    (cond
      [requested-root
       (unless (member requested-root names)
         (raise-arguments-error
          who "a tree root naming a declared vertex"
          "tree root" requested-root))
       requested-root]
      [(= (length inferred-roots) 1)
       (car inferred-roots)]
      [else
       (raise-arguments-error
        who "one inferred root for a tree layout, or an explicit #:tree-root"
        "inferred roots" inferred-roots)]))
  (unless (zero? (hash-ref incoming-counts root))
    (raise-arguments-error
     who "a tree root without an incoming edge"
     "tree root" root))
  (for ([name (in-list names)] #:unless (eq? name root))
    (unless (= (hash-ref incoming-counts name) 1)
      (raise-arguments-error
       who "every non-root tree vertex having exactly one parent"
       "vertex" name
       "incoming-edge-count" (hash-ref incoming-counts name))))
  (define-values (levels order)
    (tree-levels root children-by-parent))
  (unless (= (length order) (length vertices))
    (raise-arguments-error
     who "a connected acyclic directed tree"
     "reachable-vertices" order
     "vertices" names))
  (define max-level
    (apply max (hash-values levels)))
  (define positions
    (for/fold ([result (hash)]) ([level (in-range (add1 max-level))])
      (define members
        (filter (lambda (name) (= (hash-ref levels name) level)) order))
      (define count (length members))
      (for/fold ([with-level result]) ([name (in-list members)]
                                      [index (in-naturals)])
        (hash-set
         with-level name
         (vec2 (+ (vec2-x center)
                  (* x-spacing (- index (/ (sub1 count) 2))))
               (+ (vec2-y center)
                  (* y-spacing (- (/ max-level 2) level))))))))
  (for/list ([vertex (in-list vertices)])
    (graph-vertex-spec (graph-vertex-name vertex)
                       (hash-ref positions (graph-vertex-name vertex))
                       (graph-vertex-label vertex)
                       (graph-vertex-partition vertex))))

(define (tree-levels root children-by-parent)
  (let loop ([pending (list root)]
             [levels (hash root 0)]
             [order '()])
    (cond
      [(null? pending)
       (values levels (reverse order))]
      [else
       (define current (car pending))
       (define current-level (hash-ref levels current))
       (define children (hash-ref children-by-parent current '()))
       (when (ormap (lambda (child) (hash-has-key? levels child)) children)
         (raise-arguments-error
          'graph "an acyclic tree layout" "revisited vertex" current))
       (loop (append (cdr pending) children)
             (for/fold ([next-levels levels]) ([child (in-list children)])
               (hash-set next-levels child (add1 current-level)))
             (cons current order))])))

;; The spring layout is a deterministic Jacobi force iteration.  It starts from
;; declared positions when available and otherwise uses a circle, so there is no
;; hidden random seed or frame-history dependence.  It is deliberately a layout
;; snapshot: later vertex animation still uses the normal derived-edge model.
(define (install-spring-layout vertices edges center radius iterations attraction repulsion)
  (define names (map graph-vertex-name vertices))
  (define count (length vertices))
  (define starting-positions
    (for/hash ([vertex (in-list vertices)] [index (in-naturals)])
      (values
       (graph-vertex-name vertex)
       (or (graph-vertex-position vertex)
           (vec2+ center
                  (vec2 (* radius (cos (* 2 pi (/ index count))))
                        (* radius (sin (* 2 pi (/ index count))))))))))
  (define (add-force forces name force)
    (hash-update forces name (lambda (previous) (vec2+ previous force)) origin))
  (define (direction first second first-index second-index)
    (define difference (vec2- second first))
    (define distance (vector-length difference))
    (if (> distance 1e-9)
        (vec2-scale (/ 1 distance) difference)
        (let ([angle (* 2 pi
                        (/ (modulo (+ (* 17 first-index) (* 29 second-index)) 97)
                           97))])
          (vec2 (cos angle) (sin angle)))))
  (define (recenter positions)
    (define average
      (for/fold ([total origin]) ([name (in-list names)])
        (vec2+ total (hash-ref positions name))))
    (define mean (vec2-scale (/ 1 count) average))
    (for/hash ([name (in-list names)])
      (values name (vec2+ center (vec2- (hash-ref positions name) mean)))))
  (define final-positions
    (for/fold ([positions starting-positions]) ([iteration (in-range iterations)])
      (define initial-forces
        (for/hash ([name (in-list names)]) (values name origin)))
      (define with-repulsion
        (for*/fold ([forces initial-forces])
                   ([first-index (in-range count)]
                    [second-index (in-range (add1 first-index) count)])
          (define first-name (list-ref names first-index))
          (define second-name (list-ref names second-index))
          (define first-position (hash-ref positions first-name))
          (define second-position (hash-ref positions second-name))
          (define displacement (vec2- second-position first-position))
          (define distance (max 1e-6 (vector-length displacement)))
          (define unit (direction first-position second-position first-index second-index))
          (define magnitude (/ (* repulsion radius radius) (* distance distance)))
          (define force (vec2-scale magnitude unit))
          (add-force (add-force forces first-name (vec2-scale -1 force))
                     second-name force)))
      (define with-attraction
        (for/fold ([forces with-repulsion]) ([edge (in-list edges)])
          (if (eq? (graph-edge-source edge) (graph-edge-target edge))
              forces
              (let* ([source (graph-edge-source edge)]
                     [target (graph-edge-target edge)]
                     [source-position (hash-ref positions source)]
                     [target-position (hash-ref positions target)]
                     [difference (vec2- target-position source-position)]
                     [distance (max 1e-6 (vector-length difference))]
                     [unit (vec2-scale (/ 1 distance) difference)]
                     [magnitude (* attraction (/ (* distance distance) radius))]
                     [force (vec2-scale magnitude unit)])
                (add-force (add-force forces source force)
                           target (vec2-scale -1 force))))))
      (define cooling
        (* (/ radius 8)
           (max 1/20 (- 1 (/ iteration iterations)))))
      (recenter
       (for/hash ([name (in-list names)])
         (define force (hash-ref with-attraction name))
         (define magnitude (vector-length force))
         (define step
           (if (> magnitude cooling)
               (vec2-scale (/ cooling magnitude) force)
               force))
         (values name (vec2+ (hash-ref positions name) step))))))
  (for/list ([vertex (in-list vertices)])
    (vertex-with-position vertex
                          (hash-ref final-positions (graph-vertex-name vertex)))))

;; Layered layout uses a stable Kahn traversal. A topological layer is inferred
;; from the largest parent layer; declaration order decides sibling order.
(define (install-layered-layout vertices edges center x-spacing y-spacing who)
  (define names (map graph-vertex-name vertices))
  (define ordinary-edges
    (filter (lambda (edge)
              (not (eq? (graph-edge-source edge) (graph-edge-target edge))))
            edges))
  (define initial-incoming
    (for/fold ([counts (for/hash ([name (in-list names)]) (values name 0))])
              ([edge (in-list ordinary-edges)])
      (hash-update counts (graph-edge-target edge) add1)))
  (define-values (levels order)
    (let loop ([remaining names]
               [incoming initial-incoming]
               [current-level (for/hash ([name (in-list names)]) (values name 0))]
               [done '()])
      (cond
        [(null? remaining)
         (values current-level (reverse done))]
        [else
         (define next
           (for/first ([name (in-list remaining)]
                       #:when (zero? (hash-ref incoming name)))
             name))
         (unless next
           (raise-arguments-error
            who
            "an acyclic directed graph for the layered layout"
            "remaining vertices" remaining))
         (define next-level (hash-ref current-level next))
         (define outgoing
           (filter (lambda (edge) (eq? (graph-edge-source edge) next))
                   ordinary-edges))
         (define next-incoming
           (for/fold ([counts incoming]) ([edge (in-list outgoing)])
             (hash-update counts (graph-edge-target edge) sub1)))
         (define next-levels
           (for/fold ([result current-level]) ([edge (in-list outgoing)])
             (define target (graph-edge-target edge))
             (hash-set result target
                       (max (hash-ref result target) (add1 next-level)))))
         (loop (remove next remaining)
               next-incoming
               next-levels
               (cons next done))])))
  (define maximum-level (apply max (hash-values levels)))
  (define positions
    (for/fold ([result (hash)]) ([level (in-range (add1 maximum-level))])
      (define members
        (filter (lambda (name) (= (hash-ref levels name) level)) order))
      (define member-count (length members))
      (for/fold ([with-level result]) ([name (in-list members)] [index (in-naturals)])
        (hash-set
         with-level name
         (vec2 (+ (vec2-x center)
                  (* x-spacing (- index (/ (sub1 member-count) 2))))
               (+ (vec2-y center)
                  (* y-spacing (- (/ maximum-level 2) level))))))))
  (for/list ([vertex (in-list vertices)])
    (vertex-with-position vertex (hash-ref positions (graph-vertex-name vertex)))))

;; Partite placement uses author-named vertex partitions. The order is either
;; explicit or the stable first-occurrence order in the vertex declaration.
(define (install-partite-layout vertices center x-spacing y-spacing supplied-order who)
  (define discovered-order
    (for/fold ([order '()]) ([vertex (in-list vertices)])
      (define partition (graph-vertex-partition vertex))
      (unless partition
        (raise-arguments-error who "a #:partition for every partite vertex"
                               "vertex" (graph-vertex-name vertex)))
      (if (member partition order) order (append order (list partition)))))
  (define partitions (or supplied-order discovered-order))
  (unless (andmap (lambda (partition) (member partition partitions)) discovered-order)
    (raise-arguments-error who "a #:partite-order covering every vertex partition"
                           "partitions" discovered-order
                           "partite order" partitions))
  (define partition-count (length partitions))
  (define positions
    (for/fold ([result (hash)]) ([partition (in-list partitions)] [partition-index (in-naturals)])
      (define members
        (filter (lambda (vertex)
                  (eq? (graph-vertex-partition vertex) partition))
                vertices))
      (define member-count (length members))
      (for/fold ([with-partition result])
                ([vertex (in-list members)] [index (in-naturals)])
        (hash-set
         with-partition
         (graph-vertex-name vertex)
         (vec2 (+ (vec2-x center)
                  (* x-spacing (- partition-index (/ (sub1 partition-count) 2))))
               (+ (vec2-y center)
                  (* y-spacing (- (/ (sub1 member-count) 2) index))))))))
  (for/list ([vertex (in-list vertices)])
    (vertex-with-position vertex (hash-ref positions (graph-vertex-name vertex)))))

;; This first deterministic planar layout searches for a crossing-free circular
;; embedding. It therefore covers trees, cycles, and small outerplanar graphs;
;; it rejects an input that has no such embedding instead of presenting a
;; misleading crossed drawing as planar.
(define (install-planar-layout vertices edges center radius who)
  (define names (map graph-vertex-name vertices))
  (define order
    (cond
      [(<= (length names) 8)
       (for/first ([tail (in-list (permutations (cdr names)))]
                   #:when (outerplanar-order? (cons (car names) tail) edges))
         (cons (car names) tail))]
      [(outerplanar-order? names edges) names]
      [else #f]))
  (unless order
    (raise-arguments-error
     who
     "a crossing-free outerplanar circular embedding (up to eight vertices are searched)"
     "vertex count" (length vertices)))
  (define count (length order))
  (define positions
    (for/hash ([name (in-list order)] [index (in-naturals)])
      (values name
              (vec2+ center
                     (vec2 (* radius (cos (* 2 pi (/ index count))))
                           (* radius (sin (* 2 pi (/ index count)))))))))
  (for/list ([vertex (in-list vertices)])
    (vertex-with-position vertex (hash-ref positions (graph-vertex-name vertex)))))

(define (outerplanar-order? order edges)
  (define indices
    (for/hash ([name (in-list order)] [index (in-naturals)]) (values name index)))
  (define ordinary-edges
    (filter (lambda (edge)
              (not (eq? (graph-edge-source edge) (graph-edge-target edge))))
            edges))
  (not
   (for*/or ([first (in-list ordinary-edges)]
             [second (in-list ordinary-edges)]
             #:when (< (graph-edge-id-index first ordinary-edges)
                       (graph-edge-id-index second ordinary-edges)))
     (and (not (or (eq? (graph-edge-source first) (graph-edge-source second))
                   (eq? (graph-edge-source first) (graph-edge-target second))
                   (eq? (graph-edge-target first) (graph-edge-source second))
                   (eq? (graph-edge-target first) (graph-edge-target second))))
          (chords-cross?
           (hash-ref indices (graph-edge-source first))
           (hash-ref indices (graph-edge-target first))
           (hash-ref indices (graph-edge-source second))
           (hash-ref indices (graph-edge-target second)))))))

(define (graph-edge-id-index edge edges)
  (or (for/first ([candidate (in-list edges)] [index (in-naturals)]
                  #:when (eq? edge candidate))
        index)
      -1))

(define (chords-cross? first-start first-end second-start second-end)
  (define low-first (min first-start first-end))
  (define high-first (max first-start first-end))
  (define low-second (min second-start second-end))
  (define high-second (max second-start second-end))
  (or (and (< low-first low-second high-first) (< high-first high-second))
      (and (< low-second low-first high-second) (< high-second high-first))))

(define (vertex-with-position vertex position)
  (graph-vertex-spec (graph-vertex-name vertex)
                     position
                     (graph-vertex-label vertex)
                     (graph-vertex-partition vertex)))

(define (vector-length value)
  (sqrt (+ (sqr (vec2-x value)) (sqr (vec2-y value)))))


;;;
;;; Group Contents and Live Edges
;;;

;; A route records only immutable construction choices. The actual curve is a
;; derived Visual and is rebuilt from current sampled endpoint positions.
(struct edge-route (curvature loop-index loop-count loop-radius)
  #:transparent)

(define (edge-routing edge all-edges default-curvature parallel-separation loop-radius)
  (define source (graph-edge-source edge))
  (define target (graph-edge-target edge))
  (cond
    [(eq? source target)
     (define loops
       (filter (lambda (candidate)
                 (and (eq? (graph-edge-source candidate) source)
                      (eq? (graph-edge-target candidate) target)))
               all-edges))
     (edge-route 0
                 (edge-index edge loops)
                 (length loops)
                 loop-radius)]
    [else
     ;; Lanes are assigned in an unordered pair's declaration order. Convert
     ;; the lane back to the current edge orientation so A->B and B->A occupy
     ;; different geometric arcs instead of one shared curve with two tips.
     (define parallel
       (filter (lambda (candidate)
                 (and (not (eq? (graph-edge-source candidate)
                                (graph-edge-target candidate)))
                      (same-unordered-endpoints? edge candidate)))
               all-edges))
     (define lane
       (- (edge-index edge parallel)
          (/ (sub1 (length parallel)) 2)))
     (define orientation
       (if (symbol-name<? source target) 1 -1))
     (edge-route
      (or (graph-edge-curvature edge)
          (+ default-curvature
             (* orientation lane parallel-separation)))
      #f #f loop-radius)]))

(define (same-unordered-endpoints? first second)
  (or (and (eq? (graph-edge-source first) (graph-edge-source second))
           (eq? (graph-edge-target first) (graph-edge-target second)))
      (and (eq? (graph-edge-source first) (graph-edge-target second))
           (eq? (graph-edge-target first) (graph-edge-source second)))))

(define (edge-index edge edges)
  (or (for/first ([candidate (in-list edges)] [index (in-naturals)]
                  #:when (eq? edge candidate))
        index)
      (raise-arguments-error 'graph "an edge from its declared edge list"
                             "edge" edge)))

(define (symbol-name<? first second)
  (string<? (symbol->string first) (symbol->string second)))

(define (make-vertex-group vertex shape size fill stroke stroke-width
                           label-offset label-size label-color)
  (define name (graph-vertex-name vertex))
  (define marker
    (point-marker #:id 'body #:center origin #:shape shape #:size size
                  #:fill fill #:stroke stroke #:stroke-width stroke-width))
  (define children
    (if (graph-vertex-label vertex)
        (list marker
              (plain-text (graph-vertex-label vertex)
                          #:id 'label #:center label-offset
                          #:font-size label-size #:font-family 'swiss
                          #:font-weight 'bold #:color label-color))
        (list marker)))
  (group children #:id name #:center (graph-vertex-position vertex)))

(define (make-edge-group graph-id edge directed? vertex-size default-stroke
                         default-stroke-width label-offset label-size label-color route)
  (define start-path
    (graph-vertex-path graph-id (graph-edge-source edge)))
  (define end-path
    (graph-vertex-path graph-id (graph-edge-target edge)))
  (define stroke (or (graph-edge-stroke edge) default-stroke))
  (define stroke-width
    (or (graph-edge-stroke-width edge)
        (* default-stroke-width (graph-edge-weight edge))))
  (define (current-endpoints context)
    (values
     (graph-world-point->local
      context graph-id
      (visual-position (derived-context-visual-ref context start-path)))
     (graph-world-point->local
      context graph-id
      (visual-position (derived-context-visual-ref context end-path)))))
  (define edge-line
    (derived-visual
     (live-edge-visual (vec2 -1/2 0) (vec2 1/2 0) 'line directed?
                       vertex-size route stroke stroke-width)
     (lambda (context _template)
       (define-values (start end) (current-endpoints context))
       (live-edge-visual start end 'line directed? vertex-size route
                         stroke stroke-width))))
  (define children
    (if (graph-edge-label edge)
        (list edge-line
              (derived-visual
               (plain-text (graph-edge-label edge)
                           #:id 'label #:center origin
                           #:font-size label-size #:font-family 'swiss
                           #:color label-color)
               (lambda (context template)
                 (define-values (start end) (current-endpoints context))
                 (visual-with-position
                  template
                  (vec2+ (edge-label-position start end vertex-size route)
                         label-offset)))))
        (list edge-line)))
  (group children #:id (graph-edge-id edge)))

;; A straight edge keeps the established line/arrow leaf representation. A
;; curved edge becomes a path leaf, or a small shaft/tip group for directed
;; graphs; both have stable `line` identities inside their containing edge.
(define (live-edge-visual start end id directed? vertex-size route stroke stroke-width)
  (cond
    [(eq? (edge-route-loop-index route) #f)
     (define-values (trimmed-start trimmed-end)
       (trim-edge-endpoints start end vertex-size id))
     (define curvature (edge-route-curvature route))
     (if (zero? curvature)
         (if directed?
             (arrow trimmed-start trimmed-end #:id id #:stroke stroke
                    #:stroke-width stroke-width #:tip-length 1/4 #:tip-width 1/5)
             (line trimmed-start trimmed-end #:id id #:stroke stroke
                   #:stroke-width stroke-width))
         (curved-edge-visual trimmed-start trimmed-end id directed? curvature
                             stroke stroke-width))]
    [else
     (loop-edge-visual start id directed? vertex-size route stroke stroke-width)]))

(define (curved-edge-visual start end id directed? curvature stroke stroke-width)
  (define geometry (curved-edge-geometry start end curvature))
  (cond
    [(not directed?)
     (make-path-visual geometry #:id id #:center origin #:fill #f
                       #:stroke stroke #:stroke-width stroke-width)]
    [else
     (define shaft
       (make-path-visual geometry #:id 'shaft #:center origin #:fill #f
                         #:stroke stroke #:stroke-width stroke-width))
     (define endpoint-tangent
       (curved-edge-end-tangent start end curvature))
     (define tip
       (make-path-visual
        (path-geometry
         (list
          (arrowhead-subpath end
                             (vec2- end endpoint-tangent)
                             1/4 1/5)))
        #:id 'tip #:center origin #:fill stroke #:stroke stroke
        #:stroke-width stroke-width))
     (group (list shaft tip) #:id id)]))

(define (loop-edge-visual center id directed? vertex-size route stroke stroke-width)
  (define geometry (loop-edge-geometry center vertex-size route))
  (cond
    [(not directed?)
     (make-path-visual geometry #:id id #:center origin #:fill #f
                       #:stroke stroke #:stroke-width stroke-width)]
    [else
     (define endpoint (loop-edge-endpoint center vertex-size route))
     (define tangent (loop-edge-end-tangent center vertex-size route))
     (define shaft
       (make-path-visual geometry #:id 'shaft #:center origin #:fill #f
                         #:stroke stroke #:stroke-width stroke-width))
     (define tip
       (make-path-visual
        (path-geometry
         (list (arrowhead-subpath endpoint
                                  (vec2- endpoint tangent)
                                  1/4 1/5)))
        #:id 'tip #:center origin #:fill stroke #:stroke stroke
        #:stroke-width stroke-width))
     (group (list shaft tip) #:id id)]))

(define (curved-edge-geometry start end curvature)
  (define chord (vec2- end start))
  (define distance (vector-length chord))
  (define normal
    (vec2 (/ (- (vec2-y chord)) distance)
          (/ (vec2-x chord) distance)))
  (define offset (vec2-scale (* curvature distance) normal))
  (path-geometry
   (list
    (path-subpath
     start
     (list (cubic-bezier-path-segment (vec2+ start offset)
                                      (vec2+ end offset)
                                      end))
     #f))))

(define (curved-edge-end-tangent start end curvature)
  (define chord (vec2- end start))
  (define distance (vector-length chord))
  (define normal
    (vec2 (/ (- (vec2-y chord)) distance)
          (/ (vec2-x chord) distance)))
  (vec2- end (vec2+ end (vec2-scale (* curvature distance) normal))))

(define (loop-edge-geometry center vertex-size route)
  (define-values (start top end _control2)
    (loop-edge-points center vertex-size route))
  (define radius (loop-route-radius route))
  (path-geometry
   (list
    (path-subpath
     start
     (list
      (cubic-bezier-path-segment
       (vec2+ start (vec2 (- radius) (/ radius 2)))
       (vec2+ top (vec2 (- radius) (- (/ radius 2))))
       top)
      (cubic-bezier-path-segment
       (vec2+ top (vec2 radius (- (/ radius 2))))
       (vec2+ end (vec2 radius (/ radius 2)))
       end))
     #f))))

(define (loop-edge-points center vertex-size route)
  (define radius (loop-route-radius route))
  (define lane
    (- (edge-route-loop-index route)
       (/ (sub1 (edge-route-loop-count route)) 2)))
  (define loop-center
    (vec2+ center (vec2 (* lane radius) 0)))
  (define half-width (max (/ vertex-size 3) (/ radius 3)))
  (define base-height (/ vertex-size 2))
  (define start (vec2+ loop-center (vec2 (- half-width) base-height)))
  (define top (vec2+ loop-center (vec2 0 (+ base-height (* 2 radius)))))
  (define end (vec2+ loop-center (vec2 half-width base-height)))
  (values start top end (vec2+ end (vec2 radius (/ radius 2)))))

(define (loop-route-radius route)
  (* (edge-route-loop-radius route)
     (+ 1 (* 2/3 (edge-route-loop-index route)))))

(define (loop-edge-endpoint center vertex-size route)
  (define-values (_start _top end _control2)
    (loop-edge-points center vertex-size route))
  end)

(define (loop-edge-end-tangent center vertex-size route)
  (define-values (_start _top end control2)
    (loop-edge-points center vertex-size route))
  (vec2- end control2))

(define (edge-label-position start end vertex-size route)
  (cond
    [(not (eq? (edge-route-loop-index route) #f))
     (define-values (_start top _end _control2)
       (loop-edge-points start vertex-size route))
     top]
    [(zero? (edge-route-curvature route))
     (vec2-scale 1/2 (vec2+ start end))]
    [else
     ;; The midpoint of a cubic with symmetric normal controls is its chord
     ;; midpoint plus three quarters of the control offset.
     (define chord (vec2- end start))
     (define distance (vector-length chord))
     (define normal
       (vec2 (/ (- (vec2-y chord)) distance)
             (/ (vec2-x chord) distance)))
     (vec2+ (vec2-scale 1/2 (vec2+ start end))
            (vec2-scale (* 3/4 (edge-route-curvature route) distance)
                        normal))]))


;;;
;;; Pure Educational Graph Traversals
;;;

;; These helpers operate on the author-declared immutable edge list rather than
;; a rendered graph. They return stable vertex-name sequences that an author can
;; turn into `fill-color-to`, `indicate`, or sectioned animation requests.

(define (graph-bfs edges source #:directed? [directed? #t])
  (check-traversal-input 'graph-bfs edges source directed?)
  (define adjacency (graph-adjacency edges directed?))
  (let loop ([queue (list source)]
             [seen (hash source #t)]
             [order '()])
    (cond
      [(null? queue) (reverse order)]
      [else
       (define current (car queue))
       (define-values (new-neighbours next-seen)
         (for/fold ([new '()] [known seen])
                   ([neighbour (in-list (hash-ref adjacency current '()))])
           (if (hash-has-key? known neighbour)
               (values new known)
               (values (append new (list neighbour))
                       (hash-set known neighbour #t)))))
       (loop (append (cdr queue) new-neighbours)
             next-seen
             (cons current order))])))

(define (graph-dfs edges source #:directed? [directed? #t])
  (check-traversal-input 'graph-dfs edges source directed?)
  (define adjacency (graph-adjacency edges directed?))
  (define-values (_seen reverse-order)
    (let visit ([current source] [seen (hash)] [order '()])
      (if (hash-has-key? seen current)
          (values seen order)
          (for/fold ([next-seen (hash-set seen current #t)]
                     [next-order (cons current order)])
                    ([neighbour (in-list (hash-ref adjacency current '()))])
            (visit neighbour next-seen next-order)))))
  (reverse reverse-order))

;; graph-shortest-path : (listof graph-edge?) symbol? symbol?
;;                       [#:directed? boolean?] -> (or/c (listof symbol?) false/c)
;; Unweighted shortest path uses the same deterministic breadth-first order.
(define (graph-shortest-path edges source target #:directed? [directed? #t])
  (check-traversal-input 'graph-shortest-path edges source directed?)
  (check-traversal-vertex 'graph-shortest-path edges target)
  (define adjacency (graph-adjacency edges directed?))
  (cond
    [(eq? source target) (list source)]
    [else
     (let loop ([queue (list source)] [parents (hash source #f)])
       (cond
         [(null? queue) #f]
         [else
          (define current (car queue))
          (define-values (new-neighbours next-parents found?)
            (for/fold ([new '()] [known parents] [found? #f])
                      ([neighbour (in-list (hash-ref adjacency current '()))])
              (cond
                [(hash-has-key? known neighbour)
                 (values new known found?)]
                [else
                 (values (append new (list neighbour))
                         (hash-set known neighbour current)
                         (or found? (eq? neighbour target)))])))
          (if found?
              (reconstruct-graph-path next-parents target)
              (loop (append (cdr queue) new-neighbours) next-parents))]))]))

(define (graph-adjacency edges directed?)
  (for/fold ([adjacency (hash)]) ([edge (in-list edges)])
    (define source (graph-edge-source edge))
    (define target (graph-edge-target edge))
    (define with-forward
      (hash-update adjacency source (lambda (old) (append old (list target))) '()))
    (if directed?
        with-forward
        (hash-update with-forward target (lambda (old) (append old (list source))) '()))))

(define (reconstruct-graph-path parents target)
  (let loop ([current target] [path (list target)])
    (define parent (hash-ref parents current #f))
    (if parent
        (loop parent (cons parent path))
        path)))

(define (check-traversal-input who edges source directed?)
  (unless (and (list? edges) (pair? edges) (andmap graph-edge? edges))
    (raise-argument-error who "nonempty list of graph-edge? values" edges))
  (unless (boolean? directed?)
    (raise-argument-error who "boolean?" directed?))
  (check-traversal-vertex who edges source))

(define (check-traversal-vertex who edges vertex)
  (unless (symbol? vertex)
    (raise-argument-error who "symbol?" vertex))
  (unless (for/or ([edge (in-list edges)])
            (or (eq? vertex (graph-edge-source edge))
                (eq? vertex (graph-edge-target edge))))
    (raise-arguments-error who "a vertex named by the edge list"
                           "vertex" vertex)))

;; A graph's edge geometry is local to its root group. Endpoint references from
;; the generic derived context are world-space (which is essential for normal
;; nested dependencies), so remove the graph root's own affine transform before
;; returning local line/arrow points. This makes moving, rotating, or scaling a
;; complete graph apply exactly once to both vertices and live edges.
(define (graph-world-point->local context graph-id point)
  (define root
    (derived-context-visual-ref context graph-id))
  (unless (affine-visual? root)
    (raise-arguments-error
     'graph "an affine graph root" "graph ID" graph-id "root" root))
  (define transform (visual-transform root))
  (define displacement
    (vec2- point (affine-transform-translation transform)))
  (define angle (affine-transform-rotation transform))
  (define scale (affine-transform-scale transform))
  (define cosine (cos angle))
  (define sine (sin angle))
  (vec2 (/ (+ (* cosine (vec2-x displacement))
              (* sine (vec2-y displacement)))
           (vec2-x scale))
        (/ (+ (* (- sine) (vec2-x displacement))
              (* cosine (vec2-y displacement)))
           (vec2-y scale))))

(define (trim-edge-endpoints start end vertex-size edge-id)
  (define displacement (vec2- end start))
  (define distance
    (sqrt (+ (sqr (vec2-x displacement))
             (sqr (vec2-y displacement)))))
  (unless (positive? distance)
    (raise-arguments-error
     'graph
     "distinct sampled positions for the edge endpoints"
     "edge ID" edge-id
     "start" start
     "end" end))
  ;; Preserve a visible shaft even when authors move two vertices closer than
  ;; their visual diameters. A true coincidence remains invalid geometry.
  (define trim (min (/ vertex-size 2) (/ distance 3)))
  (define direction (vec2-scale (/ 1 distance) displacement))
  (values (vec2+ start (vec2-scale trim direction))
          (vec2- end (vec2-scale trim direction))))


;;;
;;; Small Validation Helpers
;;;

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-positive who label value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "a positive finite real" label value)))

(define (check-nonnegative who label value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who "a nonnegative finite real" label value)))

(define (check-optional-symbol-list who label value)
  (unless (or (not value)
              (and (list? value) (andmap symbol? value)))
    (raise-arguments-error who "false or a list of symbols" label value))
  (when value
    (check-unique who value label)))

(define (check-unique who values label)
  (define duplicate
    (let loop ([remaining values] [seen (hash)])
      (cond
        [(null? remaining) #f]
        [(hash-has-key? seen (car remaining)) (car remaining)]
        [else
         (loop (cdr remaining) (hash-set seen (car remaining) #t))])))
  (when duplicate
    (raise-arguments-error who "names must be unique" label duplicate)))
