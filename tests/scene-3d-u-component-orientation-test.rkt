#lang racket/base

;;; SCENE-3D-U correction: orientation reports are per face component.

(require rackunit
         racket/list
         "../3d.rkt")

(define mobius-vertices
  (vector (vec3 0 0 0) (vec3 0 1 0)
          (vec3 1 0 0) (vec3 1 1 0)
          (vec3 2 0 0) (vec3 2 1 0)))

(define mobius-triangles
  (vector (vector 0 2 3) (vector 0 3 1)
          (vector 2 4 5) (vector 2 5 3)
          (vector 4 1 0) (vector 4 0 5)))

(define (offset-triangles triangles offset)
  (for/list ([triangle (in-vector triangles)])
    (vector (+ offset (vector-ref triangle 0))
            (+ offset (vector-ref triangle 1))
            (+ offset (vector-ref triangle 2)))))

(module+ test
  (define tetra (tetrahedron3d 1 #:id 'tetra))
  (define tetra-vertices (vector->list (mesh3d-vertices tetra)))
  (define tetra-count (length tetra-vertices))
  (define assembled
    (mesh3d
     #:id 'tetra-mobius-isolated
     #:vertices
     (list->vector
      (append tetra-vertices (vector->list mobius-vertices) (list (vec3 9 9 9))))
     #:triangles
     (list->vector
      (append (vector->list (mesh3d-triangles tetra))
              (offset-triangles mobius-triangles tetra-count)))))
  (define topology (mesh3d-topology assembled))
  (define components (mesh-topology3d-connected-components topology))
  (define invariants (mesh3d-component-invariants topology))

  ;; The full mesh is nonorientable, but the tetrahedron and an isolated
  ;; vertex remain truthful local components rather than inheriting the
  ;; Möbius strip's conflict bit.
  (check-false (mesh-topology3d-orientable? topology))
  (check-equal?
   (for/list ([component (in-vector components)])
     (mesh-component-topology3d-orientable? component))
   '(#t #f #t))
  (check-equal?
   (for/list ([invariant (in-vector invariants)])
     (mesh3d-component-invariants3d-orientable? invariant))
   '(#t #f #t))
  (check-equal?
   (for/list ([invariant (in-vector invariants)])
     (mesh3d-component-invariants3d-reason invariant))
   '(#f nonorientable no-faces))
  (check-equal? (hash-ref (mesh-topology3d-diagnostics topology)
                          'component-orientation-conflicts)
                '#(#f #t #f)))
