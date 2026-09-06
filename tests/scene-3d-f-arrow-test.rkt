#lang racket/base

;;; SCENE-3D-F Point, Line, and Arrow Tests

(require racket/list
         rackunit
         "../3d.rkt")

(module+ test
  (define arrow (arrow3d origin3 (vec3 0 0 2) #:id 'arrow #:radius 1/10))
  (check-true (group3d? arrow))
  (check-equal? (map spatial-id (group3d-children arrow)) '(shaft tip))
  (check-true (curve3d? (first (group3d-children arrow))))
  (check-true (mesh3d? (second (group3d-children arrow))))
  (define double (double-arrow3d (vec3 -2 0 0) (vec3 2 0 0) #:id 'both))
  (check-equal? (map spatial-id (group3d-children double))
                '(shaft start-tip end-tip))
  (check-true (mesh3d? (point3d origin3 #:id 'point)))
  (check-exn exn:fail?
             (lambda () (arrow3d origin3 origin3 #:id 'bad))))
