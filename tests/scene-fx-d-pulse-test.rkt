#lang racket/base

;;;
;;; FX-D2 Pulse Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define card
    (rectangle #:id 'card #:width 2 #:height 1
               #:center (vec2 1 -1)
               #:scale (vec2 3/2 4/3)
               #:opacity 3/4 #:fill "gold"))

  ;; Pulse samples a deterministic there-and-back envelope from the captured
  ;; source, keeps exact endpoints, and leaves no transient helper Visual.
  (define pulsed
    (scene-play (scene-add (make-scene) card)
                (pulse 'card #:scale-factor 6/5 #:opacity-factor 1/2 #:cycles 2)
                #:duration 2))
  (check-true (pulse-request? (pulse 'card)))
  (check-equal? (scene-visual-at pulsed 'card 0) card)
  (check-=
   (vec2-x (visual-scale (scene-visual-at pulsed 'card 1/2)))
   9/5
   1e-12)
  (check-=
   (vec2-y (visual-scale (scene-visual-at pulsed 'card 1/2)))
   8/5
   1e-12)
  (check-=
   (visual-opacity (scene-visual-at pulsed 'card 1/2))
   3/8
   1e-12)
  (check-equal? (scene-visual-at pulsed 'card 2) card)
  (define inspection
    (car (scene-animation-inspections-at pulsed 1/4)))
  (check-equal? (animation-inspection-kind inspection) 'pulse)
  (check-equal? (hash-ref (animation-inspection-data inspection) 'cycles) 2)
  (check-equal? (hash-ref (animation-inspection-data inspection) 'endpoint-action)
                'restore-source)

  ;; The public request has no hidden sampling history.
  (define samples
    (for/hash ([time (in-list '(0 1/4 1/2 3/4 1 3/2 2))])
      (values time (scene-sample pulsed time))))
  (for ([time (in-list '(2 1/2 0 3/2 1/4 1 3/4))])
    (check-equal? (scene-sample pulsed time) (hash-ref samples time)))

  ;; A pulse declares only components it changes. It therefore coexists with a
  ;; move, preserving the move's exact endpoint, but rejects another scale
  ;; writer in the same overlapping clip.
  (define moving
    (scene-play
     (scene-add (make-scene) card)
     (move-to 'card (vec2 5 3))
     (pulse 'card #:scale-factor 6/5)
     #:duration 1))
  (check-equal? (visual-position (scene-visual-at moving 'card 1)) (vec2 5 3))
  (check-equal? (visual-scale (scene-visual-at moving 'card 1)) (vec2 3/2 4/3))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) card)
                 (pulse 'card)
                 (scale-by 'card 2))))

  ;; Nested paths use the normal in-place replacement machinery, leaving
  ;; siblings intact after the exact restoration boundary.
  (define sibling (circle #:id 'sibling #:radius 1/3 #:center (vec2 -2 0)))
  (define nested (group (list card sibling) #:id 'panel))
  (define nested-pulse
    (scene-play (scene-add (make-scene) nested)
                (pulse '(panel card) #:scale-factor 5/4)
                #:duration 1))
  (check-not-equal? (scene-visual-at nested-pulse '(panel card) 1/2) card)
  (check-equal? (scene-visual-at nested-pulse '(panel card) 1) card)
  (check-equal? (scene-visual-at nested-pulse '(panel sibling) 1) sibling)

  (check-exn exn:fail:contract? (lambda () (pulse 'card #:cycles 0)))
  (check-exn exn:fail:contract? (lambda () (pulse 'card #:opacity-factor 2))))
