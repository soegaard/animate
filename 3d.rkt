#lang racket/base

;;;
;;; Spatial Algebra and Wireframe Views
;;;

;; Provides SCENE-3D-A's pure mathematical kernel and SCENE-3D-B's immutable
;; spatial tree, camera, mesh, and `view3d` interface. This public model module
;; remains Pict-free; requiring `animate` supplies the ordinary Pict wireframe
;; adapter when a view3d is rendered as part of a scene.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "private/3d/vec3.rkt"
         "private/3d/linear3.rkt"
         "private/3d/rotation3.rkt"
         "private/3d/affine3.rkt"
         "private/3d/transform3.rkt"
         "private/3d/bounds3.rkt"
         "private/3d/ray-plane.rkt"
         "private/3d/bvh3d.rkt"
         "private/3d/spatial-visual.rkt"
         "private/3d/spatial-group.rkt"
         "private/3d/spatial-path.rkt"
         "private/3d/mesh3d.rkt"
         "private/3d/geometry-fingerprint3d.rkt"
         "private/3d/mesh-topology3d.rkt"
         "private/3d/polyhedral-complex3d.rkt"
         "private/3d/convex-hull3d.rkt"
         "private/3d/dual-polyhedron3d.rkt"
         "private/3d/schlegel3d.rkt"
         "private/3d/polyhedron-net3d.rkt"
         "private/3d/polyhedron-fold-animation3d.rkt"
         "private/3d/correspondence3d.rkt"
         "private/3d/matching-animation3d.rkt"
         "private/3d/edge-adjacency3d.rkt"
         "private/3d/mesh-analysis3d.rkt"
         "private/3d/mesh-orientation3d.rkt"
         "private/3d/tube3d.rkt"
         "private/3d/tube-style3d.rkt"
         "private/3d/curve3d.rkt"
         "private/3d/stroke3d.rkt"
         "private/3d/marker3d.rkt"
         "private/3d/billboard3d.rkt"
         "private/3d/edge-style3d.rkt"
         "private/3d/edge-overlay3d.rkt"
         "private/3d/curve-animation3d.rkt"
         "private/3d/function-surface3d.rkt"
         "private/3d/parametric-surface3d.rkt"
         "private/3d/adaptive-surface3d.rkt"
         "private/3d/trimmed-surface3d.rkt"
         "private/3d/implicit-surface3d.rkt"
         "private/3d/surface-mesh3d.rkt"
         "private/3d/surface-provenance3d.rkt"
         "private/3d/surface-picking3d.rkt"
         "private/3d/surface-animation.rkt"
         "private/3d/surface-calculus.rkt"
         "private/3d/surface-color.rkt"
         "private/3d/solids3d.rkt"
         "private/3d/clipping3d.rkt"
         "private/3d/section-settings3d.rkt"
         "private/3d/plane-basis3d.rkt"
         "private/3d/cap-style3d.rkt"
         "private/3d/mesh-cut3d.rkt"
         "private/3d/cutaway3d.rkt"
         "private/3d/multi-clip3d.rkt"
         "private/3d/section-measure3d.rkt"
         "private/3d/section-fill3d.rkt"
         "private/3d/section-hatch3d.rkt"
         "private/3d/slice-stack3d.rkt"
         "private/3d/volume-estimate3d.rkt"
         "private/3d/riemann-volume3d.rkt"
         "private/3d/point-line-arrow3d.rkt"
         (only-in "private/3d/axes3d.rkt"
                  axes3d
                  coordinate-plane3d
                  grid-plane3d)
         "private/3d/vector-diagram3d.rkt"
         "private/3d/material3d.rkt"
         "private/3d/color-space3d.rkt"
         "private/3d/light-attenuation3d.rkt"
         "private/3d/shadow3d.rkt"
         "private/3d/shadow-bounds3d.rkt"
         "private/3d/shadow-map3d.rkt"
         "private/3d/light-animation3d.rkt"
         "private/3d/light3d.rkt"
         "private/3d/lighting-inspection3d.rkt"
         "private/3d/spatial-dependency.rkt"
         "private/3d/spatial-relation-context.rkt"
         "private/3d/spatial-relation.rkt"
         "private/3d/anchor3d.rkt"
         "private/3d/label-placement3d.rkt"
         "private/3d/label-layout3d.rkt"
         "private/3d/label-layout-preparation3d.rkt"
         "private/3d/projected-label.rkt"
         "private/3d/spatial-animation.rkt"
         "private/3d/spatial-map3d.rkt"
         "private/3d/ode-flow3d.rkt"
         "private/3d/jacobian3d.rkt"
         "private/3d/equilibrium3d.rkt"
         "private/3d/eigensystem3d.rkt"
         "private/3d/linearization3d.rkt"
         "private/3d/flow-map3d.rkt"
         "private/3d/trajectory-visual3d.rkt"
         "private/3d/dynamical-inspection3d.rkt"
         "private/3d/spatial-inspection.rkt"
         "private/3d/topology-inspection3d.rkt"
         "private/3d/projection3d.rkt"
         "private/3d/camera3d.rkt"
         "private/3d/camera3d-animation.rkt"
         "private/3d/camera3d-fit.rkt"
         "private/3d/view3d-visual.rkt")

;; Exports
(provide
 ;; Spatial coordinates
 (struct-out vec3)
 origin3
 x-axis3
 y-axis3
 z-axis3
 vec3+
 vec3-
 vec3*
 vec3-scale
 vec3-dot
 vec3-cross
 vec3-length
 vec3-distance
 vec3-normalize
 vec3-lerp
 vec3-finite?

 ;; General linear algebra
 (struct-out linear3)
 identity-linear3
 linear3-compose
 linear3-invert
 linear3-determinant
 linear3-transpose
 linear3-apply-vector
 linear3-normal-transform

 ;; Proper rotations
 rotation3?
 rotation3-components
 identity-rotation3
 axis-angle
 rotation3-from-to
 rotation3-look-at
 rotation3-compose
 rotation3-invert
 rotation3-apply
 rotation3->linear3
 rotation3-slerp

 ;; General affine maps
 affine3
 affine3?
 affine3-linear
 affine3-translation
 identity-affine3
 affine3-compose
 affine3-invert
 affine3-apply-point
 affine3-apply-vector
 affine3-normal-transform
 affine3-lerp

 ;; Author-oriented transforms
 (struct-out transform3)
 make-transform3
 identity-transform3
 transform3->affine3
 transform3-compose
 transform3-apply-point
 transform3-lerp

 ;; Bounds and intersection values
 aabb3
 aabb3?
 aabb3-minimum
 aabb3-maximum
 aabb3-empty
 aabb3-empty?
 aabb3-union
 aabb3-from-points
 aabb3-transform
 aabb3-center
 aabb3-size
 aabb3-contains?
 ray3
 ray3?
 ray3-origin
 ray3-direction
 plane3
 plane3?
 plane3-point
 plane3-normal
 (struct-out ray3-plane-hit)
 (struct-out ray3-aabb-hit)
 ray3-at
 ray3-intersect-plane
 ray3-intersect-aabb

 ;; Spatial tree
 gen:spatial-visual
 spatial-visual?
 spatial-id
 spatial-transform
 spatial-with-transform
 spatial-opacity
 spatial-with-opacity
 spatial-local-bounds
 spatial-position
 spatial-with-position
 spatial-rotation
 spatial-with-rotation
 spatial-scale
 spatial-with-scale
 gen:spatial-container
 spatial-container?
 spatial-child-entries
 (struct-out spatial-child)
 group3d
 group3d?
 group3d-children
 group3d-with-children
 spatial-path?
 spatial-relative-ref
 spatial-relative-replace

 ;; Spatial relations and projected 2D labels
 spatial-dependency?
 spatial-relation
 spatial-relation?
 spatial-relation-dependencies
 spatial-relation-structure
 spatial-relation-cache-key
 spatial-relation-cacheability
 (struct-out spatial-visual-dependency)
 (struct-out spatial-value-dependency)
 (struct-out spatial-camera-dependency)
 spatial-relation-context?
 spatial-relation-context-relation-path
 spatial-relation-context-view
 spatial-relation-context-declared-dependencies
 spatial-relation-context-used-dependencies
 spatial-relation-context-unused-dependencies
 spatial-relation-context-spatial-has?
 spatial-relation-context-spatial-ref
 spatial-relation-context-spatial-world-transform
 spatial-relation-context-spatial-position
 spatial-relation-context-value-has?
 spatial-relation-context-value-ref
 spatial-relation-context-camera
 line-between3d
 segment-between3d
 arrow-between3d
 plane-through3d
 normal-at3d
 distance-segment3d
 distance-dimension3d
 angle-marker3d
 right-angle-marker3d
 dihedral-angle3d
 normal-marker3d
 coordinate-tripod3d
 projected-label
 projected-label?
 projected-label-view
 projected-label-target
 projected-label-offset
 projected-label-occlusion
 follow-projected-point
 follow-projected-spatial
 label3d
 (struct-out resolved-anchor3d)
 gen:anchor3d
 anchor3d?
 anchor3d-resolve
 anchor3d-normal
 anchor3d-tangent
 anchor3d-identity
 point-anchor3d
 spatial-origin-anchor3d
 bounds-anchor3d
 vertex-anchor3d
 edge-anchor3d
 face-anchor3d
 curve-anchor3d
 surface-anchor3d
 surface-pick-anchor3d
 (struct-out label-placement3d)
 (struct-out leader-style3d)
 default-label-placement3d
 (struct-out label-layout-item3d)
 (struct-out label-layout-candidate3d)
 (struct-out label-layout3d)
 layout-labels3d
 (struct-out prepared-label-layout3d)
 prepare-label-layout3d
 prepare-scene-label-layout3d
 prepared-label-layout3d-ref

 ;; Section fills and hatching
 section-fill3d
 section-hatch3d
 slice-stack3d
 (struct-out cross-section-sample3d)
 (struct-out prepared-cross-section-function3d)
 (struct-out volume-estimate3d)
 prepare-cross-section-function3d
 volume-by-slices3d

 ;; Meshes
 mesh3d
 mesh3d?
 mesh3d-vertices
 mesh3d-triangles
 mesh3d-edges
 mesh3d-vertex-ids
 mesh3d-edge-ids
 mesh3d-face-ids
 mesh3d-vertex-id
 mesh3d-edge-id
 mesh3d-face-id
 mesh3d-normals
 mesh3d-colors
 mesh3d-material
 mesh3d-wireframe-color
 mesh3d-wireframe-width
 mesh3d-local-bounds
 (struct-out geometry-key3d)
 (struct-out mesh3d-semantic-key3d)
 mesh3d-geometry-key
 mesh3d-semantic-key
 (struct-out mesh-vertex-topology3d)
 (struct-out mesh-halfedge3d)
 (struct-out mesh-edge-topology3d)
 (struct-out mesh-triangle-topology3d)
 (struct-out mesh-boundary-component3d)
 (struct-out mesh-component-topology3d)
 (struct-out mesh-topology3d)
 (struct-out mesh3d-component-invariants3d)
 (struct-out mesh3d-genus-report)
 mesh3d-topology
 mesh-topology3d-vertex-neighbours
 mesh-topology3d-incident-edges
 mesh-topology3d-incident-faces
 mesh-topology3d-face-neighbours
 mesh-topology3d-boundary-components
 mesh-topology3d-connected-components
 mesh-topology3d-manifold?
 mesh-topology3d-closed?
 mesh-topology3d-orientable?
 mesh3d-euler-characteristic
 mesh3d-boundary-count
 mesh3d-component-invariants
 mesh3d-genus
 (struct-out polyhedral-plane3d)
 (struct-out polyhedral-source-face-id3d)
 (struct-out polyhedral-face-declaration3d)
 (struct-out polyhedral-face3d)
 polyhedral-complex3d?
 polyhedral-complex3d-source-mesh
 polyhedral-complex3d-analysis-mesh
 polyhedral-complex3d-source-transform
 polyhedral-complex3d-mesh
 polyhedral-complex3d-topology
 polyhedral-complex3d-faces
 polyhedral-complex3d-edge-to-faces
 polyhedral-complex3d-vertex-to-faces
 polyhedral-complex3d-diagnostics
 polyhedral-complex3d
 (struct-out convex-hull3d-result)
 (struct-out convex-hull3d-coplanar-group3d)
 convex-hull3d
 (struct-out dual-polyhedron-face3d)
 (struct-out dual-polyhedron3d-result)
 combinatorial-dual3d
 polar-dual3d
 (struct-out schlegel-diagram3d-data)
 prepare-schlegel-diagram3d
 schlegel-diagram3d
 (struct-out net-overlap3d)
 (struct-out net-hinge3d) (struct-out net-face-transform3d) (struct-out polyhedron-net3d)
 polyhedron-net3d-face-child-ids
 prepare-polyhedron-net3d
 polyhedron-net3d-group
 polyhedron-net3d-sample-transforms
 unfold-polyhedron3d unfold-polyhedron3d-request?
 fold-polyhedron3d fold-polyhedron3d-request?
 (struct-out spatial-correspondence3d) (struct-out mesh-correspondence3d)
 prepare-mesh-correspondence3d
 (struct-out mesh3d-duplicate-triangle)
 (struct-out mesh3d-analysis)
 analyze-mesh3d
 mesh3d-validate
 (struct-out mesh3d-orientation-report)
 mesh3d-orient-consistently
 mesh3d-orient-outward
 mesh3d-self-intersection-candidates
 (struct-out edge-incidence3d)
 (struct-out edge-adjacency3d)

 ;; Surface protocol and adaptive sampling
 gen:surface3d
 surface3d?
 surface3d-kind
 surface3d-local-mesh
 surface3d-mesh
 surface3d->mesh3d
 surface3d-local-bounds
 surface3d-diagnostics
 surface3d-provenance
 surface3d-domain
 surface3d-evaluate
 surface3d-frame-at
 (struct-out surface-domain3d)
 (struct-out surface-diagnostics3d)
 (struct-out surface-frame3d)
 (struct-out surface-mesh3d)
 (struct-out dyadic-coordinate)
 (struct-out uv-key)
 (struct-out parametric-sample3d)
 (struct-out adaptive-surface-diagnostics)
 adaptive-parametric-surface3d
 adaptive-function-surface3d
 trim-expression3d?
 trim-field3d
 trim-field3d?
 trim-and3d
 trim-or3d
 trim-not3d
 surface-trim
 surface-trim?
 surface-trim-field
 surface-trim-keep
 surface-trim-id
 surface-trim-tolerance
 trimmed-parametric-surface3d
 (struct-out implicit-surface-diagnostics)
 implicit-surface3d
 surface3d-domain-contains?
 surface3d-position-at?

 ;; Curves, tubes, and diagrams
 tube3d
 tube-style3d
 tube-style3d?
 tube-style3d-radius
 tube-style3d-sides
 tube-style3d-color
 stroke3d
 stroke3d?
 stroke3d-color
 stroke3d-width
 stroke3d-width-mode
 stroke3d-cap
 stroke3d-join
 stroke3d-miter-limit
 stroke3d-dash
 stroke3d-dash-offset
 stroke3d-dash-space
 stroke3d-opacity
 stroke3d-depth-mode
 stroke3d-depth-bias
 stroke3d-with-color
 stroke3d-with-opacity
 point-style3d
 point-style3d?
 point-style3d-size
 point-style3d-size-mode
 point-style3d-color
 point-style3d-opacity
 point-style3d-depth-mode
 point-style3d-depth-bias
 point-style3d-with-color
 point-style3d-with-opacity
 arrow-style3d
 arrow-style3d?
 arrow-style3d-length
 arrow-style3d-length-mode
 arrow-style3d-width
 arrow-style3d-color
 arrow-style3d-opacity
 arrow-style3d-depth-mode
 arrow-style3d-depth-bias
 arrow-style3d-with-color
 arrow-style3d-with-opacity
 billboard-image3d
 billboard-image3d?
 billboard-image3d-width
 billboard-image3d-height
 billboard-image3d-argb
 billboard-style3d
 billboard-style3d?
 billboard-style3d-width
 billboard-style3d-height
 billboard-style3d-size-mode
 billboard-style3d-facing
 billboard-style3d-axis
 billboard-style3d-opacity
 billboard-style3d-depth-mode
 billboard-style3d-depth-bias
 billboard3d
 billboard3d?
 billboard3d-image
 billboard3d-position
 billboard3d-style
 edge-style3d
 edge-style3d?
 edge-style3d-edges
 edge-style3d-visible
 edge-style3d-hidden
 edge-style3d-crease-angle
 edge-style3d-surface
 with-edges3d
 edge-overlay3d?
 edge-overlay3d-content
 edge-overlay3d-style
 curve3d?
 curve3d-points
 curve3d-style
 curve3d-closed?
 curve3d-local-bounds
 curve3d-with-color
 curve3d-partial
 polyline3d
 parametric-curve3d
 curve3d-point-at
 curve3d-tangent-at
 point3d
 line3d
 segment3d
 arrow3d
 double-arrow3d
 axes3d
 coordinate-plane3d
 grid-plane3d
 basis-vectors3d
 vector-arrow3d
 vector-components3d
 linear-transformation-diagram3d

 ;; Parametric surfaces and calculus helpers
 surface3d-grid
 surface3d-u-range
 surface3d-v-range
 surface3d-resolution
 surface3d-points
 surface3d-normals
 surface3d-unresolved-normal-indices
 surface3d-colors
 surface3d-material
 surface3d-position-at
 surface3d-tangent-u-at
 surface3d-tangent-v-at
 surface3d-normal-at
 parametric-surface3d
 function-surface3d
 surface-color
 surface-color-by-height
 surface-color-by-scalar
 surface-checkerboard
 surface-wireframe
 surface-point
 surface-tangent-u
 surface-tangent-v
 surface-normal
 surface-tangent-plane
 surface-coordinate-curve
 surface-gradient-arrow
 surface-level-curve

 ;; Solids, constructive geometry, and mesh utilities
 cube3d
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
 mesh3d-merge
 riemann-volume3d
 washer-sum3d
 shell-sum3d

 ;; Clipping, semantic slicing, and section curves
 clip-plane3d
 clip-plane3d?
 clip-plane3d-plane
 clip-plane3d-keep
 clip3d
 clip3d?
clip3d-content
clip3d-plane
slice-mesh3d
slice-mesh-by-planes3d
section3d?
 section3d-loops
 section3d-chains
 section-by-plane3d
 section-curve3d
 (struct-out section3d-settings)
 default-section3d-settings
 section3d-settings-for-bounds
 (struct-out plane-basis3d)
 plane3d-basis
 plane-basis3d-project
 plane-basis3d-unproject
 plane-basis3d-signed-area
 plane-basis3d-centroid
 (struct-out section-component3d)
 section3d-plane
 section3d-basis
 section3d-components
 section3d-diagnostics
 (struct-out cap-style3d)
 default-cap-style3d
(struct-out mesh-cut3d-result)
cut-mesh3d
cap-section3d
mesh3d-weld
cutaway3d
 clip-planes3d
 clip-box3d
 cut-mesh-by-box3d
 section3d-area
 section3d-centroid
 section3d-perimeter
 section3d-second-moments

 ;; Curve-animation requests
 move-along-curve3d
 move-along-curve3d-request?
 orient-along-curve3d
 orient-along-curve3d-request?

 ;; Surface-animation requests
 reveal-surface-u
 reveal-surface-u-request?
 reveal-surface-v
 reveal-surface-v-request?
 transform-surface3d
 transform-surface3d-request?

 ;; Spatial maps and homotopies
 apply-linear3
 apply-linear3-request?
 apply-affine3
 apply-affine3-request?
 apply-pointwise3
 apply-pointwise3-request?
 apply-homotopy3
 apply-homotopy3-request?

 ;; Prepared spatial ODE trajectories and vector fields
 ode-field3d
 ode-field3d?
 ode-field3d-procedure
 ode-field3d-arity
 ode-field3d-cache-key
 ode-field3d-autonomous?
 ode-field3d-parallel-safe?
 jacobian3d
 (struct-out jacobian3d-result)
 (struct-out equilibrium-solver3d)
 default-equilibrium-solver3d
 (struct-out equilibrium-seed-result3d)
 (struct-out equilibrium-root3d)
 (struct-out equilibrium-search3d)
 equilibrium-points3d
 (struct-out eigensystem3d)
 eigensystem3d-of
 (struct-out linearization3d)
 linearize3d
 linearization-diagram3d
 (struct-out prepared-flow-map3d)
 prepare-flow-map3d
 flow-map3d-ref
 flow-map3d-pairs
 flow-map3d-displacement
 flow-map-grid3d
 flow-volume-cell3d
 flow-map3d-local-jacobian
 flow-map3d-volume-factor
 trajectory-samples3d
 trajectory-tube3d
 trajectory-ribbon3d
 trajectory-bundle3d
 trajectory-inspection3d
 trajectory-pick-inspection3d
 view3d-dynamical-inspections3d
 equilibrium-inspection3d
 linearization-inspection3d
 flow-map-inspection3d
 fixed-rk4-solver3d
 fixed-rk4-solver3d?
 fixed-rk4-solver3d-step-size
 adaptive-rk45-solver3d
 adaptive-rk45-solver3d?
 adaptive-rk45-solver3d-settings
 ode-event3d
 ode-event3d?
 ode-event3d-id
 ode-event3d-function
 ode-event3d-direction
 ode-event3d-terminal?
 ode-event3d-value-tolerance
 ode-event3d-time-tolerance
 ode-event3d-maximum-iterations
 ode-event3d-cache-key
 ode-event3d-parallel-safe?
 ode-event3d-root-kind
 ode-event3d-initial-subdivisions
 ode-event3d-maximum-depth
 ode-event-hit3d?
 ode-event-hit3d-event-id
 ode-event-hit3d-time
 ode-event-hit3d-position
 ode-event-hit3d-value
 ode-event-hit3d-direction
 ode-event-hit3d-segment-index
 ode-event-hit3d-iterations
 ode-event-hit3d-provenance
 trajectory-termination3d
 trajectory-termination3d?
 trajectory-termination3d-time-limit
 trajectory-termination3d-arc-length-limit
 trajectory-termination3d-bounds
 trajectory-termination3d-minimum-speed
 trajectory-termination3d-maximum-steps
 trajectory-termination3d-events
 trajectory-termination3d-on-field-error
 trajectory-termination-hit3d?
 trajectory-termination-hit3d-reason
 trajectory-termination-hit3d-time
 trajectory-termination-hit3d-position
 trajectory-termination-hit3d-details
 prepared-trajectory3d?
 trajectory-segment3d?
 trajectory-segment3d-t0
 trajectory-segment3d-t1
 trajectory-segment3d-p0
 trajectory-segment3d-p1
 trajectory-segment3d-d0
 trajectory-segment3d-d1
 trajectory-segment3d-arc-length
 trajectory-segment3d-bounds
 ode-trajectory3d?
 ode-trajectory3d-time-range
 ode-trajectory3d-step-size
 ode-trajectory3d-checkpoint-every
 ode-trajectory3d-solver
 ode-trajectory3d-diagnostics
 ode-trajectory3d-segments
 ode-trajectory3d-event-hits
 ode-trajectory3d-termination
 ode-trajectory3d-diagnostics?
 ode-trajectory3d-diagnostics-solver
 ode-trajectory3d-diagnostics-accepted-steps
 ode-trajectory3d-diagnostics-rejected-steps
 ode-trajectory3d-diagnostics-termination-time
 ode-trajectory3d-diagnostics-termination-reason
 ode-trajectory3d-diagnostics-maximum-error
 ode-trajectory3d-diagnostics-field-evaluations
 ode-trajectory3d-diagnostics-dense-segment-count
 ode-trajectory3d-diagnostics-total-arc-length
 ode-trajectory3d-diagnostics-event-count
 ode-trajectory3d-diagnostics-warnings
 prepare-ode-trajectory3d
 ode-trajectory3d-position
 ode-trajectory3d-derivative
 ode-trajectory3d-speed
 ode-trajectory3d-arc-length-at
 ode-trajectory3d-time-at-arc-length
 ode-trajectory3d-segment-index
 streamline-sample-policy3d
 streamline-sample-policy3d?
 streamline-sample-policy3d-maximum-chord-error
 streamline-sample-policy3d-maximum-turn-angle
 streamline-sample-policy3d-maximum-segment-length
 streamline-sample-policy3d-minimum-segment-length
 prepared-streamline3d?
 prepared-streamline3d-seed
 prepared-streamline3d-direction
 prepared-streamline3d-parameterization
 prepared-streamline3d-trajectory
 prepared-streamline3d-curve-samples
 prepared-streamline3d-diagnostics
 prepared-streamline3d-seed-index
 streamline-diagnostics3d?
 streamline-diagnostics3d-forward
 streamline-diagnostics3d-backward
 streamline-diagnostics3d-field-evaluations
 streamline-diagnostics3d-curve-sample-count
 streamline-diagnostics3d-total-arc-length
 streamline-diagnostics3d-termination-reasons
 streamline-branch-diagnostics3d?
 streamline-branch-diagnostics3d-direction
 streamline-branch-diagnostics3d-time-range
 streamline-branch-diagnostics3d-segment-count
 streamline-branch-diagnostics3d-termination
 prepare-streamline3d
 adaptive-streamline3d
 seed-set3d?
 seed-set3d-kind
 seed-set3d-points
 seed-set3d-count
 seed-set3d-provenance
 seed-set3d-diagnostics
 seed-set3d-cache-key
 explicit-seeds3d
 grid-seeds3d
 plane-seeds3d
 curve-seeds3d
 surface-seeds3d
 sphere-seeds3d
 poisson-seeds3d
 prepared-streamline-set3d?
 prepared-streamline-set3d-seeds
 prepared-streamline-set3d-streamlines
 prepared-streamline-set3d-diagnostics
 prepared-streamline-set3d-spatial-index
 streamline-set-diagnostics3d?
 streamline-set-diagnostics3d-seed-count
 streamline-set-diagnostics3d-accepted-seed-count
 streamline-set-diagnostics3d-rejected-seed-count
 streamline-set-diagnostics3d-termination-reasons
 streamline-set-diagnostics3d-field-evaluations
 streamline-set-diagnostics3d-total-curve-samples
 streamline-set-diagnostics3d-minimum-separation
 streamline-set-diagnostics3d-discarded-short-lines
 streamline-set-diagnostics3d-parallel-mode
 prepare-streamlines3d
 adaptive-streamline-set3d
 poincare-hit3d?
 poincare-hit3d-trajectory-id
 poincare-hit3d-crossing-index
 poincare-hit3d-time
 poincare-hit3d-point
 poincare-hit3d-direction
 poincare-hit3d-source-event
 poincare-section3d
 poincare-hit3d-plane-coordinates
 poincare-hits3d
 prepared-poincare-map3d?
 prepared-poincare-map3d-plane
 prepared-poincare-map3d-seeds
 prepared-poincare-map3d-trajectories
 prepared-poincare-map3d-first-hits
 prepared-poincare-map3d-second-hits
 prepared-poincare-map3d-pairs
 prepared-poincare-map3d-diagnostics
 prepare-poincare-map3d
 vector-field3d
 streamline3d
 streamlines3d
 flow-particle3d
 flow-cloud3d

 ;; Spatial inspection and exact picking
 (struct-out spatial-inspection)
 (struct-out spatial-pick)
 (struct-out spatial-topology-overlay3d)
 (struct-out topology-inspection3d)
 (struct-out surface-pick3d)
 spatial-pick-kind
 spatial-pick-topology-inspection3d
 spatial-pick-topology-overlay3d
 view3d-spatial-inspections
 view3d-spatial-inspection-tree
 view3d-spatial-inspection-at
 view3d-pick
 view3d-surface-pick
 view3d-pixel-pick
 mesh3d-bvh
 mesh3d-bvh?
 bvh3d-node?
 bvh3d-leaf?
 bvh3d-bounds
 bvh3d-triangle-indices
 bvh3d-ray-candidates
 (struct-out ray3-triangle-hit)
 ray3-intersect-triangle

 ;; Opaque materials and lights
 material3d
 material3d?
 material3d-color
 material3d-shading
 material3d-ambient
 material3d-diffuse
 material3d-specular
 material3d-specular-color
 material3d-roughness
 material3d-specular-exponent
 material3d-lighting
 material3d-emission
 material3d-emission-strength
 material3d-double-sided?
 material3d-casts-shadow?
 material3d-receives-shadow?
 material3d-wireframe?
 material3d-with-color
 material3d-with-roughness
 material3d-with-emission
 material3d-with-shadow-policy

 ;; Linear-light colour and final output policy
 (struct-out linear-rgba3d)
 srgb-channel->linear
 linear-channel->srgb
 rgba-srgb->linear
 rgba-linear->srgb
 linear-rgba3d-over
 (struct-out tone-map3d)
 default-tone-map3d
 tone-map3d-apply
 (struct-out light-attenuation3d)
 constant-attenuation3d
 inverse-square-attenuation3d
 polynomial-attenuation3d
 light-attenuation3d-factor
 spot-smoothstep3d
 spot-cone-factor3d
 shadow-settings3d
 shadow-settings3d?
 shadow-settings3d-map-size
 shadow-settings3d-depth-bias
 shadow-settings3d-normal-bias
 shadow-settings3d-pcf-radius
 shadow-settings3d-bounds
 shadow-settings3d-near
 shadow-settings3d-far
 shadow-settings3d-prepared-bounds-key
 directional-shadow3d
 directional-shadow3d?
 directional-shadow3d-settings
 spot-shadow3d
 spot-shadow3d?
 spot-shadow3d-settings
 shadow3d?
 shadow3d-kind
 shadow3d-settings
 (struct-out prepared-shadow-bounds3d)
 prepare-shadow-bounds3d
 prepared-shadow-bounds3d-key
 shadow-map3d-identity
 (struct-out shadow-map3d)
 shadow-map3d-factor
 shadow-light-camera3d
 ambient-light3d
 ambient-light3d?
 ambient-light3d-id
 ambient-light3d-intensity
 ambient-light3d-color
 ambient-light3d-shadow
 directional-light3d
 directional-light3d?
 directional-light3d-id
 directional-light3d-direction
 directional-light3d-intensity
 directional-light3d-color
 directional-light3d-shadow
 point-light3d
 point-light3d?
 point-light3d-id
 point-light3d-position
 point-light3d-intensity
 point-light3d-color
 point-light3d-attenuation
 point-light3d-range
 point-light3d-shadow
 spot-light3d
 spot-light3d?
 spot-light3d-id
 spot-light3d-position
 spot-light3d-direction
 spot-light3d-intensity
 spot-light3d-color
 spot-light3d-inner-angle
 spot-light3d-outer-angle
 spot-light3d-attenuation
 spot-light3d-range
 spot-light3d-shadow
 light3d?
 light3d-id
 light3d-kind
 light3d-color
 light3d-intensity
 light3d-shadow

 ;; Material/light and fragment inspection
 (struct-out material-inspection3d)
 (struct-out light-inspection3d)
 (struct-out fragment-light-sample3d)
 (struct-out fragment-lighting-report3d)
 material3d-inspection
 light3d-inspection
 fragment-lighting-inspection3d

 ;; Immutable finite-light animation requests
 light3d-intensity-to
 light3d-intensity-to-request?
 light3d-color-to
 light3d-color-to-request?
 point-light3d-move-to
 point-light3d-move-to-request?
 point-light3d-move-by
 point-light3d-move-by-request?
 spot-light3d-move-to
 spot-light3d-move-to-request?
 spot-light3d-aim-at
 spot-light3d-aim-at-request?
 spot-light3d-cone-to
 spot-light3d-cone-to-request?

 ;; Camera and projection
 (struct-out perspective-projection3d)
 (struct-out orthographic-projection3d)
 camera3d?
 perspective-camera3d
 orthographic-camera3d
 camera3d-position
 camera3d-rotation
 camera3d-near
 camera3d-far
 camera3d-projection
 camera3d-with-position
 camera3d-with-rotation
 camera3d-with-projection
 camera3d-forward
 camera3d-right
 camera3d-up
 camera3d-look-at
 camera3d-world->view
 camera3d-project
 camera3d-view-depth
 camera3d-pixel-ray
 camera3d-frustum
 camera3d-fit-bounds

 ;; Stable authored lights in a view3d
 view3d-lights
 view3d-light-ref
 view3d-light-replace
 view3d-light-update

 ;; Spatial and camera animation requests
 move3d-to
 move3d-to-request?
 move3d-by
 move3d-by-request?
 rotate3d-to
 rotate3d-to-request?
 rotate3d-by
 rotate3d-by-request?
 scale3d-to
 scale3d-to-request?
 scale3d-by
 scale3d-by-request?
 transform3d-to
 transform3d-to-request?
 transform-matching-mesh3d
 transform-matching-mesh3d-request?
 transform-matching-spatial
 transform-matching-spatial-request?
 spatial-line-route3d
 spatial-line-route3d?
 spatial-arc-route3d
 spatial-arc-route3d?
 spatial-bezier-route3d
 spatial-bezier-route3d?
 spatial-route3d?
 spatial-route3d-sample
 mesh3d-correspondence-compatible?
 mesh3d-matching-sample
 mesh3d-cross-fade-sample
 group3d-face-parts-matching-sample
 unfold-polyhedron3d
 unfold-polyhedron3d-request?
 fold-polyhedron3d
 fold-polyhedron3d-request?
 camera3d-move-to
 camera3d-move-to-request?
 camera3d-look-at-to
 camera3d-look-at-to-request?
 camera3d-orbit-by
 camera3d-orbit-by-request?
 camera3d-roll-to
 camera3d-roll-to-request?
 camera3d-field-of-view-to
 camera3d-field-of-view-to-request?
 camera3d-orthographic-height-to
 camera3d-orthographic-height-to-request?
 camera3d-dolly-by
 camera3d-dolly-by-request?
 camera3d-fit
 camera3d-fit-request?
 camera3d-follow
 camera3d-follow-request?

 ;; 2D viewport boundary
 view3d
 view3d?
 view3d-children
 view3d-width
 view3d-height
 view3d-camera
 view3d-with-camera
 view3d-lights
 view3d-background
 view3d-tone-map
 view3d-render-mode
 view3d-transparency-mode
 view3d-spatial-ref
 view3d-spatial-has?
 view3d-spatial-replace
 view3d-spatial-update
 view3d-spatial-bounds
 view3d-spatial-world-transform)
