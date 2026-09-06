#lang racket/base

;;;
;;; Semantic Two-Sided Mesh Cuts and Deterministic Cap Meshes
;;;

(require racket/list
         "../geometry.rkt"
         "cap-style3d.rkt"
         "clipping3d.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "mesh-orientation3d.rkt"
         "plane-basis3d.rkt"
         "ray-plane.rkt"
         "section-settings3d.rkt"
         "spatial-visual.rkt"
         "vec3.rkt")

(provide cut-mesh3d
         (struct-out mesh-cut3d-result)
         cap-section3d
         mesh3d-weld)

(struct mesh-cut3d-result
  (positive negative section positive-cap negative-cap positive-solid negative-solid diagnostics)
  #:transparent)

; cut-mesh3d : mesh3d? (or/c plane3? clip-plane3d?) ... -> mesh-cut3d-result?
;; Computes both retained half-spaces from exactly one immutable source mesh.
;; The cap fields remain separate on purpose: callers can layer, style, pick,
;; or merge them explicitly without losing provenance of the exposed surface.
(define (cut-mesh3d mesh plane-or-clip
                    #:settings [settings (section3d-settings-for-bounds (mesh3d-local-bounds mesh))]
                    #:positive-id [positive-id (string->symbol (format "~a-positive" (spatial-id mesh)))]
                    #:negative-id [negative-id (string->symbol (format "~a-negative" (spatial-id mesh)))]
                    #:cap [cap #f])
  (unless (mesh3d? mesh) (raise-argument-error 'cut-mesh3d "mesh3d?" mesh))
  (unless (section3d-settings? settings)
    (raise-argument-error 'cut-mesh3d "section3d-settings?" settings))
  (unless (and (symbol? positive-id) (symbol? negative-id))
    (raise-argument-error 'cut-mesh3d "symbol identifiers" (list positive-id negative-id)))
  (unless (or (not cap) (cap-style3d? cap))
    (raise-argument-error 'cut-mesh3d "#f or cap-style3d?" cap))
  (define plane (if (clip-plane3d? plane-or-clip)
                    (clip-plane3d-plane plane-or-clip)
                    plane-or-clip))
  (unless (plane3? plane) (raise-argument-error 'cut-mesh3d "plane3? or clip-plane3d?" plane-or-clip))
  (define section (section-by-plane3d mesh plane #:settings settings))
  (define positive (slice-mesh3d mesh plane #:id positive-id #:keep 'positive #:settings settings))
  (define negative (slice-mesh3d mesh plane #:id negative-id #:keep 'negative #:settings settings))
  (define positive-cap
    (and cap
         (spatial-with-transform
          (cap-section3d section #:side 'positive #:id (string->symbol (format "~a-cap" positive-id))
                         #:style cap)
          (spatial-transform mesh))))
  (define negative-cap
    (and cap
         (spatial-with-transform
          (cap-section3d section #:side 'negative #:id (string->symbol (format "~a-cap" negative-id))
                         #:style cap)
          (spatial-transform mesh))))
  ;; Separate caps preserve the deliberate style/provenance surface of a cut.
  ;; The optional solid forms are instead a single topological mesh for
  ;; analysis and later operations.  Welding is exact-coordinate only: the
  ;; side and cap were both derived from this one plane, so no tolerance-based
  ;; repair is allowed to invent topology.
  (define positive-solid
    (and positive-cap (zero? (cap-style3d-offset cap))
         (orient-cut-solid
          (mesh3d-weld (list positive positive-cap)
                       #:id (string->symbol (format "~a-solid" positive-id))
                       #:material (mesh3d-material mesh)))))
  (define negative-solid
    (and negative-cap (zero? (cap-style3d-offset cap))
         (orient-cut-solid
          (mesh3d-weld (list negative negative-cap)
                       #:id (string->symbol (format "~a-solid" negative-id))
                       #:material (mesh3d-material mesh)))))
  (mesh-cut3d-result
   positive negative section positive-cap negative-cap positive-solid negative-solid
   (hasheq 'settings settings
           'source-id (spatial-id mesh)
           'positive-triangle-count (vector-length (mesh3d-triangles positive))
           'negative-triangle-count (vector-length (mesh3d-triangles negative))
           'capped? (and cap #t)
           'solid? (and cap (zero? (cap-style3d-offset cap)))
           'solid-limit "a welded solid requires cap-style3d offset zero; use the separate offset cap for z-fighting avoidance"
           'cap-limit "closed nested loops are triangulated as holes; self-intersecting or touching contours are rejected")))

; mesh3d-weld : (nonempty-listof mesh3d?) #:id symbol? #:material material3d? -> mesh3d?
;; Combines meshes that share an exact generated boundary into one indexed
;; topology.  It deliberately compares local `vec3` values structurally, not
;; within a distance tolerance: callers with merely close geometry need to
;; repair that geometry explicitly before asking this operation to claim a
;; watertight mesh.  Per-vertex normals are omitted because `mesh3d` has only
;; one normal per shared vertex; retaining cap and side normals would require a
;; future per-corner-normal representation.
(define (mesh3d-weld meshes
                     #:id [id #f]
                     #:material [material #f])
  (unless (and (list? meshes) (pair? meshes) (andmap mesh3d? meshes))
    (raise-argument-error 'mesh3d-weld "nonempty list of mesh3d?" meshes))
  (define first-mesh (car meshes))
  (define final-id (or id (spatial-id first-mesh)))
  (unless (symbol? final-id)
    (raise-argument-error 'mesh3d-weld "symbol? as #:id" final-id))
  (define final-material (or material (mesh3d-material first-mesh)))
  (unless (material3d? final-material)
    (raise-argument-error 'mesh3d-weld "material3d? as #:material" final-material))
  (define transform (spatial-transform first-mesh))
  (define opacity (spatial-opacity first-mesh))
  (for ([mesh (in-list (cdr meshes))])
    (unless (and (equal? transform (spatial-transform mesh))
                 (= opacity (spatial-opacity mesh)))
      (raise-arguments-error 'mesh3d-weld
                             "meshes with one shared transform and opacity"
                             "first-transform" transform
                             "mesh-transform" (spatial-transform mesh)
                             "first-opacity" opacity
                             "mesh-opacity" (spatial-opacity mesh))))
  (define index-by-position (make-hash))
  ;; Gather colours by exact position before allocating output indices.  A cap
  ;; normally has no authored vertex colours, but all of its vertices are
  ;; already cut-boundary vertices in the side mesh and therefore inherit the
  ;; side's interpolated colour.  A mesh that introduces an uncoloured unique
  ;; vertex into an otherwise coloured weld is rejected rather than given a
  ;; misleading made-up value.
  (define color-by-position (make-hash))
  (for ([mesh (in-list meshes)]
        #:when (mesh3d-colors mesh))
    (for ([point (in-vector (mesh3d-vertices mesh))]
          [color (in-vector (mesh3d-colors mesh))])
      (cond [(hash-ref color-by-position point #f)
             => (lambda (old-color)
                  (unless (equal? old-color color)
                    (raise-arguments-error 'mesh3d-weld
                                           "identical colours at shared welded vertices"
                                           "position" point
                                           "first-colour" old-color
                                           "later-colour" color)))]
            [else (hash-set! color-by-position point color)])))
  (define carry-colors? (positive? (hash-count color-by-position)))
  (define vertices-reversed '())
  (define colors-reversed '())
  (define triangles-reversed '())
  (define next-index 0)
  (define (register! point)
    (cond [(hash-ref index-by-position point #f) => values]
          [else
           (define index next-index)
           (set! next-index (add1 next-index))
           (hash-set! index-by-position point index)
           (set! vertices-reversed (cons point vertices-reversed))
           (when carry-colors?
             (define color (hash-ref color-by-position point #f))
             (unless color
               (raise-arguments-error 'mesh3d-weld
                                      "a colour for each new welded vertex"
                                      "position" point))
             (set! colors-reversed (cons color colors-reversed)))
           index]))
  (for ([mesh (in-list meshes)])
    (define remap
      (for/vector ([point (in-vector (mesh3d-vertices mesh))])
        (register! point)))
    (for ([triangle (in-vector (mesh3d-triangles mesh))])
      (define welded-triangle
        (vector (vector-ref remap (vector-ref triangle 0))
                (vector-ref remap (vector-ref triangle 1))
                (vector-ref remap (vector-ref triangle 2))))
      (unless (= (length (remove-duplicates (vector->list welded-triangle))) 3)
        (raise-arguments-error 'mesh3d-weld
                               "input meshes without collapsed welded triangles"
                               "triangle" triangle))
      (set! triangles-reversed (cons welded-triangle triangles-reversed))))
  (mesh3d #:id final-id
          #:vertices (list->vector (reverse vertices-reversed))
          #:triangles (list->vector (reverse triangles-reversed))
          #:colors (and carry-colors? (list->vector (reverse colors-reversed)))
          #:material final-material
          #:transform transform
          #:opacity opacity
          #:wireframe-color (mesh3d-wireframe-color first-mesh)
          #:wireframe-width (mesh3d-wireframe-width first-mesh)))

(define (orient-cut-solid mesh)
  ;; Exact welding establishes adjacency; this separate purely topological
  ;; pass makes the combined result consistently outward-facing without ever
  ;; moving or merging a vertex.
  (define-values (oriented _report) (mesh3d-orient-outward mesh))
  oriented)

; cap-section3d : section3d? #:side ... -> (or/c #f mesh3d?)
;; Produces flat cap geometry for every closed simple component.  Nested loops
;; are interpreted as a planar containment forest: even-depth loops are
;; filled, and their immediate odd-depth children are holes.  This makes an
;; annular section truthful rather than silently filling its void.
;; Open chains do not manufacture a false surface.  The cap is purposely a
;; separate mesh so original smooth side normals cannot be overwritten.
(define (cap-section3d section #:side [side 'positive]
                       #:id [id 'section-cap]
                       #:style [style default-cap-style3d])
  (unless (section3d? section) (raise-argument-error 'cap-section3d "section3d?" section))
  (unless (memq side '(positive negative))
    (raise-argument-error 'cap-section3d "positive or negative side" side))
  (unless (symbol? id) (raise-argument-error 'cap-section3d "symbol?" id))
  (unless (cap-style3d? style) (raise-argument-error 'cap-section3d "cap-style3d?" style))
  (define loops (section3d-loops section))
  (cond [(null? loops) #f]
        [else
         (define vertices-reversed '())
         (define normals-reversed '())
         (define triangles-reversed '())
         (define next-index 0)
         (define basis (section3d-basis section))
         ;; The positive kept side exposes the removed negative half-space.
         (define normal (vec3-scale (if (eq? side 'positive) -1 1)
                                    (plane3-normal (section3d-plane section))))
         (define offset (vec3-scale (cap-style3d-offset style) normal))
         (for ([region (in-list (section-cap-regions basis loops))])
           (define outer (car region))
           (define holes (cdr region))
           (define ordered
             (bridge-cap-holes basis
                               (canonical-counterclockwise-loop basis outer)
                               (for/list ([hole (in-list holes)])
                                 ;; A hole must run opposite its enclosing
                                 ;; outer boundary before bridge insertion.
                                 (reverse (canonical-counterclockwise-loop basis hole)))))
           (define local-triangles (triangulate-simple-loop basis ordered))
           (verify-cap-triangulation! basis ordered local-triangles)
           (define base next-index)
           (set! next-index (+ next-index (length ordered)))
           (for ([point (in-list ordered)])
             (set! vertices-reversed (cons (vec3+ point offset) vertices-reversed))
             (set! normals-reversed (cons normal normals-reversed)))
           (for ([triangle (in-list local-triangles)])
             ;; A CCW plane-basis triangle faces the plane normal.  The
             ;; positive retained half must expose the opposite normal.
             (define indices
               (vector (+ base (vector-ref triangle 0))
                       (+ base (vector-ref triangle 1))
                       (+ base (vector-ref triangle 2))))
             (set! triangles-reversed
                   (cons (if (eq? side 'positive)
                             (vector (vector-ref indices 0)
                                     (vector-ref indices 2)
                                     (vector-ref indices 1))
                             indices)
                         triangles-reversed))))
         (mesh3d #:id id
                 #:vertices (list->vector (reverse vertices-reversed))
                 #:triangles (list->vector (reverse triangles-reversed))
                 #:normals (list->vector (reverse normals-reversed))
                 #:material (cap-style3d-material style))]))

;; An ear-clipping input is a cyclic list of the original point indexes.  The
;; public section points stay in 3D; all robustness decisions take place in a
;; stable section-plane coordinate system.
(struct cap-corner (index point coordinates) #:transparent)

(define (canonical-counterclockwise-loop basis loop)
  (unless (>= (length loop) 3)
    (raise-arguments-error 'cap-section3d "a closed component with at least three points"
                           "loop" loop))
  (define ccw
    (if (negative? (plane-basis3d-signed-area basis loop)) (reverse loop) loop))
  ;; A section graph may choose a different starting node after harmless mesh
  ;; reindexing.  Rotate at the lexicographically least plane point so cap
  ;; vertex/triangle order remains deterministic.
  (define start
    (for/fold ([best 0]) ([point (in-list (cdr ccw))] [index (in-naturals 1)])
      (if (coordinates<? (plane-basis3d-project basis point)
                         (plane-basis3d-project basis (list-ref ccw best)))
          index
          best)))
  (append (drop ccw start) (take ccw start)))

(define (triangulate-simple-loop basis points)
  (define corners
    (for/list ([point (in-list points)] [index (in-naturals)])
      (cap-corner index point (plane-basis3d-project basis point))))
  (define (clip current triangles-reversed)
    (cond [(= (length current) 3)
           (reverse
            (cons (vector (cap-corner-index (first current))
                          (cap-corner-index (second current))
                          (cap-corner-index (third current)))
                  triangles-reversed))]
          [else
           (define ear-index
             (for/first ([index (in-range (length current))]
                         #:when (ear? current index))
               index))
           (cond [ear-index
                  (define previous (list-ref current (modulo (sub1 ear-index) (length current))))
                  (define corner (list-ref current ear-index))
                  (define next (list-ref current (modulo (add1 ear-index) (length current))))
                  (clip (remove-at current ear-index)
                        (cons (vector (cap-corner-index previous)
                                      (cap-corner-index corner)
                                      (cap-corner-index next))
                              triangles-reversed))]
                 ;; Collinear corners have no area and must not make an
                 ;; otherwise valid concave contour appear untriangulable.
                 [(for/first ([index (in-range (length current))]
                              #:when (collinear-corner? current index))
                    index)
                  => (lambda (index) (clip (remove-at current index) triangles-reversed))]
                 [else
                  (raise-arguments-error 'cap-section3d
                                         "a simple non-self-intersecting section loop"
                                         "reason" "no deterministic ear found"
                                         "points" points)])]))
  (clip corners '()))

;; The bridge path has zero signed area, so its weakly-simple contour has the
;; same area as outer minus holes.  Verifying the emitted triangles against it
;; detects a bridge/ear error before a cap can be presented as a valid solid.
(define (verify-cap-triangulation! basis points triangles)
  (define expected (abs (plane-basis3d-signed-area basis points)))
  (define actual
    (for/sum ([triangle (in-list triangles)])
      (define first (plane-basis3d-project basis (list-ref points (vector-ref triangle 0))))
      (define second (plane-basis3d-project basis (list-ref points (vector-ref triangle 1))))
      (define third (plane-basis3d-project basis (list-ref points (vector-ref triangle 2))))
      (/ (abs (cross2 first second third)) 2)))
  (unless (<= (abs (- actual expected)) (* 1e-8 (max 1 expected)))
    (raise-arguments-error 'cap-section3d
                           "a cap triangulation whose area preserves its section holes"
                           "expected-area" expected
                           "triangle-area" actual)))

(define (ear? corners index)
  (define count (length corners))
  (define previous (list-ref corners (modulo (sub1 index) count)))
  (define corner (list-ref corners index))
  (define next (list-ref corners (modulo (add1 index) count)))
  (and (positive? (cross2 (cap-corner-coordinates previous)
                          (cap-corner-coordinates corner)
                          (cap-corner-coordinates next)))
       (ear-diagonal-clear? corners index)
       (not
        (for/or ([other (in-list corners)] [other-index (in-naturals)]
                 #:unless (or (= other-index (modulo (sub1 index) count))
                              (= other-index index)
                              (= other-index (modulo (add1 index) count))))
          (point-in-triangle? (cap-corner-coordinates other)
                              (cap-corner-coordinates previous)
                              (cap-corner-coordinates corner)
                              (cap-corner-coordinates next))))))

;; The ordinary "contains no vertex" ear test is enough for a strict simple
;; contour.  Hole bridging creates a weakly-simple contour with duplicated
;; bridge endpoints, where it can otherwise accept a diagonal crossing the
;; bridge and fill part of the hole.  Reject such diagonals explicitly.
(define (ear-diagonal-clear? corners index)
  (define count (length corners))
  (define previous-index (modulo (sub1 index) count))
  (define next-index (modulo (add1 index) count))
  (define start (cap-corner-coordinates (list-ref corners previous-index)))
  (define end (cap-corner-coordinates (list-ref corners next-index)))
  (not
   (for/or ([edge-index (in-range count)])
     (define edge-next (modulo (add1 edge-index) count))
     (and (not (member edge-index (list previous-index index next-index)))
          (not (member edge-next (list previous-index index next-index)))
          (segments-properly-intersect?
           start end
           (cap-corner-coordinates (list-ref corners edge-index))
           (cap-corner-coordinates (list-ref corners edge-next)))))))

(define (collinear-corner? corners index)
  (define count (length corners))
  (zero? (cross2 (cap-corner-coordinates (list-ref corners (modulo (sub1 index) count)))
                 (cap-corner-coordinates (list-ref corners index))
                 (cap-corner-coordinates (list-ref corners (modulo (add1 index) count))))))

(define (cross2 first second third)
  (- (* (- (vector-ref second 0) (vector-ref first 0))
        (- (vector-ref third 1) (vector-ref first 1)))
     (* (- (vector-ref second 1) (vector-ref first 1))
        (- (vector-ref third 0) (vector-ref first 0)))))

(define (point-in-triangle? point first second third)
  ;; Strict containment deliberately ignores bridge endpoint duplicates in a
  ;; weakly-simple polygon produced by joining a hole to its outer loop.
  ;; Inclusive containment would make those duplicates incorrectly veto every
  ;; otherwise valid ear around the bridge.
  (and (positive? (cross2 first second point))
       (positive? (cross2 second third point))
       (positive? (cross2 third first point))))

(define (remove-at values index)
  (append (take values index) (drop values (add1 index))))

(define (coordinates<? first second)
  (or (< (vector-ref first 0) (vector-ref second 0))
      (and (= (vector-ref first 0) (vector-ref second 0))
           (< (vector-ref first 1) (vector-ref second 1)))))

;; Returns deterministic `(outer hole ...)` regions from a containment forest.
;; An island inside a hole has even depth and becomes its own region; it is not
;; incorrectly subtracted from its grandparent outer loop.
(define (section-cap-regions basis loops)
  (define loop-data
    (for/list ([loop (in-list loops)] [index (in-naturals)])
      (list index loop
            (for/list ([point (in-list loop)]) (plane-basis3d-project basis point)))))
  (define (contains? candidate subject)
    (point-in-polygon? (car (third subject)) (third candidate)))
  (define (depth subject)
    (for/sum ([candidate (in-list loop-data)]
              #:unless (= (first candidate) (first subject)))
      (if (contains? candidate subject) 1 0)))
  (define (parent subject)
    (define containers
      (for/list ([candidate (in-list loop-data)]
                 #:unless (= (first candidate) (first subject))
                 #:when (contains? candidate subject))
        candidate))
    (for/fold ([best #f]) ([candidate (in-list containers)])
      ;; The immediate enclosing loop is the one with the greatest depth;
      ;; source order resolves a geometrically degenerate tie.
      (cond [(not best) candidate]
            [(> (depth candidate) (depth best)) candidate]
            [(and (= (depth candidate) (depth best))
                  (< (first candidate) (first best)))
             candidate]
            [else best])))
  (for/list ([outer-data (in-list loop-data)]
             #:when (even? (depth outer-data)))
    (cons (second outer-data)
          (for/list ([hole-data (in-list loop-data)]
                     #:when (and (odd? (depth hole-data))
                                 (let ([container (parent hole-data)])
                                   (and container
                                        (= (first container) (first outer-data))))))
            (second hole-data)))))

;; Bridges each clockwise hole into an enclosing CCW loop.  A bridge is chosen
;; from the hole's rightmost point to the nearest visible outer vertex; all
;; ties are authored-loop order.  The result is weakly simple, which the
;; strict ear test above is designed to triangulate without filling the hole.
(define (bridge-cap-holes basis outer holes)
  (define-values (bridged _bridges)
    (for/fold ([polygon outer] [bridges '()]) ([hole (in-list holes)])
      (define hole-index
        (for/fold ([best 0]) ([point (in-list (cdr hole))] [index (in-naturals 1)])
          (define candidate (plane-basis3d-project basis point))
          (define current (plane-basis3d-project basis (list-ref hole best)))
          (if (or (> (vector-ref candidate 0) (vector-ref current 0))
                  (and (= (vector-ref candidate 0) (vector-ref current 0))
                       (< (vector-ref candidate 1) (vector-ref current 1))))
              index
              best)))
      (define hole-point (list-ref hole hole-index))
      (define outer-index
        (for/first ([index (in-range (length polygon))]
                    #:when (cap-bridge-visible? basis
                                                 (list-ref polygon index) hole-point
                                                 polygon holes bridges))
          index))
      (unless outer-index
        (raise-arguments-error 'cap-section3d
                               "a section whose holes have a deterministic visible bridge"
                               "hole" hole))
      (define outer-point (list-ref polygon outer-index))
      (define hole-cycle (append (drop hole hole-index) (take hole hole-index)))
      ;; outer-point -> hole-point, around the hole, then hole-point ->
      ;; outer-point.  The duplicated bridge endpoints represent the two sides
      ;; of a zero-width bridge in the resulting weakly-simple polygon.
      (values (append (take polygon (add1 outer-index))
                      hole-cycle (list hole-point outer-point)
                      (drop polygon (add1 outer-index)))
              (cons (list outer-point hole-point) bridges))))
  bridged)

(define (cap-bridge-visible? basis outer-point hole-point polygon holes bridges)
  (define start (plane-basis3d-project basis outer-point))
  (define end (plane-basis3d-project basis hole-point))
  (define midpoint
    (vector (/ (+ (vector-ref start 0) (vector-ref end 0)) 2)
            (/ (+ (vector-ref start 1) (vector-ref end 1)) 2)))
  (define contours (cons polygon holes))
  (and (point-in-polygon? midpoint
                          (for/list ([point (in-list polygon)])
                            (plane-basis3d-project basis point)))
       (not (for/or ([hole (in-list holes)])
              (point-in-polygon? midpoint
                                 (for/list ([point (in-list hole)])
                                   (plane-basis3d-project basis point)))))
       (not
        (for*/or ([contour (in-list contours)]
                  [first (in-list contour)]
                  [second (in-list (append (cdr contour) (list (car contour))))])
          (segments-properly-intersect?
           start end
           (plane-basis3d-project basis first)
           (plane-basis3d-project basis second))))
       (not
        (for/or ([bridge (in-list bridges)])
          (segments-properly-intersect?
           start end
           (plane-basis3d-project basis (first bridge))
           (plane-basis3d-project basis (second bridge)))))))

(define (segments-properly-intersect? first second third fourth)
  (define (orientation a b c) (cross2 a b c))
  (and (< (* (orientation first second third)
             (orientation first second fourth))
          0)
       (< (* (orientation third fourth first)
             (orientation third fourth second))
          0)))

(define (point-in-polygon? point polygon)
  (for/fold ([inside? #f])
            ([first (in-list polygon)]
             [second (in-list (append (cdr polygon) (list (car polygon))))])
    (define first-y (vector-ref first 1))
    (define second-y (vector-ref second 1))
    (define crosses? (not (eq? (> first-y (vector-ref point 1))
                               (> second-y (vector-ref point 1)))))
    (define x-at-y
      (if (= first-y second-y)
          +inf.0
          (+ (vector-ref first 0)
             (* (- (vector-ref point 1) first-y)
                (/ (- (vector-ref second 0) (vector-ref first 0))
                   (- second-y first-y))))))
    (if (and crosses? (< (vector-ref point 0) x-at-y))
        (not inside?)
        inside?)))
