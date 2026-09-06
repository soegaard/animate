#lang racket/base

;;; SCENE-3D-Q Surface Producer Invariants

(require rackunit
         "../3d.rkt")

(module+ test
  (define adaptive
    (adaptive-parametric-surface3d
     (lambda (u v) (vec3 u v (* 1/3 (sin (* 5 u)))))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'adaptive
     #:maximum-depth 4 #:position-tolerance 1/100))
  (check-eq? (surface3d-kind adaptive) 'adaptive-parametric)
  (check-true (positive? (vector-length (mesh3d-triangles (surface3d->mesh3d adaptive)))))
  ;; Generated parametric surfaces retain an evaluator and parameter range, so
  ;; anchors/calculus can obtain a deterministic local finite-difference frame
  ;; without pretending the adaptive mesh is a rectangular grid.
  (define adaptive-tangent (surface3d-tangent-u-at adaptive 0 0))
  (define adaptive-normal (surface3d-normal-at adaptive 0 0))
  (check-true (positive? (vec3-length adaptive-tangent)))
  (check-true (positive? (vec3-length adaptive-normal)))
  (check-equal? (surface3d-mesh adaptive)
                (surface3d-mesh
                 (adaptive-parametric-surface3d
                  (lambda (u v) (vec3 u v (* 1/3 (sin (* 5 u)))))
                  #:u-range '(-1 1) #:v-range '(-1 1) #:id 'adaptive
                  #:maximum-depth 4 #:position-tolerance 1/100)))

  ;; A localized feature must remain local.  The 2:1 balancing pass may refine
  ;; its immediate neighbours, but must not promote the whole connected square
  ;; to maximum depth.  Transition triangles also leave one ordinary boundary
  ;; loop instead of cracks along a coarse/fine side.
  (define localized
    (adaptive-parametric-surface3d
     (lambda (u v)
       (define du (- u 1/3))
       (define dv (+ v 1/4))
       (define distance-squared (+ (* du du) (* dv dv)))
       (vec3 u v (exp (* -80 distance-squared))))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'localized
     #:position-tolerance 1/200 #:maximum-depth 5))
  (define localized-mesh (surface3d->mesh3d localized))
  (define localized-diagnostics (surface3d-diagnostics localized))
  (check-true (< (adaptive-surface-diagnostics-leaf-count localized-diagnostics)
                 (expt 4 5)))
  (define localized-analysis (mesh3d-validate localized-mesh))
  (check-equal? (vector-length (mesh3d-analysis-nonmanifold-edges localized-analysis)) 0)
  (check-equal? (vector-length (mesh3d-analysis-boundary-loops localized-analysis)) 1)

  (define disk
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0))
     #:u-range '(-1 1) #:v-range '(-1 1) #:id 'disk
     #:trims (list (surface-trim (lambda (u v) (- 1 (+ (* u u) (* v v))))))))
  (check-eq? (surface3d-kind disk) 'trimmed-parametric)
  (check-true (surface3d-domain-contains? disk 0 0))
  (check-false (surface3d-domain-contains? disk 1 1))
  (check-true (positive? (vec3-length (surface3d-normal-at disk 0 0))))

  ;; A trimmed plane now asks the shared adaptive dyadic tree to refine from
  ;; corner/edge/centre trim samples.  This central hole is invisible to a
  ;; corner-only planar mesh, yet it is discovered without imposing the old
  ;; global four-level minimum lattice. Boundary-loop reconstruction remains a
  ;; separate Q limitation; this test checks the retained domain and mesh
  ;; validity rather than claiming that provenance has already joined it.
  (define centre-hole
    (trim-field3d (lambda (u v) (- 1/100 (+ (* u u) (* v v))))
                  #:id 'centre-hole #:tolerance 1e-7))
  (define holed-plane
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0)) #:u-range '(-1 1) #:v-range '(-1 1)
     #:id 'holed-plane #:minimum-depth 0 #:maximum-depth 6
     #:trims (trim-not3d centre-hole)))
  (check-false (surface3d-domain-contains? holed-plane 0 0))
  (check-true (surface3d-domain-contains? holed-plane 1/2 0))
  (check-equal? (vector-length
                 (mesh3d-analysis-degenerate-triangles
                  (mesh3d-validate (surface3d->mesh3d holed-plane))))
                0)
  (check-true
   (< (adaptive-surface-diagnostics-leaf-count
       (hash-ref (surface3d-diagnostics holed-plane) 'base))
      (expt 4 4)))

  ;; Compound signed fields use min/max/complement, not a list interpreted
  ;; only as intersection.  That provides a direct spelling for the annulus
  ;; while retaining field IDs for exact boundary provenance.
  (define annulus
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0)) #:u-range '(-1 1) #:v-range '(-1 1)
     #:id 'annulus #:maximum-depth 6
     #:trims
     (trim-and3d
      (trim-field3d (lambda (u v) (- 9/16 (+ (* u u) (* v v)))) #:id 'outer)
      (trim-not3d
       (trim-field3d (lambda (u v) (- 1/16 (+ (* u u) (* v v)))) #:id 'inner)))))
  (check-false (surface3d-domain-contains? annulus 0 0))
  (check-true (surface3d-domain-contains? annulus 1/2 0))
  (check-false (surface3d-domain-contains? annulus 1 0))

  ;; Trim crossings are root-refined, not a single linear interpolation.  The
  ;; retained provenance coordinates meet the declared signed-field tolerance.
  (define root-trim (surface-trim (lambda (u _v) (- (* u u u) 1/20))
                                  #:id 'root #:tolerance 1e-8))
  (define root-trimmed
    (trimmed-parametric-surface3d
     (lambda (u v) (vec3 u v 0)) #:u-range '(-1 1) #:v-range '(-1 1)
     #:id 'root-trimmed #:maximum-depth 5 #:trims (list root-trim)))
  (define root-provenance
    (surface-mesh3d-vertex-provenance (surface3d-mesh root-trimmed)))
  (define root-points
    (for/list ([entry (in-vector root-provenance)]
               #:when (eq? (hash-ref entry 'trim-boundary #f) 'root))
      entry))
  (check-true (pair? root-points))
  (for ([entry (in-list root-points)])
    (check-true (<= (abs (- (* (hash-ref entry 'u) (hash-ref entry 'u)
                                (hash-ref entry 'u))
                             1/20))
                     1e-8)))
  (check-exn exn:fail:contract?
             (lambda ()
               (trimmed-parametric-surface3d
                (lambda (u v) (vec3 u v 0)) #:id 'duplicate-trims
                #:trims (list (surface-trim (lambda (u _v) u) #:id 'same)
                              (surface-trim (lambda (_u v) v) #:id 'same)))))

  (define sphere
    (implicit-surface3d
     (lambda (point)
       (- (+ (* (vec3-x point) (vec3-x point))
             (* (vec3-y point) (vec3-y point))
             (* (vec3-z point) (vec3-z point)))
          16/25))
     #:id 'sphere #:resolution 12))
  (define sphere-mesh (surface3d->mesh3d sphere))
  (check-eq? (surface3d-kind sphere) 'implicit)
  (check-true (positive? (vector-length (mesh3d-triangles sphere-mesh))))
  (check-equal? (vector-length (mesh3d-boundary-edges sphere-mesh)) 0)

  ;; Exact level hits belong to one canonical lattice vertex. This plane lies
  ;; directly on an even-resolution sample column; it must not produce the
  ;; coincident-edge degeneracies that independently keyed tetra edges create.
  (define exact-plane
    (implicit-surface3d (lambda (point) (vec3-x point))
                        #:bounds '(-1 1 -1 1 -1 1) #:resolution 8 #:id 'exact-plane))
  (check-equal? (vector-length (mesh3d-analysis-degenerate-triangles
                                (mesh3d-validate (surface3d->mesh3d exact-plane))))
                0)

  ;; Finite-difference normals use bounded one-sided samples at box faces.
  (define normal-probe-outside? #f)
  (define bounded-gradient-sphere
    (implicit-surface3d
     (lambda (point)
       (when (or (< (vec3-x point) -1) (> (vec3-x point) 1)
                 (< (vec3-y point) -1) (> (vec3-y point) 1)
                 (< (vec3-z point) -1) (> (vec3-z point) 1))
         (set! normal-probe-outside? #t))
       (- (+ (* (vec3-x point) (vec3-x point))
             (* (vec3-y point) (vec3-y point))
             (* (vec3-z point) (vec3-z point)))
          1))
     #:bounds '(-1 1 -1 1 -1 1) #:resolution 8 #:id 'bounded-gradient))
  (check-false normal-probe-outside?)
  (check-true (positive? (vector-length
                          (mesh3d-triangles (surface3d->mesh3d bounded-gradient-sphere)))))

  ;; Invalid cells have a declared policy. Skipping is diagnosed rather than
  ;; silently pretending that a non-finite result equals the iso level.
  (define skipped
    (implicit-surface3d
     (lambda (point)
       (if (> (vec3-x point) 1/2) +nan.0
           (- (+ (* (vec3-x point) (vec3-x point))
                 (* (vec3-y point) (vec3-y point))
                 (* (vec3-z point) (vec3-z point)))
              1/4)))
     #:bounds '(-1 1 -1 1 -1 1) #:resolution 8 #:id 'skipped #:on-invalid 'skip-cell))
  (define skipped-report (hash-ref (surface3d-diagnostics skipped) 'implicit))
  (check-true (positive? (implicit-surface-diagnostics-invalid-sample-count skipped-report)))
  (check-exn exn:fail?
             (lambda ()
               (implicit-surface3d (lambda (_point) +nan.0) #:id 'invalid-default))))
