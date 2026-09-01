#lang racket/base

;;;
;;; SCENE-BM Vector Field Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define axes-value
    (axes #:id 'axes
          #:x-range (axis-range -1 1 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 2
          #:y-length 2
          #:x-tip? #f
          #:y-tip? #f))
  (define field
    (vector-field axes-value
                  (lambda (x y) (vec2 (- y) x))
                  #:id 'rotation
                  #:x-count 3
                  #:y-count 3
                  #:scale 1/2))
  (check-true (group-visual? field))
  ;; The zero vector at the center is omitted; all other grid positions retain
  ;; stable identities and are nested child animation targets.
  (check-equal? (length (group-visual-children field)) 8)
  (check-true
   (scene-state-has?
    (scene-current-state (scene-add (make-scene) field))
    '(rotation rotation-vector-0-0)))
  (define animated
    (scene-play
     (scene-add (make-scene) field)
     (fade-to '(rotation rotation-vector-0-0) 1/2)
     #:duration 2))
  (check-equal?
   (visual-opacity
    (scene-visual-at animated '(rotation rotation-vector-0-0) 1))
   3/4)
  (check-exn exn:fail:contract?
             (lambda ()
               (vector-field axes-value (lambda (_x _y) 0) #:id 'bad)))
  (check-exn exn:fail:contract?
             (lambda ()
               (vector-field axes-value (lambda (_x _y) origin)
                             #:id 'bad #:x-count 0))))
