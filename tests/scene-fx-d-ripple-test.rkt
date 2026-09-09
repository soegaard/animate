#lang racket/base

;;;
;;; FX-D3 Ripple Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define card
    (rectangle #:id 'card #:width 2 #:height 1
               #:center (vec2 -1 1) #:fill "navy"))

  ;; Ripple lowers eagerly to the existing lagged composition and contributes
  ;; no helper at either exact endpoint. Each interior ring has an independent
  ;; deterministic helper id under the public instance id.
  (define request
    (ripple 'card #:rings 3 #:spacing 1/2 #:lag-ratio 1/4 #:id 'notice))
  (check-true (lagged-start-animation-request? request))
  (define rippled
    (scene-play (scene-add (make-scene) card) request #:duration 2))
  (for ([ring-id (in-list '(notice-ring-0 notice-ring-1 notice-ring-2))])
    (check-false (scene-state-has? (scene-sample rippled 0) ring-id))
    (check-true (scene-state-has? (scene-sample rippled 1) ring-id))
    (check-false (scene-state-has? (scene-sample rippled 2) ring-id)))
  (check-equal? (scene-visual-at rippled 'card 0) card)
  (check-equal? (scene-visual-at rippled 'card 2) card)

  ;; The overlay reads the target at the sampled time, so a concurrent move
  ;; changes the helper's location without altering the target's identity.
  (define moving
    (scene-play (scene-add (make-scene) card)
                (move-to 'card (vec2 5 -2))
                (ripple 'card #:rings 1 #:id 'moving-ripple)
                #:duration 2))
  (define middle-target (scene-visual-at moving 'card 1))
  (define middle-ring (scene-visual-at moving 'moving-ripple-ring-0 1))
  (check-equal? (visual-position middle-ring)
                (visual-position middle-target))
  (check-equal? (scene-visual-at moving 'card 2)
                (visual-with-position card (vec2 5 -2)))
  (check-false
   (scene-state-has? (scene-sample moving 2) 'moving-ripple-ring-0))

  ;; Explicit helper instances make simultaneous use intentional. Reusing an
  ;; instance id is rejected by the normal component-conflict validator.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) card)
                 (ripple 'card #:id 'collision)
                 (ripple 'card #:id 'collision))))
  (check-not-exn
   (lambda ()
     (scene-play (scene-add (make-scene) card)
                 (ripple 'card #:id 'left)
                 (ripple 'card #:id 'right))))

  ;; Construction is parameter-checked, yet symbolic targets remain deferred
  ;; until a concrete scene is available for compilation.
  (check-exn exn:fail:contract? (lambda () (ripple 'card #:rings 0)))
  (check-exn exn:fail:contract? (lambda () (ripple 'card #:lag-ratio -1)))
  (check-exn exn:fail? (lambda () (scene-play (make-scene) (ripple 'missing)))))
