#lang racket/base

;;; SCENE-3D-R Pure Cut and Measurement Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define plane (plane3 origin3 x-axis3))
  (define result (cut-mesh3d cube plane #:cap default-cap-style3d))
  (define section (mesh-cut3d-result-section result))
  (check-equal? (length (section3d-loops section)) 1)
  (check-equal? (section3d-chains section) '())
  (check-= (section3d-area section) 4 1e-7)
  (check-= (section3d-perimeter section) 8 1e-7)
  (define centroid (section3d-centroid section))
  (check-= (vec3-x centroid) 0 1e-7)
  (check-= (vec3-y centroid) 0 1e-7)
  (check-= (vec3-z centroid) 0 1e-7)
  (define moments (section3d-second-moments section))
  (check-= (vector-ref moments 0) 4/3 1e-7)
  (check-= (vector-ref moments 1) 4/3 1e-7)
  (check-= (vector-ref moments 2) 0 1e-7)
  (check-true (mesh3d? (mesh-cut3d-result-positive-cap result)))
  (check-true (mesh3d? (mesh-cut3d-result-negative-cap result)))
  (check-true (mesh3d? (section-fill3d section #:id 'fill)))
  (define hatch (section-hatch3d section #:spacing 1/2 #:id 'hatch))
  (check-true (group3d? hatch))
  (check-true (positive? (length (group3d-children hatch))))
  (check-true (positive? (vector-length (mesh3d-triangles (mesh-cut3d-result-positive result)))))
  (check-true (positive? (vector-length (mesh3d-triangles (mesh-cut3d-result-negative result)))))
  ;; The indexed half contains shared source-edge intersections rather than a
  ;; separate copy of each clipped polygon corner.
  (check-true
   (< (vector-length (mesh3d-vertices (mesh-cut3d-result-positive result)))
      (* 3 (vector-length (mesh3d-triangles (mesh-cut3d-result-positive result))))))
  (define slices
    (prepare-cross-section-function3d cube #:normal x-axis3
                                       #:range (list -9/10 9/10) #:samples 5))
  (define estimate (volume-by-slices3d slices #:rule 'trapezoid))
  (check-= (volume-estimate3d-value estimate) 36/5 1e-7)
  (check-equal? (vector-length (volume-estimate3d-terms estimate)) 5)
  (define stack (slice-stack3d cube #:normal x-axis3 #:range (list -1 1) #:count 3))
  (check-equal? (length (group3d-children stack)) 3)

  ;; The cap is no longer a centre fan: an L-shaped section requires a
  ;; deterministic concave-polygon triangulation.  Only side faces are needed
  ;; here, because the plane/mesh section is the semantic source of the cap.
  (define l-contour
    (list (vec3 0 0 -1) (vec3 2 0 -1) (vec3 2 1 -1)
          (vec3 1 1 -1) (vec3 1 2 -1) (vec3 0 2 -1)))
  (define l-prism
    (let* ([bottom l-contour]
           [top (map (lambda (point) (vec3 (vec3-x point) (vec3-y point) 1)) bottom)]
           [vertices (list->vector (append bottom top))]
           [count (length bottom)])
      (mesh3d #:id 'concave-prism #:vertices vertices
              #:triangles
              (list->vector
               (apply append
                (for/list ([index (in-range count)])
                  (define next (modulo (add1 index) count))
                  (list (vector index next (+ count next))
                        (vector index (+ count next) (+ count index)))))))))
  (define l-section (section-by-plane3d l-prism (plane3 origin3 z-axis3)))
  (define l-cap (cap-section3d l-section #:side 'positive #:id 'concave-cap))
  (check-equal? (length (section3d-loops l-section)) 1)
  (check-= (section3d-area l-section) 3 1e-7)
  (check-true (mesh3d? l-cap))
  (check-true (positive? (vector-length (mesh3d-triangles l-cap))))
  (check-=
   (for/sum ([triangle (in-vector (mesh3d-triangles l-cap))])
     (define first (vector-ref (mesh3d-vertices l-cap) (vector-ref triangle 0)))
     (define second (vector-ref (mesh3d-vertices l-cap) (vector-ref triangle 1)))
     (define third (vector-ref (mesh3d-vertices l-cap) (vector-ref triangle 2)))
     (/ (abs (vec3-dot (vec3-cross (vec3- second first) (vec3- third first)) z-axis3)) 2))
   3 1e-7)
  (check-true
   (for/and ([normal (in-vector (mesh3d-normals l-cap))])
     (negative? (vec3-dot normal z-axis3)))))
