#lang racket/base

;;; SCENE-3D-C Frustum Clipping Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         "../private/3d/frustum-clip3d.rkt")

(define camera
  (perspective-camera3d #:position (vec3 0 0 0) #:rotation identity-rotation3
                        #:near 1 #:far 10 #:vertical-field-of-view 1))
(define normal (vec3 0 0 1))
(define color (rgb-color 10 20 30))
(define (vertex x y z [source 'source])
  (clip-vertex3d (vec3 x y z) normal color source))
(define (clip first second third)
  (clip-triangle3d camera 1 first second third))

(module+ test
  ;; Every plane rejects a wholly exterior triangle in the canonical order.
  (for ([triangle
         (in-list
          (list (list (vertex -1 -1 -1/2) (vertex 1 -1 -1/2) (vertex 0 1 -1/2))
                (list (vertex -1 -1 -11) (vertex 1 -1 -11) (vertex 0 1 -11))
                (list (vertex -8 -1 -2) (vertex -7 1 -2) (vertex -7 -1 -2))
                (list (vertex 8 -1 -2) (vertex 7 1 -2) (vertex 7 -1 -2))
                (list (vertex -1 -8 -2) (vertex 1 -7 -2) (vertex -1 -7 -2))
                (list (vertex -1 8 -2) (vertex 1 7 -2) (vertex -1 7 -2))))])
    (check-equal? (apply clip triangle) '()))
  ;; A near-plane crossing becomes a stable clipped fan and the boundary is
  ;; inclusive, so exact near vertices remain visible.
  (define crossing
    (clip (vertex -1 -1 -1/2 'outside) (vertex 1 -1 -2 'inside) (vertex 0 1 -2 'inside)))
  (check-true (pair? crossing))
  (for* ([triangle (in-list crossing)] [point (in-vector triangle)])
    (check-true (>= (- (vec3-z (clip-vertex3d-view-position point))) 1)))
  (check-equal? (length (clip (vertex -1/4 -1/4 -1)
                              (vertex 1/4 -1/4 -1)
                              (vertex 0 1/4 -1)))
                1))
