#lang racket/base

;;; SCENE-3D-U2: mathematical polygonal faces over render triangles

(require rackunit
         racket/list
         "../3d.rkt")

(define cube-face-partition
  '((bottom 0 1)
    (top 2 3)
    (left 4 5)
    (right 6 7)
    (back 8 9)
    (front 10 11)))

(define annulus
  (mesh3d #:id 'annulus
          #:vertices (vector (vec3 -2 -2 0) (vec3 2 -2 0) (vec3 2 2 0) (vec3 -2 2 0)
                            (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 1 1 0) (vec3 -1 1 0))
          #:triangles (vector (vector 0 1 5) (vector 0 5 4)
                              (vector 1 2 6) (vector 1 6 5)
                              (vector 2 3 7) (vector 2 7 6)
                              (vector 3 0 4) (vector 3 4 7))))

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define automatic (polyhedral-complex3d cube))
  (define automatic-faces (polyhedral-complex3d-faces automatic))

  ;; Twelve render triangles coalesce to six square mathematical faces.
  (check-equal? (vector-length automatic-faces) 6)
  (for ([face (in-vector automatic-faces)])
    (check-equal? (vector-length (polyhedral-face3d-triangle-indices face)) 2)
    (check-equal? (vector-length (polyhedral-face3d-boundary-vertex-indices face)) 4)
    (check-equal? (polyhedral-face3d-area face) 4)
    (check-true (polyhedral-plane3d? (polyhedral-face3d-plane face)))
    (check-true (vec3? (polyhedral-face3d-centroid face))))
  (check-equal?
   (for/list ([face (in-vector automatic-faces)])
     (polyhedral-face3d-id face))
   (for/list ([triangle-index '(0 2 4 6 8 10)])
     (polyhedral-source-face-id3d triangle-index)))

  ;; Source order is observable and stable across repeat construction.
  (check-equal? automatic (polyhedral-complex3d cube))
  (check-equal?
   (for/list ([face (in-vector automatic-faces)])
     (vector->list (polyhedral-face3d-triangle-indices face)))
   '((0 1) (2 3) (4 5) (6 7) (8 9) (10 11)))

  ;; Coplanarity is measured after the mesh's local-to-world transform. A
  ;; non-uniform scale leaves the six planar regions intact and changes area
  ;; in the expected world-coordinate units.
  (define scaled-cube
    (mesh3d #:id 'scaled-cube
            #:vertices (mesh3d-vertices cube) #:triangles (mesh3d-triangles cube)
            #:transform (make-transform3 #:scale (vec3 2 3 4))))
  (define scaled-faces (polyhedral-complex3d-faces (polyhedral-complex3d scaled-cube)))
  (check-equal? (vector-length scaled-faces) 6)
  (check-equal? (sort (for/list ([face (in-vector scaled-faces)])
                         (polyhedral-face3d-area face))
                      <)
                '(24 24 32 32 48 48))

  ;; Incidence distinguishes face diagonals (one polygon) from cube edges
  ;; (two polygons), while every cube vertex meets exactly three faces.
  (define edge-incidences (polyhedral-complex3d-edge-to-faces automatic))
  (check-equal? (vector-length edge-incidences) 18)
  (check-equal?
   (sort (for/list ([entry (in-vector edge-incidences)]) (vector-length entry)) <)
   '(1 1 1 1 1 1 2 2 2 2 2 2 2 2 2 2 2 2))
  (for ([entry (in-vector (polyhedral-complex3d-vertex-to-faces automatic))])
    (check-equal? (vector-length entry) 3))

  ;; The author can keep every renderer triangle separate, including its
  ;; existing semantic face identity.
  (define named-cube
    (mesh3d #:id 'named-cube
            #:vertices (mesh3d-vertices cube)
            #:triangles (mesh3d-triangles cube)
            #:face-ids '#(t0 t1 t2 t3 t4 t5 t6 t7 t8 t9 t10 t11)))
  (define triangle-complex (polyhedral-complex3d named-cube #:faces 'triangles))
  (check-equal? (vector-length (polyhedral-complex3d-faces triangle-complex)) 12)
  (check-equal?
   (for/list ([face (in-vector (polyhedral-complex3d-faces triangle-complex))])
     (polyhedral-face3d-id face))
   '(t0 t1 t2 t3 t4 t5 t6 t7 t8 t9 t10 t11))

  ;; An explicit declaration wins over coplanar recognition and supplies the
  ;; stable face IDs to be used later by duals, diagrams, and net hinges.
  (define explicit-complex
    (polyhedral-complex3d cube #:faces cube-face-partition #:coplanar-angle 0))
  (check-equal?
   (for/list ([face (in-vector (polyhedral-complex3d-faces explicit-complex))])
     (polyhedral-face3d-id face))
   '(bottom top left right back front))
  (check-equal? (hash-ref (polyhedral-complex3d-diagnostics explicit-complex) 'mode)
                'explicit)

  ;; An explicit declaration controls membership, but it cannot make a folded
  ;; pair into a planar mathematical polygon. The complex says so explicitly.
  (define folded
    (mesh3d #:id 'folded
            #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0) (vec3 0 0 1))
            #:triangles (vector (vector 0 1 2) (vector 1 0 3))))
  (define folded-complex (polyhedral-complex3d folded #:faces '((folded-face 0 1))))
  (define folded-face (vector-ref (polyhedral-complex3d-faces folded-complex) 0))
  (check-false (polyhedral-face3d-plane folded-face))
  (check-false (polyhedral-face3d-boundary-vertex-indices folded-face))
  (check-false
   (hash-ref (vector-ref (hash-ref (polyhedral-complex3d-diagnostics folded-complex)
                                    'face-boundary-diagnostics)
                          0)
             'planar?))

  ;; A connected planar annulus has two loops, not one invented polygon.  U2
  ;; retains the triangle region but records why U5/U6 cannot use it as a
  ;; simple polygon without a later holes-capable operation.
  (define annular-complex (polyhedral-complex3d annulus))
  (check-equal? (vector-length (polyhedral-complex3d-faces annular-complex)) 1)
  (define annular-face (vector-ref (polyhedral-complex3d-faces annular-complex) 0))
  (check-false (polyhedral-face3d-boundary-vertex-indices annular-face))
  (define annular-diagnostic
    (vector-ref (hash-ref (polyhedral-complex3d-diagnostics annular-complex)
                           'face-boundary-diagnostics)
                0))
  (check-equal? (hash-ref annular-diagnostic 'boundary-loop-count) 2)
  (check-equal? (hash-ref (polyhedral-complex3d-diagnostics annular-complex)
                           'invalid-face-indices)
                '#(0))

  ;; Explicit partitions must be partitions; an omitted or duplicated triangle
  ;; cannot quietly disappear from the mathematical complex.
  (check-exn exn:fail?
             (lambda () (polyhedral-complex3d cube #:faces '((only 0 1))))))
