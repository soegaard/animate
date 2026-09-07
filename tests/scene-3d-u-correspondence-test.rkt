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
               '#(#f #f #f))
 (check-exn exn:fail:contract?
            (lambda ()
              (prepare-mesh-correspondence3d a b
                                               #:vertex-map '#(0 0 2))))
 (define signature-source
   (mesh3d #:id 'signature-source
           #:vertices (vector origin3 (vec3 1 0 0) (vec3 2 0 0)
                              (vec3 3 0 0) (vec3 4 0 0) (vec3 5 0 0)
                              (vec3 6 0 0))
           #:triangles (vector (vector 0 1 2)
                               (vector 0 2 3)
                               (vector 0 3 4)
                               (vector 2 5 6))))
 (define signature-destination
   (mesh3d #:id 'signature-destination
           #:vertices (vector (vec3 2 0 0) (vec3 4 0 0) (vec3 6 0 0)
                              origin3 (vec3 5 0 0) (vec3 1 0 0)
                              (vec3 3 0 0))
           #:triangles (vector (vector 3 5 0)
                               (vector 3 0 6)
                               (vector 3 6 1)
                               (vector 0 4 2))))
 (define signature-plan
   (prepare-mesh-correspondence3d signature-source signature-destination))
 (check-equal? (mesh-correspondence3d-vertex-map signature-plan)
               '#(3 5 0 6 1 #f #f))
 (check-eq? (hash-ref (mesh-correspondence3d-diagnostics signature-plan)
                       'vertex-reason)
            'topological-signature)
 (check-true (hash-ref (mesh-correspondence3d-diagnostics signature-plan)
                        'ambiguous?))
 (check-equal? (hash-ref (mesh-correspondence3d-unmatched-source signature-plan)
                         'vertex)
               '#(5 6))

 ;; Geometric matching is deliberately opt-in.  The two remaining vertices
 ;; have symmetric local signatures, but their normalized local positions are
 ;; distinct, so the bounded Hungarian assignment can complete only the
 ;; author-requested fallback stage.
 (define geometric-plan
   (prepare-mesh-correspondence3d
    signature-source signature-destination
    #:geometric-fallback? #t))
 (check-equal? (mesh-correspondence3d-vertex-map geometric-plan)
               '#(3 5 0 6 1 4 2))
 (check-false (hash-ref (mesh-correspondence3d-diagnostics geometric-plan)
                        'ambiguous?))
 (check-eq? (hash-ref (mesh-correspondence3d-diagnostics geometric-plan)
                       'vertex-reason)
            'geometric-fallback)
 (define geometric-report
   (hash-ref (mesh-correspondence3d-diagnostics geometric-plan)
             'vertex-geometric-fallback))
 (check-equal? (vector-length (hash-ref geometric-report 'accepted)) 2)
 (check-equal? (hash-ref (mesh-correspondence3d-unmatched-source geometric-plan)
                         'vertex)
               '#())
 (check-exn exn:fail:contract?
            (lambda ()
              (prepare-mesh-correspondence3d
               signature-source signature-destination
               #:geometric-fallback? #t #:geometric-limit 1)))

 ;; A maximum cost rejects an otherwise deterministic pair and reports the
 ;; reason instead of silently treating it as a successful correspondence.
 (define shifted-destination
   (mesh3d #:id 'shifted-destination
           #:vertices (vector (vec3 2 0 0) (vec3 4 0 0) (vec3 8 0 0)
                              origin3 (vec3 7 0 0) (vec3 1 0 0)
                              (vec3 3 0 0))
           #:triangles (vector (vector 3 5 0)
                               (vector 3 0 6)
                               (vector 3 6 1)
                               (vector 0 4 2))))
 (define rejected-plan
   (prepare-mesh-correspondence3d
    signature-source shifted-destination
    #:geometric-fallback? #t #:maximum-geometric-cost 0))
 (check-true (positive?
              (vector-length
               (hash-ref
                (hash-ref (mesh-correspondence3d-diagnostics rejected-plan)
                          'vertex-geometric-fallback)
                'rejected))))

 ;; Rectangular candidate sets use the same global assignment after a
 ;; deterministic transpose.  Only the two extremal source points have an
 ;; unused destination; the middle point receives an explicit capacity report.
 (define three-loose-points
   (mesh3d #:id 'three-loose-points
           #:vertices (vector origin3 (vec3 1 0 0) (vec3 2 0 0))))
 (define two-loose-points
   (mesh3d #:id 'two-loose-points
           #:vertices (vector origin3 (vec3 2 0 0))))
 (define rectangular-plan
   (prepare-mesh-correspondence3d
    three-loose-points two-loose-points #:geometric-fallback? #t))
 (check-equal? (mesh-correspondence3d-vertex-map rectangular-plan) '#(0 #f 1))
 (define rectangular-report
   (hash-ref (mesh-correspondence3d-diagnostics rectangular-plan)
             'vertex-geometric-fallback))
 (check-equal? (vector-length (hash-ref rectangular-report 'accepted)) 2)
 (check-equal? (hash-ref (vector-ref (hash-ref rectangular-report 'rejected) 0)
                         'reason)
               'no-unused-destination)
 )
