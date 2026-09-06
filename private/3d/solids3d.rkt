#lang racket/base

;;;
;;; Constructive Spatial Solids
;;;

;; Defines deterministic indexed meshes for standard solids and the first
;; constructive operations.  Every constructor returns ordinary `mesh3d`
;; data; no renderer state or tessellation history is retained.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/math
         "../geometry.rkt"
         "affine3.rkt"
         "curve3d.rkt"
         "linear3.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "rotation3.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "vec3.rkt")

(provide cube3d
         box3d
         prism3d
         sphere3d
         cylinder3d
         cone3d
         torus3d
         tetrahedron3d
         octahedron3d
         icosahedron3d
         polyhedron3d
         extrude3d
         revolve3d
         sweep3d
         mesh3d-transform
         mesh3d-reverse-winding
         mesh3d-flat-normals
         mesh3d-smooth-normals
         mesh3d-boundary-edges
         mesh3d-wireframe
         mesh3d-merge)


;;;
;;; Shared Construction
;;;

; solid-material : any/c color-spec? -> material3d?
;;   Chooses an explicit material or a deterministic smooth solid material.
(define (solid-material material color)
  (cond [material
         (unless (material3d? material)
           (raise-argument-error 'solid3d "(or/c #f material3d?)" material))
         material]
        [else (material3d #:color color #:shading 'smooth)]))

; make-solid : symbol? (vectorof vec3?) (vectorof index-triple?) ... -> mesh3d?
;;   Creates one uniformly configured solid mesh and supplies smooth normals.
(define (make-solid id vertices triangles
                    #:material [material #f]
                    #:color [color "cornflowerblue"]
                    #:transform [transform identity-transform3]
                    #:opacity [opacity 1])
  (define base
    (mesh3d #:id id #:vertices vertices #:triangles triangles
            #:material (solid-material material color)
            #:transform transform #:opacity opacity))
  (mesh3d-smooth-normals base))

; check-id : symbol? symbol? -> void?
;;   Checks the stable public identity used by every solid constructor.
(define (check-id who id)
  (unless (symbol? id) (raise-argument-error who "symbol?" id)))

; check-positive : symbol? any/c -> void?
;;   Checks a strictly positive finite size parameter.
(define (check-positive who value)
  (unless (and (finite-real? value) (positive? value))
    (raise-argument-error who "positive finite real?" value)))

; check-segments : symbol? any/c [exact-positive-integer?] -> void?
;;   Checks a stable circular tessellation count.
(define (check-segments who value [minimum 3])
  (unless (and (exact-integer? value) (>= value minimum))
    (raise-argument-error who (format "exact integer at least ~a" minimum) value)))

; closed-loop : symbol? any/c -> (listof vec2?)
;;   Freezes one simple, nonrepeated planar contour without its optional closing
;; duplicate.  More elaborate contour and hole construction is deliberately
;; left to a later Boolean/trimmed-surface stage.
(define (closed-loop who contour)
  (unless (or (list? contour) (vector? contour))
    (raise-argument-error who "(or/c list? vector?)" contour))
  (define supplied (if (vector? contour) (vector->list contour) contour))
  (unless (andmap vec2? supplied)
    (raise-argument-error who "a sequence of vec2?" contour))
  (define points
    (if (and (>= (length supplied) 2)
             (equal? (first supplied) (last supplied)))
        (drop-right supplied 1)
        supplied))
  (unless (>= (length points) 3)
    (raise-arguments-error who "at least three contour corners" "contour" contour))
  (when (check-duplicates points equal?)
    (raise-arguments-error who "a simple contour with distinct corners" "contour" contour))
  (unless (positive? (abs (polygon-area points)))
    (raise-arguments-error who "a contour with nonzero signed area" "contour" contour))
  (when (self-intersecting? points)
    (raise-arguments-error who "a non-self-intersecting contour" "contour" contour))
  points)

; polygon-area : (listof vec2?) -> finite-real?
;;   Returns twice the signed area of a closed contour.
(define (polygon-area points)
  (/ (for/sum ([point (in-list points)] [next (in-list (rotate-left points))])
       (- (* (vec2-x point) (vec2-y next))
          (* (vec2-y point) (vec2-x next))))
     2))

; rotate-left : pair? -> list?
;;   Produces the cyclic successor order of a nonempty list.
(define (rotate-left values) (append (rest values) (list (first values))))

; self-intersecting? : (listof vec2?) -> boolean?
;;   Detects nonadjacent planar segment intersections deterministically.
(define (self-intersecting? points)
  (define count (length points))
  (for/or ([index (in-range count)])
    (for/or ([other (in-range (+ index 1) count)]
             #:unless (or (= other (add1 index))
                          (and (= index 0) (= other (sub1 count)))))
      (segments-intersect? (list-ref points index)
                           (list-ref points (modulo (add1 index) count))
                           (list-ref points other)
                           (list-ref points (modulo (add1 other) count))))))

; segments-intersect? : vec2? vec2? vec2? vec2? -> boolean?
;;   Tests closed line segments by their signed orientations.
(define (segments-intersect? a b c d)
  (define (orientation p q r)
    (- (* (- (vec2-x q) (vec2-x p)) (- (vec2-y r) (vec2-y p)))
       (* (- (vec2-y q) (vec2-y p)) (- (vec2-x r) (vec2-x p)))))
  (define ab-c (orientation a b c))
  (define ab-d (orientation a b d))
  (define cd-a (orientation c d a))
  (define cd-b (orientation c d b))
  (and (<= (* ab-c ab-d) 0) (<= (* cd-a cd-b) 0)))


;;;
;;; Standard Solids
;;;

; box3d : finite-real? finite-real? finite-real? #:id symbol? ... -> mesh3d?
;;   Creates an origin-centred axis-aligned rectangular solid.
(define (box3d width height depth #:id id
               #:material [material #f] #:color [color "cornflowerblue"]
               #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'box3d id)
  (for ([value (in-list (list width height depth))]) (check-positive 'box3d value))
  (define x (/ width 2)) (define y (/ height 2)) (define z (/ depth 2))
  (make-solid id
              (vector (vec3 (- x) (- y) (- z)) (vec3 x (- y) (- z))
                      (vec3 x y (- z)) (vec3 (- x) y (- z))
                      (vec3 (- x) (- y) z) (vec3 x (- y) z)
                      (vec3 x y z) (vec3 (- x) y z))
              (vector (vector 0 2 1) (vector 0 3 2)
                      (vector 4 5 6) (vector 4 6 7)
                      (vector 0 4 7) (vector 0 7 3)
                      (vector 1 2 6) (vector 1 6 5)
                      (vector 3 7 6) (vector 3 6 2)
                      (vector 0 1 5) (vector 0 5 4))
              #:material material #:color color #:transform transform #:opacity opacity))

; cube3d : finite-real? #:id symbol? ... -> mesh3d?
;;   Creates an origin-centred cube with equal edge lengths.
(define (cube3d side #:id id
                #:material [material #f] #:color [color "cornflowerblue"]
                #:transform [transform identity-transform3] #:opacity [opacity 1])
  (box3d side side side #:id id #:material material #:color color
         #:transform transform #:opacity opacity))

; prism3d : exact-positive-integer? #:radius finite-real? #:height finite-real?
;;           #:id symbol? ... -> mesh3d?
;;   Creates a regular polygonal prism aligned with the z axis.
(define (prism3d sides #:id id #:radius [radius 1] #:height [height 2]
                 #:material [material #f] #:color [color "cornflowerblue"]
                 #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'prism3d id) (check-segments 'prism3d sides) (check-positive 'prism3d radius)
  (check-positive 'prism3d height)
  (define contour
    (for/list ([index (in-range sides)])
      (vec2 (* radius (cos (* 2 pi (/ index sides))))
            (* radius (sin (* 2 pi (/ index sides)))))))
  (extrude3d contour #:id id #:vector (vec3 0 0 height)
             #:material material #:color color #:transform transform #:opacity opacity))

; sphere3d : finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a latitude-longitude sphere with stable pole and ring samples.
(define (sphere3d radius #:id id #:latitude-segments [latitudes 24]
                  #:longitude-segments [longitudes 48]
                  #:material [material #f] #:color [color "cornflowerblue"]
                  #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'sphere3d id) (check-positive 'sphere3d radius)
  (check-segments 'sphere3d latitudes 2) (check-segments 'sphere3d longitudes)
  (define vertices
    (list->vector
     (append (list (vec3 0 0 radius))
             (for*/list ([latitude (in-range 1 latitudes)]
                         [longitude (in-range longitudes)])
               (define phi (* pi (/ latitude latitudes)))
               (define theta (* 2 pi (/ longitude longitudes)))
               (vec3 (* radius (sin phi) (cos theta))
                     (* radius (sin phi) (sin theta))
                     (* radius (cos phi))))
             (list (vec3 0 0 (- radius))))))
  (define (ring index longitude) (+ 1 (* (sub1 index) longitudes) longitude))
  (define south (sub1 (vector-length vertices)))
  (define triangles
    (list->vector
     (append
      (for/list ([longitude (in-range longitudes)])
        (vector 0 (ring 1 longitude) (ring 1 (modulo (add1 longitude) longitudes))))
      (apply append
             (for/list ([latitude (in-range 1 (sub1 latitudes))])
               (apply append
                      (for/list ([longitude (in-range longitudes)])
                        (define next (modulo (add1 longitude) longitudes))
                        (list (vector (ring latitude longitude) (ring (add1 latitude) longitude)
                                      (ring (add1 latitude) next))
                              (vector (ring latitude longitude) (ring (add1 latitude) next)
                                      (ring latitude next)))))))
      (for/list ([longitude (in-range longitudes)])
        (vector (ring (sub1 latitudes) (modulo (add1 longitude) longitudes))
                (ring (sub1 latitudes) longitude) south)))))
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))

; cylinder3d : finite-real? finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a capped circular cylinder aligned with the z axis.
(define (cylinder3d radius height #:id id #:segments [segments 48]
                    #:caps? [caps? #t] #:material [material #f]
                    #:color [color "cornflowerblue"] #:transform [transform identity-transform3]
                    #:opacity [opacity 1])
  (check-id 'cylinder3d id) (check-positive 'cylinder3d radius)
  (check-positive 'cylinder3d height) (check-segments 'cylinder3d segments)
  (define contour (for/list ([index (in-range segments)])
                    (vec2 (* radius (cos (* 2 pi (/ index segments))))
                          (* radius (sin (* 2 pi (/ index segments)))))))
  (extrude3d contour #:id id #:vector (vec3 0 0 height) #:caps? caps?
             #:material material #:color color #:transform transform #:opacity opacity))

; cone3d : finite-real? finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a capped cone with its apex on positive z and base centred at z=0.
(define (cone3d radius height #:id id #:segments [segments 48] #:caps? [caps? #t]
                #:material [material #f] #:color [color "cornflowerblue"]
                #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'cone3d id) (check-positive 'cone3d radius) (check-positive 'cone3d height)
  (check-segments 'cone3d segments)
  (define vertices
    (list->vector
     (append (for/list ([index (in-range segments)])
               (define theta (* 2 pi (/ index segments)))
               (vec3 (* radius (cos theta)) (* radius (sin theta)) 0))
             (list (vec3 0 0 height))
             (if caps? (list origin3) '()))))
  (define apex segments)
  (define center (and caps? (add1 segments)))
  (define triangles
    (list->vector
     (append (for/list ([index (in-range segments)])
               (vector index (modulo (add1 index) segments) apex))
             (if caps?
                 (for/list ([index (in-range segments)])
                   (vector center (modulo (add1 index) segments) index))
                 '()))))
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))

; torus3d : finite-real? finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a z-axis torus with major radius from origin to tube centre.
(define (torus3d major-radius minor-radius #:id id #:major-segments [major 48]
                #:minor-segments [minor 20] #:material [material #f]
                #:color [color "cornflowerblue"] #:transform [transform identity-transform3]
                #:opacity [opacity 1])
  (check-id 'torus3d id) (check-positive 'torus3d major-radius)
  (check-positive 'torus3d minor-radius) (check-segments 'torus3d major)
  (check-segments 'torus3d minor)
  (define (index first second) (+ (* first minor) second))
  (define vertices
    (for*/vector ([first (in-range major)] [second (in-range minor)])
      (define theta (* 2 pi (/ first major)))
      (define phi (* 2 pi (/ second minor)))
      (define radial (+ major-radius (* minor-radius (cos phi))))
      (vec3 (* radial (cos theta)) (* radial (sin theta)) (* minor-radius (sin phi)))))
  (define triangles
    (list->vector
     (apply append
            (for*/list ([first (in-range major)] [second (in-range minor)])
              (define next-first (modulo (add1 first) major))
              (define next-second (modulo (add1 second) minor))
              (list (vector (index first second) (index next-first second)
                            (index next-first next-second))
                    (vector (index first second) (index next-first next-second)
                            (index first next-second)))))))
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))

; tetrahedron3d : finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a regular tetrahedron centred at the origin.
(define (tetrahedron3d radius #:id id #:material [material #f] #:color [color "cornflowerblue"]
                      #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'tetrahedron3d id) (check-positive 'tetrahedron3d radius)
  (define scale (/ radius (sqrt 3)))
  (make-solid id
              (vector (vec3 scale scale scale) (vec3 scale (- scale) (- scale))
                      (vec3 (- scale) scale (- scale)) (vec3 (- scale) (- scale) scale))
              (vector (vector 0 1 2) (vector 0 3 1) (vector 0 2 3) (vector 1 3 2))
              #:material material #:color color #:transform transform #:opacity opacity))

; octahedron3d : finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a regular octahedron with vertices on coordinate axes.
(define (octahedron3d radius #:id id #:material [material #f] #:color [color "cornflowerblue"]
                     #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'octahedron3d id) (check-positive 'octahedron3d radius)
  (make-solid id (vector (vec3 radius 0 0) (vec3 (- radius) 0 0)
                         (vec3 0 radius 0) (vec3 0 (- radius) 0)
                         (vec3 0 0 radius) (vec3 0 0 (- radius)))
              (vector (vector 0 2 4) (vector 2 1 4) (vector 1 3 4) (vector 3 0 4)
                      (vector 2 0 5) (vector 1 2 5) (vector 3 1 5) (vector 0 3 5))
              #:material material #:color color #:transform transform #:opacity opacity))

; icosahedron3d : finite-real? #:id symbol? ... -> mesh3d?
;;   Creates a regular icosahedron normalized to the requested vertex radius.
(define (icosahedron3d radius #:id id #:material [material #f] #:color [color "cornflowerblue"]
                     #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'icosahedron3d id) (check-positive 'icosahedron3d radius)
  (define phi (/ (+ 1 (sqrt 5)) 2))
  (define normalizer (/ radius (sqrt (+ 1 (* phi phi)))))
  (define (v x y z) (vec3 (* normalizer x) (* normalizer y) (* normalizer z)))
  (make-solid id
              (vector (v -1 phi 0) (v 1 phi 0) (v -1 (- phi) 0) (v 1 (- phi) 0)
                      (v 0 -1 phi) (v 0 1 phi) (v 0 -1 (- phi)) (v 0 1 (- phi))
                      (v phi 0 -1) (v phi 0 1) (v (- phi) 0 -1) (v (- phi) 0 1))
              (vector (vector 0 11 5) (vector 0 5 1) (vector 0 1 7) (vector 0 7 10) (vector 0 10 11)
                      (vector 1 5 9) (vector 5 11 4) (vector 11 10 2) (vector 10 7 6) (vector 7 1 8)
                      (vector 3 9 4) (vector 3 4 2) (vector 3 2 6) (vector 3 6 8) (vector 3 8 9)
                      (vector 4 9 5) (vector 2 4 11) (vector 6 2 10) (vector 8 6 7) (vector 9 8 1))
              #:material material #:color color #:transform transform #:opacity opacity))

; polyhedron3d : (vectorof vec3?) (vectorof index-triple?) #:id symbol? ... -> mesh3d?
;;   Validates arbitrary explicit triangular polyhedron topology.
(define (polyhedron3d vertices triangles #:id id #:material [material #f]
                      #:color [color "cornflowerblue"] #:transform [transform identity-transform3]
                      #:opacity [opacity 1])
  (check-id 'polyhedron3d id)
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))


;;;
;;; Constructive Operations
;;;

; extrude3d : (sequenceof vec2?) #:id symbol? #:vector vec3? [#:caps? boolean?] ... -> mesh3d?
;;   Extrudes one simple xy-plane contour through a noncoplanar vector. Caps use
;; deterministic ear clipping; holes and self-intersections are rejected.
(define (extrude3d contour #:id id #:vector [direction (vec3 0 0 1)] #:caps? [caps? #t]
                   #:material [material #f] #:color [color "cornflowerblue"]
                   #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'extrude3d id)
  (unless (vec3? direction) (raise-argument-error 'extrude3d "vec3?" direction))
  (when (zero? (vec3-length direction))
    (raise-argument-error 'extrude3d "nonzero extrusion vector" direction))
  ;; An in-plane vector would have no volume from an xy contour.
  (when (zero? (vec3-z direction))
    (raise-argument-error 'extrude3d "an extrusion vector with nonzero z component" direction))
  (unless (boolean? caps?) (raise-argument-error 'extrude3d "boolean?" caps?))
  (define loop (closed-loop 'extrude3d contour))
  (define oriented (if (negative? (* (polygon-area loop) (vec3-z direction)))
                       (reverse loop) loop))
  (define count (length oriented))
  (define base (for/list ([point (in-list oriented)]) (vec3 (vec2-x point) (vec2-y point) 0)))
  (define vertices (list->vector (append base (map (lambda (point) (vec3+ point direction)) base))))
  (define side-triangles
    (apply append
           (for/list ([index (in-range count)])
             (define next (modulo (add1 index) count))
             (list (vector index next (+ count next))
                   (vector index (+ count next) (+ count index))))))
  (define cap-indices (ear-triangulate oriented))
  (define triangles
    (list->vector
     (append side-triangles
             (if caps?
                 (append (for/list ([triangle (in-list cap-indices)])
                           (vector (vector-ref triangle 2) (vector-ref triangle 1) (vector-ref triangle 0)))
                         (for/list ([triangle (in-list cap-indices)])
                           (vector (+ count (vector-ref triangle 0)) (+ count (vector-ref triangle 1))
                                   (+ count (vector-ref triangle 2)))))
                 '()))))
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))

; revolve3d : (sequenceof vec2?) #:id symbol? [#:axis symbol?] ... -> mesh3d?
;;   Revolves a nonnegative-radius planar profile. A profile point `(vec2 a r)`
;; means axis coordinate a and radius r. Full closed turns use triangle fans at
;; the endpoint disks; partial turns leave their radial cut faces open.
(define (revolve3d profile #:id id #:axis [axis 'z] #:angle [angle (* 2 pi)]
                   #:segments [segments 96] #:caps? [caps? #t]
                   #:material [material #f] #:color [color "cornflowerblue"]
                   #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'revolve3d id) (check-segments 'revolve3d segments)
  (unless (memq axis '(x y z)) (raise-argument-error 'revolve3d "(or/c 'x 'y 'z)" axis))
  (unless (and (finite-real? angle) (positive? angle) (<= angle (* 2 pi)))
    (raise-argument-error 'revolve3d "finite angle in (0, 2*pi]" angle))
  (unless (boolean? caps?) (raise-argument-error 'revolve3d "boolean?" caps?))
  (define samples (closed-profile 'revolve3d profile))
  (unless (andmap (lambda (point) (>= (vec2-y point) 0)) samples)
    (raise-argument-error 'revolve3d "a profile with nonnegative radial coordinates" profile))
  (define full? (= angle (* 2 pi)))
  (define ring-count (if full? segments (add1 segments)))
  (define vertex-lists '())
  (define rings
    (for/list ([sample (in-list samples)])
      (define coordinate (vec2-x sample)) (define radius (vec2-y sample))
      (if (zero? radius)
          (let ([index (length vertex-lists)])
            (set! vertex-lists (append vertex-lists (list (axis-point axis coordinate 0))))
            (list index))
          (for/list ([segment (in-range ring-count)])
            (define index (length vertex-lists))
            (set! vertex-lists
                  (append vertex-lists (list (revolution-point axis coordinate radius
                                                              (* angle (/ segment segments))))))
            index))))
  (define triangles
    (apply append
           (for/list ([first (in-list rings)] [second (in-list (rest rings))])
             (ring-band-triangles first second full?))))
  ;; A non-axis endpoint needs a centre vertex for its closing disk. Axis
  ;; endpoints already collapse to one vertex and require no zero-area fan.
  (when (and caps? full?)
    (for ([ring (in-list (list (first rings) (last rings)))]
          [sample (in-list (list (first samples) (last samples)))]
          [reverse? (in-list (list #t #f))])
      (when (> (length ring) 1)
        (define centre (length vertex-lists))
        (set! vertex-lists (append vertex-lists (list (axis-point axis (vec2-x sample) 0))))
        (define fan
          (for/list ([index (in-range (length ring))])
            (define next (modulo (add1 index) (length ring)))
            (if reverse?
                (vector centre (list-ref ring next) (list-ref ring index))
                (vector centre (list-ref ring index) (list-ref ring next)))))
        (set! triangles (append triangles fan)))))
  (make-solid id (list->vector vertex-lists) (list->vector triangles)
              #:material material #:color color #:transform transform #:opacity opacity))

; sweep3d : (sequenceof vec2?) curve3d? #:id symbol? ... -> mesh3d?
;;   Sweeps a simple closed planar profile along a sampled curve with a
;; deterministic parallel-transport frame. Caps are supported by ear clipping.
(define (sweep3d profile curve #:id id #:caps? [caps? #t]
                 #:material [material #f] #:color [color "cornflowerblue"]
                 #:transform [transform identity-transform3] #:opacity [opacity 1])
  (check-id 'sweep3d id)
  (unless (curve3d? curve) (raise-argument-error 'sweep3d "curve3d?" curve))
  (unless (boolean? caps?) (raise-argument-error 'sweep3d "boolean?" caps?))
  (define contour (closed-loop 'sweep3d profile))
  (define points (for/list ([point (in-vector (curve3d-points curve))])
                   (transform3-apply-point (spatial-transform curve) point)))
  (define tangents (curve-tangents points))
  (define normals (parallel-transport-normals tangents))
  (define binormals (map vec3-cross tangents normals))
  (define count (length contour))
  (define vertices
    (list->vector
     (apply append
            (for/list ([point (in-list points)] [normal (in-list normals)] [binormal (in-list binormals)])
              (for/list ([corner (in-list contour)])
                (vec3+ point
                       (vec3+ (vec3-scale (vec2-x corner) normal)
                              (vec3-scale (vec2-y corner) binormal))))))))
  (define (index ring corner) (+ (* ring count) corner))
  (define side-triangles
    (apply append
           (for/list ([ring (in-range (sub1 (length points)))])
             (apply append
                    (for/list ([corner (in-range count)])
                      (define next (modulo (add1 corner) count))
                      (list (vector (index ring corner) (index ring next) (index (add1 ring) next))
                            (vector (index ring corner) (index (add1 ring) next) (index (add1 ring) corner))))))))
  (define cap-triangles (ear-triangulate contour))
  (define triangles
    (list->vector
     (append side-triangles
             (if caps?
                 (append (for/list ([triangle (in-list cap-triangles)])
                           (vector (vector-ref triangle 2) (vector-ref triangle 1) (vector-ref triangle 0)))
                         (for/list ([triangle (in-list cap-triangles)])
                           (vector (+ (* (sub1 (length points)) count) (vector-ref triangle 0))
                                   (+ (* (sub1 (length points)) count) (vector-ref triangle 1))
                                   (+ (* (sub1 (length points)) count) (vector-ref triangle 2)))))
                 '()))))
  (make-solid id vertices triangles #:material material #:color color
              #:transform transform #:opacity opacity))


;;;
;;; Mesh Utilities
;;;

; mesh3d-transform : mesh3d? transform3? -> mesh3d?
;;   Bakes an affine author transform into local mesh geometry and normals.
(define (mesh3d-transform mesh transform)
  (unless (mesh3d? mesh) (raise-argument-error 'mesh3d-transform "mesh3d?" mesh))
  (unless (transform3? transform) (raise-argument-error 'mesh3d-transform "transform3?" transform))
  (define map (transform3->affine3 transform))
  (define vertices (for/vector ([vertex (in-vector (mesh3d-vertices mesh))])
                     (affine3-apply-point map vertex)))
  (define normals (mesh3d-normals mesh))
  (mesh3d #:id (spatial-id mesh) #:vertices vertices #:triangles (mesh3d-triangles mesh)
          #:normals (and normals (for/vector ([normal (in-vector normals)])
                                  (safe-normal (linear3-apply-vector
                                                (affine3-normal-transform map) normal))))
          #:colors (mesh3d-colors mesh) #:material (mesh3d-material mesh)
          #:transform (spatial-transform mesh) #:opacity (spatial-opacity mesh)
          #:wireframe-color (mesh3d-wireframe-color mesh)
          #:wireframe-width (mesh3d-wireframe-width mesh)))

; mesh3d-reverse-winding : mesh3d? -> mesh3d?
;;   Reverses every face's orientation while retaining all vertex identities.
(define (mesh3d-reverse-winding mesh)
  (copy-mesh mesh #:triangles
             (for/vector ([triangle (in-vector (mesh3d-triangles mesh))])
               (vector (vector-ref triangle 0) (vector-ref triangle 2) (vector-ref triangle 1)))
             #:normals (and (mesh3d-normals mesh)
                            (for/vector ([normal (in-vector (mesh3d-normals mesh))])
                              (vec3-scale -1 normal)))))

; mesh3d-flat-normals : mesh3d? -> mesh3d?
;;   Duplicates vertices per triangle so every face gets one exact normal.
(define (mesh3d-flat-normals mesh)
  (unless (mesh3d? mesh) (raise-argument-error 'mesh3d-flat-normals "mesh3d?" mesh))
  (define vertices '()) (define normals '()) (define triangles '()) (define colors '())
  (define source-colors (mesh3d-colors mesh))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define face (face-normal mesh triangle))
    (define base (length vertices))
    (for ([index (in-vector triangle)])
      (set! vertices (append vertices (list (vector-ref (mesh3d-vertices mesh) index))))
      (set! normals (append normals (list face)))
      (when source-colors (set! colors (append colors (list (vector-ref source-colors index))))))
    (set! triangles (append triangles (list (vector base (add1 base) (+ base 2))))))
  (mesh3d #:id (spatial-id mesh) #:vertices (list->vector vertices) #:triangles (list->vector triangles)
          #:normals (list->vector normals) #:colors (and source-colors (list->vector colors))
          #:material (mesh3d-material mesh) #:transform (spatial-transform mesh)
          #:opacity (spatial-opacity mesh) #:wireframe-color (mesh3d-wireframe-color mesh)
          #:wireframe-width (mesh3d-wireframe-width mesh)))

; mesh3d-smooth-normals : mesh3d? -> mesh3d?
;;   Computes area-weighted shared-vertex normals with a stable z-axis fallback.
(define (mesh3d-smooth-normals mesh)
  (unless (mesh3d? mesh) (raise-argument-error 'mesh3d-smooth-normals "mesh3d?" mesh))
  (define count (vector-length (mesh3d-vertices mesh)))
  (define accumulators (make-vector count origin3))
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (define normal (face-cross mesh triangle))
    (for ([index (in-vector triangle)])
      (vector-set! accumulators index (vec3+ (vector-ref accumulators index) normal))))
  (copy-mesh mesh #:normals (for/vector ([normal (in-vector accumulators)]) (safe-normal normal))))

; mesh3d-boundary-edges : mesh3d? -> immutable-vector?
;;   Returns undirected edges incident to exactly one triangle in encounter order.
(define (mesh3d-boundary-edges mesh)
  (unless (mesh3d? mesh) (raise-argument-error 'mesh3d-boundary-edges "mesh3d?" mesh))
  (define counts (make-hash)) (define order '())
  (for ([triangle (in-vector (mesh3d-triangles mesh))])
    (for ([pair (in-list (list (list (vector-ref triangle 0) (vector-ref triangle 1))
                               (list (vector-ref triangle 1) (vector-ref triangle 2))
                               (list (vector-ref triangle 2) (vector-ref triangle 0))))])
      (define key (cons (min (first pair) (second pair)) (max (first pair) (second pair))))
      (unless (hash-has-key? counts key) (set! order (append order (list key))))
      (hash-set! counts key (add1 (hash-ref counts key 0)))))
  (vector->immutable-vector
   (list->vector (for/list ([edge (in-list order)] #:when (= (hash-ref counts edge) 1))
                   (vector-immutable (car edge) (cdr edge))))))

; mesh3d-wireframe : mesh3d? -> mesh3d?
;;   Marks a mesh material as a wireframe intent for supported view render modes.
(define (mesh3d-wireframe mesh)
  (unless (mesh3d? mesh) (raise-argument-error 'mesh3d-wireframe "mesh3d?" mesh))
  (define material (mesh3d-material mesh))
  (copy-mesh mesh #:material
             (material3d #:color (material3d-color material) #:shading (material3d-shading material)
                         #:ambient (material3d-ambient material) #:diffuse (material3d-diffuse material)
                         #:specular (material3d-specular material) #:roughness (material3d-roughness material)
                         #:double-sided? (material3d-double-sided? material) #:wireframe? #t)))

; mesh3d-merge : (sequenceof mesh3d?) #:id symbol? -> mesh3d?
;;   Bakes a deterministic sequence of compatible meshes into one local mesh.
(define (mesh3d-merge meshes #:id id #:material [material #f]
                      #:color [color "cornflowerblue"])
  (check-id 'mesh3d-merge id)
  (unless (or (list? meshes) (vector? meshes))
    (raise-argument-error 'mesh3d-merge "(or/c list? vector?)" meshes))
  (define inputs (if (vector? meshes) (vector->list meshes) meshes))
  (unless (pair? inputs) (raise-argument-error 'mesh3d-merge "nonempty sequence of mesh3d?" meshes))
  (unless (andmap mesh3d? inputs) (raise-argument-error 'mesh3d-merge "sequence of mesh3d?" meshes))
  (define vertices '()) (define triangles '()) (define colors '()) (define every-color? (andmap mesh3d-colors inputs))
  (for ([mesh (in-list inputs)])
    (define offset (length vertices))
    (define map (transform3->affine3 (spatial-transform mesh)))
    (set! vertices (append vertices (for/list ([vertex (in-vector (mesh3d-vertices mesh))])
                                      (affine3-apply-point map vertex))))
    (set! triangles (append triangles
                            (for/list ([triangle (in-vector (mesh3d-triangles mesh))])
                              (vector (+ offset (vector-ref triangle 0)) (+ offset (vector-ref triangle 1))
                                      (+ offset (vector-ref triangle 2))))))
    (when every-color? (set! colors (append colors (vector->list (mesh3d-colors mesh))))))
  (make-solid id (list->vector vertices) (list->vector triangles)
              #:material material #:color color))


;;;
;;; Constructive Helpers
;;;

(define (closed-profile who profile) (closed-loop who profile))

(define (axis-point axis coordinate radial)
  (case axis [(x) (vec3 coordinate radial 0)] [(y) (vec3 radial coordinate 0)] [(z) (vec3 radial 0 coordinate)]))

(define (revolution-point axis coordinate radius theta)
  (case axis
    [(x) (vec3 coordinate (* radius (cos theta)) (* radius (sin theta)))]
    [(y) (vec3 (* radius (cos theta)) coordinate (* radius (sin theta)))]
    [(z) (vec3 (* radius (cos theta)) (* radius (sin theta)) coordinate)]))

(define (ring-band-triangles first-ring second-ring full?)
  (cond [(and (= (length first-ring) 1) (= (length second-ring) 1)) '()]
        [(= (length first-ring) 1)
         (for/list ([index (in-range (if full? (length second-ring) (sub1 (length second-ring))))])
           (vector (first first-ring) (list-ref second-ring index)
                   (list-ref second-ring (if full? (modulo (add1 index) (length second-ring)) (add1 index)))))]
        [(= (length second-ring) 1)
         (for/list ([index (in-range (if full? (length first-ring) (sub1 (length first-ring))))])
           (vector (list-ref first-ring index) (first second-ring)
                   (list-ref first-ring (if full? (modulo (add1 index) (length first-ring)) (add1 index)))))]
        [else
         (apply append
                (for/list ([index (in-range (if full? (length first-ring) (sub1 (length first-ring))))])
                  (define next (if full? (modulo (add1 index) (length first-ring)) (add1 index)))
                  (list (vector (list-ref first-ring index) (list-ref second-ring index) (list-ref second-ring next))
                        (vector (list-ref first-ring index) (list-ref second-ring next) (list-ref first-ring next)))))]))

(define (ear-triangulate points)
  (define counter-clockwise? (positive? (polygon-area points)))
  (let loop ([indices (build-list (length points) values)] [triangles '()])
    (cond [(= (length indices) 3) (reverse (cons (list->vector indices) triangles))]
          [else
           (define ear
             (for/first ([position (in-range (length indices))]
                         #:when (ear? points indices position counter-clockwise?)) position))
           (unless ear (raise-arguments-error 'extrude3d "a triangulable simple contour" "contour" points))
           (define previous (list-ref indices (modulo (sub1 ear) (length indices))))
           (define current (list-ref indices ear))
           (define next (list-ref indices (modulo (add1 ear) (length indices))))
           (loop (append (take indices ear) (drop indices (add1 ear)))
                 (cons (vector previous current next) triangles))])))

(define (ear? points indices position counter-clockwise?)
  (define count (length indices))
  (define previous (list-ref indices (modulo (sub1 position) count)))
  (define current (list-ref indices position))
  (define next (list-ref indices (modulo (add1 position) count)))
  (define a (list-ref points previous)) (define b (list-ref points current)) (define c (list-ref points next))
  (and (if counter-clockwise? (positive? (cross2 a b c)) (negative? (cross2 a b c)))
       (not (for/or ([index (in-list indices)] #:unless (memq index (list previous current next)))
              (point-in-triangle? (list-ref points index) a b c)))))

(define (cross2 a b c)
  (- (* (- (vec2-x b) (vec2-x a)) (- (vec2-y c) (vec2-y a)))
     (* (- (vec2-y b) (vec2-y a)) (- (vec2-x c) (vec2-x a)))))

(define (point-in-triangle? point a b c)
  (define first-cross (cross2 a b point)) (define second-cross (cross2 b c point)) (define third-cross (cross2 c a point))
  (or (and (>= first-cross 0) (>= second-cross 0) (>= third-cross 0))
      (and (<= first-cross 0) (<= second-cross 0) (<= third-cross 0))))

(define (curve-tangents points)
  (for/list ([point (in-list points)] [index (in-naturals)])
    (safe-normal (vec3- (list-ref points (min (sub1 (length points)) (add1 index)))
                        (list-ref points (max 0 (sub1 index)))))))

(define (parallel-transport-normals tangents)
  (define initial (orthogonal-direction (first tangents)))
  (define-values (_normal reversed)
    (for/fold ([normal initial] [reversed (list initial)])
              ([previous (in-list tangents)] [next (in-list (rest tangents))])
      (define transported (rotation3-apply (rotation3-from-to previous next) normal))
      (define adjusted (safe-normal (vec3-cross (vec3-cross next transported) next)))
      (values adjusted (cons adjusted reversed))))
  (reverse reversed))

(define (orthogonal-direction direction)
  (safe-normal (vec3-cross direction
                            (if (< (abs (vec3-z direction)) 9/10) z-axis3 y-axis3))))

(define (face-cross mesh triangle)
  (define vertices (mesh3d-vertices mesh))
  (vec3-cross (vec3- (vector-ref vertices (vector-ref triangle 1))
                     (vector-ref vertices (vector-ref triangle 0)))
              (vec3- (vector-ref vertices (vector-ref triangle 2))
                     (vector-ref vertices (vector-ref triangle 0)))))

(define (safe-normal vector)
  (if (zero? (vec3-length vector)) z-axis3 (vec3-normalize vector)))

(define (face-normal mesh triangle) (safe-normal (face-cross mesh triangle)))

(define (copy-mesh mesh #:triangles [triangles (mesh3d-triangles mesh)]
                   #:normals [normals (mesh3d-normals mesh)]
                   #:material [material (mesh3d-material mesh)])
  (mesh3d #:id (spatial-id mesh) #:vertices (mesh3d-vertices mesh) #:triangles triangles
          #:normals normals #:colors (mesh3d-colors mesh) #:material material
          #:transform (spatial-transform mesh) #:opacity (spatial-opacity mesh)
          #:wireframe-color (mesh3d-wireframe-color mesh)
          #:wireframe-width (mesh3d-wireframe-width mesh)))
