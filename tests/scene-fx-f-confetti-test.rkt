#lang racket/base

;;;
;;; FX-F6 Deterministic Confetti Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; The public plan is entirely determined by explicit inputs; constructing a
  ;; request never reads or mutates Racket's process-global random generator.
  (define first-plan
    (confetti (vec2 1 -1) #:count 5 #:seed 17 #:spread 3 #:height 2
              #:gravity 4 #:id 'celebration))
  (define same-plan
    (confetti (vec2 1 -1) #:count 5 #:seed 17 #:spread 3 #:height 2
              #:gravity 4 #:id 'celebration))
  (define different-plan
    (confetti (vec2 1 -1) #:count 5 #:seed 18 #:spread 3 #:height 2
              #:gravity 4 #:id 'celebration))
  (check-true (confetti-request? first-plan))
  (check-equal? first-plan same-plan)
  (check-not-equal? first-plan different-plan)

  ;; Particle helpers exist only during the open animation interval. Their
  ;; sampled positions come from the same closed-form plan regardless of query
  ;; order, and finalization removes the entire helper group exactly.
  (define exploded
    (scene-play (make-scene) first-plan #:duration 2))
  (check-false (scene-state-has? (scene-sample exploded 0) 'celebration))
  (check-true (scene-state-has? (scene-sample exploded 1) 'celebration))
  (check-not-false (scene-frame->bitmap exploded 1 #:fps 2))
  (check-false (scene-state-has? (scene-sample exploded 2) 'celebration))
  (check-equal? (scene-sample exploded 1/2)
                (scene-sample exploded 1/2))
  (check-false (scene-state-has? (scene-sample exploded 2) 'celebration))

  ;; A target origin is resolved once at the clip's exact start state. It does
  ;; not rewrite the target, and inspection exposes plan metadata rather than
  ;; a mutable renderer resource.
  (define anchor
    (circle #:id 'anchor #:center (vec2 -2 1) #:radius 1/3 #:fill "navy"))
  (define target-exploded
    (scene-play (scene-add (make-scene) anchor)
                (confetti 'anchor #:count 3 #:seed 4 #:id 'target-confetti)
                #:duration 1))
  (check-equal? (scene-visual-at target-exploded 'anchor 1/2) anchor)
  (check-true
   (scene-state-has? (scene-sample target-exploded 1/2) 'target-confetti))
  (check-equal?
   (animation-inspection-kind
    (car (scene-animation-inspections-at target-exploded 1/2)))
   'confetti)
  (check-false
   (scene-state-has? (scene-sample target-exploded 1) 'target-confetti))

  ;; Overlay identities are ordinary scene identities: accidental helper-id
  ;; reuse is rejected while distinct effect instances compose independently.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (make-scene)
                 (confetti (vec2 0 0) #:id 'collision)
                 (confetti (vec2 1 0) #:id 'collision))))
  (check-not-exn
   (lambda ()
     (scene-play (make-scene)
                 (confetti (vec2 0 0) #:id 'left)
                 (confetti (vec2 1 0) #:id 'right))))

  (check-exn exn:fail:contract? (lambda () (confetti (vec2 0 0) #:count 0)))
  (check-exn exn:fail:contract? (lambda () (confetti (vec2 0 0) #:palette '())))
  (check-exn exn:fail? (lambda () (scene-play (make-scene) (confetti 'missing)))))
