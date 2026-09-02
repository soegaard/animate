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
         "point-marker-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide graph-vertex
         graph-vertex?
         graph-vertex-name
         graph-vertex-position
         graph-vertex-label
         graph-edge
         graph-edge?
         graph-edge-source
         graph-edge-target
         graph-edge-id
         graph-edge-label
         graph-layout?
         graph
         digraph
         graph-vertices-path
         graph-edges-path
         graph-vertex-path
         graph-edge-path)


;;;
;;; Author-Facing Specifications
;;;

(struct graph-vertex-spec (name position label)
  #:transparent)

;; graph-vertex : symbol? [#:position (or/c vec2? false/c)]
;;                [#:label (or/c string? false/c)] -> graph-vertex?
;; A position is required by the manual layout and intentionally ignored by the
;; circle/tree layouts, which calculate it deterministically from list order.
(define (graph-vertex name
                      #:position [position #f]
                      #:label [label #f])
  (unless (symbol? name)
    (raise-argument-error 'graph-vertex "symbol?" name))
  (unless (or (not position) (vec2? position))
    (raise-argument-error 'graph-vertex "(or/c vec2? false/c)" position))
  (unless (or (not label) (string? label))
    (raise-argument-error 'graph-vertex "(or/c string? false/c)" label))
  (graph-vertex-spec name position label))

(define graph-vertex? graph-vertex-spec?)
(define graph-vertex-name graph-vertex-spec-name)
(define graph-vertex-position graph-vertex-spec-position)
(define graph-vertex-label graph-vertex-spec-label)

(struct graph-edge-spec (source target id label)
  #:transparent)

;; graph-edge : symbol? symbol? [#:id symbol?] [#:label (or/c string? false/c)]
;;               -> graph-edge?
;; An omitted ID is stable and readable, for example `A->B`.
(define (graph-edge source target
                    #:id [id #f]
                    #:label [label #f])
  (unless (symbol? source)
    (raise-argument-error 'graph-edge "symbol?" source))
  (unless (symbol? target)
    (raise-argument-error 'graph-edge "symbol?" target))
  (unless (or (not id) (symbol? id))
    (raise-argument-error 'graph-edge "(or/c symbol? false/c)" id))
  (unless (or (not label) (string? label))
    (raise-argument-error 'graph-edge "(or/c string? false/c)" label))
  (graph-edge-spec source target
                   (or id (default-edge-id source target))
                   label))

(define graph-edge? graph-edge-spec?)
(define graph-edge-source graph-edge-spec-source)
(define graph-edge-target graph-edge-spec-target)
(define graph-edge-id graph-edge-spec-id)
(define graph-edge-label graph-edge-spec-label)

(define (default-edge-id source target)
  (string->symbol
   (string-append (symbol->string source)
                  "->"
                  (symbol->string target))))

(define (graph-layout? value)
  (and (symbol? value)
       (memq value '(manual circle tree))
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
;;         [#:vertex-shape point-marker-shape?]
;;         [#:vertex-size positive-finite-real?]
;;         [#:vertex-fill any/c] [#:vertex-stroke any/c]
;;         [#:vertex-stroke-width nonnegative-finite-real?]
;;         [#:vertex-label-offset vec2?] [#:vertex-label-size positive-finite-real?]
;;         [#:vertex-label-color any/c]
;;         [#:edge-stroke any/c] [#:edge-stroke-width nonnegative-finite-real?]
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
               #:edge-label-offset [edge-label-offset (vec2 0 1/5)]
               #:edge-label-size [edge-label-size 1/5]
               #:edge-label-color [edge-label-color "darkslategray"])
  (make-graph
   #f vertices edges id layout layout-center layout-radius tree-root
   tree-x-spacing tree-y-spacing vertex-shape vertex-size vertex-fill
   vertex-stroke vertex-stroke-width vertex-label-offset vertex-label-size
   vertex-label-color edge-stroke edge-stroke-width edge-label-offset
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
                 #:edge-label-offset [edge-label-offset (vec2 0 1/5)]
                 #:edge-label-size [edge-label-size 1/5]
                 #:edge-label-color [edge-label-color "darkslategray"])
  (make-graph
   #t vertices edges id layout layout-center layout-radius tree-root
   tree-x-spacing tree-y-spacing vertex-shape vertex-size vertex-fill
   vertex-stroke vertex-stroke-width vertex-label-offset vertex-label-size
   vertex-label-color edge-stroke edge-stroke-width edge-label-offset
   edge-label-size edge-label-color 'digraph))

(define (make-graph directed? vertices edges id layout layout-center layout-radius
                    tree-root tree-x-spacing tree-y-spacing vertex-shape
                    vertex-size vertex-fill vertex-stroke vertex-stroke-width
                    vertex-label-offset vertex-label-size vertex-label-color
                    edge-stroke edge-stroke-width edge-label-offset
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
  (check-graph-identities who id vertices edges)
  (check-graph-endpoints who vertices edges)
  (define positioned-vertices
    (install-layout vertices edges layout layout-center layout-radius tree-root
                    tree-x-spacing tree-y-spacing who))
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
                        edge-label-color))
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
    (when (eq? (graph-edge-source edge) (graph-edge-target edge))
      (raise-arguments-error
       who "an edge joining two distinct vertices"
       "edge ID" (graph-edge-id edge)
       "vertex" (graph-edge-source edge)))))

(define (install-layout vertices edges layout center radius tree-root
                        tree-x-spacing tree-y-spacing who)
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
        (graph-vertex-label vertex)))]
    [(tree)
     (install-tree-layout vertices edges center tree-root tree-x-spacing
                          tree-y-spacing who)]))

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
                       (graph-vertex-label vertex))))

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


;;;
;;; Group Contents and Live Edges
;;;

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

(define (make-edge-group graph-id edge directed? vertex-size stroke
                         stroke-width label-offset label-size label-color)
  (define start-path
    (graph-vertex-path graph-id (graph-edge-source edge)))
  (define end-path
    (graph-vertex-path graph-id (graph-edge-target edge)))
  (define edge-line
    (derived-visual
     (if directed?
         (arrow origin (vec2 1 0) #:id 'line #:stroke stroke
                #:stroke-width stroke-width #:tip-length 1/4 #:tip-width 1/5)
         (line origin (vec2 1 0) #:id 'line #:stroke stroke
               #:stroke-width stroke-width))
     (lambda (context _template)
       (define start
         (graph-world-point->local
          context graph-id
          (visual-position (derived-context-visual-ref context start-path))))
       (define end
         (graph-world-point->local
          context graph-id
          (visual-position (derived-context-visual-ref context end-path))))
       (define-values (trimmed-start trimmed-end)
         (trim-edge-endpoints start end vertex-size (graph-edge-id edge)))
       (if directed?
           (arrow trimmed-start trimmed-end #:id 'line #:stroke stroke
                  #:stroke-width stroke-width #:tip-length 1/4 #:tip-width 1/5)
           (line trimmed-start trimmed-end #:id 'line #:stroke stroke
                 #:stroke-width stroke-width)))))
  (define children
    (if (graph-edge-label edge)
        (list edge-line
              (derived-visual
               (plain-text (graph-edge-label edge)
                           #:id 'label #:center origin
                           #:font-size label-size #:font-family 'swiss
                           #:color label-color)
               (lambda (context template)
                 (define start
                   (graph-world-point->local
                    context graph-id
                    (visual-position
                     (derived-context-visual-ref context start-path))))
                 (define end
                   (graph-world-point->local
                    context graph-id
                    (visual-position
                     (derived-context-visual-ref context end-path))))
                 (visual-with-position
                  template
                  (vec2+ (vec2-scale 1/2 (vec2+ start end))
                         label-offset)))))
        (list edge-line)))
  (group children #:id (graph-edge-id edge)))

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
