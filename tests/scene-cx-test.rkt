#lang racket/base

;;;
;;; SCENE-CX Mathematical Graph and Network Tests
;;;

;; A graph is a regular nested group tree. Its vertices remain normal animation
;; targets, while the line/arrow children under each edge are derived from the
;; current endpoint groups at arbitrary sample times.

(require rackunit
         racket/class
         racket/draw
         "../private/scene-state.rkt"
         "../main.rkt")

(module+ test
  (define a
    (graph-vertex 'A #:position (vec2 -2 0) #:label "A"))
  (define b
    (graph-vertex 'B #:position (vec2 2 0) #:label "B"))
  (define c
    (graph-vertex 'C #:position (vec2 0 2) #:label "C"))
  (define ab
    (graph-edge 'A 'B #:label "f"))
  (define bc
    (graph-edge 'B 'C #:id 'B-to-C))
  (define network
    (digraph (list a b c) (list ab bc) #:id 'network))

  ;; Public paths expose regular `edges` and `vertices` group structure.
  (check-equal? (graph-vertices-path 'network) '(network vertices))
  (check-equal? (graph-edges-path 'network) '(network edges))
  (check-equal? (graph-vertex-path 'network 'A) '(network vertices A))
  (check-equal? (graph-edge-path 'network ab) '(network edges A->B))
  (check-true (group-visual? network))

  (define base
    (scene-add (make-scene) network))
  (define animated
    (scene-play base
                (move-to (graph-vertex-path 'network 'B) (vec2 2 2))
                #:duration 2))

  ;; The arrow and its optional label are derived children, not a frame-history
  ;; effect. Their sampled midpoint follows the moving target exactly.
  (define edge-line-path
    '(network edges A->B line))
  (define edge-label-path
    '(network edges A->B label))
  (define start-edge
    (scene-visual-at animated edge-line-path 0))
  (define middle-edge
    (scene-visual-at animated edge-line-path 1))
  (define end-edge
    (scene-visual-at animated edge-line-path 2))
  (check-true (arrow-visual? start-edge))
  (check-equal? (visual-position start-edge) origin)
  (check-= (vec2-x (visual-position middle-edge)) 0 1e-9)
  (check-= (vec2-y (visual-position middle-edge)) 1/2 1e-9)
  (check-= (vec2-x (visual-position end-edge)) 0 1e-9)
  (check-= (vec2-y (visual-position end-edge)) 1 1e-9)
  (check-equal?
   (visual-position (scene-visual-at animated edge-label-path 2))
   (vec2 0 6/5))
  (check-equal?
   (visual-position
    (scene-visual-at animated (graph-vertex-path 'network 'B) 2))
   (vec2 2 2))

  ;; A whole-graph affine move is composed once. The derived edge first converts
  ;; world endpoint positions back into graph-local coordinates before the root
  ;; group is rendered, avoiding a doubled translation.
  (define whole-graph-move
    (scene-play base (move-to 'network (vec2 1 -1)) #:duration 1))
  (define moved-edge-world
    (scene-state-resolved-world-ref
     (scene-sample whole-graph-move 1)
     edge-line-path))
  (check-= (vec2-x (visual-position moved-edge-world)) 1 1e-9)
  (check-= (vec2-y (visual-position moved-edge-world)) -1 1e-9)

  ;; Rendering sees concrete nested edge children after scene sampling.
  (check-true
   (is-a? (scene-frame->bitmap animated 2 #:fps 2) bitmap%))

  ;; The undirected constructor uses the same tree but produces a line rather
  ;; than an arrow for the edge's concrete child.
  (define undirected
    (graph (list a b) (list ab) #:id 'undirected))
  (check-true
   (path-visual?
    (scene-visual-at (scene-add (make-scene) undirected)
                     '(undirected edges A->B line)
                     0)))

  ;; Circle layout follows input order and places each vertex at the requested
  ;; radius around the layout centre.
  (define circle-layout
    (graph (list (graph-vertex 'one)
                 (graph-vertex 'two)
                 (graph-vertex 'three))
           '()
           #:id 'circle-layout #:layout 'circle
           #:layout-center (vec2 1 -1) #:layout-radius 2))
  (define circle-scene
    (scene-add (make-scene) circle-layout))
  (check-equal?
   (visual-position (scene-visual-at circle-scene '(circle-layout vertices one) 0))
   (vec2 3 -1))

  ;; A tree layout makes direction meaningful: root above child levels and the
  ;; declared edge order gives stable left-to-right sibling order.
  (define tree-layout
    (digraph
     (list (graph-vertex 'root)
           (graph-vertex 'left)
           (graph-vertex 'right)
           (graph-vertex 'leaf))
     (list (graph-edge 'root 'left)
           (graph-edge 'root 'right)
           (graph-edge 'left 'leaf))
     #:id 'tree #:layout 'tree
     #:tree-x-spacing 2 #:tree-y-spacing 1))
  (define tree-scene (scene-add (make-scene) tree-layout))
  (define root-position
    (visual-position (scene-visual-at tree-scene '(tree vertices root) 0)))
  (define left-position
    (visual-position (scene-visual-at tree-scene '(tree vertices left) 0)))
  (define right-position
    (visual-position (scene-visual-at tree-scene '(tree vertices right) 0)))
  (define leaf-position
    (visual-position (scene-visual-at tree-scene '(tree vertices leaf) 0)))
  (check-true (> (vec2-y root-position) (vec2-y left-position)))
  (check-true (> (vec2-y left-position) (vec2-y leaf-position)))
  (check-true (< (vec2-x left-position) (vec2-x right-position)))

  ;; Graph declarations catch ambiguous or unsupported topology before a scene
  ;; is built, leaving every resulting nested target unambiguous.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (graph (list (graph-vertex 'same #:position origin)
                  (graph-vertex 'same #:position (vec2 1 0)))
            '() #:id 'bad)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (graph (list (graph-vertex 'A #:position origin))
            (list (graph-edge 'A 'missing)) #:id 'bad)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (graph (list (graph-vertex 'A #:position origin))
            (list (graph-edge 'A 'A)) #:id 'bad)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (graph (list (graph-vertex 'A)) '() #:id 'bad #:layout 'manual)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (digraph (list (graph-vertex 'A) (graph-vertex 'B))
              (list (graph-edge 'A 'B)
                    (graph-edge 'B 'A))
              #:id 'bad #:layout 'tree))))
