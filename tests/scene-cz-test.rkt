#lang racket/base

;;;
;;; SCENE-CZ Linear-Algebra Diagram Tests
;;;

(require rackunit
         racket/class
         racket/draw
         "../main.rkt")

(module+ test
  (define (check-vec2-close actual expected)
    (check-= (vec2-x actual) (vec2-x expected) 1e-10)
    (check-= (vec2-y actual) (vec2-y expected) 1e-10))

  ;; A number plane is a regular addressable group, not a special scene type.
  (define plane
    (number-plane #:id 'plane #:labels? #t
                  #:x-range (axis-range -2 2 1)
                  #:y-range (axis-range -1 1 1)))
  (check-true (group-visual? plane))
  (check-equal? (number-plane-grid-path 'plane) '(plane grid))
  (check-equal? (number-plane-axes-path 'plane) '(plane axes))
  (check-equal? (number-plane-labels-path 'plane) '(plane labels))
  (define plane-scene (scene-add (make-scene) plane))
  (check-true (path-visual?
               (scene-visual-at plane-scene '(plane grid) 0)))
  (check-true (axes-visual?
               (scene-visual-at plane-scene '(plane axes) 0)))
  (check-true (group-visual?
               (scene-visual-at plane-scene '(plane labels) 0)))

  ;; vector-arrow leaves racket/base's vector constructor unshadowed while
  ;; providing semantic arrow coordinates and a conventional text label.
  (define v
    (vector-arrow (vec2 3 -1) #:start (vec2 1 2) #:id 'v))
  (check-true (arrow-visual? v))
  (check-equal? (vector-coordinates v) (vec2 2 -3))
  (define v-label
    (vector-label v #:id 'v-label))
  (check-equal? (visual-position v-label) (vec2 16/5 -4/5))

  (define basis
    (basis-vectors #:id 'basis
                   #:origin (vec2 1 1)
                   #:e1 (vec2 3 1)
                   #:e2 (vec2 1 4)))
  (define basis-scene (scene-add (make-scene) basis))
  (check-equal? (vector-coordinates
                 (scene-visual-at basis-scene '(basis e1) 0))
                (vec2 2 0))
  (check-equal? (vector-coordinates
                 (scene-visual-at basis-scene '(basis e2) 0))
                (vec2 0 3))

  ;; The canonical diagram is one ordinary group and can receive the CY-A map
  ;; as a single coherent operation.
  (define diagram
    (linear-transformation-diagram #:id 'diagram #:vector-end (vec2 2 3)))
  (define diagram-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) diagram)
      (apply-matrix 'diagram (make-linear2 1 0 1 1))
      #:duration 1)
     1))
  (check-true (group-visual?
               (scene-visual-at diagram-scene 'diagram 0)))
  (check-true (affine-map-visual?
               (scene-visual-at diagram-scene 'diagram 1)))
  (check-true (is-a? (scene-frame->bitmap diagram-scene 1 #:fps 1)
                      bitmap%))

  ;; Constructor validation remains eager and deterministic.
  (check-exn exn:fail:contract?
             (lambda () (number-plane #:id 1)))
  (check-exn exn:fail:contract?
             (lambda () (vector-arrow origin #:id 'zero)))
  (check-exn exn:fail:contract?
             (lambda () (vector-label v #:id 'label #:offset 1))))
