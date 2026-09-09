#lang racket/base

;;;
;;; FX-D Existing Attention Cleanup Regression Tests
;;;

;; Every legacy attention request is a transient presentation effect: an
;; interior sample may add an overlay or transform the target, but both exact
;; lifecycle endpoints retain the authored scene without a helper leak.

(require rackunit
         "../main.rkt")

(module+ test
  (define marker
    (circle #:id 'marker #:radius 1/2 #:fill "gold" #:stroke "navy"))
  (define trail
    (line (vec2 -2 -1) (vec2 2 -1) #:id 'trail
          #:stroke "steelblue" #:stroke-width 2))
  (define initial (scene-add (make-scene) marker trail))
  (define exact-initial (scene-current-state initial))

  ;; Each overlay effect owns exactly one temporary helper at an interior
  ;; sample, keeps the target intact, and cleans the helper on both boundaries.
  (for ([request (in-list (list (circumscribe 'marker)
                                (indicate 'marker)
                                (flash 'marker)
                                (focus-on 'marker)
                                (show-passing-flash 'trail)))])
    (define animated (scene-play initial request #:duration 1))
    (check-equal? (scene-sample animated 0) exact-initial)
    (check-equal? (scene-state-count (scene-sample animated 1/2)) 3)
    (check-equal? (scene-state-ref (scene-sample animated 1/2) 'marker) marker)
    (check-equal? (scene-sample animated 1) exact-initial)
    (check-equal? (scene-current-state animated) exact-initial))

  ;; Wiggle has no helper Visual, but it is still transient: the authored
  ;; target is exact at both boundaries after its interior rotation samples.
  (define wiggled
    (scene-play initial (wiggle 'marker #:angle 1/10 #:cycles 2) #:duration 1))
  (check-equal? (scene-sample wiggled 0) exact-initial)
  (check-not-equal? (scene-visual-at wiggled 'marker 1/8) marker)
  (check-equal? (scene-sample wiggled 1) exact-initial)
  (check-equal? (scene-current-state wiggled) exact-initial))
