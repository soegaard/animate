#lang racket/base

;;; SCENE-3D-U: dual construction uses canonical analysis-space geometry.

(require rackunit
         "../3d.rkt")

(define (transformed-complex)
  (polyhedral-complex3d
   (cube3d 2 #:id 'transformed-dual-cube
           #:transform
           (make-transform3 #:translation (vec3 5 -3 2)
                            #:scale (vec3 2 3 4)))))

(module+ test
  (define transformed (transformed-complex))
  (define analysis (polyhedral-complex3d-analysis-mesh transformed))
  (define baked (polyhedral-complex3d analysis))
  (define transformed-dual (combinatorial-dual3d transformed))
  (define baked-dual (combinatorial-dual3d baked))
  ;; The source transform must neither be applied twice nor left behind in
  ;; local coordinates when face-centres become the dual's vertices.
  (check-equal? transformed-dual baked-dual)
  (check-equal? (dual-polyhedron3d-result-mesh transformed-dual)
                (dual-polyhedron3d-result-mesh baked-dual))
  (check-equal? (spatial-transform (dual-polyhedron3d-result-mesh transformed-dual))
                identity-transform3))
