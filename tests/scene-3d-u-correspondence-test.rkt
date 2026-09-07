#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
 (define a (mesh3d #:id 'a #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0)) #:triangles (vector (vector 0 1 2)) #:vertex-ids '#(a b c) #:face-ids '#(f)))
 (define b (mesh3d #:id 'b #:vertices (vector (vec3 1 0 0) origin3 (vec3 0 1 0)) #:triangles (vector (vector 0 1 2)) #:vertex-ids '#(b a c) #:face-ids '#(f)))
 (define m (prepare-mesh-correspondence3d a b))
 (check-equal? (mesh-correspondence3d-vertex-map m) '#(1 0 2))
 (check-eq? (hash-ref (mesh-correspondence3d-diagnostics m) 'vertex-reason) 'semantic-id)
 (define explicit (prepare-mesh-correspondence3d a b #:vertex-map '#(0 #f 2)))
 (check-equal? (mesh-correspondence3d-vertex-map explicit) '#(0 #f 2))
 (check-eq? (hash-ref (mesh-correspondence3d-diagnostics explicit) 'vertex-reason) 'explicit)
 (define anonymous-a
   (mesh3d #:id 'anonymous-a
           #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0))
           #:triangles (vector (vector 0 1 2))))
 (define anonymous-b
   (mesh3d #:id 'anonymous-b
           #:vertices (vector (vec3 3 0 0) (vec3 4 0 0) (vec3 3 1 0))
           #:triangles (vector (vector 0 1 2))))
 (check-equal? (mesh-correspondence3d-vertex-map
                (prepare-mesh-correspondence3d anonymous-a anonymous-b))
               '#(0 1 2))
 (define extra-vertex
   (mesh3d #:id 'extra-vertex
           #:vertices (vector origin3 (vec3 1 0 0) (vec3 0 1 0) (vec3 2 2 2))
           #:triangles (vector (vector 0 1 2))))
 (check-equal? (mesh-correspondence3d-vertex-map
                (prepare-mesh-correspondence3d a extra-vertex))
               '#(#f #f #f)))
