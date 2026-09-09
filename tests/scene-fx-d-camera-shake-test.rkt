#lang racket/base

;;;
;;; FX-D4 Deterministic Camera-Shake Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; Plans are transparent eager successions: identical seeds reproduce the
  ;; exact same deltas, while another seed chooses another local path.
  (define shake-a (camera-shake #:amplitude 1/2 #:samples 6 #:seed 11))
  (define shake-a-again (camera-shake #:amplitude 1/2 #:samples 6 #:seed 11))
  (define shake-b (camera-shake #:amplitude 1/2 #:samples 6 #:seed 12))
  (check-true (succession-animation-request? shake-a))
  (check-equal? shake-a shake-a-again)
  (check-not-equal? shake-a shake-b)

  ;; Consecutive relative pan deltas telescope back to zero, so the primary
  ;; camera returns exactly to its source center after an arbitrary-time play.
  (define camera (make-camera #:center (vec2 3 -2) #:world-width 10))
  (define scene
    (scene-play (make-scene #:camera camera) shake-a #:duration 6))
  (check-equal? (camera-center (scene-camera-at scene 0)) (vec2 3 -2))
  (check-not-equal? (camera-center (scene-camera-at scene 1)) (vec2 3 -2))
  (check-equal? (camera-center (scene-camera-at scene 6)) (vec2 3 -2))
  (define samples
    (for/hash ([time (in-list '(0 1 2 3 4 5 6))])
      (values time (scene-camera-at scene time))))
  (for ([time (in-list '(6 2 0 5 1 4 3))])
    (check-equal? (scene-camera-at scene time) (hash-ref samples time)))

  ;; Zero amplitude is still a valid finite composition and leaves all samples
  ;; exactly at the source camera center.
  (define quiet
    (scene-play (make-scene #:camera camera)
                (camera-shake #:amplitude 0 #:samples 2 #:seed 9 #:decay 'smooth)
                #:duration 2))
  (check-equal? (camera-center (scene-camera-at quiet 1)) (vec2 3 -2))
  (check-exn exn:fail:contract? (lambda () (camera-shake #:samples 0)))
  (check-exn exn:fail:contract? (lambda () (camera-shake #:seed 1/2)))
  (check-exn exn:fail:contract? (lambda () (camera-shake #:decay 'exponential))))
