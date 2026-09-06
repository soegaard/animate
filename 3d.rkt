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
         "private/3d/tube3d.rkt"
         "private/3d/curve3d.rkt"
         "private/3d/curve-animation3d.rkt"
         "private/3d/function-surface3d.rkt"
         "private/3d/parametric-surface3d.rkt"
         "private/3d/surface-animation.rkt"
         "private/3d/surface-calculus.rkt"
         "private/3d/surface-color.rkt"
         "private/3d/solids3d.rkt"
         "private/3d/clipping3d.rkt"
         "private/3d/point-line-arrow3d.rkt"
         (only-in "private/3d/axes3d.rkt"
                  axes3d
                  coordinate-plane3d
                  grid-plane3d)
         "private/3d/vector-diagram3d.rkt"
         "private/3d/material3d.rkt"
         "private/3d/light3d.rkt"
         "private/3d/spatial-dependency.rkt"
         "private/3d/spatial-relation-context.rkt"
         "private/3d/spatial-relation.rkt"
         "private/3d/projected-label.rkt"
         "private/3d/spatial-animation.rkt"
         "private/3d/spatial-map3d.rkt"
         "private/3d/ode-flow3d.rkt"
         "private/3d/spatial-inspection.rkt"
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
 projected-label
 projected-label?
 projected-label-view
 projected-label-target
 projected-label-offset
 projected-label-occlusion
 follow-projected-point
 follow-projected-spatial

 ;; Meshes
 mesh3d
 mesh3d?
 mesh3d-vertices
 mesh3d-triangles
 mesh3d-edges
 mesh3d-normals
 mesh3d-colors
 mesh3d-material
 mesh3d-wireframe-color
 mesh3d-wireframe-width
 mesh3d-local-bounds

 ;; Curves, tubes, and diagrams
 tube3d
 curve3d?
 curve3d-points
 curve3d-radius
 curve3d-sides
 curve3d-color
 curve3d-width-mode
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
 surface3d?
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
 section3d?
 section3d-loops
 section3d-chains
 section-by-plane3d
 section-curve3d

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
 ode-trajectory3d?
 ode-trajectory3d-time-range
 ode-trajectory3d-step-size
 ode-trajectory3d-checkpoint-every
 ode-trajectory3d-solver
 ode-trajectory3d-diagnostics
 ode-trajectory3d-diagnostics?
 ode-trajectory3d-diagnostics-solver
 ode-trajectory3d-diagnostics-accepted-steps
 ode-trajectory3d-diagnostics-rejected-steps
 ode-trajectory3d-diagnostics-termination-time
 ode-trajectory3d-diagnostics-maximum-error
 prepare-ode-trajectory3d
 ode-trajectory3d-position
 vector-field3d
 streamline3d
 streamlines3d
 flow-particle3d
 flow-cloud3d

 ;; Spatial inspection and exact picking
 (struct-out spatial-inspection)
 (struct-out spatial-pick)
 view3d-spatial-inspections
 view3d-spatial-inspection-tree
 view3d-spatial-inspection-at
 view3d-pick
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
 material3d-roughness
 material3d-double-sided?
 material3d-wireframe?
 ambient-light3d
 ambient-light3d?
 ambient-light3d-intensity
 ambient-light3d-color
 directional-light3d
 directional-light3d?
 directional-light3d-direction
 directional-light3d-intensity
 directional-light3d-color

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
 view3d-render-mode
 view3d-transparency-mode
 view3d-spatial-ref
 view3d-spatial-has?
 view3d-spatial-replace
 view3d-spatial-update
 view3d-spatial-bounds
 view3d-spatial-world-transform)
