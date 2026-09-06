#lang racket/base

;;; SCENE-3D-G Direct Surface Animation Tests

(require rackunit
         "../3d.rkt"
         "../main.rkt")

(define source
  (function-surface3d (lambda (x y) (+ (* x x) (* y y)))
                      #:x-range (list -1 1) #:y-range (list -1 1)
                      #:resolution (list 5 5) #:id 'surface))
(define destination
  (function-surface3d (lambda (x y) (- (* x x) (* y y)))
                      #:x-range (list -1 1) #:y-range (list -1 1)
                      #:resolution (list 5 5) #:id 'other))
(define world
  (view3d (list source) #:id 'world #:render-mode 'opaque
          #:camera (perspective-camera3d #:position (vec3 3 3 6) #:look-at origin3)))

(define (sampled-surface scene time)
  (view3d-spatial-ref (scene-state-resolved-ref (scene-sample scene time) 'world)
                      '(world surface)))

(module+ test
  (define revealed
    (scene-play (scene-add (make-scene) world) (reveal-surface-u '(world surface)) #:duration 1))
  (check-equal? (surface3d-resolution (sampled-surface revealed 0)) (list 5 5))
  (check-equal? (surface3d-points (sampled-surface revealed 1)) (surface3d-points source))
  ;; The beginning reveal is degenerate but retains all fixed topology samples.
  (check-equal? (vector-ref (surface3d-points (sampled-surface revealed 0)) 0)
                (vector-ref (surface3d-points (sampled-surface revealed 0)) 20))

  (define morphed
    (scene-play (scene-add (make-scene) world)
                (transform-surface3d '(world surface) destination) #:duration 1))
  (check-equal? (surface3d-points (sampled-surface morphed 0)) (surface3d-points source))
  (check-equal? (surface3d-points (sampled-surface morphed 1)) (surface3d-points destination)))
