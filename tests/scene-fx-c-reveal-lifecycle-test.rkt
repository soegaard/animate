#lang racket/base

;;;
;;; FX-C2/C3 Hard-Clip Reveal Lifecycle Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define card
    (rectangle #:id 'card
               #:width 2 #:height 1
               #:center (vec2 1 2)
               #:rotation 1/5
               #:scale (vec2 3/2 4/3)
               #:opacity 3/4
               #:fill "gold"))
  (define front (linear-reveal-front (vec2 1 0) #:padding 0))

  ;; An introduction is structurally present behind an empty clip at the local
  ;; start, advances through a local clip in the interior, and restores the
  ;; exact authored Visual at its endpoint.
  (define entering
    (scene-play (make-scene) (reveal-in card front) #:duration 2))
  (check-true (reveal-in-request? (reveal-in card front)))
  (check-true (scene-state-has? (scene-sample entering 0) 'card))
  (check-true (clipped-visual? (scene-visual-at entering 'card 0)))
  (check-true
   (path-geometry-empty?
    (clipped-visual-path (scene-visual-at entering 'card 0))))
  (check-true (clipped-visual? (scene-visual-at entering 'card 1)))
  (check-false
   (path-geometry-empty?
    (clipped-visual-path (scene-visual-at entering 'card 1))))
  (check-equal? (scene-visual-at entering 'card 2) card)

  ;; The public inspection model identifies the clip lifecycle and retains the
  ;; immutable front value without exposing the private wrapper representation.
  (define entry-inspection
    (car (scene-animation-inspections-at entering 1)))
  (check-equal? (animation-inspection-kind entry-inspection) 'reveal-in)
  (check-equal? (hash-ref (animation-inspection-data entry-inspection) 'target) 'card)
  (check-equal? (hash-ref (animation-inspection-data entry-inspection) 'front) front)
  (check-false (hash-ref (animation-inspection-data entry-inspection) 'remove-at-end?))

  ;; A leave keeps its exact source at local time zero, clips in reverse, and
  ;; removes its target only at the structural boundary.
  (define leaving
    (scene-play
     (scene-add (make-scene) card)
     (reveal-out 'card front)
     #:duration 2))
  (check-true (reveal-out-request? (reveal-out 'card front)))
  (check-equal? (scene-visual-at leaving 'card 0) card)
  (check-true (clipped-visual? (scene-visual-at leaving 'card 1)))
  (check-false (scene-state-has? (scene-sample leaving 2) 'card))
  (define leave-inspection
    (car (scene-animation-inspections-at leaving 1)))
  (check-equal? (animation-inspection-kind leave-inspection) 'reveal-out)
  (check-true (hash-ref (animation-inspection-data leave-inspection) 'remove-at-end?))

  ;; Readable wipe/iris names lower directly to the generic lifecycle instead
  ;; of introducing separate timing or endpoint semantics.
  (define wiped
    (scene-play (make-scene) (wipe-in card 'right #:padding 0) #:duration 1))
  (define irised
    (scene-play (make-scene) (iris-in card #:padding 0) #:duration 1))
  (define wiped-out
    (scene-play (scene-add (make-scene) card) (wipe-out 'card 'left) #:duration 1))
  (define irised-out
    (scene-play (scene-add (make-scene) card) (iris-out 'card) #:duration 1))
  (check-true (reveal-in-request? (wipe-in card 'right)))
  (check-true (reveal-in-request? (iris-in card)))
  (check-true (reveal-out-request? (wipe-out 'card 'left)))
  (check-true (reveal-out-request? (iris-out 'card)))
  (check-equal? (scene-visual-at wiped 'card 1) card)
  (check-equal? (scene-visual-at irised 'card 1) card)
  (check-false (scene-state-has? (scene-sample wiped-out 1) 'card))
  (check-false (scene-state-has? (scene-sample irised-out 1) 'card))

  ;; Translation and opacity remain ordinary independent components. Sampling
  ;; is deterministic for shuffled frame-time queries, and the endpoint keeps
  ;; those concurrent component results while discarding the clip wrapper.
  (define moving-entry
    (scene-play
     (make-scene)
     (reveal-in card front)
     (move-to 'card (vec2 5 -1))
     (fade-to 'card 1/2)
     #:duration 2))
  (check-equal? (visual-position (scene-visual-at moving-entry 'card 1))
                (vec2 3 1/2))
  (check-equal? (visual-opacity (scene-visual-at moving-entry 'card 1)) 5/8)
  (define sampled
    (for/hash ([time (in-list '(0 1/2 1 3/2 2))])
      (values time (scene-sample moving-entry time))))
  (for ([time (in-list '(3/2 0 2 1/2 1))])
    (check-equal? (scene-sample moving-entry time) (hash-ref sampled time)))
  (check-equal? (visual-position (scene-visual-at moving-entry 'card 2))
                (vec2 5 -1))
  (check-equal? (visual-opacity (scene-visual-at moving-entry 'card 2)) 1/2)
  (check-false (clipped-visual? (scene-visual-at moving-entry 'card 2)))

  ;; A nested target is wrapped and removed in place; unrelated siblings stay
  ;; untouched, which is required for composition inside a group tree.
  (define sibling
    (circle #:id 'sibling #:radius 1/3 #:center (vec2 -2 0) #:fill "navy"))
  (define nested (group (list card sibling) #:id 'panel))
  (define nested-leave
    (scene-play
     (scene-add (make-scene) nested)
     (reveal-out '(panel card) (radial-reveal-front))
     #:duration 1))
  (check-true (clipped-visual? (scene-visual-at nested-leave '(panel card) 1/2)))
  (check-equal? (scene-visual-at nested-leave '(panel sibling) 1) sibling)
  (check-false (scene-state-has? (scene-sample nested-leave 1) '(panel card)))

  ;; Immediate argument errors name the public constructor; symbolic targets
  ;; remain deferred until the scene has a concrete target to inspect.
  (check-exn exn:fail:contract? (lambda () (reveal-in card 'not-a-front)))
  (check-exn exn:fail:contract? (lambda () (reveal-out 'card 'not-a-front)))
  (check-exn exn:fail? (lambda () (scene-play (make-scene) (reveal-out 'missing front)))))
