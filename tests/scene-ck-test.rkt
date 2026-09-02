#lang racket/base

;;;
;;; SCENE-CK Live Attention Tests
;;;

;; Attention overlays are derived from the sampled target after ordinary
;; motion/scale components, even when the attention request appears first.

(require rackunit
         racket/list
         "../main.rkt")

(module+ test
  (define target
    (rectangle #:id 'target
               #:center origin
               #:width 2
               #:height 1
               #:fill "aliceblue"
               #:stroke "navy"))
  (define live-attention
    (scene-play
     (scene-add (make-scene) target)
     ;; The request order deliberately puts attention before target updates.
     (circumscribe 'target #:padding 1/5 #:color "crimson")
     (move-to 'target (vec2 4 2))
     (scale-to 'target 2)
     #:duration 1))
  (define middle
    (scene-sample live-attention 1/2))
  (define sampled-target
    (scene-state-ref middle 'target))
  (define sampled-outline
    (last (scene-state-visuals-in-drawing-order middle)))

  ;; At progress 1/2 circumscribe holds a complete outline. Its center and
  ;; width track the simultaneous halfway translation and scale.
  (check-equal? (visual-position sampled-target) (vec2 2 1))
  (check-equal? (visual-position sampled-outline) (vec2 2 1))
  (define-values (left bottom right top)
    (path-geometry-bounds (path-visual-path sampled-outline)))
  (check-true (> (- right left) 3))
  (check-true (> (- top bottom) 3/2))

  ;; A live layout-anchor callout accepts the nine-point vocabulary and uses
  ;; the sampled rendered target instead of a construction-time box.
  (define edge-note
    (callout
     (plain-text "right edge" #:id 'edge-note)
     'target
     #:target-anchor 'right))
  (check-equal? (callout-visual-target-anchor edge-note) 'right)
  (check-not-exn
   (lambda ()
     (scene-state->pict
      (scene-current-state
       (scene-add live-attention edge-note)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (callout (plain-text "bad" #:id 'bad-note)
              'target
              #:target-anchor 'diagonal))))
