#lang racket/base

;;;
;;; SCENE-DA Complex-Plane Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (check-equal? (complex->point (+ 3 (* 4 0+1i))) (vec2 3 4))
  (check-equal? (point->complex (vec2 -2 5)) (+ -2 (* 5 0+1i)))
  (check-exn exn:fail:contract? (lambda () (complex->point +nan.0)))
  (check-exn exn:fail:contract? (lambda () (point->complex 'not-a-point)))

  (define plane
    (complex-plane #:id 'plane #:x-length 6 #:y-length 4))
  (check-true (group-visual? plane))
  (check-equal? (map visual-id (group-visual-children plane))
                '(coordinates real-axis imaginary-axis))

  ;; A complete complex-plane tree contains both ordinary paths and an
  ;; axes Visual; both are converted before the nonlinear map is applied.
  (define plane-scene
    (scene-play
     (scene-add (make-scene) (complex-plane #:id 'mapped-plane #:labels? #f))
     (apply-complex-function 'mapped-plane (lambda (z) (* z z)))
     #:duration 1))
  (check-not-false (scene-frame->bitmap plane-scene 1 #:fps 2))

  (define source
    (line (vec2 -1 1) (vec2 1 1) #:id 'curve))
  (define scene
    (scene-play
     (scene-add (make-scene) source)
     (apply-complex-function 'curve (lambda (z) (* z z)) #:samples 8)
     #:duration 1))
  (define endpoint
    (scene-visual-at scene 'curve 1))
  (check-true (path-visual? endpoint))
  (define points
    (car (path-geometry-subpath-points (path-visual-path endpoint))))
  (check-equal? (car points) (vec2 0 -2))
  (check-equal? (list-ref points 4) (vec2 -1 0))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) source)
      (apply-complex-function 'curve (lambda (z) 'wrong))))))
