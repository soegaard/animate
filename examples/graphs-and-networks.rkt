#lang racket/base

;;;
;;; SCENE-CX: Mathematical Graphs and Networks
;;;

;; Vertices are ordinary nested groups. Moving them through normal scene-play
;; requests rebuilds the graph's derived arrow and label children at each sampled
;; time; no object keeps mutable frame-to-frame updater state.

(require "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define network
    (digraph
     (list (graph-vertex 'A #:position (vec2 -3 0) #:label "A")
           (graph-vertex 'B #:position (vec2 -1 3/2) #:label "B")
           (graph-vertex 'C #:position (vec2 -1 -3/2) #:label "C")
           (graph-vertex 'D #:position (vec2 2 0) #:label "D"))
     (list (graph-edge 'A 'B #:label "r")
           (graph-edge 'A 'C #:label "s")
           (graph-edge 'B 'D #:label "t")
           (graph-edge 'C 'D #:label "u"))
     #:id 'network
     #:vertex-size 3/5
     #:vertex-fill "aliceblue"
     #:vertex-stroke "navy"
     #:edge-stroke "slategray"
     #:edge-stroke-width 3))
  (define title
    (plain-text "SCENE-CX: mathematical graphs and networks"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Move named vertices; derived arrows and edge labels follow their endpoints."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define note
    (plain-text "(graph-vertex-path 'network 'B)  ⇒  '(network vertices B)"
                #:id 'note #:center (vec2 0 -3)
                #:font-size 1/5 #:font-family 'modern #:color "darkslategray"))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation network note) 1))
  (define rearranged
    (scene-play
     initial
     (move-to (graph-vertex-path 'network 'A) (vec2 -5/2 0))
     (move-to (graph-vertex-path 'network 'B) (vec2 0 2))
     (move-to (graph-vertex-path 'network 'C) (vec2 0 -2))
     (move-to (graph-vertex-path 'network 'D) (vec2 5/2 0))
     #:duration 3))
  (scene-wait rearranged 2))

(module+ main
  (run-demo "graphs-and-networks.rkt" make-demo-scene))
