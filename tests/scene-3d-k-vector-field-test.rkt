#lang racket/base

(require rackunit
         "../3d.rkt")

(module+ test
  (define field
    (vector-field3d
     (lambda (_x y _z) (vec3 1 y 0))
     #:id 'field
     #:x-range '(0 1) #:y-range '(0 1) #:z-range '(0 0)
     #:x-count 2 #:y-count 2 #:z-count 1
     #:normalize? #t #:length-range '(1/2 1)
     #:color-by-magnitude? #t #:seed-order 'zyx))
  (check-true (group3d? field))
  (check-equal? (map spatial-id (group3d-children field))
                '(field-0 field-1 field-2 field-3))
  ;; A zero field sample does not manufacture a degenerate arrow.
  (define sparse
    (vector-field3d
     (lambda (x _y _z) (if (zero? x) origin3 x-axis3))
     #:id 'sparse
     #:x-range '(0 1) #:y-range '(0 0) #:z-range '(0 0)
     #:x-count 2 #:y-count 1 #:z-count 1))
  (check-equal? (map spatial-id (group3d-children sparse)) '(sparse-0))
  (check-exn exn:fail:contract?
             (lambda ()
               (vector-field3d (lambda (_x _y _z) x-axis3)
                               #:id 'bad #:seed-order 'not-an-order))))
