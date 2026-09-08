#lang racket/base

;;; SCENE-3D-U correction: canonical analysis/world coordinates.

(require rackunit
         racket/list
         "../3d.rkt")

(module+ test
  (define source
    (cube3d 2 #:id 'translated-cube
            #:transform
            (make-transform3 #:translation (vec3 5 -2 3)
                             #:scale (vec3 2 3 4))))
  (define complex (polyhedral-complex3d source))
  (define analysis (polyhedral-complex3d-analysis-mesh complex))

  ;; The provenance source is untouched, while all U mathematics sees the
  ;; explicitly baked world mesh rather than transformed planes plus local
  ;; vertices. The legacy accessor deliberately agrees with analysis space.
  (check-eq? (polyhedral-complex3d-source-mesh complex) source)
  (check-equal? (polyhedral-complex3d-mesh complex) analysis)
  (check-equal? (spatial-transform analysis) identity-transform3)
  (check-equal? (polyhedral-complex3d-source-transform complex)
                (spatial-transform source))
  (check-equal?
   (mesh3d-vertices analysis)
   (for/vector ([vertex (in-vector (mesh3d-vertices source))])
     (transform3-apply-point (spatial-transform source) vertex)))
  (check-equal? (hash-ref (polyhedral-complex3d-diagnostics complex) 'analysis-space)
                'world)
  (check-equal? (vector-length (polyhedral-complex3d-faces complex)) 6)
  (check-equal?
   (sort (for/list ([face (in-vector (polyhedral-complex3d-faces complex))])
           (polyhedral-face3d-area face)) <)
   '(24 24 32 32 48 48))

  ;; Every downstream U operation receives the same canonical analysis mesh,
  ;; whether the author supplied a transform or pre-baked world vertices.
  (define pre-baked (polyhedral-complex3d analysis))
  (check-equal? (combinatorial-dual3d complex)
                (combinatorial-dual3d pre-baked))
  (check-equal? (prepare-schlegel-diagram3d complex)
                (prepare-schlegel-diagram3d pre-baked))
  (check-equal? (prepare-polyhedron-net3d complex)
                (prepare-polyhedron-net3d pre-baked))

  ;; Reflection is baked once, with triangle winding reversed. The topology
  ;; remains orientable and face normals agree with the analysis geometry.
  (define reflected
    (polyhedral-complex3d
     (cube3d 2 #:id 'reflected-cube
             #:transform (make-transform3 #:scale (vec3 -1 2 3)))))
  (define reflected-mesh (polyhedral-complex3d-analysis-mesh reflected))
  (check-true (hash-ref (polyhedral-complex3d-diagnostics reflected) 'reflection?))
  (check-equal? (spatial-transform reflected-mesh) identity-transform3)
  (check-true (mesh-topology3d-orientable?
               (polyhedral-complex3d-topology reflected)))
  (check-equal? (vector-length (polyhedral-complex3d-faces reflected)) 6))
