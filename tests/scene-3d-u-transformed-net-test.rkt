#lang racket/base

;;; SCENE-3D-U: net preparation uses canonical analysis-space geometry.

(require rackunit
         "../3d.rkt")

(define (transformed-complex)
  (polyhedral-complex3d
   (cube3d 2 #:id 'transformed-net-cube
           #:transform
           (make-transform3 #:translation (vec3 2 -5 4)
                            #:scale (vec3 2 4 3)))))

(module+ test
  (define transformed (transformed-complex))
  (define baked (polyhedral-complex3d
                 (polyhedral-complex3d-analysis-mesh transformed)))
  (define transformed-net (prepare-polyhedron-net3d transformed))
  (define baked-net (prepare-polyhedron-net3d baked))
  ;; Face flattening and cut/tree selection are deterministic over the same
  ;; world-space analysis mesh, regardless of where the source transform was
  ;; represented by the author.
  (check-equal? transformed-net baked-net)
  (check-equal? (polyhedron-net3d-flat-polygons transformed-net)
                (polyhedron-net3d-flat-polygons baked-net))
  (check-equal? (polyhedron-net3d-hinge-tree transformed-net)
                (polyhedron-net3d-hinge-tree baked-net))
  (check-equal? (polyhedron-net3d-cut-edges transformed-net)
                (polyhedron-net3d-cut-edges baked-net)))
