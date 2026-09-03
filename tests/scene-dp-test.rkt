#lang racket/base

;;;
;;; SCENE-DP — Graph Layout and Edge Upgrade Tests
;;;

(require racket/class
         racket/draw
         rackunit
         "../main.rkt")

(module+ test
  (define a (graph-vertex 'A #:position (vec2 -2 0) #:label "A"))
  (define b (graph-vertex 'B #:position (vec2 2 0) #:label "B"))
  (define parallel-edges
    (list (graph-edge 'A 'B #:id 'first #:label "one" #:weight 3/2)
          (graph-edge 'A 'B #:id 'second #:label "two")
          (graph-edge 'B 'A #:id 'return #:label "back")))
  (define routed
    (digraph (list a b) parallel-edges #:id 'routed
             #:parallel-edge-separation 1/3))
  (define routed-scene (scene-wait (scene-add (make-scene) routed) 1))

  ;; Parallel arrows acquire stable distinct curved routes while their labels
  ;; use the same live curve geometry. The declared weight scales the default
  ;; cosmetic stroke width unless the edge explicitly overrides it.
  (check-equal? (graph-edge-weight (car parallel-edges)) 3/2)
  (check-false (graph-edge-curvature (car parallel-edges)))
  (check-true
   (group-visual?
    (scene-visual-at routed-scene '(routed edges first line) 0)))
  ;; A curved route has radial start/end handles, so it leaves and enters a
  ;; circular vertex rather than skimming its boundary. Its two cubic halves
  ;; also have matching midpoint tangents.
  (define first-curved-shaft
    (scene-visual-at routed-scene '(routed edges first line shaft) 0))
  (define first-curved-subpath
    (car (path-geometry-subpaths (path-visual-path first-curved-shaft))))
  (define first-curved-segments (path-subpath-segments first-curved-subpath))
  (define first-curved-half (car first-curved-segments))
  (define second-curved-half (cadr first-curved-segments))
  (define curved-start (path-subpath-start first-curved-subpath))
  (define curved-midpoint (cubic-bezier-path-segment-end first-curved-half))
  (define curved-end (cubic-bezier-path-segment-end second-curved-half))
  (define route-chord (vec2- curved-end curved-start))
  (define initial-handle
    (vec2- (cubic-bezier-path-segment-control1 first-curved-half)
           curved-start))
  (define final-handle
    (vec2- curved-end
           (cubic-bezier-path-segment-control2 second-curved-half)))
  (check-equal? (* (vec2-x initial-handle) (vec2-y route-chord))
                (* (vec2-y initial-handle) (vec2-x route-chord)))
  (check-equal? (* (vec2-x final-handle) (vec2-y route-chord))
                (* (vec2-y final-handle) (vec2-x route-chord)))
  (check-equal?
   (vec2- curved-midpoint
          (cubic-bezier-path-segment-control2 first-curved-half))
   (vec2- (cubic-bezier-path-segment-control1 second-curved-half)
          curved-midpoint))
  (check-not-equal?
   (visual-position (scene-visual-at routed-scene '(routed edges first label) 0))
   (visual-position (scene-visual-at routed-scene '(routed edges second label) 0)))
  (check-true (is-a? (scene-frame->bitmap routed-scene 0 #:fps 1) bitmap%))
  (define routed-moving
    (scene-play routed-scene
                (move-to '(routed vertices B) (vec2 2 3/2))
                #:duration 1))
  (check-true (is-a? (scene-frame->bitmap routed-moving 1 #:fps 1) bitmap%))

  ;; A loop is a live derived curve rather than a degenerate zero-length line.
  (define loop-graph
    (digraph (list (graph-vertex 'L #:position origin #:label "L"))
             (list (graph-edge 'L 'L #:id 'loop #:label "repeat"))
             #:id 'loops))
  (define loop-scene (scene-wait (scene-add (make-scene) loop-graph) 1))
  (check-true
   (group-visual?
    (scene-visual-at loop-scene '(loops edges loop line) 0)))
  ;; The two cubic segments meet at the loop apex.  Their endpoint handles
  ;; must define the same tangent, rather than the mirrored diagonal handles
  ;; that formerly made this join visibly kinked.
  (define loop-shaft
    (scene-visual-at loop-scene '(loops edges loop line shaft) 0))
  (define loop-segments
    (path-subpath-segments
     (car (path-geometry-subpaths (path-visual-path loop-shaft)))))
  (define first-loop-curve (car loop-segments))
  (define second-loop-curve (cadr loop-segments))
  (define apex (cubic-bezier-path-segment-end first-loop-curve))
  (check-equal?
   (vec2- apex (cubic-bezier-path-segment-control2 first-loop-curve))
   (vec2- (cubic-bezier-path-segment-control1 second-loop-curve) apex))
  (check-true (is-a? (scene-frame->bitmap loop-scene 0 #:fps 1) bitmap%))
  (define loop-moving
    (scene-play loop-scene
                (move-to '(loops vertices L) (vec2 1 1))
                #:duration 1))
  (check-true (is-a? (scene-frame->bitmap loop-moving 1 #:fps 1) bitmap%))

  ;; All new layouts are deterministic construction snapshots.
  (define spring-vertices
    (list (graph-vertex 'one) (graph-vertex 'two)
          (graph-vertex 'three) (graph-vertex 'four)))
  (define spring-edges
    (list (graph-edge 'one 'two) (graph-edge 'two 'three)
          (graph-edge 'three 'four) (graph-edge 'four 'one)))
  (define spring-a
    (graph spring-vertices spring-edges #:id 'spring-a #:layout 'spring
           #:spring-iterations 25))
  (define spring-b
    (graph spring-vertices spring-edges #:id 'spring-b #:layout 'spring
           #:spring-iterations 25))
  (define spring-a-scene (scene-add (make-scene) spring-a))
  (define spring-b-scene (scene-add (make-scene) spring-b))
  (check-equal?
   (visual-position (scene-visual-at spring-a-scene '(spring-a vertices one) 0))
   (visual-position (scene-visual-at spring-b-scene '(spring-b vertices one) 0)))

  (define layered
    (digraph
     (list (graph-vertex 'root) (graph-vertex 'left)
           (graph-vertex 'right) (graph-vertex 'sink))
     (list (graph-edge 'root 'left) (graph-edge 'root 'right)
           (graph-edge 'left 'sink) (graph-edge 'right 'sink))
     #:id 'layered #:layout 'layered))
  (define layered-scene (scene-add (make-scene) layered))
  (check-true
   (> (vec2-y (visual-position (scene-visual-at layered-scene '(layered vertices root) 0)))
      (vec2-y (visual-position (scene-visual-at layered-scene '(layered vertices left) 0)))))

  (define partite
    (graph
     (list (graph-vertex 'u #:partition 'left)
           (graph-vertex 'v #:partition 'left)
           (graph-vertex 'x #:partition 'right)
           (graph-vertex 'y #:partition 'right))
     (list (graph-edge 'u 'x) (graph-edge 'v 'y))
     #:id 'partite #:layout 'partite #:partite-order '(left right)))
  (define partite-scene (scene-add (make-scene) partite))
  (check-true
   (< (vec2-x (visual-position (scene-visual-at partite-scene '(partite vertices u) 0)))
      (vec2-x (visual-position (scene-visual-at partite-scene '(partite vertices x) 0)))))

  ;; The planar mode finds a crossing-free circular embedding for this cycle.
  (define planar
    (graph (list (graph-vertex 'p) (graph-vertex 'q)
                 (graph-vertex 'r) (graph-vertex 's))
           (list (graph-edge 'p 'q) (graph-edge 'q 'r)
                 (graph-edge 'r 's) (graph-edge 's 'p))
           #:id 'planar #:layout 'planar))
  (check-not-false
   (scene-visual-at (scene-add (make-scene) planar) '(planar vertices p) 0))

  ;; The algorithms are pure declaration-order traversals suitable for driving
  ;; an explicitly authored highlight sequence.
  (define traversal-edges
    (list (graph-edge 'A 'B) (graph-edge 'A 'C)
          (graph-edge 'B 'D) (graph-edge 'C 'D)))
  (check-equal? (graph-bfs traversal-edges 'A) '(A B C D))
  (check-equal? (graph-dfs traversal-edges 'A) '(A B D C))
  (check-equal? (graph-shortest-path traversal-edges 'A 'D) '(A B D))
  (check-false (graph-shortest-path traversal-edges 'D 'A))

  (check-exn exn:fail:contract?
              (lambda ()
                (graph (list (graph-vertex 'A)) '()
                       #:id 'bad #:layout 'layered)))
  (check-exn exn:fail:contract?
              (lambda ()
                (graph (list (graph-vertex 'A #:partition 'left)
                             (graph-vertex 'B))
                       '() #:id 'bad #:layout 'partite))))
