#lang racket/base

;;;
;;; SCENE-EM Documented Binding Tests
;;;

;; The concise guide modules name the current public API directly. This test
;; protects those examples from silently drifting to private or removed names.

(require rackunit)

(define absent
  (gensym 'absent))

(define (public-binding module-path name)
  (dynamic-require module-path name (lambda () absent)))

(module+ test
  (for ([name (in-list '(circle vec2 scene-play scene-add make-scene
                         move-to scene-sample formula-select
                         formula-source-select source-occurrence
                         relation-visual))])
    (check-not-eq? (public-binding "../main.rkt" name) absent))
  (for ([name (in-list '(scene-program? scene-block-spec? make-scene-program))])
    (check-not-eq? (public-binding "../authoring.rkt" name) absent))
  (for ([name (in-list '(open-program-preview preview-available?))])
    (check-not-eq? (public-binding "../preview.rkt" name) absent))
  (for ([name (in-list '(render-frames! encode-mp4!))])
    (check-not-eq? (public-binding "../render.rkt" name) absent))
  (for ([name (in-list '(animate-project? plan-project prepare-project!
                         prepare-project-label-layout3d
                         project-target-section project-plan->datum))])
    (check-not-eq? (public-binding "../project.rkt" name) absent))
  (for ([name (in-list '(vec3 linear3 axis-angle affine3 make-transform3
                         aabb3 ray3 plane3
                         ray3-triangle-hit? ray3-intersect-triangle
                         spatial-visual? spatial-id spatial-transform
                         spatial-with-transform spatial-opacity spatial-with-opacity
                         spatial-local-bounds group3d spatial-child
                         spatial-path? spatial-relative-ref spatial-relative-replace
                         mesh3d mesh3d-material material3d directional-light3d
                         tube3d tube-style3d tube-style3d? tube-style3d-radius
                         tube-style3d-sides tube-style3d-color
                         stroke3d stroke3d? stroke3d-color stroke3d-width
                         stroke3d-width-mode stroke3d-cap stroke3d-join
                         stroke3d-miter-limit stroke3d-dash stroke3d-dash-offset
                         stroke3d-dash-space stroke3d-opacity stroke3d-depth-mode
                         stroke3d-depth-bias stroke3d-with-color stroke3d-with-opacity
                         point-style3d point-style3d? point-style3d-size
                         point-style3d-size-mode point-style3d-color point-style3d-opacity
                         point-style3d-depth-mode point-style3d-depth-bias
                         arrow-style3d arrow-style3d? arrow-style3d-length
                         arrow-style3d-length-mode arrow-style3d-width arrow-style3d-color
                         arrow-style3d-opacity arrow-style3d-depth-mode arrow-style3d-depth-bias
                         edge-style3d edge-style3d? edge-style3d-edges edge-style3d-visible
                         edge-style3d-hidden edge-style3d-crease-angle edge-style3d-surface
                         with-edges3d edge-overlay3d? edge-overlay3d-content edge-overlay3d-style
                         point3d line3d segment3d polyline3d arrow3d double-arrow3d
                         parametric-curve3d axes3d coordinate-plane3d grid-plane3d
                         basis-vectors3d vector-arrow3d vector-components3d
                         linear-transformation-diagram3d
                         move-along-curve3d orient-along-curve3d
                         surface3d? surface3d-grid surface3d-resolution
                         surface3d-position-at surface3d-tangent-u-at
                         surface3d-tangent-v-at surface3d-normal-at
                         parametric-surface3d function-surface3d
                         surface-color surface-color-by-height surface-color-by-scalar
                         surface-checkerboard surface-wireframe
                         surface-point surface-tangent-u surface-tangent-v
                         surface-normal surface-tangent-plane surface-coordinate-curve
                         surface-gradient-arrow surface-level-curve
                         reveal-surface-u reveal-surface-v transform-surface3d
                         cube3d box3d prism3d sphere3d cylinder3d cone3d torus3d
                         tetrahedron3d octahedron3d icosahedron3d polyhedron3d
                         extrude3d revolve3d sweep3d mesh3d-transform
                         mesh3d-reverse-winding mesh3d-flat-normals
                         mesh3d-smooth-normals mesh3d-boundary-edges
                         mesh3d-wireframe mesh3d-merge
                         riemann-volume3d washer-sum3d shell-sum3d
                         clip-plane3d clip3d slice-mesh3d section-by-plane3d
                         section-curve3d view3d-transparency-mode
                         perspective-camera3d orthographic-camera3d
                         camera3d-project camera3d-pixel-ray camera3d-frustum
                         view3d view3d-spatial-ref view3d-spatial-replace
                         spatial-relation spatial-relation-dependencies
                         spatial-relation-structure spatial-relation-cacheability
                         spatial-visual-dependency spatial-value-dependency
                         spatial-camera-dependency
                         spatial-relation-context?
                         spatial-relation-context-spatial-ref
                         spatial-relation-context-spatial-position
                         spatial-relation-context-value-ref
                         spatial-relation-context-camera
                         line-between3d segment-between3d arrow-between3d
                         plane-through3d normal-at3d distance-segment3d
                         distance-dimension3d angle-marker3d right-angle-marker3d
                         dihedral-angle3d normal-marker3d coordinate-tripod3d
                         projected-label follow-projected-point
                         follow-projected-spatial projected-label-occlusion
                         billboard-image3d billboard-image3d?
                         billboard-style3d billboard-style3d?
                         billboard3d billboard3d?
                         prepare-scene-label-layout3d
                         move3d-to move3d-by rotate3d-to rotate3d-by
                         scale3d-to scale3d-by transform3d-to
                         camera3d-move-to camera3d-look-at-to camera3d-orbit-by
                         camera3d-roll-to camera3d-field-of-view-to
                         camera3d-orthographic-height-to camera3d-dolly-by
                         camera3d-fit camera3d-follow
                         apply-linear3 apply-affine3 apply-pointwise3
                         apply-homotopy3
                         ode-field3d ode-field3d? ode-field3d-procedure
                         ode-field3d-arity ode-field3d-cache-key ode-field3d-autonomous?
                         fixed-rk4-solver3d fixed-rk4-solver3d? fixed-rk4-solver3d-step-size
                         adaptive-rk45-solver3d adaptive-rk45-solver3d?
                         adaptive-rk45-solver3d-settings prepared-trajectory3d?
                         ode-event3d ode-event3d? ode-event3d-id ode-event3d-function
                         ode-event3d-direction ode-event3d-terminal?
                         ode-event3d-value-tolerance ode-event3d-time-tolerance
                         ode-event3d-maximum-iterations ode-event3d-cache-key
                         ode-event-hit3d? ode-event-hit3d-event-id ode-event-hit3d-time
                         ode-event-hit3d-position ode-event-hit3d-value ode-event-hit3d-direction
                         ode-event-hit3d-segment-index ode-event-hit3d-iterations
                         ode-event-hit3d-provenance
                         trajectory-termination3d trajectory-termination3d?
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
                         trajectory-segment3d? trajectory-segment3d-t0 trajectory-segment3d-t1
                         trajectory-segment3d-p0 trajectory-segment3d-p1
                         trajectory-segment3d-d0 trajectory-segment3d-d1
                         trajectory-segment3d-arc-length trajectory-segment3d-bounds
                         ode-trajectory3d? ode-trajectory3d-time-range
                         ode-trajectory3d-step-size ode-trajectory3d-checkpoint-every
                         ode-trajectory3d-solver ode-trajectory3d-diagnostics ode-trajectory3d-event-hits
                         ode-trajectory3d-termination
                         ode-trajectory3d-diagnostics-termination-reason
                         ode-trajectory3d-diagnostics-field-evaluations
                         ode-trajectory3d-diagnostics-dense-segment-count
                         ode-trajectory3d-diagnostics-total-arc-length
                         ode-trajectory3d-diagnostics-event-count
                         ode-trajectory3d-diagnostics-warnings
                         prepare-ode-trajectory3d ode-trajectory3d-position
                         ode-trajectory3d-derivative ode-trajectory3d-speed
                         ode-trajectory3d-arc-length-at ode-trajectory3d-time-at-arc-length
                         ode-trajectory3d-segment-index
                         streamline-sample-policy3d streamline-sample-policy3d?
                         streamline-sample-policy3d-maximum-chord-error
                         streamline-sample-policy3d-maximum-turn-angle
                         streamline-sample-policy3d-maximum-segment-length
                         streamline-sample-policy3d-minimum-segment-length
                         prepared-streamline3d? prepared-streamline3d-seed
                         prepared-streamline3d-direction
                         prepared-streamline3d-parameterization
                         prepared-streamline3d-trajectory
                         prepared-streamline3d-curve-samples
                         prepared-streamline3d-diagnostics
                         prepared-streamline3d-seed-index
                         streamline-diagnostics3d? streamline-diagnostics3d-forward
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
                         prepare-streamline3d adaptive-streamline3d
                         seed-set3d? seed-set3d-kind seed-set3d-points seed-set3d-count
                         seed-set3d-provenance seed-set3d-diagnostics seed-set3d-cache-key
                         explicit-seeds3d grid-seeds3d plane-seeds3d curve-seeds3d
                         surface-seeds3d sphere-seeds3d poisson-seeds3d
                         prepared-streamline-set3d? prepared-streamline-set3d-seeds
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
                         prepare-streamlines3d adaptive-streamline-set3d
                         poincare-hit3d? poincare-hit3d-trajectory-id
                         poincare-hit3d-crossing-index poincare-hit3d-time
                         poincare-hit3d-point poincare-hit3d-direction
                         poincare-hit3d-source-event poincare-section3d
                         poincare-hit3d-plane-coordinates poincare-hits3d
                         prepared-poincare-map3d? prepared-poincare-map3d-plane
                         prepared-poincare-map3d-seeds prepared-poincare-map3d-trajectories
                         prepared-poincare-map3d-first-hits prepared-poincare-map3d-second-hits
                         prepared-poincare-map3d-pairs prepared-poincare-map3d-diagnostics
                         prepare-poincare-map3d
                         jacobian3d jacobian3d-result jacobian3d-result?
                         jacobian3d-result-matrix jacobian3d-result-method
                         jacobian3d-result-step jacobian3d-result-evaluations
                         jacobian3d-result-error-estimate jacobian3d-result-diagnostics
                         equilibrium-solver3d equilibrium-solver3d?
                         equilibrium-solver3d-residual-tolerance
                         equilibrium-solver3d-step-tolerance
                         equilibrium-solver3d-maximum-iterations
                         equilibrium-solver3d-damping equilibrium-solver3d-minimum-damping
                         default-equilibrium-solver3d equilibrium-seed-result3d
                         equilibrium-seed-result3d? equilibrium-root3d equilibrium-root3d?
                         equilibrium-search3d equilibrium-search3d? equilibrium-points3d
                         eigensystem3d eigensystem3d? eigensystem3d-eigenvalues
                         eigensystem3d-real-directions eigensystem3d-diagnostics eigensystem3d-of
                         linearization3d linearization3d? linearization3d-point
                         linearization3d-jacobian linearization3d-eigenvalues
                         linearization3d-real-directions linearization3d-invariant-planes
                         linearization3d-classification linearization3d-diagnostics
                         linearize3d linearization-diagram3d
                         prepared-flow-map3d prepared-flow-map3d?
                         prepared-flow-map3d-start-time prepared-flow-map3d-end-time
                         prepared-flow-map3d-seeds prepared-flow-map3d-endpoints
                         prepared-flow-map3d-trajectories prepared-flow-map3d-diagnostics
                         prepare-flow-map3d flow-map3d-ref flow-map3d-pairs flow-map3d-displacement
                         vector-field3d streamline3d streamlines3d
                         flow-particle3d flow-cloud3d
                         spatial-inspection? spatial-pick? surface-pick3d?
                         surface-pick-anchor3d
                         view3d-spatial-inspections view3d-spatial-inspection-tree
                         view3d-spatial-inspection-at view3d-pick view3d-surface-pick view3d-pixel-pick
                         mesh3d-bvh mesh3d-bvh? bvh3d-node? bvh3d-leaf?
                         bvh3d-bounds bvh3d-triangle-indices bvh3d-ray-candidates
                         analyze-mesh3d mesh3d-validate mesh3d-orient-consistently
                         mesh3d-orient-outward mesh3d-self-intersection-candidates))])
    (check-not-eq? (public-binding "../3d.rkt" name) absent))
  (for ([name (in-list '(renderer3d? renderer3d-id renderer3d-capabilities
                         renderer3d-fingerprint renderer3d-prepare renderer3d-render
                         renderer3d-release renderer3d-capability-set
                         compile-view3d compiled-view3d-primitives
                         view3d->frame3d-spec view3d->render3d-request
                         render3d-request renderer3d-render-result renderer3d-statistics
                         renderer3d-render-result->bitmap software-renderer3d
                         retained-software-renderer3d
                         retained-software-renderer3d-cache-hits
                         retained-software-renderer3d-cache-misses
                         retained-software-renderer3d-cache-size
                         renderer3d-statistics-reset! renderer3d-statistics-snapshot
                         current-view3d-renderer3d))])
    (check-not-eq? (public-binding "../3d/render.rkt" name) absent))
  (check-not-eq? (public-binding "../experimental.rkt" 'derived-visual) absent))
