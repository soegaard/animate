#lang racket/base

;;;
;;; Graph Layouts and Curved Edges Example
;;;

;; SCENE-DP builds a layered network as ordinary nested Visuals. Parallel edges
;; and a self-loop are derived paths: when `state` moves, their shafts, tips,
;; and labels are rebuilt from the one sampled vertex position.

(require racket/cmdline
         "../main.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define network
    (digraph
     (list (graph-vertex 'start)
           (graph-vertex 'state)
           (graph-vertex 'finish))
     (list (graph-edge 'start 'state #:id 'accept #:label "accept" #:weight 3/2)
           (graph-edge 'start 'state #:id 'reject #:label "reject")
           (graph-edge 'state 'state #:id 'retry)
           (graph-edge 'state 'finish #:id 'done #:label "done" #:weight 5/4))
     #:id 'network
     #:layout 'layered
     #:tree-x-spacing 2
     #:tree-y-spacing 2
     #:parallel-edge-separation 2/3
     #:self-loop-radius 1/3
     #:vertex-size 3/4
     #:vertex-fill "aliceblue"
     #:vertex-stroke "navy"
     #:edge-stroke "slategray"
     #:edge-stroke-width 2
     #:edge-label-offset (vec2 0 1/4)))
  (define title
    (plain-text "SCENE-DP: graph layouts and live edge routing"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Layered positions, parallel curves, a self-loop, and weighted strokes."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define note
    (plain-text "Move a vertex normally; the route and its label follow the sampled endpoints."
                #:id 'note #:center (vec2 0 -16/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    (scene-wait (scene-add (make-scene) title explanation network note) 1))
  (define shifted
    (scene-play
     initial
     (move-to (graph-vertex-path 'network 'state) (vec2 3/2 0))
     #:duration 3))
  (scene-wait shifted 2))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "graph-layouts-and-curved-edges.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define frame-paths
    (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length frame-paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
