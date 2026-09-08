#lang racket/base

;;; SCENE-3D-U: Schlegel projection uses canonical analysis-space geometry.

(require rackunit
         "../3d.rkt")

(define (transformed-complex)
  (polyhedral-complex3d
   (cube3d 2 #:id 'transformed-schlegel-cube
           #:transform
           (make-transform3 #:translation (vec3 -4 3 1)
                            #:scale (vec3 3 2 4)))))

(module+ test
  (define transformed (transformed-complex))
  (define baked (polyhedral-complex3d
                 (polyhedral-complex3d-analysis-mesh transformed)))
  (define transformed-diagram
    (prepare-schlegel-diagram3d transformed #:outer-face 0))
  (define baked-diagram
    (prepare-schlegel-diagram3d baked #:outer-face 0))
  ;; Projection rays, the target plane, and the labelled face cycles all use
  ;; the same baked-world input as an explicitly pre-baked mesh.
  (check-equal? transformed-diagram baked-diagram)
  (check-equal? (schlegel-diagram3d-data-vertex-positions transformed-diagram)
                (schlegel-diagram3d-data-vertex-positions baked-diagram))
  (check-equal? (schlegel-diagram3d-data-face-polygons transformed-diagram)
                (schlegel-diagram3d-data-face-polygons baked-diagram)))
