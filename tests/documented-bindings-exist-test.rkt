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
  (for ([name (in-list '(circle vec2 scene-play scene-add make-scene stagger-map eager-stagger-map
                         stagger-requests parallel-map successive-map crossfade-subsets
                         target-sequence? concrete-targets children-of descendants-of selection-targets
                         formula-part-targets target-ref? target-ref-path target-ref-source-index
                         delay-plan? index-delay constant-delay distance-delay radial-delay wave-delay
                         target-ref-scheduled-index named-request-template procedure-request-template request-template?
                         reveal-subsets
                         enter leave reveal-in reveal-out reveal-formula-parts
                         linear-reveal-front radial-reveal-front reveal-front-path
                         wipe-in wipe-out iris-in iris-out
                         pulse ripple confetti confetti-request? default-confetti-palette
                         typewrite typewrite-request?
                         erase-text erase-text-request?
                         underline-sweep underline-sweep-request?
                         strike-through strike-through-request?
                         highlight-sweep highlight-sweep-request?
                         apply-wave apply-wave-request?
                         forward-order reverse-order permutation-order shuffled-order
                         resolve-animation-order repeat-animation ping-pong camera-shake
                         move-to scene-sample formula-select
                         formula-source-select source-occurrence
                         relation-visual))])
    (check-not-eq? (public-binding "../main.rkt" name) absent))
  ;; Animate's former source-addressed string-copy constructor shadowed the
  ;; ordinary racket/base string-copy. Its formula-specific replacement is
  ;; public, while the common base name is deliberately absent.
  (check-eq? (public-binding "../main.rkt" 'string-copy) absent)
  (for ([name (in-list '(formula-string-copy formula-string-copy?
                         formula-string-copy-source-selector
                         formula-string-copy-destination-selector
                         formula-string-copy-route formula-string-copy-mode))])
    (check-not-eq? (public-binding "../main.rkt" name) absent))
  ;; Keep racket/base's numeric angle available to clients. The annotation
  ;; constructor uses an explicit marker name instead.
  (check-eq? (public-binding "../main.rkt" 'angle) absent)
  (check-not-eq? (public-binding "../main.rkt" 'angle-marker) absent)
  (for ([name (in-list '(scene-program? scene-block-spec? make-scene-program))])
    (check-not-eq? (public-binding "../authoring.rkt" name) absent))
  (for ([name (in-list '(open-program-preview open-scene-preview preview-available?
                         preview-color-theme preview-set-color-theme!))])
    (check-not-eq? (public-binding "../preview.rkt" name) absent))
  (for ([name (in-list '(render-frames! encode-mp4! render-color->draw-color
                         load-color-theme!))])
    (check-not-eq? (public-binding "../render.rkt" name) absent))
  (for ([name (in-list '(animate-project? plan-project prepare-project!
                         prepare-project-label-layout3d
                         project-target-section project-plan->datum
                         render-spec-theme render-spec-with-theme))])
    (check-not-eq? (public-binding "../project.rkt" name) absent))
  (for ([name (in-list '(literal-color-spec? palette-color role-color series-color
                         color-token? color-token-kind color-token-key
                         series-color? series-color-index
                         color-expression? color-mix color-with-alpha color-opacity
                         color-inspection? inspect-color rgba-color->hex
                         color-contrast-ratio color-theme-diagnostics
                         color-theme-datum-diagnostics color-resolution-diagnostics
                         color-scale color-scale? color-scale-stops color-scale-space
                         color-scale-outside color-scale-at
                         sequential-color-scale diverging-color-scale
                         scientific-color-scale? scientific-color-scale-kind
                         scientific-color-scale-minimum scientific-color-scale-maximum
                         scientific-color-scale-midpoint scientific-color-scale-missing
                         scientific-color-scale-outside scientific-color-scale-at
                         color-spec-schema-version color-spec->datum datum->color-spec
                         color-palette-schema-version color-palette color-palette?
                         color-palette-id color-palette-display-name color-palette-version
                         color-palette-provenance palette-ref palette-keys palette-groups
                         palette->datum datum->palette
                         color-theme-schema-version color-theme color-theme?
                         color-theme-id color-theme-display-name color-theme-palette
                         color-theme-provenance theme-ref theme-role-keys theme-series
                         color-theme-fingerprint theme->datum datum->theme resolve-color
                         animate-palette animate-palette-checksum
                         animate-light-theme animate-dark-theme
                         blue-a aqua-c gray-e theme-accent pure-cyan))])
    (check-not-eq? (public-binding "../colors.rkt" name) absent))
  (for ([name (in-list '(vec3 linear3 axis-angle affine3 make-transform3
                         aabb3 ray3 plane3
                         ray3-triangle-hit? ray3-intersect-triangle
                         spatial-visual? spatial-id spatial-transform
                         spatial-with-transform spatial-opacity spatial-with-opacity
                         spatial-local-bounds group3d spatial-child
                         spatial-path? spatial-relative-ref spatial-relative-replace
                         mesh3d mesh3d-material mesh3d-vertex-ids mesh3d-edge-ids
                         mesh3d-face-ids mesh3d-vertex-id mesh3d-edge-id mesh3d-face-id
                         mesh3d-geometry-key mesh3d-semantic-key
                         mesh3d-topology mesh-topology3d-manifold? mesh-topology3d-closed?
                         mesh-topology3d-orientable? mesh3d-euler-characteristic
                         mesh3d-boundary-count mesh3d-component-invariants mesh3d-genus
                         polyhedral-complex3d polyhedral-complex3d?
                         polyhedral-complex3d-source-mesh polyhedral-complex3d-analysis-mesh
                         polyhedral-complex3d-source-transform polyhedral-complex3d-mesh
                         polyhedral-complex3d-topology
                         polyhedral-complex3d-faces polyhedral-complex3d-edge-to-faces
                         polyhedral-complex3d-vertex-to-faces polyhedral-complex3d-diagnostics
                         convex-hull3d convex-hull3d-result?
                         combinatorial-dual3d polar-dual3d dual-polyhedron3d-result?
                         prepare-schlegel-diagram3d schlegel-diagram3d schlegel-diagram3d-data?
                         material3d material3d-lighting material3d-specular-color
                         material3d-specular-exponent material3d-emission
                         material3d-emission-strength material3d-casts-shadow?
                         material3d-receives-shadow? material3d-with-color
                         material3d-with-roughness material3d-with-emission
                         material3d-with-shadow-policy
                         light-attenuation3d constant-attenuation3d
                         inverse-square-attenuation3d polynomial-attenuation3d
                         light-attenuation3d-factor spot-smoothstep3d spot-cone-factor3d
                         shadow-bias3d shadow-bias3d? shadow-bias3d-world-normal-offset
                         shadow-bias3d-slope-scale shadow-bias3d-constant-depth-offset
                         shadow-bias3d-pcf-radius-texels
                         shadow-settings3d shadow-settings3d? shadow-settings3d-map-size
                         shadow-settings3d-bias
                         shadow-settings3d-depth-bias shadow-settings3d-normal-bias
                         shadow-settings3d-pcf-radius shadow-settings3d-bounds
                         shadow-settings3d-near shadow-settings3d-far
                         shadow-settings3d-prepared-bounds-key
                         directional-shadow3d directional-shadow3d? directional-shadow3d-settings
                         spot-shadow3d spot-shadow3d? spot-shadow3d-settings
                         shadow3d? shadow3d-kind shadow3d-settings
                         prepared-shadow-bounds3d prepared-shadow-bounds3d?
                         prepare-shadow-bounds3d prepared-shadow-bounds3d-key shadow-map3d-identity
                         shadow-map3d shadow-map3d? shadow-map3d-width shadow-map3d-height
                         shadow-map3d-depth shadow-map3d-camera shadow-map3d-settings
                         shadow-map3d-bounds shadow-map3d-diagnostics
                         shadow-map3d-factor shadow-light-camera3d
                         ambient-light3d directional-light3d point-light3d spot-light3d
                         light3d? light3d-id light3d-kind light3d-color
                         light3d-intensity light3d-shadow
                         light3d-intensity-to light3d-color-to
                         point-light3d-move-to point-light3d-move-by
                         spot-light3d-move-to spot-light3d-aim-at spot-light3d-cone-to
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
                         surface3d? surface3d-kind surface3d-local-mesh surface3d-mesh
                         surface3d->mesh3d surface3d-local-bounds surface3d-diagnostics
                         surface3d-provenance surface3d-domain surface3d-evaluate surface3d-frame-at
                         surface-mesh3d surface-mesh3d? surface-mesh3d-mesh
                         surface-mesh3d-vertex-provenance surface-mesh3d-triangle-provenance
                         surface-mesh3d-topology-key surface-mesh3d-diagnostics
                         surface-domain3d surface-diagnostics3d surface-frame3d
                         surface3d-grid surface3d-resolution
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
                         ode-field3d-parallel-safe?
                         fixed-rk4-solver3d fixed-rk4-solver3d? fixed-rk4-solver3d-step-size
                         adaptive-rk45-solver3d adaptive-rk45-solver3d?
                         adaptive-rk45-solver3d-settings prepared-trajectory3d?
                         ode-event3d ode-event3d? ode-event3d-id ode-event3d-function
                         ode-event3d-direction ode-event3d-terminal?
                         ode-event3d-value-tolerance ode-event3d-time-tolerance
                         ode-event3d-maximum-iterations ode-event3d-cache-key
                         ode-event3d-parallel-safe?
                         ode-event3d-root-kind ode-event3d-initial-subdivisions
                         ode-event3d-maximum-depth
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
                         ode-trajectory3d-solver ode-trajectory3d-diagnostics ode-trajectory3d-segments
                         ode-trajectory3d-event-hits
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
                         flow-map-grid3d
                         flow-volume-cell3d
                         flow-map3d-local-jacobian flow-map3d-volume-factor
                         trajectory-samples3d trajectory-tube3d trajectory-ribbon3d trajectory-bundle3d
                         trajectory-inspection3d trajectory-pick-inspection3d
                         view3d-dynamical-inspections3d equilibrium-inspection3d
                         linearization-inspection3d flow-map-inspection3d
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
  (for ([name (in-list '(renderer3d? renderer3d-id renderer3d-capabilities-of
                         renderer3d-fingerprint renderer3d-prepare renderer3d-render
                         renderer3d-release renderer3d-capabilities
                         renderer3d-known-features renderer3d-known-limits
                         renderer3d-supports? renderer3d-capability-limit
                         renderer3d-missing-capabilities renderer3d-require-capabilities
                         renderer3d-request-required-features
                         renderer3d-request-required-limits
                         renderer3d-require-request-capabilities
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
