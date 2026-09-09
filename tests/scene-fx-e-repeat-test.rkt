#lang racket/base

;;;
;;; FX-E2/E3 Repetition and Explicit Ping-Pong Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define arrow
    (rectangle #:id 'arrow #:width 2 #:height 1 #:rotation 1/10 #:fill "gold"))
  (define base (scene-add (make-scene) arrow))

  ;; Eager repetition is exactly an ordinary succession: relative operations
  ;; compile from prior endpoints, whereas absolute operations stabilize.
  (define repeated-relative
    (scene-play base (repeat-animation (rotate-by 'arrow 1/6) 3) #:duration 3))
  (check-equal? (visual-rotation (scene-visual-at repeated-relative 'arrow 3))
                (+ 1/10 1/2))
  (define repeated-absolute
    (scene-play base (repeat-animation (move-to 'arrow (vec2 4 0)) 3) #:duration 3))
  (check-equal? (visual-position (scene-visual-at repeated-absolute 'arrow 1))
                (vec2 4 0))
  (check-equal? (visual-position (scene-visual-at repeated-absolute 'arrow 3))
                (vec2 4 0))

  ;; Ping-pong never guesses an inverse. The explicit pair returns exactly to
  ;; the source when its forward and backward leaves really are inverse.
  (define pinged
    (scene-play base
                (ping-pong (rotate-by 'arrow 1/4)
                           (rotate-by 'arrow -1/4)
                           #:count 3)
                #:duration 6))
  (check-equal? (scene-visual-at pinged 'arrow 6) arrow)
  (check-equal? (visual-rotation (scene-visual-at pinged 'arrow 1)) (+ 1/10 1/4))

  ;; Timed children retain their ordinary span semantics after eager expansion.
  (define timed-repeat
    (scene-play base
                (repeat-animation (timed (rotate-by 'arrow 1/4) #:duration 2) 2)
                #:duration 4))
  (check-equal? (visual-rotation (scene-visual-at timed-repeat 'arrow 4))
                (+ 1/10 1/2))

  ;; Structural cycles are validated against every iteration's exact local
  ;; endpoint before rendering. The high-level diagnostic reports the actual
  ;; failing repeat/ping-pong pair and child position.
  (check-exn
   #px"repeat-animation:(?s:.)*iteration: 2"
   (lambda ()
     (scene-play (make-scene)
                 (repeat-animation (enter arrow) 2)
                 #:duration 2)))
  (check-exn
   #px"repeat-animation:(?s:.)*lifecycle-effects"
   (lambda ()
     (scene-play (make-scene)
                 (repeat-animation (enter arrow) 2)
                 #:duration 2)))
  (check-exn
   #px"repeat-animation:(?s:.)*iteration: 1"
   (lambda ()
     (scene-play (make-scene)
                 (repeat-animation (leave 'arrow) 2)
                 #:duration 2)))
  (check-not-exn
   (lambda ()
     (scene-play (make-scene)
                 (repeat-animation (succession (enter arrow) (leave 'arrow)) 2)
                 #:duration 4)))
  (check-exn
   #px"ping-pong:(?s:.)*iteration: 1(?s:.)*child-index: 1"
   (lambda ()
     (scene-play base
                 (ping-pong (rotate-by 'arrow 1/4) (enter arrow) #:count 1)
                 #:duration 2)))

  (check-exn exn:fail:contract? (lambda () (repeat-animation (rotate-by 'arrow 1) 0)))
  (check-exn exn:fail:contract? (lambda () (ping-pong (rotate-by 'arrow 1) 'bad)))
  (check-exn exn:fail:contract?
             (lambda () (ping-pong (rotate-by 'arrow 1) (rotate-by 'arrow -1)
                                    #:count 0))))
