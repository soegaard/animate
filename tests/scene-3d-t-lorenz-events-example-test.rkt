#lang racket/base

;; The canonical Lorenz example must retain both directional nonterminal roots
;; as ordinary named marker geometry, rather than re-running event procedures
;; while a frame is sampled.

(require rackunit
         "../3d.rkt"
         "../main.rkt"
         "../examples/3d/lorenz-events.rkt")

(module+ test
  (define demo (make-demo-scene))
  (define world (scene-visual-at demo 'world 0))
  (define markers (view3d-spatial-ref world '(world event-markers)))
  (check-true (group3d? markers))
  (check-true (>= (length (group3d-children markers)) 2))
  (for ([marker (in-list (group3d-children markers))])
    (check-true (spatial-visual? marker))))
