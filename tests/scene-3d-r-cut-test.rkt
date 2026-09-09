#lang racket/base

;;; SCENE-3D-R Pure Cut and Measurement Tests

(require rackunit
         "../3d.rkt"
         "../private/color-style.rkt"
         (only-in "../colors.rkt" resolve-color animate-light-theme))

(module+ test
  (define cube (cube3d 2 #:id 'cube))
  (define plane (plane3 origin3 x-axis3))
  (define result (cut-mesh3d cube plane #:cap default-cap-style3d))
  (define section (mesh-cut3d-result-section result))
  (check-equal? (length (section3d-loops section)) 1)
  (check-equal? (section3d-chains section) '())
  (check-= (section3d-area section) 4 1e-7)
  (check-= (section3d-perimeter section) 8 1e-7)
  ;; Measurement must not silently discard a chain or assign an even/odd area
  ;; to a self-crossing loop.  Both have ambiguous planar fill topology.
  (define open-triangle
    (mesh3d #:id 'open-triangle
            #:vertices (vector (vec3 -1 0 0) (vec3 1 -1 0) (vec3 1 1 0))
            #:triangles (vector (vector 0 1 2))))
  (define open-measurement-section
    (section-by-plane3d open-triangle (plane3 origin3 x-axis3)))
  (check-exn exn:fail? (lambda () (section3d-area open-measurement-section)))
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
  (for ([solid (in-list (list (mesh-cut3d-result-positive-solid result)
                              (mesh-cut3d-result-negative-solid result)))])
    (check-true (mesh3d? solid))
    (define solid-analysis (analyze-mesh3d solid))
    (check-true (mesh3d-analysis-watertight? solid-analysis))
    (check-true (mesh3d-analysis-consistently-wound? solid-analysis))
    (check-equal? (vector-length (mesh3d-analysis-boundary-edges solid-analysis)) 0)
    (check-equal? (vector-length (mesh3d-analysis-nonmanifold-edges solid-analysis)) 0))
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
  ;; Unlike render-only multi-clips, this is material geometry.  The second
  ;; plane cuts the first sliced mesh and therefore exercises generated
  ;; vertices as valid source vertices for a later semantic operation.
  (define corner
    (slice-mesh-by-planes3d
     cube
     (list (clip-plane3d (plane3 origin3 x-axis3) #:keep 'positive)
           (clip-plane3d (plane3 origin3 y-axis3) #:keep 'positive))))
  (for ([point (in-vector (mesh3d-vertices corner))])
    (check-true (>= (vec3-x point) -1e-7))
    (check-true (>= (vec3-y point) -1e-7)))
  (check-true (positive? (vector-length (mesh3d-triangles corner))))
  ;; The matching box operation materializes the same ordered six planes as
  ;; `clip-box3d`; it is geometry, not a nested render-only wrapper.
  (define boxed
    (cut-mesh-by-box3d
     cube (aabb3 (vec3 0 0 -1) (vec3 1 1 1)) #:id 'boxed-cube))
  (for ([point (in-vector (mesh3d-vertices boxed))])
    (check-true (>= (vec3-x point) -1e-7))
    (check-true (>= (vec3-y point) -1e-7))
    (check-true (>= (vec3-z point) (- -1 1e-7)))
    (check-true (<= (vec3-x point) (+ 1 1e-7)))
    (check-true (<= (vec3-y point) (+ 1 1e-7)))
    (check-true (<= (vec3-z point) (+ 1 1e-7))))
  (check-true (positive? (vector-length (mesh3d-triangles boxed))))
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
     (negative? (vec3-dot normal z-axis3))))

  ;; A section can have a hole.  The cap must preserve its annular area rather
  ;; than filling both loops independently as two disks.
  (define (wall-triangles offset count inward?)
    (apply append
           (for/list ([index (in-range count)])
             (define next (modulo (add1 index) count))
             (define bottom (+ offset index))
             (define bottom-next (+ offset next))
             (define top (+ offset count index))
             (define top-next (+ offset count next))
             (if inward?
                 (list (vector bottom top-next bottom-next)
                       (vector bottom top top-next))
                 (list (vector bottom bottom-next top-next)
                       (vector bottom top-next top))))))
  (define outer-ring
    (list (vec3 -2 -2 -1) (vec3 2 -2 -1) (vec3 2 2 -1) (vec3 -2 2 -1)))
  (define inner-ring
    (list (vec3 -1 -1 -1) (vec3 1 -1 -1) (vec3 1 1 -1) (vec3 -1 1 -1)))
  (define (lift-ring ring) (map (lambda (point) (vec3 (vec3-x point) (vec3-y point) 1)) ring))
  (define annular-wall
    (mesh3d #:id 'annular-wall
            #:vertices (list->vector
                        (append outer-ring (lift-ring outer-ring)
                                inner-ring (lift-ring inner-ring)))
            #:triangles (list->vector
                         (append (wall-triangles 0 4 #f)
                                 (wall-triangles 8 4 #t)))))
  (define annular-section (section-by-plane3d annular-wall (plane3 origin3 z-axis3)))
  (define annular-cap (cap-section3d annular-section #:id 'annular-cap))
  (check-equal? (length (section3d-loops annular-section)) 2)
  (check-true (mesh3d? annular-cap))
  (check-=
   (for/sum ([triangle (in-vector (mesh3d-triangles annular-cap))])
     (define first (vector-ref (mesh3d-vertices annular-cap) (vector-ref triangle 0)))
     (define second (vector-ref (mesh3d-vertices annular-cap) (vector-ref triangle 1)))
     (define third (vector-ref (mesh3d-vertices annular-cap) (vector-ref triangle 2)))
     (/ (abs (vec3-dot (vec3-cross (vec3- second first) (vec3- third first)) z-axis3)) 2))
   12 1e-7)

  ;; Cutting is an indexed attribute operation, not merely a position
  ;; operation.  The two generated edge vertices carry the same interpolated
  ;; colours no matter which source triangle encountered the edge first.
  (define coloured-triangle
    (mesh3d #:id 'coloured-triangle
            #:vertices (vector (vec3 -1 0 0) (vec3 1 0 0) (vec3 1 1 0))
            #:triangles (vector (vector 0 1 2))
            #:colors (vector "red" "green" "blue")))
  (define coloured-half
    (slice-mesh3d coloured-triangle (plane3 origin3 x-axis3) #:keep 'positive))
  (check-equal? (vector-length (mesh3d-colors coloured-half))
                (vector-length (mesh3d-vertices coloured-half)))
  (define (colour-at x y)
    (for/first ([point (in-vector (mesh3d-vertices coloured-half))]
                [colour (in-vector (mesh3d-colors coloured-half))]
                #:when (and (= (vec3-x point) x) (= (vec3-y point) y)))
      colour))
  (define red-green (colour-at 0 0))
  (define red-blue (colour-at 0 1/2))
  (check-true (rgba-color? red-green))
  (check-true (rgba-color? red-blue))
  (check-= (rgba-color-red red-green) 187.51603067837462 1e-12)
  (check-= (rgba-color-green red-green) 187.51603067837462 1e-12)
  (check-= (rgba-color-blue red-green) 0 1e-12)
  (check-= (rgba-color-red red-blue) 187.51603067837462 1e-12)
  (check-= (rgba-color-green red-blue) 0 1e-12)
  (check-= (rgba-color-blue red-blue) 187.51603067837462 1e-12)

  ;; A welded cap reuses the exact cut-boundary positions, so it also retains
  ;; the already-interpolated side colour channel instead of dropping it.
  (define uniformly-coloured-cube
    (mesh3d #:id 'uniformly-coloured-cube
            #:vertices (mesh3d-vertices cube)
            #:triangles (mesh3d-triangles cube)
            #:normals (mesh3d-normals cube)
            #:colors (for/vector ([unused (in-vector (mesh3d-vertices cube))]) "tomato")))
  (define coloured-cut
    (cut-mesh3d uniformly-coloured-cube (plane3 origin3 x-axis3)
                #:cap default-cap-style3d))
  (for ([solid (in-list (list (mesh-cut3d-result-positive-solid coloured-cut)
                              (mesh-cut3d-result-negative-solid coloured-cut)))])
    (check-equal? (vector-length (mesh3d-colors solid))
                  (vector-length (mesh3d-vertices solid)))
    (define tomato (color-spec->rgba-color "tomato"))
    (check-true (for/and ([color (in-vector (mesh3d-colors solid))])
                  (equal? (resolve-color color animate-light-theme) tomato)))))
