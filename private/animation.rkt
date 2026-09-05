#lang racket/base

;;;
;;; Animation Model
;;;

;; Defines transform, path-following, style, opacity, named-value, path-morph,
;; path-reveal, and matched-formula requests with deterministic transitions.
;;
;; Animation requests capture destinations or relative changes. Scene
;; compilation supplies start values, so requests remain independent of earlier
;; timeline sampling.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         (only-in racket/math pi)
         racket/runtime-path
         "affine-map-visual.rkt"
         "affine-transform.rkt"
         "arrow-visual.rkt"
         "animation-inspection.rkt"
         "camera-animation.rkt"
         "camera.rkt"
         "color-style.rkt"
         "derived-visual.rkt"
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "interpolation.rkt"
         "path-geometry.rkt"
         "parameter.rkt"
         "paint.rkt"
         "pointwise-map.rkt"
         "rate-function.rkt"
         "relation-visual.rkt"
         "resolvable-visual.rkt"
         "scene-state.rkt"
         "visual-selection.rkt"
         "visual-model.rkt"
         "write-in-adapter.rkt")

;; Exports
(provide value-to
         value-to-request?
         change-number-to
         change-number-to-request?
         count-to
         count-to-request?
         count-from
         count-from-request?
         move-to
         move-to-request?
         move-along-path
         move-along-path-request?
         orient-along-path
         orient-along-path-request?
         rotate-to
         rotate-to-request?
         rotate-by
         rotate-by-request?
         scale-to
         scale-to-request?
         scale-by
         scale-by-request?
         apply-affine
         apply-affine-request?
         apply-matrix
         apply-pointwise
         apply-pointwise-request?
         apply-homotopy
         apply-homotopy-request?
         stroke-width-to
         stroke-width-to-request?
         fill-color-to
         fill-color-to-request?
         stroke-color-to
         stroke-color-to-request?
         fade-to
         fade-to-request?
         fade-in
         fade-in-request?
         fade-out
         fade-out-request?
         camera-view-pan-to
         camera-view-pan-to-request?
         camera-view-pan-by
         camera-view-pan-by-request?
         camera-view-zoom-to
         camera-view-zoom-to-request?
         camera-view-zoom-by
         camera-view-zoom-by-request?
         camera-view-follow
         camera-view-follow-request?
         camera-view-fit
         camera-view-fit-request?
         morph-to
         morph-to-request?
         morph-to-normalized
         morph-to-normalized-request?
         morph-to-aligned
         morph-to-aligned-request?
         morph-to-open-aligned
         morph-to-open-aligned-request?
         morph-to-open-compound-aligned
         morph-to-open-compound-aligned-request?
         morph-to-mixed-compound-aligned
         morph-to-mixed-compound-aligned-request?
         morph-to-topology-changing
         morph-to-topology-changing-request?
         morph-to-compound-aligned
         morph-to-compound-aligned-request?
         transform-shape
         transform-shape-request?
         visual-match
         visual-match?
         visual-match-source-path
         visual-match-destination-path
         transform-matching-visuals
         transform-matching-visuals-request?
         transform-from-copy
         transform-from-copy-request?
         circumscribe
         circumscribe-request?
         indicate
         indicate-request?
         flash
         flash-request?
         focus-on
         focus-on-request?
         show-passing-flash
         show-passing-flash-request?
         wiggle
         grow-from-center
         grow-from-center-request?
         grow-arrow
         grow-arrow-request?
         draw-border-then-fill
         draw-border-then-fill-request?
         transform-formula-parts
         transform-formula-parts/anchored
         transform-formula-parts-request?
         with-animation-inspection
         animation-request-inspection
         compiled-animation-inspection
         create
         create-request?
         uncreate
         uncreate-request?
         write-in
         write-in-request?
         unwrite
         unwrite-request?
         (all-from-out "rate-function.rkt")
         animation-request?
         animation-request-default-duration
         animation-request-target-id
         animation-request-components
         compile-animation-requests
         apply-compiled-animations
         finalize-compiled-animation
         complete-compiled-animations)


;;;
;;; Request Data
;;;

(struct value-to-request (target-id destination)
  #:transparent)

;; value-to-request represents an uncompiled named semantic-value transition.
;;  - target-id    symbol?       stable scene value identity.
;;  - destination  interpolable? requested final semantic value.

(struct change-number-to-request (target-id destination)
  #:transparent)

;; change-number-to-request represents an uncompiled transition of one finite
;; real or complex scene value.  It is intentionally separate from value-to:
;; authors can communicate numerical intent while compilation continues to use
;; the normal immutable scalar-value animation.
;;  - target-id    symbol?         stable scene value identity.
;;  - destination  finite-number?  requested final numerical value.

(struct count-to-request (target-id destination)
  #:transparent)

;; count-to-request represents a counter transition from the named value's
;; current clip-start value to a finite real destination.
;;  - target-id    symbol?       stable scene value identity.
;;  - destination  finite-real?  requested final counter value.

(struct count-from-request (target-id from to)
  #:transparent)

;; count-from-request represents a counter transition with explicit endpoints.
;; The `from` value is installed at clip phase zero even if the preceding scene
;; state had another value, making the request independently reproducible.
;;  - target-id  symbol?       stable scene value identity.
;;  - from       finite-real?  requested clip-start counter value.
;;  - to         finite-real?  requested clip-end counter value.

(struct move-to-request (target-id destination)
  #:transparent)

;; move-to-request represents an uncompiled translation request.
;;  - target-id    symbol?  stable id of the Visual to move.
;;  - destination  vec2?    requested final reference position.

(struct move-along-path-request (target-id path-source start end normal-offset)
  #:transparent)

;; move-along-path-request represents an uncompiled arc-length path motion.
;;  - target-id    symbol?                     stable id of the Visual to move.
;;  - path-source  (or/c path-geometry? symbol?) direct route or scene path id.
;;  - start        finite-real?                starting arc-length fraction.
;;  - end          finite-real?                ending arc-length fraction.
;;  - normal-offset finite-real?               signed left-of-motion offset.

(struct orient-along-path-request
  (target-id path-source start end rotation-offset)
  #:transparent)

;; orient-along-path-request represents tangent-aligned path rotation.
;;  - target-id       symbol?                     stable id of the Visual.
;;  - path-source     (or/c path-geometry? symbol?) direct route or scene path id.
;;  - start           finite-real?                starting arc-length fraction.
;;  - end             finite-real?                ending arc-length fraction.
;;  - rotation-offset finite-real?                radians added to path tangent.

(struct rotate-to-request (target-id angle)
  #:transparent)

;; rotate-to-request represents an uncompiled absolute rotation request.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - angle      finite-real?  requested final counter-clockwise radians.

(struct rotate-by-request (target-id delta)
  #:transparent)

;; rotate-by-request represents an uncompiled relative rotation request.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - delta      finite-real?  counter-clockwise radians added at clip start.

(struct scale-to-request (target-id scale)
  #:transparent)

;; scale-to-request represents an uncompiled absolute scale request.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - scale      vec2?    requested final positive x and y scale factors.

(struct scale-by-request (target-id factor)
  #:transparent)

;; scale-by-request represents an uncompiled relative scale request.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - factor     vec2?    positive factors multiplied at clip start.

(struct apply-affine-request (target-id map)
  #:transparent)

;; apply-affine-request represents a whole top-level world-Visual mapping.
;;  - target-id  (or/c symbol? visual-path?)  target Visual address.
;;  - map        affine2?                     map applied after its current map.

(struct apply-pointwise-request
  (target-id map-point samples adaptive? tolerance max-depth discontinuity-mode)
  #:transparent)

;; apply-pointwise-request represents a whole top-level world-space point map.
;;  - target-id  (or/c symbol? visual-path?)  target Visual address.
;;  - map-point  (-> vec2? vec2?)              destination world point map.
;;  - samples    positive exact integer?       initial samples per original segment.
;;  - adaptive?  boolean?                      recursively refine mapped curvature.
;;  - tolerance  positive finite real?         world-space chord-deviation bound.
;;  - max-depth  exact nonnegative integer?    refinement limit per sample edge.
;;  - discontinuity-mode symbol?               'split or 'error for failed samples.

(struct apply-homotopy-request
  (target-id homotopy samples adaptive? tolerance max-depth discontinuity-mode)
  #:transparent)

;; apply-homotopy-request represents a time-dependent whole-Visual world map.
;; At a positive clip phase alpha, each geometric source sample is placed
;; directly at (homotopy point alpha), rather than linearly interpolating
;; toward a precomputed endpoint. The remaining fields have the same meaning
;; as for apply-pointwise-request.

(struct stroke-width-to-request (target-id stroke-width)
  #:transparent)

;; stroke-width-to-request represents an uncompiled absolute stroke-width request.
;;  - target-id     symbol?         stable id of the stroke-width Visual.
;;  - stroke-width  stroke-width?  requested final cosmetic stroke width.

(struct fill-color-to-request (target-id color)
  #:transparent)

;; fill-color-to-request represents an uncompiled absolute fill-color request.
;;  - target-id  symbol?      stable id of the fill-color Visual.
;;  - color      color-spec?  requested final semantic fill color.

(struct stroke-color-to-request (target-id color)
  #:transparent)

;; stroke-color-to-request represents an uncompiled absolute stroke-color request.
;;  - target-id  symbol?      stable id of the stroke-color Visual.
;;  - color      color-spec?  requested final semantic stroke color.

(struct fade-to-request (target-id opacity)
  #:transparent)

;; fade-to-request represents an uncompiled absolute opacity request.
;;  - target-id  symbol?   stable id of the opacity Visual to change.
;;  - opacity    opacity?  requested final global opacity.

(struct fade-in-request (visual)
  #:transparent)

;; fade-in-request represents an uncompiled opacity introduction request.
;;  - visual  (and/c visual? opacity-visual?)
;;            complete Visual introduced during the play clip.

(struct fade-out-request (target-id)
  #:transparent)

;; fade-out-request represents an uncompiled opacity removal request.
;;  - target-id  symbol?  stable id of the opacity Visual removed at clip end.

;; Secondary-camera requests target an ordinary frame-space camera-view Visual.
;; A follow request additionally reads one world-space target from the sampled
;; state, so it has no mutable camera history.
(struct camera-view-pan-to-request (target-id center) #:transparent)
(struct camera-view-pan-by-request (target-id delta) #:transparent)
(struct camera-view-zoom-to-request (target-id world-width) #:transparent)
(struct camera-view-zoom-by-request (target-id factor) #:transparent)
(struct camera-view-follow-request (target-id followed-target) #:transparent)
(struct camera-view-fit-request (target-id center world-width) #:transparent)

(struct morph-to-request (target-id destination)
  #:transparent)

;; morph-to-request represents an uncompiled strict local path morph request.
;;  - target-id    symbol?          stable id of the path Visual to change.
;;  - destination  path-geometry?  requested final local path geometry.

(struct morph-to-normalized-request (target-id destination)
  #:transparent)

;; morph-to-normalized-request represents an uncompiled normalized path morph.
;;  - target-id    symbol?          stable id of the path Visual to change.
;;  - destination  path-geometry?  requested final local path geometry.

(struct morph-to-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-aligned-request represents an automatically corresponded loop morph.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-open-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-open-aligned-request represents an automatically directed open-path
;; morph. Endpoint correspondence may keep or reverse destination traversal.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-open-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-open-compound-aligned-request represents an automatically paired
;; compound morph whose subpaths are all open. Distinct destination subpaths are
;; globally assigned to source subpaths, then each pair may reverse direction.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-mixed-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-mixed-compound-aligned-request represents automatic topology-aware
;; compound correspondence. Open subpaths pair only with open subpaths; closed
;; loops pair only with closed loops, and the selected subpaths are reordered to
;; source topology/order before normalized interpolation.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct morph-to-topology-changing-request
  (target-id destination allow-reverse? sample-count
             birth-anchor death-anchor birth-anchor-map death-anchor-map
             birth-penalty death-penalty birth-penalty-map death-penalty-map
             match-penalty-map)
  #:transparent)

;; morph-to-topology-changing-request represents automatic topology-aware
;; compound correspondence with deterministic subpath birth/death seeds.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

;;  - birth-anchor    (or/c 'bounds-center vec2?)  fallback local point for births.
;;  - death-anchor    (or/c 'bounds-center vec2?)  fallback local point for deaths.
;;  - birth-anchor-map hash? sparse destination-index birth-anchor overrides.
;;  - death-anchor-map hash? sparse source-index death-anchor overrides.
;;  - birth-penalty   (or/c 'forced nonnegative-finite-real?) birth cost fallback.
;;  - death-penalty   (or/c 'forced nonnegative-finite-real?) death cost fallback.
;;  - birth-penalty-map hash? sparse destination-index birth-cost overrides.
;;  - death-penalty-map hash? sparse source-index death-cost overrides.
;;  - match-penalty-map hash? sparse (source-index . destination-index) real-edge additions.

(struct morph-to-compound-aligned-request
  (target-id destination allow-reverse? sample-count)
  #:transparent)

;; morph-to-compound-aligned-request represents an automatically paired compound
;; path morph. Each closed destination subpath is globally assigned to one source
;; subpath, then SCENE-AC phase/direction alignment is applied within each pair.
;;  - target-id       symbol?          stable id of the path Visual to change.
;;  - destination     path-geometry?  exact requested final local path geometry.
;;  - allow-reverse?  boolean?        whether reverse traversal may be selected.
;;  - sample-count    exact-integer?  deterministic alignment score resolution.

(struct transform-shape-request
  (source-id destination mode correspondence allow-reverse? sample-count)
  #:transparent)

;; transform-shape-request replaces one top-level Visual with a fresh Visual.
;;  - source-id       symbol?  stable identity already present at clip start.
;;  - destination     affine/opacity Visual installed at clip completion.
;;  - mode            (or/c 'auto 'morph 'cross-fade) transition policy.
;;  - correspondence  (or/c 'auto 'perimeter 'path) geometric pairing policy.
;;  - allow-reverse?  boolean?  whether geometric correspondence may reverse.
;;  - sample-count    exact-integer?  deterministic correspondence resolution.

;; A `visual-match` names two leaf paths relative to the roots passed to
;; transform-matching-visuals. The empty list names an atomic root. It gives an
;; author an explicit semantic pairing before automatic structural matching.
(struct visual-match (source-path destination-path)
  #:transparent)

(struct transform-matching-visuals-request
  (source-id destination matches mode mismatch-mode allow-reverse? sample-count)
  #:transparent)

;; transform-matching-visuals-request replaces one top-level composite Visual
;; with a fresh composite endpoint. During the clip it draws an overlay of
;; matched world-space leaves; unmatched leaves fade, or receive moving
;; fade-transforms when mismatch-mode selects that policy.

(struct transform-formula-parts-request
  (correspondence path-arc part-paths copies mismatch-mode outline-morphs anchor stationary inspection)
  #:transparent)

;; transform-formula-parts-request represents an uncompiled matched-part change.
;;  - correspondence  formula-correspondence?  explicit source-to-destination map.
;;  - path-arc        finite-real?            default matched-part arc angle.
;;  - part-paths      (listof formula-part-path?) per-match route overrides.
;;  - copies          (listof formula-part-copy?) source-preserving copies.
;;  - mismatch-mode   (or/c 'fade 'fade-transform) handling of unmatched parts.
;;  - outline-morphs  (listof formula-part-outline-morph?) optional interiors.
;;  - anchor          (or/c #f formula-part-match?) current-state layout anchor.
;;  - stationary      (listof formula-part-match?) parts held at current positions.
;;  - inspection      (or/c #f animation-inspection?) immutable explanation data.

(struct transform-from-copy-request
  (source-id destination route)
  #:transparent)

;; transform-from-copy-request represents a source-preserving introduction.
;;  - source-id    (or/c symbol? visual-path?)  Visual already present at clip start.
;;  - destination  affine opacity Visual introduced at clip completion.
;;  - route        formula-route?  centre trajectory for the temporary copy.

(struct attention-request (target-id kind padding color stroke-width parameter)
  #:transparent)

;; attention-request is a non-mutating temporary visual emphasis. `kind` is
;; either `circumscribe` (draw, pause, erase) or `indicate` (a short pulse).
(define (circumscribe-request? value)
  (and (attention-request? value)
       (eq? (attention-request-kind value) 'circumscribe)))

(define (indicate-request? value)
  (and (attention-request? value)
       (eq? (attention-request-kind value) 'indicate)))

(define (flash-request? value)
  (and (attention-request? value) (eq? (attention-request-kind value) 'flash)))

(define (focus-on-request? value)
  (and (attention-request? value) (eq? (attention-request-kind value) 'focus-on)))

(define (show-passing-flash-request? value)
  (and (attention-request? value)
       (eq? (attention-request-kind value) 'show-passing-flash)))

(struct grow-request (visual kind)
  #:transparent)

(define (grow-from-center-request? value)
  (and (grow-request? value) (eq? (grow-request-kind value) 'center)))

(define (grow-arrow-request? value)
  (and (grow-request? value) (eq? (grow-request-kind value) 'arrow)))

(struct draw-border-then-fill-request (visual)
  #:transparent)

(struct create-request (visual)
  #:transparent)

;; create-request represents an uncompiled path introduction request.
;;  - visual  path-visual? or relation-visual? complete Visual introduced
;;            during the play clip. A relation is resolved afresh per sample.

(struct uncreate-request (target-id)
  #:transparent)

;; uncreate-request represents an uncompiled path removal request.
;;  - target-id  symbol?  stable id of the path Visual removed at clip end.

(struct write-in-request (plan)
  #:transparent)

;; write-in-request represents an uncompiled Manim-like vector write.  Its
;; plan keeps both the exact endpoint Visual and a path-only proxy used only
;; during the animation interval.

(struct unwrite-request (target order lag-ratio outline-stroke-width rate-func)
  #:transparent)

;; unwrite-request represents a Manim-like removal of a writable Visual.  The
;; current scene Visual supplies the endpoint/proxy plan at compilation time,
;; so an unwrite follows the actual current style rather than a stale caller
;; copy.


;;;
;;; Compiled Animation Data
;;;

(struct scalar-value-animation (target-id from to)
  #:transparent)

;; scalar-value-animation represents one compiled named semantic-value transition.
;;  - target-id  symbol?       stable scene value identity.
;;  - from       interpolable? semantic value at interval start.
;;  - to         interpolable? exact requested semantic endpoint.

(struct translation-animation (target-id from to)
  #:transparent)

;; translation-animation represents one compiled position transition.
;;  - target-id  symbol?  stable id of the Visual to move.
;;  - from       vec2?    reference position at clip start.
;;  - to         vec2?    reference position at clip end.

(struct path-motion-animation (target-id path start end normal-offset)
  #:transparent)

;; path-motion-animation represents one compiled arc-length path traversal.
;;  - target-id  symbol?          stable id of the Visual to move.
;;  - path       path-geometry?  continuous route in target coordinates.
;;  - start      finite-real?    starting route fraction.
;;  - end        finite-real?    ending route fraction.
;;  - normal-offset finite-real? signed left-of-motion offset.

(struct path-orientation-animation
  (target-id path start end rotation-offset)
  #:transparent)

;; path-orientation-animation represents tangent-derived absolute rotation.
;;  - target-id       symbol?          stable id of the affine Visual.
;;  - path            path-geometry?  continuous route in target coordinates.
;;  - start           finite-real?    starting route fraction.
;;  - end             finite-real?    ending route fraction.
;;  - rotation-offset finite-real?    radians added to traversal tangent.

(struct rotation-animation (target-id from to)
  #:transparent)

;; rotation-animation represents one compiled rotation transition.
;;  - target-id  symbol?       stable id of the affine Visual to rotate.
;;  - from       finite-real?  rotation at clip start.
;;  - to         finite-real?  rotation at clip end.

(struct scaling-animation (target-id from to)
  #:transparent)

;; scaling-animation represents one compiled scale transition.
;;  - target-id  symbol?  stable id of the affine Visual to scale.
;;  - from       vec2?    positive scale at clip start.
;;  - to         vec2?    positive scale at clip end.

(struct affine-map-animation (target-id content from-map map opacity)
  #:transparent)

;; affine-map-animation represents a world-coordinate affine map applied to a
;; Visual subtree. `content` is its normalized semantic subtree, `from-map` is
;; its existing local affine2 map, `map` is the world request rebased into the
;; target's containing coordinates, and `opacity` preserves an existing outer
;; affine-wrapper opacity.

(struct pointwise-map-animation
  (target-id source map-point samples adaptive? tolerance max-depth
             discontinuity-mode parent-map)
  #:transparent)

;; pointwise-map-animation samples a world-resolved source Visual by mapping
;; its geometric points at each clip progress. `parent-map` rebases a nested
;; result back into its containing group after the world-space deformation.

(struct homotopy-map-animation
  (target-id source homotopy samples adaptive? tolerance max-depth
             discontinuity-mode parent-map)
  #:transparent)

;; homotopy-map-animation evaluates its world-space map afresh from the source
;; geometry and sampled clip phase. It intentionally stores neither frame
;; history nor a mutable integrator-like state.

(struct stroke-width-animation (target-id from to)
  #:transparent)

;; stroke-width-animation represents one compiled cosmetic-width transition.
;;  - target-id  symbol?         stable id of the stroke-width Visual.
;;  - from       stroke-width?  width at clip start.
;;  - to         stroke-width?  requested width at clip end.

(struct fill-color-animation
  (target-id from-paint to-paint)
  #:transparent)

;; fill-color-animation keeps exact semantic paint endpoints. Solid colours,
;; compatible gradients, and compatible checker patterns interpolate directly.

(struct stroke-color-animation
  (target-id from-spec from-color to-spec to-color)
  #:transparent)

;; stroke-color-animation is the corresponding semantic stroke-color transition.

(struct camera-view-center-animation (target-id from to)
  #:transparent)

(struct camera-view-world-width-animation (target-id from to)
  #:transparent)

(struct camera-view-follow-animation (target-id followed-target offset)
  #:transparent)

(struct camera-view-fit-animation
  (target-id center-from center-to world-width-from world-width-to)
  #:transparent)

(struct opacity-animation
  (target-id from to force-to-at-end? remove-at-end?)
  #:transparent)

;; opacity-animation represents one compiled global-opacity transition.
;;  - target-id        symbol?   stable id of the opacity Visual to change.
;;  - from             opacity?  global opacity at clip start.
;;  - to               opacity?  requested global opacity at clip end.
;;  - force-to-at-end? boolean?  whether structural completion installs to.
;;  - remove-at-end?   boolean?  whether structural completion removes Visual.

(struct path-morph-animation (target-id from to)
  #:transparent)

;; path-morph-animation represents one compiled compatible path transition.
;;  - target-id  symbol?          stable id of the path Visual to change.
;;  - from       path-geometry?  complete local path at clip start.
;;  - to         path-geometry?  complete local path at clip end.

(struct normalized-path-morph-animation
  (target-id source normalized-source normalized-destination destination)
  #:transparent)

;; normalized-path-morph-animation represents one normalized path transition.
;;  - target-id               symbol?          stable id of the path Visual.
;;  - source                  path-geometry?  exact source representation.
;;  - normalized-source       path-geometry?  cubic source used in interiors.
;;  - normalized-destination  path-geometry?  compatible cubic destination.
;;  - destination             path-geometry?  exact requested destination.

(struct formula-parts-transform-animation (target-id plan inspection)
  #:transparent)

;; formula-parts-transform-animation represents one compiled part transition.
;;  - target-id  symbol?                    stable assembly identity.
;;  - plan       formula-transition-plan?  exact endpoints and interior layers.
;;  - inspection (or/c #f animation-inspection?) retained planner explanation.

(struct transform-from-copy-animation (source destination route overlay-id)
  #:transparent)

;; transform-from-copy-animation renders two transient moving layers while the
;; original source stays in the scene. `destination` is added structurally only
;; when the clip completes.

(struct transform-shape-animation
  (source-id source destination overlay-id normalized-source normalized-destination)
  #:transparent)

;; transform-shape-animation renders an interior replacement layer, then swaps
;; source for destination structurally at the clip boundary. Normalized paths
;; are false for an intentional cross-fade fallback.

(struct visual-match-spec
  (source destination normalized-source normalized-destination)
  #:transparent)

;; `source` or `destination` is false only for a one-sided unmatched leaf.
;; When both normalized paths are present the two leaf layers share a
;; geometry-morph interior; otherwise they share an affine interpolant.

(struct transform-matching-visuals-animation
  (source-id source destination overlay-id specs)
  #:transparent)

;; transform-matching-visuals-animation follows the same exact endpoint rule
;; as transform-shape: the root source/destination trees are never rewritten,
;; only hidden/replaced around a temporary overlay at interior samples.

(struct attention-animation (overlay-id target-paths kind padding color stroke-width parameter)
  #:transparent)

;; attention-animation stores a declarative target and outline style. Its
;; renderer-measured box is resolved from the fully sampled scene state, so it
;; is never part of either structural endpoint and follows a simultaneous
;; motion, scale, rotation, or formula rewrite.

(struct grow-animation (target-id source destination kind)
  #:transparent)

;; grow-animation is a structural introduction with an invisible tiny source
;; and the caller's exact endpoint Visual.

(struct border-fill-animation (target-id visual)
  #:transparent)

;; border-fill-animation reveals a path's outline first, then fades in its fill
;; without changing the endpoint path or semantic style.

(struct path-reveal-animation (target-id path from to remove-at-end?)
  #:transparent)

;; path-reveal-animation represents one compiled arc-length reveal transition.
;;  - target-id       symbol?          stable id of the path Visual.
;;  - path            path-geometry?  complete local path geometry.
;;  - from            finite-real?    visible prefix fraction at clip start.
;;  - to              finite-real?    visible prefix fraction at clip end.
;;  - remove-at-end?  boolean?        whether completion removes the Visual.

(struct relation-path-reveal-animation (target-id reverse? remove-at-end?)
  #:transparent)

;; relation-path-reveal-animation is the deferred counterpart to
;; path-reveal-animation. It stores no path geometry: the current relation
;; result is resolved first at each sample and only then partially revealed.

(struct write-in-animation (target-id plan reverse? remove-at-end?)
  #:transparent)

;; write-in-animation samples a staggered two-phase outline/fill proxy, then
;; either restores the original endpoint Visual or removes it at the clip
;; boundary.  Reverse writing reverses leaf order and path traversal.

(struct write-plan (endpoint proxy leaves outline-stroke-width reveal reverse? rate-func)
  #:transparent)

;; write-plan records immutable write-in compilation data.
;;  - endpoint              visual?             exact caller-supplied Visual.
;;  - proxy                 path/group Visual    write-time vector equivalent.
;;  - leaves                (listof write-leaf?) reveal order and local timing.
;;  - outline-stroke-width  nonnegative-real?    cosmetic outline width.
;;  - reveal                (or/c 'bezier 'arc-length) path progress model.
;;  - reverse?              boolean?             reverse leaf/path traversal.
;;  - rate-func             (-> real? real?)     local leaf easing.

(struct write-leaf (id visual start duration)
  #:transparent)

;; write-leaf stores one styled complete path and its normalized local interval.


;;;
;;; Public Animation Requests
;;;

; value-to : (or/c symbol? scene-parameter?) interpolable? -> value-to-request?
;;   Creates an absolute animation request for one named scene semantic value.
(define (value-to target destination)
  (define target-id
    (parameter-target-id target 'value-to))
  (unless (interpolable? destination)
    (raise-argument-error 'value-to "interpolable?" destination))
  (value-to-request target-id destination))

; change-number-to : (or/c symbol? scene-parameter?) finite-number?
;                    -> change-number-to-request?
;; Creates an absolute numerical-value request.  Unlike value-to it accepts
;; only finite real or complex values, so it is a useful author-level contract
;; for numeric displays and simulations.
(define (change-number-to target destination)
  (define target-id
    (parameter-target-id target 'change-number-to))
  (check-numeric-animation-value 'change-number-to destination)
  (change-number-to-request target-id destination))

; count-to : (or/c symbol? scene-parameter?) finite-real? -> count-to-request?
;; Counts from the target's clip-start value to destination.
(define (count-to target destination)
  (define target-id
    (parameter-target-id target 'count-to))
  (check-finite-real-value 'count-to destination)
  (count-to-request target-id destination))

; count-from : (or/c symbol? scene-parameter?) finite-real? finite-real?
;              -> count-from-request?
;; Counts between explicit values, overriding the target's preceding value at
;; the start of this clip.  It remains a pure sampled transition rather than a
;; mutable counter.
(define (count-from target from to)
  (define target-id
    (parameter-target-id target 'count-from))
  (check-finite-real-value 'count-from from)
  (check-finite-real-value 'count-from to)
  (count-from-request target-id from to))

; move-to : (or/c visual? symbol?) vec2? -> move-to-request?
;;   Creates a request to move target to destination.
(define (move-to target destination)
  (unless (vec2? destination)
    (raise-argument-error 'move-to "vec2?" destination))
  (move-to-request (visual-target-id target 'move-to)
                   destination))

; move-along-path : (or/c visual? symbol?)
;                   (or/c path-geometry? path-visual? derived-visual? symbol?)
;                   [#:start unit-real?]
;                   [#:end unit-real?]
;                   [#:normal-offset finite-real?]
;                   -> move-along-path-request?
;;   Creates a request that places target along a semantic path by arc length.
(define (move-along-path target path
                         #:start [start 0]
                         #:end [end 1]
                         #:normal-offset [normal-offset 0])
  (define target-id
    (visual-target-id target 'move-along-path))
  (define path-source
    (normalize-path-animation-source 'move-along-path path))
  (check-path-motion-fraction 'move-along-path "start" start)
  (check-path-motion-fraction 'move-along-path "end" end)
  (unless (finite-real? normal-offset)
    (raise-argument-error 'move-along-path "finite real?" normal-offset))
  (move-along-path-request target-id
                           path-source
                           start
                           end
                           normal-offset))

; orient-along-path : (or/c visual? symbol?)
;                     (or/c path-geometry? path-visual? derived-visual? symbol?)
;                     [#:start unit-real?]
;                     [#:end unit-real?]
;                     [#:rotation-offset finite-real?]
;                     -> orient-along-path-request?
;;   Creates a request that rotates target to the route's traversal tangent.
(define (orient-along-path target path
                           #:start [start 0]
                           #:end [end 1]
                           #:rotation-offset [rotation-offset 0])
  (define target-id
    (visual-target-id target 'orient-along-path))
  (define path-source
    (normalize-path-animation-source 'orient-along-path path))
  (check-path-motion-fraction 'orient-along-path "start" start)
  (check-path-motion-fraction 'orient-along-path "end" end)
  (unless (finite-real? rotation-offset)
    (raise-argument-error 'orient-along-path
                          "finite real?"
                          rotation-offset))
  (orient-along-path-request target-id
                             path-source
                             start
                             end
                             rotation-offset))

; rotate-to : (or/c visual? symbol?) finite-real? -> rotate-to-request?
;;   Creates a request to rotate target to an absolute angle.
(define (rotate-to target angle)
  (unless (finite-real? angle)
    (raise-argument-error 'rotate-to "finite real?" angle))
  (rotate-to-request (visual-target-id target 'rotate-to)
                     angle))

; rotate-by : (or/c visual? symbol?) finite-real? -> rotate-by-request?
;;   Creates a request to add a counter-clockwise rotation to target.
(define (rotate-by target delta)
  (unless (finite-real? delta)
    (raise-argument-error 'rotate-by "finite real?" delta))
  (rotate-by-request (visual-target-id target 'rotate-by)
                     delta))

; scale-to : (or/c visual? symbol?) (or/c positive-real? vec2?)
;            -> scale-to-request?
;;   Creates a request to replace target's absolute local scale.
(define (scale-to target scale)
  (check-animation-scale 'scale-to scale)
  (scale-to-request (visual-target-id target 'scale-to)
                    (scale-factor->vec2 scale)))

; scale-by : (or/c visual? symbol?) (or/c positive-real? vec2?)
;            -> scale-by-request?
;;   Creates a request to multiply target's local scale.
(define (scale-by target factor)
  (check-animation-scale 'scale-by factor)
  (scale-by-request (visual-target-id target 'scale-by)
                    (scale-factor->vec2 factor)))

; apply-affine : (or/c visual? symbol? visual-path?) affine2?
;                -> apply-affine-request?
;; Applies a world-coordinate affine map after target's current map. Nested
;; paths remain valid: SCENE-DK rebases the request through enclosing affine
;; maps and replaces only the addressed semantic subtree.
(define (apply-affine target map)
  (unless (affine2? map)
    (raise-argument-error 'apply-affine "affine2?" map))
  (apply-affine-request
   (visual-target-id target 'apply-affine)
   map))

; apply-matrix : (or/c visual? symbol? visual-path?) linear2?
;                -> apply-affine-request?
;; Applies a linear matrix about the world origin. Use apply-affine when a
;; translation belongs to the same map.
(define (apply-matrix target matrix)
  (unless (linear2? matrix)
    (raise-argument-error 'apply-matrix "linear2?" matrix))
  (apply-affine target
                (make-affine2 #:linear matrix)))

; apply-pointwise : (or/c visual? symbol? visual-path?) (-> vec2? vec2?)
;                   [#:samples positive-exact-integer?] [#:adaptive? boolean?]
;                   [#:tolerance positive-finite-real?]
;                   [#:max-depth exact-nonnegative-integer?]
;                   [#:discontinuities (or/c 'split 'error)]
;                   -> apply-pointwise-request?
;; Applies a nonlinear world-coordinate point map to one ordinary Visual path.
;; Geometric leaves are adaptively sampled before mapping; non-geometric leaves
;; remain legible at their ordinary affine world placement.
(define (apply-pointwise target map-point
                         #:samples [samples 24]
                         #:adaptive? [adaptive? #t]
                         #:tolerance [tolerance 1/32]
                         #:max-depth [max-depth 8]
                         #:discontinuities [discontinuity-mode 'split])
  (unless (and (procedure? map-point)
               (procedure-arity-includes? map-point 1))
    (raise-argument-error
     'apply-pointwise "(procedure-arity-includes/c 1)" map-point))
  (unless (and (exact-integer? samples)
               (positive? samples))
    (raise-argument-error 'apply-pointwise "positive exact integer" samples))
  (unless (boolean? adaptive?)
    (raise-argument-error 'apply-pointwise "boolean?" adaptive?))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'apply-pointwise "positive finite real?" tolerance))
  (unless (and (exact-integer? max-depth) (not (negative? max-depth)))
    (raise-argument-error 'apply-pointwise "exact nonnegative integer" max-depth))
  (unless (memq discontinuity-mode '(split error))
    (raise-argument-error 'apply-pointwise "(or/c 'split 'error)" discontinuity-mode))
  (apply-pointwise-request
   (visual-target-id target 'apply-pointwise)
   map-point
   samples adaptive? tolerance max-depth discontinuity-mode))

; apply-homotopy : (or/c visual? symbol? visual-path?)
;                  (-> vec2? finite-real? vec2?)
;                  [#:samples positive-exact-integer?] [#:adaptive? boolean?]
;                  [#:tolerance positive-finite-real?]
;                  [#:max-depth exact-nonnegative-integer?]
;                  [#:discontinuities (or/c 'split 'error)]
;                  -> apply-homotopy-request?
;; Applies a time-dependent nonlinear world-coordinate map to one ordinary
;; Visual tree. The homotopy is evaluated directly from the clip's eased local
;; phase, so arbitrary frame sampling never relies on a previous frame. Authors
;; normally provide H(p, 0) = p; the source Visual is retained exactly at the
;; clip's zero boundary.
(define (apply-homotopy target homotopy
                        #:samples [samples 24]
                        #:adaptive? [adaptive? #t]
                        #:tolerance [tolerance 1/32]
                        #:max-depth [max-depth 8]
                        #:discontinuities [discontinuity-mode 'split])
  (unless (and (procedure? homotopy)
               (procedure-arity-includes? homotopy 2))
    (raise-argument-error
     'apply-homotopy "(procedure-arity-includes/c 2)" homotopy))
  (unless (and (exact-integer? samples)
               (positive? samples))
    (raise-argument-error 'apply-homotopy "positive exact integer" samples))
  (unless (boolean? adaptive?)
    (raise-argument-error 'apply-homotopy "boolean?" adaptive?))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'apply-homotopy "positive finite real?" tolerance))
  (unless (and (exact-integer? max-depth) (not (negative? max-depth)))
    (raise-argument-error 'apply-homotopy
                          "exact nonnegative integer" max-depth))
  (unless (memq discontinuity-mode '(split error))
    (raise-argument-error 'apply-homotopy
                          "(or/c 'split 'error)" discontinuity-mode))
  (apply-homotopy-request
   (visual-target-id target 'apply-homotopy)
   homotopy
   samples adaptive? tolerance max-depth discontinuity-mode))

; stroke-width-to : (or/c symbol? (and/c visual? stroke-width-visual?))
;                   stroke-width?
;                   -> stroke-width-to-request?
;;   Creates a request to replace target's cosmetic stroke width.
(define (stroke-width-to target stroke-width)
  (check-stroke-width-request-target 'stroke-width-to target)
  (check-animation-stroke-width 'stroke-width-to stroke-width)
  (stroke-width-to-request
   (visual-target-id target 'stroke-width-to)
   stroke-width))

; fill-color-to : (or/c symbol? (and/c visual? fill-color-visual?)) paint?
;                 -> fill-color-to-request?
;;   Creates a request to replace target's semantic fill color.
(define (fill-color-to target color)
  (check-fill-color-request-target 'fill-color-to target)
  (check-animation-paint 'fill-color-to color)
  (fill-color-to-request
   (visual-target-id target 'fill-color-to)
   color))

; stroke-color-to : (or/c symbol? (and/c visual? stroke-color-visual?))
;                   color-spec? -> stroke-color-to-request?
;;   Creates a request to replace target's semantic stroke color.
(define (stroke-color-to target color)
  (check-stroke-color-request-target 'stroke-color-to target)
  (check-animation-color-spec 'stroke-color-to color)
  (stroke-color-to-request
   (visual-target-id target 'stroke-color-to)
   color))

; fade-to : (or/c symbol? (and/c visual? opacity-visual?)) opacity?
;           -> fade-to-request?
;;   Creates a request to replace target's global opacity.
(define (fade-to target opacity)
  (check-opacity-request-target 'fade-to target)
  (check-animation-opacity 'fade-to opacity)
  (fade-to-request (visual-target-id target 'fade-to)
                   opacity))

; fade-in : (and/c visual? opacity-visual?) -> fade-in-request?
;;   Creates a request that introduces visual by increasing its opacity.
(define (fade-in visual)
  (check-opacity-visual-value 'fade-in visual)
  (fade-in-request visual))

; fade-out : (or/c symbol? (and/c visual? opacity-visual?))
;            -> fade-out-request?
;;   Creates a request that lowers and then removes an opacity Visual.
(define (fade-out target)
  (check-opacity-request-target 'fade-out target)
  (fade-out-request (visual-target-id target 'fade-out)))

; camera-view-pan-to : (or/c symbol? camera-view-visual?) vec2?
;;                      -> camera-view-pan-to-request?
;;   Animates the centre of one named secondary camera.
(define (camera-view-pan-to target center)
  (check-camera-view-animation-target 'camera-view-pan-to target)
  (unless (vec2? center)
    (raise-argument-error 'camera-view-pan-to "vec2?" center))
  (camera-view-pan-to-request
   (camera-view-animation-target-id target 'camera-view-pan-to) center))

; camera-view-pan-by : (or/c symbol? camera-view-visual?) vec2?
;;                      -> camera-view-pan-by-request?
;;   Adds a clip-start-relative world displacement to one secondary camera.
(define (camera-view-pan-by target delta)
  (check-camera-view-animation-target 'camera-view-pan-by target)
  (unless (vec2? delta)
    (raise-argument-error 'camera-view-pan-by "vec2?" delta))
  (camera-view-pan-by-request
   (camera-view-animation-target-id target 'camera-view-pan-by) delta))

; camera-view-zoom-to : (or/c symbol? camera-view-visual?) positive-real?
;;                       -> camera-view-zoom-to-request?
;;   Sets a secondary camera's visible world width at the clip endpoint.
(define (camera-view-zoom-to target world-width)
  (check-camera-view-animation-target 'camera-view-zoom-to target)
  (check-positive-finite-real 'camera-view-zoom-to world-width)
  (camera-view-zoom-to-request
   (camera-view-animation-target-id target 'camera-view-zoom-to) world-width))

; camera-view-zoom-by : (or/c symbol? camera-view-visual?) positive-real?
;;                       -> camera-view-zoom-by-request?
;;   Applies a magnification factor above one for zooming in.
(define (camera-view-zoom-by target factor)
  (check-camera-view-animation-target 'camera-view-zoom-by target)
  (check-positive-finite-real 'camera-view-zoom-by factor)
  (camera-view-zoom-by-request
   (camera-view-animation-target-id target 'camera-view-zoom-by) factor))

; camera-view-follow : (or/c symbol? camera-view-visual?)
;;                      (or/c visual? symbol? visual-path?)
;;                      -> camera-view-follow-request?
;;   Keeps a target at its clip-start inset-frame offset with no frame history.
(define (camera-view-follow target followed-target)
  (check-camera-view-animation-target 'camera-view-follow target)
  (check-world-follow-target 'camera-view-follow followed-target)
  (camera-view-follow-request
   (camera-view-animation-target-id target 'camera-view-follow)
   (visual-target-id followed-target 'camera-view-follow)))

; camera-view-fit : (or/c symbol? camera-view-visual?) camera-fit-request?
;;                   -> camera-view-fit-request?
;;   Animates a secondary camera to one renderer-aware measured fit endpoint.
;;   Construct the fit with camera-fit-visuals, camera-fit-scene, or
;;   camera-fit-layout-box using the inset camera.
(define (camera-view-fit target fit)
  (check-camera-view-animation-target 'camera-view-fit target)
  (unless (camera-fit-request? fit)
    (raise-argument-error 'camera-view-fit "camera-fit-request?" fit))
  (camera-view-fit-request
   (camera-view-animation-target-id target 'camera-view-fit)
   (camera-fit-request-center fit)
   (camera-fit-request-world-width fit)))

; morph-to : (or/c path-visual? symbol?) path-geometry?
;            -> morph-to-request?
;;   Creates a request to interpolate target to destination path geometry.
(define (morph-to target destination)
  (check-path-morph-request-arguments 'morph-to target destination)
  (morph-to-request (visual-target-id target 'morph-to)
                    destination))

; morph-to-normalized : (or/c path-visual? symbol?) path-geometry?
;                       -> morph-to-normalized-request?
;;   Creates a request that normalizes limited path differences before morphing.
(define (morph-to-normalized target destination)
  (check-path-morph-request-arguments
   'morph-to-normalized
   target
   destination)
  (morph-to-normalized-request
   (visual-target-id target 'morph-to-normalized)
   destination))

; morph-to-aligned : (or/c path-visual? symbol?) path-geometry?
;                    [#:allow-reverse? boolean?]
;                    [#:sample-count exact-integer?]
;                    -> morph-to-aligned-request?
;;   Creates a normalized morph with automatic closed-loop correspondence.
(define (morph-to-aligned target destination
                          #:allow-reverse? [allow-reverse? #t]
                          #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error 'morph-to-aligned "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-aligned-request
   (visual-target-id target 'morph-to-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-open-aligned : (or/c path-visual? symbol?) path-geometry?
;                         [#:allow-reverse? boolean?]
;                         [#:sample-count exact-integer?]
;                         -> morph-to-open-aligned-request?
;;   Creates a normalized morph with automatic open-path endpoint correspondence.
(define (morph-to-open-aligned target destination
                               #:allow-reverse? [allow-reverse? #t]
                               #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-open-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error 'morph-to-open-aligned "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-open-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-open-aligned-request
   (visual-target-id target 'morph-to-open-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-open-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                                  [#:allow-reverse? boolean?]
;                                  [#:sample-count exact-integer?]
;                                  -> morph-to-open-compound-aligned-request?
;;   Creates a normalized morph with automatic open-subpath pairing.
(define (morph-to-open-compound-aligned target destination
                                        #:allow-reverse? [allow-reverse? #t]
                                        #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-open-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-open-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-open-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-open-compound-aligned-request
   (visual-target-id target 'morph-to-open-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-mixed-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                                   [#:allow-reverse? boolean?]
;                                   [#:sample-count exact-integer?]
;                                   -> morph-to-mixed-compound-aligned-request?
;;   Creates a normalized morph with topology-aware compound pairing.
(define (morph-to-mixed-compound-aligned target destination
                                         #:allow-reverse? [allow-reverse? #t]
                                         #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-mixed-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-mixed-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-mixed-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-mixed-compound-aligned-request
   (visual-target-id target 'morph-to-mixed-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; morph-to-topology-changing : (or/c path-visual? symbol?) path-geometry?
;                               [#:allow-reverse? boolean?]
;                               [#:sample-count exact-integer?]
;                               [#:birth-anchor (or/c 'bounds-center vec2?)]
;                               [#:death-anchor (or/c 'bounds-center vec2?)]
;                               [#:birth-anchor-map hash?]
;                               [#:death-anchor-map hash?]
;                               [#:birth-penalty (or/c 'forced nonnegative-finite-real?)]
;                               [#:death-penalty (or/c 'forced nonnegative-finite-real?)]
;                               [#:birth-penalty-map hash?]
;                               [#:death-penalty-map hash?]
;                               [#:match-penalty-map hash?]
;                               -> morph-to-topology-changing-request?
;;   Creates a normalized topology-aware morph with subpath births/deaths.
(define (morph-to-topology-changing target destination
                                    #:allow-reverse? [allow-reverse? #t]
                                    #:sample-count [sample-count 64]
                                    #:birth-anchor [birth-anchor 'bounds-center]
                                    #:death-anchor [death-anchor 'bounds-center]
                                    #:birth-anchor-map [birth-anchor-map #hash()]
                                    #:death-anchor-map [death-anchor-map #hash()]
                                    #:birth-penalty [birth-penalty 'forced]
                                    #:death-penalty [death-penalty 'forced]
                                    #:birth-penalty-map [birth-penalty-map #hash()]
                                    #:death-penalty-map [death-penalty-map #hash()]
                                    #:match-penalty-map [match-penalty-map #hash()])
  (check-path-morph-request-arguments
   'morph-to-topology-changing
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-topology-changing
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-topology-changing
     "exact integer greater than or equal to 8"
     sample-count))
  (check-topology-morph-anchor-argument
   'morph-to-topology-changing "#:birth-anchor" birth-anchor)
  (check-topology-morph-anchor-argument
   'morph-to-topology-changing "#:death-anchor" death-anchor)
  (define immutable-birth-anchor-map
    (snapshot-topology-morph-anchor-map
     'morph-to-topology-changing "#:birth-anchor-map" birth-anchor-map))
  (define immutable-death-anchor-map
    (snapshot-topology-morph-anchor-map
     'morph-to-topology-changing "#:death-anchor-map" death-anchor-map))
  (define immutable-birth-penalty-map
    (snapshot-topology-morph-penalty-map
     'morph-to-topology-changing "#:birth-penalty-map" birth-penalty-map))
  (define immutable-death-penalty-map
    (snapshot-topology-morph-penalty-map
     'morph-to-topology-changing "#:death-penalty-map" death-penalty-map))
  (define immutable-match-penalty-map
    (snapshot-topology-morph-match-penalty-map
     'morph-to-topology-changing "#:match-penalty-map" match-penalty-map))
  (check-topology-morph-penalty-arguments
   'morph-to-topology-changing
   birth-penalty
   death-penalty
   immutable-birth-penalty-map
   immutable-death-penalty-map)
  (morph-to-topology-changing-request
   (visual-target-id target 'morph-to-topology-changing)
   destination
   allow-reverse?
   sample-count
   birth-anchor
   death-anchor
   immutable-birth-anchor-map
   immutable-death-anchor-map
   birth-penalty
   death-penalty
   immutable-birth-penalty-map
   immutable-death-penalty-map
   immutable-match-penalty-map))

; snapshot-topology-morph-anchor-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse per-subpath anchor overrides in a request.
(define (snapshot-topology-morph-anchor-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph anchor map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index anchor) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer anchor-map keys"
       field value
       "key" subpath-index))
    (check-topology-morph-anchor-argument who field anchor)
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "anchor-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index anchor)))

; check-topology-morph-anchor-argument : symbol? string? any/c -> void?
;;   Validates one declarative local anchor captured by a morph request.
(define (check-topology-morph-anchor-argument who field value)
  (unless (or (eq? value 'bounds-center)
              (vec2? value))
    (raise-arguments-error
     who
     "expected a topology morph anchor"
     field value
     "expected" "'bounds-center or vec2?")))

; snapshot-topology-morph-penalty-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse per-subpath numeric penalty overrides.
(define (snapshot-topology-morph-penalty-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index penalty) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer penalty-map keys"
       field value
       "key" subpath-index))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative penalty-map values"
       field value
       "key" subpath-index
       "value" penalty))
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "penalty-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index penalty)))

; snapshot-topology-morph-match-penalty-map : symbol? string? any/c -> hash?
;;   Validates and snapshots sparse pairwise additive real-match costs.
(define (snapshot-topology-morph-match-penalty-map who field value)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph match-penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(pair-key penalty) (in-hash value)])
    (unless (and (pair? pair-key)
                 (exact-nonnegative-integer? (car pair-key))
                 (exact-nonnegative-integer? (cdr pair-key)))
      (raise-arguments-error
       who
       "expected match-penalty-map keys of the form (cons source-index destination-index)"
       field value
       "key" pair-key))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative match-penalty-map values"
       field value
       "key" pair-key
       "value" penalty))
    (define normalized-key (cons (car pair-key) (cdr pair-key)))
    (when (hash-has-key? result normalized-key)
      (raise-arguments-error
       who
       "match-penalty-map contains duplicate pair keys under equal? lookup"
       field value
       "key" pair-key))
    (hash-set result normalized-key penalty)))

; check-topology-morph-penalty-arguments : symbol? any/c any/c hash? hash? -> void?
;;   Requires forced-only defaults with empty maps or numeric costs with overrides.
(define (check-topology-morph-penalty-arguments
         who birth-penalty death-penalty birth-penalty-map death-penalty-map)
  (define (numeric-penalty? value)
    (and (finite-real? value)
         (>= value 0)))
  (unless (or (and (eq? birth-penalty 'forced)
                   (eq? death-penalty 'forced))
              (and (numeric-penalty? birth-penalty)
                   (numeric-penalty? death-penalty)))
    (raise-arguments-error
     who
     "expected both birth/death penalties to use the same policy mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "expected" "both 'forced, or both nonnegative finite real numbers"))
  (when (and (eq? birth-penalty 'forced)
             (or (positive? (hash-count birth-penalty-map))
                 (positive? (hash-count death-penalty-map))))
    (raise-arguments-error
     who
     "per-subpath penalty maps require numeric birth/death penalty mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "#:birth-penalty-map" birth-penalty-map
     "#:death-penalty-map" death-penalty-map)))

; morph-to-compound-aligned : (or/c path-visual? symbol?) path-geometry?
;                             [#:allow-reverse? boolean?]
;                             [#:sample-count exact-integer?]
;                             -> morph-to-compound-aligned-request?
;;   Creates a normalized morph with automatic closed-subpath pairing.
(define (morph-to-compound-aligned target destination
                                   #:allow-reverse? [allow-reverse? #t]
                                   #:sample-count [sample-count 64])
  (check-path-morph-request-arguments
   'morph-to-compound-aligned
   target
   destination)
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'morph-to-compound-aligned
     "boolean?"
     allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'morph-to-compound-aligned
     "exact integer greater than or equal to 8"
     sample-count))
  (morph-to-compound-aligned-request
   (visual-target-id target 'morph-to-compound-aligned)
   destination
   allow-reverse?
   sample-count))

; transform-shape : (or/c visual? symbol?)
;                   (and/c visual? affine-visual? opacity-visual?)
;                   [#:mode (or/c 'auto 'morph 'cross-fade)]
;                   [#:correspondence (or/c 'auto 'perimeter 'path)]
;                   [#:allow-reverse? boolean?]
;                   [#:sample-count exact-integer?]
;                   -> transform-shape-request?
;; Replaces a top-level source Visual with destination. In 'auto mode, paths,
;; circles, and rectangles use topology-aware geometric correspondence when
;; possible; unsupported Visuals or incompatible geometry cross-fade. 'morph
;; requires a geometric transition, while 'cross-fade always selects the
;; graceful fallback. `perimeter` gives circle/rectangle pairs a canonical
;; eight-segment contour with matching cardinal anchors; `path`
;; retains the general topology-aware stored-path policy. Source and
;; destination identities must differ.
(define (transform-shape source destination
                         #:mode [mode 'auto]
                         #:correspondence [correspondence 'auto]
                         #:allow-reverse? [allow-reverse? #t]
                         #:sample-count [sample-count 64])
  (unless (or (visual? source) (symbol? source))
    (raise-argument-error 'transform-shape "(or/c visual? symbol?)" source))
  (unless (and (visual? destination)
               (affine-visual? destination)
               (opacity-visual? destination))
    (raise-argument-error
     'transform-shape
     "(and/c visual? affine-visual? opacity-visual?)"
     destination))
  (unless (memq mode '(auto morph cross-fade))
    (raise-argument-error
     'transform-shape
     "(or/c 'auto 'morph 'cross-fade)"
     mode))
  (unless (memq correspondence '(auto perimeter path))
    (raise-argument-error
     'transform-shape
     "(or/c 'auto 'perimeter 'path)"
     correspondence))
  (unless (boolean? allow-reverse?)
    (raise-argument-error 'transform-shape "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     'transform-shape
     "exact integer greater than or equal to 8"
     sample-count))
  (define source-id
    (visual-target-id source 'transform-shape))
  (when (eq? source-id (visual-id destination))
    (raise-arguments-error
     'transform-shape
     "source and destination must have distinct Visual identities"
     "source-id" source-id
     "destination-id" (visual-id destination)))
  (transform-shape-request
   source-id destination mode correspondence allow-reverse? sample-count))

; transform-matching-visuals : visual? (and/c visual? affine-visual? opacity-visual?)
;                              [#:matches (listof visual-match?)]
;                              [#:mode (or/c 'auto 'morph 'cross-fade)]
;                              [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                              [#:allow-reverse? boolean?]
;                              [#:sample-count exact-integer?]
;                              -> transform-matching-visuals-request?
;; Replaces a present top-level Visual with a fresh composite endpoint. The
;; matching passes are deterministic: explicit relative leaf paths, equal
;; relative paths, exact semantic type/style, exact local-shape fingerprints,
;; then nearest compatible geometry. Matched path/circle/rectangle leaves use
;; the established topology-aware shape morph where possible; all other pairs
;; use a moving cross-fade. This deliberately complements, rather than
;; replaces, tagged-formula's glyph-specific matching machinery.
(define (transform-matching-visuals source destination
                                    #:matches [matches '()]
                                    #:mode [mode 'auto]
                                    #:mismatch-mode [mismatch-mode 'fade]
                                    #:allow-reverse? [allow-reverse? #t]
                                    #:sample-count [sample-count 64])
  (unless (visual? source)
    (raise-argument-error 'transform-matching-visuals "visual?" source))
  (unless (and (visual? destination)
               (affine-visual? destination)
               (opacity-visual? destination))
    (raise-argument-error
     'transform-matching-visuals
     "(and/c visual? affine-visual? opacity-visual?)"
     destination))
  (unless (memq mode '(auto morph cross-fade))
    (raise-argument-error
     'transform-matching-visuals
     "(or/c 'auto 'morph 'cross-fade)"
     mode))
  (unless (memq mismatch-mode '(fade fade-transform))
    (raise-argument-error
     'transform-matching-visuals
     "(or/c 'fade 'fade-transform)"
     mismatch-mode))
  (unless (boolean? allow-reverse?)
    (raise-argument-error
     'transform-matching-visuals "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count) (>= sample-count 8))
    (raise-argument-error
     'transform-matching-visuals
     "exact integer greater than or equal to 8"
     sample-count))
  (unless (and (list? matches) (andmap visual-match? matches))
    (raise-argument-error
     'transform-matching-visuals "(listof visual-match?)" matches))
  (for ([match (in-list matches)])
    (check-relative-visual-path
     'transform-matching-visuals (visual-match-source-path match))
    (check-relative-visual-path
     'transform-matching-visuals (visual-match-destination-path match)))
  (define source-id (visual-id source))
  (when (eq? source-id (visual-id destination))
    (raise-arguments-error
     'transform-matching-visuals
     "source and destination must have distinct Visual identities"
     "source-id" source-id
     "destination-id" (visual-id destination)))
  (transform-matching-visuals-request
   source-id destination matches mode mismatch-mode allow-reverse? sample-count))

(define (check-relative-visual-path who path)
  (unless (and (list? path) (andmap symbol? path))
    (raise-argument-error who "(listof symbol?)" path)))

; transform-from-copy : (or/c visual? symbol? visual-path?)
;                       (and/c visual? affine-visual? opacity-visual?)
;                       [#:path-arc finite-real?]
;                       [#:route formula-route?]
;                       -> transform-from-copy-request?
;; Keeps the source Visual visible, then introduces `destination` through a
;; moving cross-fade.  The destination id must be absent at the start of the
;; clip.  `route`, when supplied, overrides the default circular `path-arc`.
(define (transform-from-copy source destination
                             #:path-arc [path-arc 0]
                             #:route [route #f])
  (unless (or (visual? source)
              (symbol? source)
              (visual-path? source))
    (raise-argument-error
     'transform-from-copy
     "(or/c visual? symbol? visual-path?)"
     source))
  (unless (and (visual? destination)
               (affine-visual? destination)
               (opacity-visual? destination))
    (raise-argument-error
     'transform-from-copy
     "(and/c visual? affine-visual? opacity-visual?)"
     destination))
  (define checked-route
    (cond
      [route
       (unless (formula-route? route)
         (raise-argument-error
          'transform-from-copy
          "formula-route?"
          route))
       route]
      [else
       (formula-arc #:angle path-arc)]))
  (transform-from-copy-request
   (visual-target-id source 'transform-from-copy)
   destination
   checked-route))

; circumscribe : (or/c visual? symbol? visual-path? visual-selection?)
;               [#:padding nonnegative-finite-real?]
;               [#:color any/c]
;               [#:stroke-width nonnegative-finite-real?]
;               -> circumscribe-request?
;; Draws a rounded temporary outline around a Visual path, pauses briefly, then
;; erases it. Bounds are measured through the normal Pict renderer so TeX, SVG,
;; text, and composites use their actual rendered extents.
(define (circumscribe target
                      #:padding [padding 1/5]
                      #:color [color "gold"]
                      #:stroke-width [stroke-width 3])
  (make-attention-request
   'circumscribe target padding color stroke-width 'circumscribe))

; indicate : (or/c visual? symbol? visual-path? visual-selection?)
;            [#:padding nonnegative-finite-real?]
;            [#:color any/c]
;            [#:stroke-width nonnegative-finite-real?]
;            -> indicate-request?
;; Pulses a temporary rounded outline around a Visual path without
;; changing that Visual's transform, fill, stroke, or opacity.
(define (indicate target
                  #:padding [padding 1/5]
                  #:color [color "gold"]
                  #:stroke-width [stroke-width 3])
  (make-attention-request
   'indicate target padding color stroke-width 'indicate))

; flash : (or/c visual? symbol? visual-path?) ... -> flash-request?
;; Emits a short radial stroke burst centred on the target's live rendered box.
(define (flash target
               #:radius [radius 1/2]
               #:color [color "gold"]
               #:stroke-width [stroke-width 3])
  (make-attention-request
   'flash target radius color stroke-width 'flash))

; focus-on : (or/c visual? symbol? visual-path? visual-selection?) ...
;             -> focus-on-request?
;; Expands and fades a circular focus ring at the target's live box centre.
(define (focus-on target
                  #:radius [radius 1/2]
                  #:color [color "gold"]
                  #:stroke-width [stroke-width 3])
  (make-attention-request
   'focus-on target radius color stroke-width 'focus-on))

; show-passing-flash : (or/c path-visual? symbol? visual-path?) ...
;; Draws only a moving arc-length sliver of the target's path. The target must
;; resolve to a path Visual when the clip is compiled.
(define (show-passing-flash target
                            #:time-width [time-width 1/5]
                            #:color [color "gold"]
                            #:stroke-width [stroke-width 4])
  (unless (and (finite-real? time-width) (positive? time-width) (<= time-width 1))
    (raise-argument-error
     'show-passing-flash "finite real in (0, 1]" time-width))
  (make-attention-request
   'show-passing-flash target 0 color stroke-width 'show-passing-flash
   #:parameter time-width))

; wiggle : (or/c visual? symbol? visual-path?) ... -> succession-animation-request?
;; A deterministic rotation wiggle that returns exactly to the initial angle.
;; It is intentionally an ordinary composition so it combines with the
;; scheduler and rate-function infrastructure without a special mutable effect.
(define (wiggle target #:angle [angle 1/12] #:cycles [cycles 2])
  (unless (finite-real? angle)
    (raise-argument-error 'wiggle "finite real?" angle))
  (unless (and (exact-integer? cycles) (positive? cycles))
    (raise-argument-error 'wiggle "positive exact integer" cycles))
  (define moves
    (append
     (list (rotate-by target angle))
     (apply append
            (for/list ([index (in-range cycles)])
              (if (= index (sub1 cycles))
                  (list (rotate-by target (* -2 angle))
                        (rotate-by target angle))
                  (list (rotate-by target (* -2 angle))
                        (rotate-by target (* 2 angle))))))))
  ;; Scene owns compositions and imports this module, so obtain its public
  ;; constructor lazily to keep the module graph acyclic.
  (apply (dynamic-require scene-module 'succession) moves))

; grow-from-center : (and/c visual? affine-visual? opacity-visual?)
;;                    -> grow-from-center-request?
;; Introduces a Visual from an invisible, centre-scaled source.
(define (grow-from-center visual)
  (check-grow-visual 'grow-from-center visual)
  (grow-request visual 'center))

; grow-arrow : arrow-visual? -> grow-arrow-request?
;; Introduces an arrow from its shaft start, retaining its exact endpoint form.
(define (grow-arrow visual)
  (unless (arrow-visual? visual)
    (raise-argument-error 'grow-arrow "arrow-visual?" visual))
  (grow-request visual 'arrow))

; draw-border-then-fill : path-visual? -> draw-border-then-fill-request?
;; Reveals a path's border, then fades the original fill in underneath it.
(define (draw-border-then-fill visual)
  (unless (path-visual? visual)
    (raise-argument-error 'draw-border-then-fill "path-visual?" visual))
  (draw-border-then-fill-request visual))

(define (make-attention-request kind target padding color stroke-width who
                                #:parameter [parameter #f])
  (unless (or (visual? target)
              (symbol? target)
              (visual-path? target)
              (visual-selection? target))
    (raise-argument-error
     who
     "(or/c visual? symbol? visual-path? visual-selection?)"
     target))
  (when (and (visual-selection? target)
             (visual-selection-empty? target))
    (raise-arguments-error
     who
     "a nonempty visual selection"
     "selection" target))
  (when (and (visual-selection? target)
             (eq? kind 'show-passing-flash))
    (raise-arguments-error
     who
     "one path Visual rather than a multi-leaf visual selection"
     "selection" target))
  (unless (and (finite-real? padding)
               (not (negative? padding)))
    (raise-argument-error who "nonnegative finite real?" padding))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-argument-error who "nonnegative finite real?" stroke-width))
  (attention-request
   (if (visual-selection? target)
       target
       (visual-target-id target who))
   kind
   padding
   color
   stroke-width
   parameter))

(define (check-grow-visual who visual)
  (unless (and (visual? visual)
               (affine-visual? visual)
               (opacity-visual? visual))
    (raise-argument-error who
                          "(and/c visual? affine-visual? opacity-visual?)"
                          visual)))

; transform-formula-parts : formula-correspondence?
;                         [#:path-arc finite-real?]
;                         [#:part-paths (listof formula-part-path?)]
;                         [#:copies (listof formula-part-copy?)]
;                         [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                         [#:outline-morphs (listof formula-part-outline-morph?)]
;                           -> transform-formula-parts-request?
;; Creates a request that moves and cross-fades explicitly matched parts.
;; `path-arc` applies to every matched part unless a `part-paths` entry selects
;; that correspondence pair explicitly. `mismatch-mode` controls remaining
;; unmatched source/destination pieces. `copies` supplies source-preserving
;; motions for otherwise unmatched destination parts.
(define (transform-formula-parts correspondence
                                 #:path-arc [path-arc 0]
                                 #:part-paths [part-paths '()]
                                 #:copies [copies '()]
                                 #:mismatch-mode [mismatch-mode 'fade]
                                 #:outline-morphs [outline-morphs '()])
  (make-transform-formula-parts-request
   'transform-formula-parts
   correspondence path-arc part-paths copies mismatch-mode outline-morphs #f '() #f))

; transform-formula-parts/anchored : formula-correspondence? formula-part-match?
;                                    [#:path-arc finite-real?]
;                                    [#:part-paths (listof formula-part-path?)]
;                                    [#:copies (listof formula-part-copy?)]
;                                    [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                                    [#:stationary (listof formula-part-match?)]
;                                    -> transform-formula-parts-request?
;;   Internal constructor used by rewrite-formula to align one destination part
;;   to the corresponding part in the current formula when scene-play compiles.
;;   Additional stationary pairs retain their individual current transforms.
(define (transform-formula-parts/anchored correspondence anchor
                                         #:path-arc [path-arc 0]
                                         #:part-paths [part-paths '()]
                                         #:copies [copies '()]
                                         #:mismatch-mode [mismatch-mode 'fade]
                                         #:stationary [stationary '()]
                                         #:outline-morphs [outline-morphs '()])
  (make-transform-formula-parts-request
   'rewrite-formula
   correspondence path-arc part-paths copies mismatch-mode outline-morphs anchor stationary #f))

; make-transform-formula-parts-request : symbol? formula-correspondence?
;                                         finite-real? list? list? list? symbol? list?
;                                         (or/c #f formula-part-match?) list?
;                                         -> transform-formula-parts-request?
;;   Validates the common ordinary and anchored formula-transition inputs.
(define (make-transform-formula-parts-request who correspondence path-arc
                                              part-paths copies mismatch-mode
                                              outline-morphs anchor stationary inspection)
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     who
     "formula-correspondence?"
     correspondence))
  ;; Validate the public route descriptor at construction time. Per-pair
  ;; selection requires the correspondence's current scene state and is
  ;; completed when scene-play compiles the request.
  (formula-arc #:angle path-arc)
  (unless (and (list? part-paths)
               (andmap formula-part-path? part-paths))
    (raise-argument-error
     who
     "(listof formula-part-path?)"
     part-paths))
  (unless (and (list? copies)
               (andmap formula-part-copy? copies))
    (raise-argument-error
     who
     "(listof formula-part-copy?)"
     copies))
  (unless (formula-mismatch-mode? mismatch-mode)
    (raise-argument-error
     who
     "(or/c 'fade 'fade-transform)"
     mismatch-mode))
  (unless (and (list? outline-morphs)
               (andmap formula-part-outline-morph? outline-morphs))
    (raise-argument-error
     who
     "(listof formula-part-outline-morph?)"
     outline-morphs))
  (unless (or (not anchor)
              (formula-part-match? anchor))
    (raise-argument-error
     who
     "(or/c #f formula-part-match?)"
     anchor))
  (unless (and (list? stationary)
               (andmap formula-part-match? stationary))
    (raise-argument-error
     who
     "(listof formula-part-match?)"
     stationary))
  (define correspondence-matches
    (formula-correspondence-matches correspondence))
  (for ([match (in-list stationary)])
    (unless (member match correspondence-matches)
      (raise-arguments-error
       who
       "stationary pairs included in the formula correspondence"
     "stationary" match
      "correspondence" correspondence)))
  (transform-formula-parts-request
   correspondence path-arc part-paths copies mismatch-mode outline-morphs anchor stationary inspection))

; with-animation-inspection : transform-formula-parts-request?
;                             animation-inspection? -> transform-formula-parts-request?
;; Attaches immutable planner data to one formula transition.  This is kept as
;; a separate operation so ordinary animation constructors do not acquire
;; preview-only keywords.
(define (with-animation-inspection request inspection)
  (unless (transform-formula-parts-request? request)
    (raise-argument-error
     'with-animation-inspection
     "transform-formula-parts-request?"
     request))
  (unless (animation-inspection? inspection)
    (raise-argument-error
     'with-animation-inspection
     "animation-inspection?"
     inspection))
  (struct-copy transform-formula-parts-request request
               [inspection inspection]))

; animation-request-inspection : animation-request? -> (or/c #f animation-inspection?)
;; Retrieves inspection data before scene compilation.  Requests without
;; attached explanation data deliberately return #f.
(define (animation-request-inspection request)
  (cond
    [(transform-formula-parts-request? request)
     (transform-formula-parts-request-inspection request)]
    [else #f]))

; compiled-animation-inspection : compiled-animation? -> (or/c #f animation-inspection?)
;; Retrieves one compiled animation's retained explanation data.
(define (compiled-animation-inspection animation)
  (cond
    [(formula-parts-transform-animation? animation)
     (formula-parts-transform-animation-inspection animation)]
    [else #f]))

; create : (or/c path-visual? relation-visual?) -> create-request?
;;   Creates a request that introduces visual by revealing its path prefix.
;;   Relation paths are deferred so their moving dependencies are sampled at
;;   every frame rather than frozen at compilation.
(define (create visual)
  (unless (or (path-visual? visual) (relation-visual? visual))
    (raise-argument-error 'create "(or/c path-visual? relation-visual?)" visual))
  (create-request visual))

; uncreate : (or/c path-visual? relation-visual? symbol? visual-path?)
;;             -> uncreate-request?
;;   Creates a request that hides and then removes a path Visual.
(define (uncreate target)
  (unless (or (symbol? target)
              (visual-path? target)
              (path-visual? target)
              (relation-visual? target))
    (raise-argument-error
     'uncreate
     "(or/c path-visual? relation-visual? symbol? visual-path?)"
     target))
  (uncreate-request (visual-target-id target 'uncreate)))

; write-in : visual?
;            [#:order (or/c 'document 'left-to-right)]
;            [#:lag-ratio (or/c false/c nonnegative-finite-real?)]
;            [#:outline-stroke-width nonnegative-finite-real?]
;            [#:reveal (or/c 'bezier 'arc-length)]
;            [#:reverse? boolean?]
;            [#:rate-func (-> finite-real? finite-real?)]
;            -> write-in-request?
;;   Introduces a vector-capable Visual by tracing every path in document order
;;   (or left-to-right), then fading its final fill and stroke into place.
;;   `bezier` is the Manim-compatible default: each stored path curve consumes
;;   equal reveal time.  The name deliberately avoids Racket's built-in `write`
;;   binding.
(define (write-in visual
                  #:order [order 'document]
                  #:lag-ratio [lag-ratio #f]
                  #:outline-stroke-width [outline-stroke-width 2]
                  #:reveal [reveal 'bezier]
                  #:reverse? [reverse? #f]
                  #:rate-func [rate-func linear])
  (unless (visual? visual)
    (raise-argument-error 'write-in "visual?" visual))
  (unless (memq order '(document left-to-right))
    (raise-argument-error 'write-in "(or/c 'document 'left-to-right)" order))
  (unless (or (not lag-ratio)
              (and (finite-real? lag-ratio)
                   (not (negative? lag-ratio))))
    (raise-argument-error
     'write-in
     "false/c or nonnegative finite real?"
     lag-ratio))
  (unless (and (finite-real? outline-stroke-width)
               (not (negative? outline-stroke-width)))
    (raise-argument-error
     'write-in
     "nonnegative finite real?"
     outline-stroke-width))
  (unless (memq reveal '(bezier arc-length))
    (raise-argument-error 'write-in "(or/c 'bezier 'arc-length)" reveal))
  (unless (boolean? reverse?)
    (raise-argument-error 'write-in "boolean?" reverse?))
  (check-write-rate-func 'write-in rate-func)
  (write-in-request
   (make-write-plan visual
                    order
                    lag-ratio
                    outline-stroke-width
                    reveal
                    reverse?
                    rate-func)))

; unwrite : (or/c visual? symbol? visual-path?)
;           [#:order (or/c 'document 'left-to-right)]
;           [#:lag-ratio (or/c false/c nonnegative-finite-real?)]
;           [#:outline-stroke-width nonnegative-finite-real?]
;           [#:rate-func (-> finite-real? finite-real?)]
;           -> unwrite-request?
;;   Removes a writable Visual by reversing the Manim-like write progression.
;;   Leaves and path traversal both run in reverse.  The target must be present
;;   at the start of the clip.
(define (unwrite target
                 #:order [order 'document]
                 #:lag-ratio [lag-ratio #f]
                 #:outline-stroke-width [outline-stroke-width 2]
                 #:rate-func [rate-func linear])
  (unless (or (visual? target)
              (symbol? target)
              (visual-path? target))
    (raise-argument-error
     'unwrite
     "(or/c visual? symbol? visual-path?)"
     target))
  (unless (memq order '(document left-to-right))
    (raise-argument-error 'unwrite "(or/c 'document 'left-to-right)" order))
  (unless (or (not lag-ratio)
              (and (finite-real? lag-ratio)
                   (not (negative? lag-ratio))))
    (raise-argument-error
     'unwrite
     "false/c or nonnegative finite real?"
     lag-ratio))
  (unless (and (finite-real? outline-stroke-width)
               (not (negative? outline-stroke-width)))
    (raise-argument-error
     'unwrite
     "nonnegative finite real?"
     outline-stroke-width))
  (check-write-rate-func 'unwrite rate-func)
  (unwrite-request
   (visual-target-id target 'unwrite)
   order
   lag-ratio
   outline-stroke-width
   rate-func))

(define (check-write-rate-func who rate-func)
  (unless (and (procedure? rate-func)
               (procedure-arity-includes? rate-func 1))
    (raise-argument-error who "(procedure-arity-includes/c 1)" rate-func)))

;;;
;;; Compilation
;;;

; compile-animation-requests : scene-state? (listof animation-request?)
;                              -> (values scene-state?
;                                         (listof compiled-animation?))
;;   Prepares the clip start state and compiles all requests against it.
(define (compile-animation-requests state requests)
  (unless (scene-state? state)
    (raise-argument-error
     'compile-animation-requests
     "scene-state?"
     state))
  (unless (and (list? requests)
               (andmap animation-request? requests))
    (raise-argument-error
     'compile-animation-requests
     "list of animation requests"
     requests))
  (check-request-component-conflicts requests)
  (define start-state
    (prepare-animation-start-state state requests))
  (values start-state
          (for/list ([request (in-list requests)])
            (compile-animation-request start-state request))))

; prepare-animation-start-state : scene-state? (listof animation-request?)
;                                  -> scene-state?
;;   Adds invisible placeholders for Visuals introduced by structural requests.
(define (prepare-animation-start-state state requests)
  (for/fold ([prepared-state state])
            ([request (in-list requests)])
    (cond
      [(create-request? request)
       (define visual
         (create-request-visual request))
       (define id
         (visual-id visual))
       (check-absent-introduction-target prepared-state id 'create)
       (scene-state-add
        prepared-state
        (if (relation-visual? visual)
            ;; Keep the definition, not a compilation-time concrete path. The
            ;; sampled relation-path-reveal effect supplies an empty prefix at
            ;; clip time zero and the complete definition at completion.
            visual
            (path-visual-with-path visual empty-path-geometry)))]
    [(fade-in-request? request)
       (define visual
         (fade-in-request-visual request))
       (define id
         (visual-id visual))
       (check-absent-introduction-target prepared-state id 'fade-in)
       (scene-state-add
        prepared-state
        (replace-visual-opacity 'scene-play visual 0))]
    [(grow-request? request)
     (define visual (grow-request-visual request))
     (define id (visual-id visual))
     (check-absent-introduction-target prepared-state id 'grow-from-center)
     (scene-state-add
      prepared-state
      (replace-visual-opacity
       'scene-play
       (grow-start-visual visual (grow-request-kind request))
       0))]
    [(draw-border-then-fill-request? request)
     (define visual (draw-border-then-fill-request-visual request))
     (define id (visual-id visual))
     (check-absent-introduction-target prepared-state id 'draw-border-then-fill)
     (scene-state-add
      prepared-state
      (path-visual-with-path visual empty-path-geometry))]
    [(write-in-request? request)
     (define plan
       (write-in-request-plan request))
       (define endpoint
         (write-plan-endpoint plan))
       (define id
         (visual-id endpoint))
       (check-absent-introduction-target prepared-state id 'write-in)
       (scene-state-add
       prepared-state
       (write-plan-sample plan 0))]
      [else
       prepared-state])))

; compile-animation-request : scene-state? animation-request?
;                             -> compiled-animation?
;;   Compiles one request against state.
(define (compile-apply-affine-request state request)
  (define target-id
    (apply-affine-request-target-id request))
  (define path
    (visual-target-path target-id 'apply-affine))
  (define visual
    (scene-state-ref state target-id))
  (when (resolvable-visual? visual)
    (raise-arguments-error
     'scene-play
     "a derived Visual cannot be mapped directly; map its ordinary inputs or output"
     "visual-id" (visual-id visual)))
  (when (frame-space-visual? visual)
    (raise-arguments-error
     'scene-play
     "apply-affine maps world-space Visuals, not frame-space overlays"
     "visual-id" (visual-id visual)))
  (unless (affine-visual? visual)
    (raise-arguments-error
     'scene-play
     "an affine Visual target"
     "visual-path" path
     "visual" visual))
  ;; The public request is always expressed in world coordinates. A nested
  ;; target needs the conjugate local map so parent transforms still produce
  ;; the requested world-space result at every interpolation progress.
  (define parent-map
    (scene-state-parent-affine-map state target-id))
  (define inverse-parent-map
    (affine2-invert parent-map))
  (unless inverse-parent-map
    (raise-arguments-error
     'scene-play
     "a nonsingular enclosing affine map for a nested affine request"
     "visual-path" path
     "parent-map" parent-map))
  (define local-request-map
    (affine2-compose
     inverse-parent-map
     (affine2-compose (apply-affine-request-map request) parent-map)))
  (define-values (content from-map opacity)
    (affine-map-visual-content+map visual))
  (affine-map-animation
   target-id
   content
   from-map
   local-request-map
   opacity))

(define (compile-apply-pointwise-request state request)
  (define target-id
    (apply-pointwise-request-target-id request))
  (define path
    (visual-target-path target-id 'apply-pointwise))
  (define visual
    (scene-state-ref state target-id))
  (when (resolvable-visual? visual)
    (raise-arguments-error
     'scene-play
     "a derived Visual cannot be mapped directly; map its ordinary inputs or output"
     "visual-id" (visual-id visual)))
  (when (frame-space-visual? visual)
    (raise-arguments-error
     'scene-play
     "apply-pointwise maps world-space Visuals, not frame-space overlays"
     "visual-id" (visual-id visual)))
  ;; Resolve the selected path to world coordinates at compilation time. A
  ;; nested result will be rebased through the inverse parent map after every
  ;; sampled deformation, preserving all unaffected siblings and their paths.
  (define parent-map
    (scene-state-parent-affine-map state target-id))
  (define inverse-parent-map
    (affine2-invert parent-map))
  (unless inverse-parent-map
    (raise-arguments-error
     'scene-play
     "a nonsingular enclosing affine map for a nested pointwise request"
     "visual-path" path
     "parent-map" parent-map))
  (pointwise-map-animation
   target-id
   (scene-state-resolved-world-ref state target-id)
   (apply-pointwise-request-map-point request)
   (apply-pointwise-request-samples request)
   (apply-pointwise-request-adaptive? request)
   (apply-pointwise-request-tolerance request)
   (apply-pointwise-request-max-depth request)
   (apply-pointwise-request-discontinuity-mode request)
   parent-map))

(define (compile-apply-homotopy-request state request)
  (define target-id
    (apply-homotopy-request-target-id request))
  (define path
    (visual-target-path target-id 'apply-homotopy))
  (define visual
    (scene-state-ref state target-id))
  (when (resolvable-visual? visual)
    (raise-arguments-error
     'scene-play
     "a derived Visual cannot be mapped directly; map its ordinary inputs or output"
     "visual-id" (visual-id visual)))
  (when (frame-space-visual? visual)
    (raise-arguments-error
     'scene-play
     "apply-homotopy maps world-space Visuals, not frame-space overlays"
     "visual-id" (visual-id visual)))
  ;; Resolve the selected source once in world coordinates. Each frame then
  ;; evaluates H(source-point, alpha) directly and rebases a nested result
  ;; through the inverse enclosing affine map.
  (define parent-map
    (scene-state-parent-affine-map state target-id))
  (define inverse-parent-map
    (affine2-invert parent-map))
  (unless inverse-parent-map
    (raise-arguments-error
     'scene-play
     "a nonsingular enclosing affine map for a nested homotopy request"
     "visual-path" path
     "parent-map" parent-map))
  (homotopy-map-animation
   target-id
   (scene-state-resolved-world-ref state target-id)
   (apply-homotopy-request-homotopy request)
   (apply-homotopy-request-samples request)
   (apply-homotopy-request-adaptive? request)
   (apply-homotopy-request-tolerance request)
   (apply-homotopy-request-max-depth request)
   (apply-homotopy-request-discontinuity-mode request)
   parent-map))

;; Secondary camera leaves compile against the camera stored in their target
;; frame-space Visual. The normal scene camera is unaffected.
(define (compile-camera-view-request state request)
  (define target-id (animation-request-target-id request))
  (define view (scene-state-ref state target-id))
  (unless (camera-view-visual? view)
    (raise-arguments-error
     'scene-play
     "a camera-view Visual target"
     "visual-id" target-id
     "request" request
     "visual" view))
  (define camera (camera-view-visual-camera view))
  (cond
    [(camera-view-pan-to-request? request)
     (camera-view-center-animation target-id
                                   (camera-center camera)
                                   (camera-view-pan-to-request-center request))]
    [(camera-view-pan-by-request? request)
     (camera-view-center-animation
      target-id
      (camera-center camera)
      (vec2+ (camera-center camera)
             (camera-view-pan-by-request-delta request)))]
    [(camera-view-zoom-to-request? request)
     (camera-view-world-width-animation
      target-id
      (camera-world-width camera)
      (camera-view-zoom-to-request-world-width request))]
    [(camera-view-zoom-by-request? request)
     (define destination
       (/ (camera-world-width camera)
          (camera-view-zoom-by-request-factor request)))
     (unless (and (finite-real? destination) (positive? destination))
       (raise-arguments-error
        'scene-play
        "a secondary-camera zoom whose resulting visible width is positive and finite"
        "visual-id" target-id
        "factor" (camera-view-zoom-by-request-factor request)))
     (camera-view-world-width-animation
      target-id (camera-world-width camera) destination)]
    [(camera-view-follow-request? request)
     (define followed
       (scene-state-resolved-world-ref
        state (camera-view-follow-request-followed-target request)))
     (when (frame-space-visual? followed)
       (raise-arguments-error
        'scene-play
        "a world-space secondary-camera follow target"
        "target" (camera-view-follow-request-followed-target request)))
     (camera-view-follow-animation
      target-id
      (camera-view-follow-request-followed-target request)
      (vec2- (camera-center camera) (visual-position followed)))]
    [(camera-view-fit-request? request)
     (camera-view-fit-animation
      target-id
      (camera-center camera)
      (camera-view-fit-request-center request)
      (camera-world-width camera)
      (camera-view-fit-request-world-width request))]
    [else
     (raise-argument-error 'compile-camera-view-request
                           "camera-view animation request" request)]))

(define (compile-animation-request state request)
  (define target-id
    (animation-request-target-id request))
  (cond
    [(transform-shape-request? request)
     (compile-transform-shape-request state request)]
    [(transform-matching-visuals-request? request)
     (compile-transform-matching-visuals-request state request)]
    [(transform-from-copy-request? request)
     (compile-transform-from-copy-request state request)]
    [(attention-request? request)
     (compile-attention-request state request)]
    [(apply-affine-request? request)
     (compile-apply-affine-request state request)]
    [(apply-pointwise-request? request)
     (compile-apply-pointwise-request state request)]
    [(apply-homotopy-request? request)
     (compile-apply-homotopy-request state request)]
    [(or (camera-view-pan-to-request? request)
         (camera-view-pan-by-request? request)
         (camera-view-zoom-to-request? request)
         (camera-view-zoom-by-request? request)
         (camera-view-follow-request? request)
         (camera-view-fit-request? request))
     (compile-camera-view-request state request)]
    [(or (value-to-request? request)
         (change-number-to-request? request)
         (count-to-request? request))
     (define from
       (scene-state-value-ref state target-id))
     (define to
       (cond
         [(value-to-request? request)
          (value-to-request-destination request)]
         [(change-number-to-request? request)
          (change-number-to-request-destination request)]
         [else
          (count-to-request-destination request)]))
     ;; Validate compatibility during compilation, before a scene acquires the
     ;; clip. The result is deliberately discarded; sampling preserves exact
     ;; endpoint representations through interpolate-value.
     (interpolate-value from to 1/2)
     (scalar-value-animation
      target-id
      from
      to)]
    [(count-from-request? request)
     ;; Explicit count endpoints deliberately ignore the preceding state.  The
     ;; scalar-value animation still gives frame t a direct, history-free value.
     (define from (count-from-request-from request))
     (define to (count-from-request-to request))
     (interpolate-value from to 1/2)
     (scalar-value-animation target-id from to)]
    [else
     (define visual
       (scene-state-ref state target-id))
     (when (and (resolvable-visual? visual)
                (not (relation-visual? visual)))
     (raise-arguments-error
        'scene-play
        "derived Visuals are controlled by named scalar values and cannot be animated directly"
        "visual-id" target-id
        "request" request))
     (cond
    [(move-to-request? request)
     (translation-animation target-id
                            (visual-position visual)
                            (move-to-request-destination request))]
    [(move-along-path-request? request)
     (define path
       (resolve-path-animation-route
        state
        visual
        (move-along-path-request-path-source request)
        'move-along-path
        (move-along-path-request-start request)
        (move-along-path-request-end request)))
     (unless (zero? (move-along-path-request-normal-offset request))
       (path-traversal-tangent-at
        path
        (move-along-path-request-start request)
        (move-along-path-request-start request)
        (move-along-path-request-end request))
       (path-traversal-tangent-at
        path
        (move-along-path-request-end request)
        (move-along-path-request-start request)
        (move-along-path-request-end request)))
     (path-motion-animation
      target-id
      path
      (move-along-path-request-start request)
      (move-along-path-request-end request)
      (move-along-path-request-normal-offset request))]
    [(orient-along-path-request? request)
     (check-affine-animation-target visual 'rotation)
     (define path
       (resolve-path-animation-route
        state
        visual
        (orient-along-path-request-path-source request)
        'orient-along-path
        (orient-along-path-request-start request)
        (orient-along-path-request-end request)))
     (path-traversal-tangent-at
      path
      (orient-along-path-request-start request)
      (orient-along-path-request-start request)
      (orient-along-path-request-end request))
     (path-traversal-tangent-at
      path
      (orient-along-path-request-end request)
      (orient-along-path-request-start request)
      (orient-along-path-request-end request))
     (path-orientation-animation
      target-id
      path
      (orient-along-path-request-start request)
      (orient-along-path-request-end request)
      (orient-along-path-request-rotation-offset request))]
    [(rotate-to-request? request)
     (check-affine-animation-target visual 'rotation)
     (rotation-animation target-id
                         (visual-rotation visual)
                         (rotate-to-request-angle request))]
    [(rotate-by-request? request)
     (check-affine-animation-target visual 'rotation)
     (let ([from (visual-rotation visual)])
       (rotation-animation target-id
                           from
                           (+ from (rotate-by-request-delta request))))]
    [(scale-to-request? request)
     (check-affine-animation-target visual 'scale)
     (define to
       (scale-to-request-scale request))
     (check-scale-animation-endpoint visual to)
     (scaling-animation target-id
                        (visual-scale visual)
                        to)]
    [(scale-by-request? request)
     (check-affine-animation-target visual 'scale)
     (define from
       (visual-scale visual))
     (define to
       (vec2* from
              (scale-by-request-factor request)))
     (check-scale-animation-endpoint visual to)
     (scaling-animation target-id from to)]
    [(stroke-width-to-request? request)
     (check-stroke-width-animation-target visual 'stroke-width-to)
     (define to
       (stroke-width-to-request-stroke-width request))
     (replace-visual-stroke-width 'scene-play visual to)
     (stroke-width-animation
      target-id
      (checked-visual-stroke-width 'scene-play visual)
      to)]

    [(fill-color-to-request? request)
     (check-fill-color-animation-target visual 'fill-color-to)
     (define from-paint
       (checked-visual-fill-color 'scene-play visual))
     (define to-paint
       (fill-color-to-request-color request))
     ;; Check the pair during compilation, so a video cannot fail only while
     ;; sampling an interior frame.  Unlike kinds need an explicit cross-fade.
     (paint-lerp from-paint to-paint 1/2)
     (replace-visual-fill-color 'scene-play visual to-paint)
     (fill-color-animation
      target-id
      from-paint
      to-paint)]
    [(stroke-color-to-request? request)
     (check-stroke-color-animation-target visual 'stroke-color-to)
     (define from-spec
       (checked-visual-stroke-color 'scene-play visual))
     (define to-spec
       (stroke-color-to-request-color request))
     (replace-visual-stroke-color 'scene-play visual to-spec)
     (stroke-color-animation
      target-id
      from-spec
      (color-spec->rgba-color from-spec 'scene-play)
      to-spec
      (color-spec->rgba-color to-spec 'scene-play))]
    [(fade-to-request? request)
     (check-opacity-animation-target visual 'fade-to)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        (fade-to-request-opacity request)
                        #f
                        #f)]
    [(fade-in-request? request)
     (define complete-visual
       (fade-in-request-visual request))
     (check-opacity-animation-target complete-visual 'fade-in)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        (checked-visual-opacity 'scene-play complete-visual)
                        #t
                        #f)]
    [(fade-out-request? request)
     (check-opacity-animation-target visual 'fade-out)
     (opacity-animation target-id
                        (checked-visual-opacity 'scene-play visual)
                        0
                        #f
                        #t)]
    [(morph-to-request? request)
     (check-path-morph-target visual 'morph-to)
     (define from-path
       (path-visual-path visual))
     (define to-path
       (morph-to-request-destination request))
     (path-geometry-lerp from-path to-path 0)
     (path-morph-animation target-id
                           from-path
                           to-path)]
    [(morph-to-normalized-request? request)
     (check-path-morph-target visual 'morph-to-normalized)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-normalized-request-destination request))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source destination))
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-aligned-request? request)
     (check-path-morph-target visual 'morph-to-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Interior frames use the aligned traversal, while progress one still
     ;; installs the exact destination representation requested by the caller.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-open-aligned-request? request)
     (check-path-morph-target visual 'morph-to-open-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-open-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-open-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-open-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-open-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Direction alignment is interior correspondence only. Progress one still
     ;; installs the exact destination representation requested by the caller.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-open-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-open-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-open-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-open-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-open-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-open-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Global open-subpath pairing and direction selection are interior
     ;; correspondence only. Progress one installs the exact requested storage.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-mixed-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-mixed-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-mixed-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-mixed-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-mixed-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-mixed-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Topology-class pairing and per-pair direction/phase alignment are
     ;; interior correspondence only. Progress one installs exact requested
     ;; destination storage and subpath ordering.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-topology-changing-request? request)
     (check-path-morph-target visual 'morph-to-topology-changing)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-topology-changing-request-destination request))
     (define-values (prepared-source prepared-destination)
       (path-geometry-prepare-topology-changing-morph
        source
        destination
        #:allow-reverse?
        (morph-to-topology-changing-request-allow-reverse? request)
        #:sample-count
        (morph-to-topology-changing-request-sample-count request)
        #:birth-anchor
        (morph-to-topology-changing-request-birth-anchor request)
        #:death-anchor
        (morph-to-topology-changing-request-death-anchor request)
        #:birth-anchor-map
        (morph-to-topology-changing-request-birth-anchor-map request)
        #:death-anchor-map
        (morph-to-topology-changing-request-death-anchor-map request)
        #:birth-penalty
        (morph-to-topology-changing-request-birth-penalty request)
        #:death-penalty
        (morph-to-topology-changing-request-death-penalty request)
        #:birth-penalty-map
        (morph-to-topology-changing-request-birth-penalty-map request)
        #:death-penalty-map
        (morph-to-topology-changing-request-death-penalty-map request)
        #:match-penalty-map
        (morph-to-topology-changing-request-match-penalty-map request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph
        prepared-source
        prepared-destination))
     ;; Birth/death seeds and correspondence are interior normalization only.
     ;; Exact caller representations remain structural clip endpoints.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(morph-to-compound-aligned-request? request)
     (check-path-morph-target visual 'morph-to-compound-aligned)
     (define source
       (path-visual-path visual))
     (define destination
       (morph-to-compound-aligned-request-destination request))
     (define aligned-destination
       (path-geometry-align-compound-for-morph
        source
        destination
        #:allow-reverse?
        (morph-to-compound-aligned-request-allow-reverse? request)
        #:sample-count
        (morph-to-compound-aligned-request-sample-count request)))
     (define-values (normalized-source normalized-destination)
       (path-geometry-normalize-for-morph source aligned-destination))
     ;; Pairing and per-loop alignment are interior correspondence only. The
     ;; exact caller-requested destination storage is installed at progress one.
     (normalized-path-morph-animation
      target-id
      source
      normalized-source
      normalized-destination
      destination)]
    [(transform-formula-parts-request? request)
     (check-formula-transform-target visual)
     (define correspondence
       (anchor-formula-correspondence
        visual
        (transform-formula-parts-request-correspondence request)
        (transform-formula-parts-request-anchor request)
        (transform-formula-parts-request-stationary request)))
     (define transition-plan
       (make-formula-transition-plan
        visual
        correspondence
        #:path-arc (transform-formula-parts-request-path-arc request)
        #:part-paths (transform-formula-parts-request-part-paths request)
        #:copies (transform-formula-parts-request-copies request)
        #:mismatch-mode
        (transform-formula-parts-request-mismatch-mode request)
        #:outline-morphs
        (transform-formula-parts-request-outline-morphs request)))
     (formula-parts-transform-animation
      target-id
      transition-plan
      (string-transition-inspection-with-compiled-plan
       (transform-formula-parts-request-inspection request)
       target-id
       transition-plan))]
    [(grow-request? request)
     (define destination (grow-request-visual request))
     (grow-animation target-id visual destination (grow-request-kind request))]
    [(draw-border-then-fill-request? request)
     (define destination (draw-border-then-fill-request-visual request))
     (check-path-animation-target destination 'draw-border-then-fill)
     (border-fill-animation target-id destination)]
    [(create-request? request)
     (define complete-visual
       (create-request-visual request))
     (if (relation-visual? complete-visual)
         (relation-path-reveal-animation target-id #f #f)
         (begin
           (check-path-animation-target complete-visual 'create)
           (path-reveal-animation target-id
                                  (path-visual-path complete-visual)
                                  0
                                  1
                                  #f)))]
    [(uncreate-request? request)
     (if (relation-visual? visual)
         (relation-path-reveal-animation target-id #t #t)
         (begin
           (check-path-animation-target visual 'uncreate)
           (path-reveal-animation target-id
                                  (path-visual-path visual)
                                  1
                                  0
                                  #t)))]
    [(write-in-request? request)
     (write-in-animation target-id
                         (write-in-request-plan request)
                         (write-plan-reverse?
                          (write-in-request-plan request))
                         #f)]
    [(unwrite-request? request)
     ;; Resolve the current scene Visual now so unwrite uses any styles or
     ;; geometry produced by preceding clips rather than caller-side data.
     (define plan
       (make-write-plan visual
                        (unwrite-request-order request)
                        (unwrite-request-lag-ratio request)
                        (unwrite-request-outline-stroke-width request)
                        'bezier
                        #t
                        (unwrite-request-rate-func request)))
     (write-in-animation target-id plan #t #t)]
    [else
     (raise-argument-error
      'compile-animation-request
      "animation request"
      request)])]))

; compile-transform-shape-request : scene-state? transform-shape-request?
;                                    -> transform-shape-animation?
;; Chooses a geometric interior only when both endpoints can be represented by
;; one atomic path. The automatic policy deliberately degrades to a visual
;; cross-fade instead of exposing low-level contour restrictions to a diagram
;; author.
(define (compile-transform-shape-request state request)
  (define source-id
    (transform-shape-request-source-id request))
  (define destination
    (transform-shape-request-destination request))
  (define destination-id
    (visual-id destination))
  (unless (scene-state-has? state source-id)
    (raise-arguments-error
     'transform-shape
     "a source Visual present at the start of the clip"
     "source-id" source-id))
  (check-absent-introduction-target state destination-id 'transform-shape)
  (define source
    (scene-state-ref state source-id))
  (when (resolvable-visual? source)
    (raise-arguments-error
     'transform-shape
     "a non-derived source Visual"
     "source-id" source-id
     "source" source))
  (unless (and (affine-visual? source)
               (opacity-visual? source))
    (raise-arguments-error
     'transform-shape
     "a source Visual that supports affine placement and opacity"
     "source-id" source-id
     "source" source))
  (define morph-paths
    (case (transform-shape-request-mode request)
      [(cross-fade) #f]
      [else
       (make-transform-shape-morph-paths
        source
        destination
        (transform-shape-request-correspondence request)
        (transform-shape-request-allow-reverse? request)
        (transform-shape-request-sample-count request))]))
  (when (and (eq? (transform-shape-request-mode request) 'morph)
             (not morph-paths))
    (raise-arguments-error
     'transform-shape
     "two atomic path, circle, or rectangle Visuals whose outlines can be morphed"
     "source-id" source-id
     "source" source
     "destination" destination))
  (define overlay-id
    (transform-shape-overlay-id source-id destination-id))
  (check-absent-introduction-target state overlay-id 'transform-shape)
  (transform-shape-animation
   source-id
   source
   destination
   overlay-id
   (and morph-paths (car morph-paths))
   (and morph-paths (cdr morph-paths))))

; compile-transform-matching-visuals-request
; : scene-state? transform-matching-visuals-request?
;   -> transform-matching-visuals-animation?
;; The source is fetched from the current start state, not trusted from the
;; construction-time value. This preserves the usual scene-play semantics when
;; an earlier clip has moved or styled the composite before it is matched.
(define (compile-transform-matching-visuals-request state request)
  (define source-id
    (transform-matching-visuals-request-source-id request))
  (define destination
    (transform-matching-visuals-request-destination request))
  (define destination-id (visual-id destination))
  (unless (scene-state-has? state source-id)
    (raise-arguments-error
     'transform-matching-visuals
     "a source Visual present at the start of the clip"
     "source-id" source-id))
  (check-absent-introduction-target state destination-id
                                    'transform-matching-visuals)
  (define source (scene-state-ref state source-id))
  (unless (and (affine-visual? source) (opacity-visual? source))
    (raise-arguments-error
     'transform-matching-visuals
     "a source Visual that supports affine placement and opacity"
     "source-id" source-id
     "source" source))
  (define source-leaves (flatten-matching-visual-leaves source))
  (define destination-leaves (flatten-matching-visual-leaves destination))
  (check-matching-leaf-protocol 'transform-matching-visuals source-leaves)
  (check-matching-leaf-protocol 'transform-matching-visuals destination-leaves)
  (define specs
    (make-visual-match-specs
     source-leaves
     destination-leaves
     (transform-matching-visuals-request-matches request)
     (transform-matching-visuals-request-mode request)
     (transform-matching-visuals-request-mismatch-mode request)
     (transform-matching-visuals-request-allow-reverse? request)
     (transform-matching-visuals-request-sample-count request)))
  (define overlay-id
    (transform-matching-visuals-overlay-id source-id destination-id))
  (check-absent-introduction-target state overlay-id
                                    'transform-matching-visuals)
  (transform-matching-visuals-animation
   source-id source destination overlay-id specs))

;; Each leaf path is relative to the matching root. Group transforms are
;; resolved before recursing, which places the overlay leaves in the same world
;; coordinate system as their original top-level roots.
(struct matching-visual-leaf (path visual) #:transparent)

(define (flatten-matching-visual-leaves visual [path '()])
  (cond
    [(group-visual? visual)
     (apply append
            (for/list ([child
                        (in-list (group-visual-resolved-children visual))])
              (flatten-matching-visual-leaves
               child
               (append path (list (visual-id child))))))]
    [else (list (matching-visual-leaf path visual))]))

(define (check-matching-leaf-protocol who leaves)
  (for ([leaf (in-list leaves)])
    (define visual (matching-visual-leaf-visual leaf))
    (unless (and (affine-visual? visual) (opacity-visual? visual))
      (raise-arguments-error
       who
       "matching leaves supporting affine placement and opacity"
       "path" (matching-visual-leaf-path leaf)
       "visual" visual))))

;; make-visual-match-specs : leaves leaves matches symbol symbol boolean integer
;;                            -> (listof visual-match-spec?)
;; Applies the public hierarchy in fixed, deterministic passes. A leaf is used
;; at most once. Equal paths make ordinary diagrams stable under reordering;
;; geometry is only a final conservative fallback for shape leaves.
(define (make-visual-match-specs source-leaves destination-leaves explicit-matches
                                 mode mismatch-mode allow-reverse? sample-count)
  (define source-by-path
    (for/hash ([leaf (in-list source-leaves)])
      (values (matching-visual-leaf-path leaf) leaf)))
  (define destination-by-path
    (for/hash ([leaf (in-list destination-leaves)])
      (values (matching-visual-leaf-path leaf) leaf)))
  (define used-source (make-hash))
  (define used-destination (make-hash))
  (define pairs '())
  (define (used? table leaf) (hash-has-key? table (matching-visual-leaf-path leaf)))
  (define (record-pair! source destination)
    (when (used? used-source source)
      (raise-arguments-error
       'transform-matching-visuals
       "each source leaf matched at most once"
       "source-path" (matching-visual-leaf-path source)))
    (when (used? used-destination destination)
      (raise-arguments-error
       'transform-matching-visuals
       "each destination leaf matched at most once"
       "destination-path" (matching-visual-leaf-path destination)))
    (hash-set! used-source (matching-visual-leaf-path source) #t)
    (hash-set! used-destination (matching-visual-leaf-path destination) #t)
    (set! pairs (append pairs (list (cons source destination)))))
  ;; 1. Explicit author intent always wins.
  (for ([match (in-list explicit-matches)])
    (define source
      (hash-ref source-by-path (visual-match-source-path match) #f))
    (define destination
      (hash-ref destination-by-path (visual-match-destination-path match) #f))
    (unless source
      (raise-arguments-error
       'transform-matching-visuals
       "an explicit source leaf path in the source Visual"
       "source-path" (visual-match-source-path match)))
    (unless destination
      (raise-arguments-error
       'transform-matching-visuals
       "an explicit destination leaf path in the destination Visual"
       "destination-path" (visual-match-destination-path match)))
    (record-pair! source destination))
  (define (remaining leaves used)
    (filter (lambda (leaf) (not (used? used leaf))) leaves))
  ;; 2. Equal nested paths are semantic identities below the replaced roots.
  (for ([source (in-list (remaining source-leaves used-source))])
    (define destination
      (hash-ref destination-by-path (matching-visual-leaf-path source) #f))
    (when (and destination (not (used? used-destination destination)))
      (record-pair! source destination)))
  ;; 3. Exact kind/style gives common diagram symbols a stable pairing even
  ;; when a parent reorders or renames them.
  (match-leaves-by-key!
   remaining used-source used-destination record-pair!
   visual-semantic-style-key source-leaves destination-leaves)
  ;; 4. A local-shape fingerprint catches identical unstyled glyph/path forms
  ;; left over after a style change.
  (match-leaves-by-key!
   remaining used-source used-destination record-pair!
   visual-fingerprint source-leaves destination-leaves)
  ;; 5. Pair remaining compatible geometry by nearest world-space reference
  ;; point. This permits, for example, a circle/rectangle semantic shape morph.
  (match-compatible-leaves-by-distance!
   remaining used-source used-destination record-pair!
   source-leaves destination-leaves)
  ;; An explicit mismatch policy remains useful when an author wants Manim's
  ;; moving cross-fade for otherwise incomparable leaf kinds.
  (when (eq? mismatch-mode 'fade-transform)
    (match-any-leaves-by-distance!
     remaining used-source used-destination record-pair!
     source-leaves destination-leaves))
  (define paired-specs
    (for/list ([pair (in-list pairs)])
      (make-one-visual-match-spec (car pair) (cdr pair)
                                  mode allow-reverse? sample-count)))
  (append
   paired-specs
   (for/list ([source (in-list (remaining source-leaves used-source))])
     (visual-match-spec (matching-visual-leaf-visual source) #f #f #f))
   (for/list ([destination (in-list (remaining destination-leaves used-destination))])
     (visual-match-spec #f (matching-visual-leaf-visual destination) #f #f))))

(define (match-leaves-by-key! remaining used-source used-destination record-pair!
                              key source-leaves destination-leaves)
  (for ([source (in-list (remaining source-leaves used-source))])
    (define source-key (key (matching-visual-leaf-visual source)))
    (when source-key
      (define destination
        (for/first ([candidate
                     (in-list (remaining destination-leaves used-destination))]
                    #:when (equal? source-key
                                   (key (matching-visual-leaf-visual candidate))))
          candidate))
      (when destination (record-pair! source destination)))))

(define (match-compatible-leaves-by-distance! remaining used-source used-destination
                                              record-pair! source-leaves destination-leaves)
  (for ([source (in-list (remaining source-leaves used-source))])
    (define source-visual (matching-visual-leaf-visual source))
    (when (matching-shape-visual? source-visual)
      (define destination
        (nearest-matching-leaf
         source
         (filter (lambda (candidate)
                   (matching-shape-visual?
                    (matching-visual-leaf-visual candidate)))
                 (remaining destination-leaves used-destination))))
      (when destination (record-pair! source destination)))))

(define (match-any-leaves-by-distance! remaining used-source used-destination
                                       record-pair! source-leaves destination-leaves)
  (for ([source (in-list (remaining source-leaves used-source))])
    (define destination
      (nearest-matching-leaf source
                             (remaining destination-leaves used-destination)))
    (when destination (record-pair! source destination))))

(define (nearest-matching-leaf source candidates)
  (and (pair? candidates)
       (argmin
        (lambda (candidate)
          (matching-leaf-distance source candidate))
        candidates)))

(define (matching-leaf-distance source destination)
  (define delta
    (vec2- (visual-position (matching-visual-leaf-visual source))
           (visual-position (matching-visual-leaf-visual destination))))
  (+ (* (vec2-x delta) (vec2-x delta))
     (* (vec2-y delta) (vec2-y delta))))

(define (matching-shape-visual? visual)
  (or (path-visual? visual) (circle-visual? visual) (rectangle-visual? visual)))

(define (visual-semantic-style-key visual)
  (define kind
    (cond [(path-visual? visual) 'path]
          [(circle-visual? visual) 'circle]
          [(rectangle-visual? visual) 'rectangle]
          [else #f]))
  (and kind
       (list kind
             (with-handlers ([exn:fail? (lambda (_ignored) #f)])
               (visual-fill-color visual))
             (with-handlers ([exn:fail? (lambda (_ignored) #f)])
               (visual-stroke-color visual))
             (with-handlers ([exn:fail? (lambda (_ignored) #f)])
               (visual-stroke-width visual)))))

(define (visual-fingerprint visual)
  (cond
    [(path-visual? visual) (list 'path (path-visual-path visual))]
    [(circle-visual? visual) (list 'circle (circle-visual-radius visual))]
    [(rectangle-visual? visual)
     (list 'rectangle (rectangle-visual-width visual)
           (rectangle-visual-height visual))]
    [else #f]))

(define (make-one-visual-match-spec source-leaf destination-leaf
                                    mode allow-reverse? sample-count)
  (define source (matching-visual-leaf-visual source-leaf))
  (define destination (matching-visual-leaf-visual destination-leaf))
  (define morph-paths
    (case mode
      [(cross-fade) #f]
      [else
       (make-transform-shape-morph-paths source destination 'auto
                                         allow-reverse? sample-count)]))
  (when (and (eq? mode 'morph) (not morph-paths))
    (raise-arguments-error
     'transform-matching-visuals
     "matched atomic path, circle, or rectangle leaves whose outlines can be morphed"
     "source" source
     "destination" destination))
  (visual-match-spec source destination
                     (and morph-paths (car morph-paths))
                     (and morph-paths (cdr morph-paths))))

(define (transform-matching-visuals-overlay-id source-id destination-id)
  (string->symbol
   (format "__transform-matching-visuals-~s-to-~s" source-id destination-id)))

; make-transform-shape-morph-paths : visual? visual? symbol? boolean? exact-integer?
;                                     -> (or/c false/c (cons/c path-geometry?
;                                                                  path-geometry?))
;; Returns normalized interiors for the broadest safe built-in shape morph. A
;; failure means the caller can choose a cross-fade rather than committing a
;; timeline with malformed or non-corresponding contours.
(define (make-transform-shape-morph-paths source destination correspondence allow-reverse?
                                          sample-count)
  (define (normalize source-path destination-path)
    (define-values (normalized-source normalized-destination)
      (path-geometry-normalize-for-morph source-path destination-path))
    (cons normalized-source normalized-destination))
  (define primitive-perimeter-paths
    (and (memq correspondence '(auto perimeter))
         (primitive-perimeter-morph-paths source destination normalize)))
  (cond
    [primitive-perimeter-paths primitive-perimeter-paths]
    [(eq? correspondence 'perimeter) #f]
    [else
     (define source-path-visual
       (transform-shape-path-proxy source))
     (define destination-path-visual
       (transform-shape-path-proxy destination))
     (and source-path-visual
          destination-path-visual
          (with-handlers ([exn:fail? (lambda (ignored) #f)])
            (define source-path
              (path-visual-path source-path-visual))
            (define destination-path
              (path-visual-path destination-path-visual))
            ;; Prefer the no-birth/death pairing, which selects the best
            ;; closed-loop phase and open-path direction. When topologies
            ;; differ, fall through to seeded births/deaths.
            (or (with-handlers ([exn:fail? (lambda (ignored) #f)])
                  (normalize
                   source-path
                   (path-geometry-align-mixed-compound-for-morph
                    source-path
                    destination-path
                    #:allow-reverse? allow-reverse?
                    #:sample-count sample-count)))
                (let ()
                  (define-values (prepared-source prepared-destination)
                    (path-geometry-prepare-topology-changing-morph
                     source-path
                     destination-path
                     #:allow-reverse? allow-reverse?
                     #:sample-count sample-count))
                  (normalize prepared-source prepared-destination)))))]))

; primitive-perimeter-morph-paths : visual? visual?
;                                  (-> path-geometry? path-geometry? pair?)
;                                  -> (or/c false/c pair?)
;; Circle and rectangle primitives have a useful semantic correspondence that
;; stored SVG/path order cannot infer: the right midpoint and the matching
;; eighth-perimeter positions.  This is the contour preparation used
;; for an evenly rounded square-to-circle transformation.
(define (primitive-perimeter-morph-paths source destination normalize)
  (define source-proxy (primitive-perimeter-proxy source))
  (define destination-proxy (primitive-perimeter-proxy destination))
  (and source-proxy
       destination-proxy
       (with-handlers ([exn:fail? (lambda (ignored) #f)])
         (normalize (path-visual-path source-proxy)
                    (path-visual-path destination-proxy)))))

; transform-shape-path-proxy : visual? -> (or/c false/c path-visual?)
;; The generic shape operation intentionally has a small structural contract:
;; one painted path (including circle/rectangle primitives). Groups and custom
;; Visuals retain their exact rendering through the cross-fade fallback.
(define (transform-shape-path-proxy visual)
  (cond
    [(path-visual? visual) visual]
    [(circle-visual? visual) (write-circle-proxy visual)]
    [(rectangle-visual? visual) (write-rectangle-proxy visual)]
    [else #f]))

; primitive-perimeter-proxy : visual? -> (or/c false/c path-visual?)
;; A separate proxy keeps write-in's document-order paths untouched. Its eight
;; segments begin at the right midpoint and visit matching cardinal/corner
;; perimeter locations for both supported primitive families.
(define (primitive-perimeter-proxy visual)
  (cond
    [(circle-visual? visual)
     (make-primitive-perimeter-proxy
      visual
      (primitive-circle-perimeter-path (circle-visual-radius visual))
      (circle-visual-fill visual)
      (circle-visual-stroke visual)
      (circle-visual-stroke-width visual))]
    [(rectangle-visual? visual)
     (make-primitive-perimeter-proxy
      visual
      (primitive-rectangle-perimeter-path
       (rectangle-visual-width visual)
       (rectangle-visual-height visual))
      (rectangle-visual-fill visual)
      (rectangle-visual-stroke visual)
      (rectangle-visual-stroke-width visual))]
    [else #f]))

(define (make-primitive-perimeter-proxy visual path fill stroke stroke-width)
  (make-path-visual
   path
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill fill
   #:stroke stroke
   #:stroke-width stroke-width))

(define (primitive-rectangle-perimeter-path width height)
  (define half-width (/ width 2))
  (define half-height (/ height 2))
  ;; Closed subpaths have an implicit final closing edge.  Make this edge
  ;; explicit here so all eight rectangle eighths correspond directly to the
  ;; eight cubic circle arcs below.  Leaving it implicit would make generic
  ;; path normalization split an unrelated edge, which produces a lopsided
  ;; halfway contour.
  (define anchors
    (list (vec2 half-width 0)
          (vec2 half-width half-height)
          (vec2 0 half-height)
          (vec2 (- half-width) half-height)
          (vec2 (- half-width) 0)
          (vec2 (- half-width) (- half-height))
          (vec2 0 (- half-height))
          (vec2 half-width (- half-height))))
  (path-geometry
   (list
    (path-subpath
     (car anchors)
     (for/list ([point (in-list (append (cdr anchors)
                                         (list (car anchors))))])
       (line-path-segment point))
     #t))))

(define (primitive-circle-perimeter-path radius)
  ;; One 45-degree cubic segment has this tangent length relative to its
  ;; radius. Keeping the same eight cardinal/diagonal anchors as rectangles
  ;; gives each square corner an equal share of the interpolation.
  (define root-half 0.7071067811865476)
  (define k 0.265216489839544)
  (define anchors
    (list (vec2 radius 0)
          (vec2 (* radius root-half) (* radius root-half))
          (vec2 0 radius)
          (vec2 (* -1 radius root-half) (* radius root-half))
          (vec2 (- radius) 0)
          (vec2 (* -1 radius root-half) (* -1 radius root-half))
          (vec2 0 (- radius))
          (vec2 (* radius root-half) (* -1 radius root-half))))
  (define (tangent point)
    (vec2 (- (vec2-y point)) (vec2-x point)))
  (define (next points)
    (append (cdr points) (list (car points))))
  (path-geometry
   (list
    (path-subpath
     (car anchors)
     (for/list ([from (in-list anchors)]
                [to (in-list (next anchors))])
       (cubic-bezier-path-segment
        (vec2+ from (vec2-scale k (tangent from)))
        (vec2- to (vec2-scale k (tangent to)))
        to))
     #t))))

(define (transform-shape-overlay-id source-id destination-id)
  (string->symbol
   (format "__transform-shape-~s-to-~s" source-id destination-id)))

(define (compile-transform-from-copy-request state request)
  (define source-target
    (transform-from-copy-request-source-id request))
  (define source-path
    (visual-target-path source-target 'transform-from-copy))
  (define destination
    (transform-from-copy-request-destination request))
  (define destination-id
    (visual-id destination))
  (check-absent-introduction-target
   state destination-id 'transform-from-copy)
  ;; A nested source becomes an independent temporary top-level layer, so its
  ;; enclosing group/formula transforms and opacities must be composed first.
  (define source-root
    (scene-state-ref state (car source-path)))
  (when (resolvable-visual? source-root)
    (raise-arguments-error
     'transform-from-copy
     "a non-derived source Visual"
     "source-path" source-path
     "source" source-root))
  (define source
    (scene-state-resolved-world-ref state source-path))
  (unless (and (affine-visual? source)
               (opacity-visual? source))
    (raise-arguments-error
     'transform-from-copy
     "a source Visual that supports affine placement and opacity"
     "source-path" source-path
     "source" source))
  (transform-from-copy-animation
   source
   destination
   (transform-from-copy-request-route request)
   (copy-overlay-id destination-id)))

(define (copy-overlay-id destination-id)
  (string->symbol
   (string-append "__transform-from-copy-"
                  (symbol->string destination-id))))

(define (compile-attention-request state request)
  (define target
    (attention-request-target-id request))
  (define target-paths
    (if (visual-selection? target)
        (visual-selection-absolute-paths target)
        (list (visual-target-path target (attention-request-kind request)))))
  (for ([target-path (in-list target-paths)])
    (unless (scene-state-has? state target-path)
      (raise-arguments-error
       (attention-request-kind request)
       "a Visual present at every requested selection path in the scene"
       "target-path" target-path)))
  (define overlay-id
    (attention-overlay-id target-paths (attention-request-kind request)))
  (check-absent-introduction-target state overlay-id (attention-request-kind request))
  (attention-animation
   overlay-id
   target-paths
   (attention-request-kind request)
   (attention-request-padding request)
   (attention-request-color request)
   (attention-request-stroke-width request)
   (attention-request-parameter request)))

(define (attention-overlay-id target-paths kind)
  (string->symbol
   (format "__~a-~s" kind target-paths)))

(define (make-attention-outline id box padding color stroke-width)
  (define half-width
    (+ (/ (renderer-layout-box-width box) 2) padding))
  (define half-height
    (+ (/ (renderer-layout-box-height box) 2) padding))
  (make-path-visual
   (rounded-rectangle-path half-width half-height)
   #:id id
   #:center (renderer-layout-box-center box)
   #:fill #f
   #:stroke color
   #:stroke-width stroke-width))

;; Relative layout intentionally lives at the Pict-adapter boundary. Loading
;; its procedures only when attention is compiled avoids a static dependency
;; cycle through tagged-formula -> animation while still measuring exactly what
;; the renderer will draw.
(define-runtime-path relative-layout-module "relative-layout.rkt")
(define-runtime-path scene-module "scene.rkt")

(define (relative-layout-procedure name)
  (dynamic-require relative-layout-module name))

(define (renderer-layout-box visual)
  ((relative-layout-procedure 'visual-layout-box) visual))

(define (renderer-layout-boxes visuals)
  ((relative-layout-procedure 'visuals-layout-box) visuals))

(define (renderer-layout-box-width box)
  ((relative-layout-procedure 'layout-box-width) box))

(define (renderer-layout-box-height box)
  ((relative-layout-procedure 'layout-box-height) box))

(define (renderer-layout-box-center box)
  ((relative-layout-procedure 'layout-box-center) box))

(define (rounded-rectangle-path half-width half-height)
  (define radius
    (min 1/4 half-width half-height))
  (define k
    (* radius 0.5522847498307936))
  (define left (- half-width))
  (define right half-width)
  (define bottom (- half-height))
  (define top half-height)
  (if (zero? radius)
      (polygon-path
       (list (vec2 left bottom)
             (vec2 right bottom)
             (vec2 right top)
             (vec2 left top)))
      (path-geometry
       (list
        (path-subpath
         (vec2 (- right radius) bottom)
         (list
          (line-path-segment (vec2 (+ left radius) bottom))
          (cubic-bezier-path-segment
           (vec2 (+ left radius (- k)) bottom)
           (vec2 left (+ bottom radius (- k)))
           (vec2 left (+ bottom radius)))
          (line-path-segment (vec2 left (- top radius)))
          (cubic-bezier-path-segment
           (vec2 left (+ top (- radius) k))
           (vec2 (+ left radius (- k)) top)
           (vec2 (+ left radius) top))
          (line-path-segment (vec2 (- right radius) top))
          (cubic-bezier-path-segment
           (vec2 (+ right (- radius) k) top)
           (vec2 right (+ top (- radius) k))
           (vec2 right (- top radius)))
          (line-path-segment (vec2 right (+ bottom radius)))
          (cubic-bezier-path-segment
           (vec2 right (+ bottom radius (- k)))
           (vec2 (+ right (- radius) k) bottom)
           (vec2 (- right radius) bottom)))
         #t)))))

; check-request-component-conflicts : (listof animation-request?) -> void?
;;   Rejects duplicate updates to one animation component in a play clip.
(define (check-request-component-conflicts requests)
  (define keys
    (for*/list ([request (in-list requests)]
                [target-id (in-list (animation-request-affected-ids request))]
                [component
                 (in-list (animation-request-components request))])
      (cons target-id
            component)))
  (define duplicate-key
    (find-duplicate-key keys))
  (when duplicate-key
    (raise-arguments-error
     'scene-play
     "two simultaneous animations target the same animation component"
     "target-id" (car duplicate-key)
     "component" (cdr duplicate-key))))

; animation-request-affected-ids : animation-request? -> (listof symbol?)
;; Most requests change one identity. Shape replacement also reserves the
;; destination identity, which prevents a simultaneous introduction or a second
;; replacement from silently colliding at the clip boundary.
(define (animation-request-affected-ids request)
  (cond
    [(transform-shape-request? request)
     (list (transform-shape-request-source-id request)
           (visual-id (transform-shape-request-destination request)))]
    [(transform-matching-visuals-request? request)
     (list (transform-matching-visuals-request-source-id request)
           (visual-id
            (transform-matching-visuals-request-destination request)))]
    [(attention-request? request)
     (define target (attention-request-target-id request))
     (if (visual-selection? target)
         (list (car (visual-selection-root target)))
         (list target))]
    [else (list (animation-request-target-id request))]))

; find-duplicate-key : list? -> any/c
;;   Returns the first duplicate key or #f when all keys are distinct.
(define (find-duplicate-key keys)
  (let loop ([remaining keys]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))

; animation-request? : any/c -> boolean?
;;   Reports whether value is a supported uncompiled animation request.
(define (animation-request? value)
  (or (value-to-request? value)
      (change-number-to-request? value)
      (count-to-request? value)
      (count-from-request? value)
      (move-to-request? value)
      (move-along-path-request? value)
      (orient-along-path-request? value)
      (rotate-to-request? value)
      (rotate-by-request? value)
      (scale-to-request? value)
      (scale-by-request? value)
      (apply-affine-request? value)
      (apply-pointwise-request? value)
      (apply-homotopy-request? value)
      (stroke-width-to-request? value)
      (fill-color-to-request? value)
      (stroke-color-to-request? value)
      (fade-to-request? value)
      (fade-in-request? value)
      (fade-out-request? value)
      (camera-view-pan-to-request? value)
      (camera-view-pan-by-request? value)
      (camera-view-zoom-to-request? value)
      (camera-view-zoom-by-request? value)
      (camera-view-follow-request? value)
      (camera-view-fit-request? value)
      (morph-to-request? value)
      (morph-to-normalized-request? value)
      (morph-to-aligned-request? value)
      (morph-to-open-aligned-request? value)
      (morph-to-open-compound-aligned-request? value)
      (morph-to-mixed-compound-aligned-request? value)
      (morph-to-topology-changing-request? value)
      (morph-to-compound-aligned-request? value)
      (transform-shape-request? value)
      (transform-matching-visuals-request? value)
      (transform-from-copy-request? value)
      (attention-request? value)
      (grow-request? value)
      (draw-border-then-fill-request? value)
      (transform-formula-parts-request? value)
      (create-request? value)
      (uncreate-request? value)
      (write-in-request? value)
      (unwrite-request? value)))

; animation-request-default-duration : animation-request? -> (or/c false/c
;                                                              positive-real?)
;; Gives an optional duration preference for a request when the caller omits
;; scene-play's #:duration.  This deliberately mirrors Manim Write's small
;; family heuristic without changing the historical one-second default of every
;; other animation type.
(define (animation-request-default-duration request)
  (unless (animation-request? request)
    (raise-argument-error
     'animation-request-default-duration
     "animation-request?"
     request))
  (cond
    [(write-in-request? request)
     (if (< (length (write-plan-leaves
                     (write-in-request-plan request)))
            15)
         1
         2)]
    [else #f]))

; animation-request-target-id : animation-request? -> symbol?
;;   Returns the stable target id of request.
(define (animation-request-target-id request)
  (cond
    [(value-to-request? request)
     (value-to-request-target-id request)]
    [(change-number-to-request? request)
     (change-number-to-request-target-id request)]
    [(count-to-request? request)
     (count-to-request-target-id request)]
    [(count-from-request? request)
     (count-from-request-target-id request)]
    [(move-to-request? request)
     (move-to-request-target-id request)]
    [(move-along-path-request? request)
     (move-along-path-request-target-id request)]
    [(orient-along-path-request? request)
     (orient-along-path-request-target-id request)]
    [(rotate-to-request? request)
     (rotate-to-request-target-id request)]
    [(rotate-by-request? request)
     (rotate-by-request-target-id request)]
    [(scale-to-request? request)
     (scale-to-request-target-id request)]
    [(scale-by-request? request)
     (scale-by-request-target-id request)]
    [(apply-affine-request? request)
     (apply-affine-request-target-id request)]
    [(apply-pointwise-request? request)
     (apply-pointwise-request-target-id request)]
    [(apply-homotopy-request? request)
     (apply-homotopy-request-target-id request)]
    [(stroke-width-to-request? request)
     (stroke-width-to-request-target-id request)]
    [(fill-color-to-request? request)
     (fill-color-to-request-target-id request)]
    [(stroke-color-to-request? request)
     (stroke-color-to-request-target-id request)]
    [(fade-to-request? request)
     (fade-to-request-target-id request)]
    [(fade-in-request? request)
     (visual-id (fade-in-request-visual request))]
    [(fade-out-request? request)
     (fade-out-request-target-id request)]
    [(camera-view-pan-to-request? request)
     (camera-view-pan-to-request-target-id request)]
    [(camera-view-pan-by-request? request)
     (camera-view-pan-by-request-target-id request)]
    [(camera-view-zoom-to-request? request)
     (camera-view-zoom-to-request-target-id request)]
    [(camera-view-zoom-by-request? request)
     (camera-view-zoom-by-request-target-id request)]
    [(camera-view-follow-request? request)
     (camera-view-follow-request-target-id request)]
    [(camera-view-fit-request? request)
     (camera-view-fit-request-target-id request)]
    [(morph-to-request? request)
     (morph-to-request-target-id request)]
    [(morph-to-normalized-request? request)
     (morph-to-normalized-request-target-id request)]
    [(morph-to-aligned-request? request)
     (morph-to-aligned-request-target-id request)]
    [(morph-to-open-aligned-request? request)
     (morph-to-open-aligned-request-target-id request)]
    [(morph-to-open-compound-aligned-request? request)
     (morph-to-open-compound-aligned-request-target-id request)]
    [(morph-to-mixed-compound-aligned-request? request)
     (morph-to-mixed-compound-aligned-request-target-id request)]
    [(morph-to-topology-changing-request? request)
     (morph-to-topology-changing-request-target-id request)]
    [(morph-to-compound-aligned-request? request)
     (morph-to-compound-aligned-request-target-id request)]
    [(transform-shape-request? request)
     (transform-shape-request-source-id request)]
    [(transform-matching-visuals-request? request)
     (transform-matching-visuals-request-source-id request)]
    [(transform-from-copy-request? request)
     (visual-id (transform-from-copy-request-destination request))]
    [(attention-request? request)
     (define target (attention-request-target-id request))
     (if (visual-selection? target)
         (car (visual-selection-root target))
         target)]
    [(grow-request? request)
     (visual-id (grow-request-visual request))]
    [(draw-border-then-fill-request? request)
     (visual-id (draw-border-then-fill-request-visual request))]
    [(transform-formula-parts-request? request)
     (visual-id
      (formula-correspondence-source
       (transform-formula-parts-request-correspondence request)))]
    [(create-request? request)
     (visual-id (create-request-visual request))]
    [(uncreate-request? request)
     (uncreate-request-target-id request)]
    [(write-in-request? request)
     (visual-id
      (write-plan-endpoint
       (write-in-request-plan request)))]
    [(unwrite-request? request)
     (unwrite-request-target request)]
    [else
     (raise-argument-error
      'animation-request-target-id
      "animation request"
      request)]))

; animation-request-components : animation-request? -> (listof symbol?)
;;   Returns every animation component changed by request.
(define (animation-request-components request)
  (cond
    [(or (value-to-request? request)
         (change-number-to-request? request)
         (count-to-request? request)
         (count-from-request? request))
     '(scalar-value)]
    [(or (move-to-request? request)
         (move-along-path-request? request))
     '(translation)]
    [(or (orient-along-path-request? request)
         (rotate-to-request? request)
         (rotate-by-request? request))
     '(rotation)]
    [(or (scale-to-request? request)
         (scale-by-request? request))
     '(scale)]
    [(apply-affine-request? request)
     ;; The map can change every spatial component at once. Rejecting a
     ;; concurrent move/rotation/scale keeps CY-A endpoint semantics explicit.
     '(translation rotation scale affine-map)]
    [(apply-pointwise-request? request)
     ;; Sampling replaces the whole ordinary Visual tree at each frame, so it
     ;; cannot be meaningfully combined with any concurrent visual component.
     '(translation rotation scale stroke-width fill-color stroke-color opacity
                   path-geometry formula-parts pointwise-map)]
    [(apply-homotopy-request? request)
     ;; Like apply-pointwise, direct phase-dependent sampling replaces the
     ;; complete ordinary Visual tree during the clip.
     '(translation rotation scale stroke-width fill-color stroke-color opacity
                   path-geometry formula-parts pointwise-map)]
    [(stroke-width-to-request? request)
     '(stroke-width)]
    [(fill-color-to-request? request)
     '(fill-color)]
    [(stroke-color-to-request? request)
     '(stroke-color)]
    [(fade-to-request? request)
     '(opacity)]
    [(or (fade-in-request? request)
         (fade-out-request? request))
     '(opacity presence)]
    [(or (camera-view-pan-to-request? request)
         (camera-view-pan-by-request? request)
         (camera-view-follow-request? request))
     '(camera-view-center)]
    [(or (camera-view-zoom-to-request? request)
         (camera-view-zoom-by-request? request))
     '(camera-view-world-width)]
    [(camera-view-fit-request? request)
     '(camera-view-center camera-view-world-width)]
    [(or (morph-to-request? request)
         (morph-to-normalized-request? request)
         (morph-to-aligned-request? request)
         (morph-to-open-aligned-request? request)
         (morph-to-open-compound-aligned-request? request)
         (morph-to-mixed-compound-aligned-request? request)
         (morph-to-topology-changing-request? request)
         (morph-to-compound-aligned-request? request))
     '(path-geometry)]
    [(transform-shape-request? request)
     '(translation rotation scale stroke-width fill-color stroke-color opacity
                   path-geometry formula-parts presence)]
    [(transform-matching-visuals-request? request)
     '(translation rotation scale stroke-width fill-color stroke-color opacity
                   path-geometry formula-parts presence)]
    [(transform-from-copy-request? request)
     '(presence)]
    [(attention-request? request)
     '(attention)]
    [(grow-request? request)
     '(translation rotation scale opacity presence)]
    [(draw-border-then-fill-request? request)
     '(path-geometry fill-color opacity presence)]
    [(transform-formula-parts-request? request)
     '(formula-parts presence)]
    [(or (create-request? request)
         (uncreate-request? request))
     '(path-geometry presence)]
    [(or (write-in-request? request)
         (unwrite-request? request))
     ;; The proxy replaces the complete target during sampling.  Treat it as a
     ;; whole-Visual transition so no simultaneous component can be overwritten
     ;; by request ordering.
     '(translation rotation scale stroke-width fill-color stroke-color opacity
                   path-geometry formula-parts presence)]
    [else
     (raise-argument-error
      'animation-request-components
      "animation request"
      request)]))

;;;
;;; Sampling
;;;

; apply-compiled-animations : scene-state?
;                             (listof compiled-animation?)
;                             finite-real?
;                             (-> finite-real? finite-real?)
;                             [#:write-progress finite-real?]
;                             [#:write-scene-rate-func
;                              (-> finite-real? finite-real?)]
;                             -> scene-state?
;;   Samples all compiled animations at progress using easing.
(define (apply-compiled-animations state
                                   animations
                                   progress
                                   easing
                                   #:write-progress [write-progress progress]
                                   #:write-scene-rate-func
                                   [write-scene-rate-func easing])
  (unless (scene-state? state)
    (raise-argument-error
     'apply-compiled-animations
     "scene-state?"
     state))
  (unless (and (list? animations)
               (andmap compiled-animation? animations))
    (raise-argument-error
     'apply-compiled-animations
     "list of compiled animations"
     animations))
  (unless (finite-real? progress)
    (raise-argument-error
     'apply-compiled-animations
     "finite real?"
     progress))
  (unless (finite-real? write-progress)
    (raise-argument-error
     'apply-compiled-animations
     "finite real?"
     write-progress))
  (unless (and (procedure? easing)
               (procedure-arity-includes? easing 1))
    (raise-argument-error
     'apply-compiled-animations
     "(procedure-arity-includes/c 1)"
     easing))
  (unless (and (procedure? write-scene-rate-func)
               (procedure-arity-includes? write-scene-rate-func 1))
    (raise-argument-error
     'apply-compiled-animations
     "(procedure-arity-includes/c 1)"
     write-scene-rate-func))
  (define eased-progress
    (clamp-unit (easing (clamp-unit progress))))
  ;; Attention is a derived overlay, not a semantic update to its target.
  ;; Sampling it after all ordinary components makes simultaneous motion and
  ;; resizing order-independent while retaining its frontmost draw position.
  (define ordered-animations
    (append
     (filter (lambda (animation)
               (and (not (attention-animation? animation))
                    (not (camera-view-follow-animation? animation))))
             animations)
     ;; A secondary-camera follow reads the current sampled world target, so
     ;; sample it after every ordinary world update in this clip. This keeps
     ;; follow a pure function of (clip-start state, time), not a history.
     (filter camera-view-follow-animation? animations)
     (filter attention-animation? animations)))
  (for/fold ([sampled-state state])
            ([animation (in-list ordered-animations)])
    ;; Write samples need the raw clip clock.  Their per-leaf rate function is
    ;; applied only after staggering, which matches Manim's `get_sub_alpha`.
    ;; All historical animation kinds keep the shared eased progress exactly.
    (if (write-in-animation? animation)
        (apply-compiled-animation sampled-state
                                  animation
                                  (clamp-unit write-progress)
                                  write-scene-rate-func)
        (apply-compiled-animation sampled-state
                                  animation
                                  eased-progress))))

; compiled-animation? : any/c -> boolean?
;;   Reports whether value is a supported compiled animation.
(define (compiled-animation? value)
  (or (scalar-value-animation? value)
      (translation-animation? value)
      (path-motion-animation? value)
      (path-orientation-animation? value)
      (rotation-animation? value)
      (scaling-animation? value)
      (affine-map-animation? value)
      (pointwise-map-animation? value)
      (homotopy-map-animation? value)
      (stroke-width-animation? value)
      (fill-color-animation? value)
      (stroke-color-animation? value)
      (camera-view-center-animation? value)
      (camera-view-world-width-animation? value)
      (camera-view-follow-animation? value)
      (camera-view-fit-animation? value)
      (opacity-animation? value)
      (path-morph-animation? value)
      (normalized-path-morph-animation? value)
      (transform-shape-animation? value)
      (transform-matching-visuals-animation? value)
      (transform-from-copy-animation? value)
      (attention-animation? value)
      (grow-animation? value)
      (border-fill-animation? value)
      (formula-parts-transform-animation? value)
      (path-reveal-animation? value)
      (relation-path-reveal-animation? value)
      (write-in-animation? value)))

; apply-compiled-animation : scene-state? compiled-animation? finite-real?
;                            [(-> finite-real? finite-real?)] -> scene-state?
;;   Applies one compiled animation component at progress.
(define (apply-compiled-animation state animation progress
                                  [write-scene-rate-func linear])
  (cond
    [(scalar-value-animation? animation)
     (apply-scalar-value-animation state animation progress)]
    [(translation-animation? animation)
     (apply-translation-animation state animation progress)]
    [(path-motion-animation? animation)
     (apply-path-motion-animation state animation progress)]
    [(path-orientation-animation? animation)
     (apply-path-orientation-animation state animation progress)]
    [(rotation-animation? animation)
     (apply-rotation-animation state animation progress)]
    [(scaling-animation? animation)
     (apply-scaling-animation state animation progress)]
    [(affine-map-animation? animation)
     (apply-affine-map-animation state animation progress)]
    [(pointwise-map-animation? animation)
     (apply-pointwise-map-animation state animation progress)]
    [(homotopy-map-animation? animation)
     (apply-homotopy-map-animation state animation progress)]
    [(stroke-width-animation? animation)
     (apply-stroke-width-animation state animation progress)]
    [(fill-color-animation? animation)
     (apply-fill-color-animation state animation progress)]
    [(stroke-color-animation? animation)
     (apply-stroke-color-animation state animation progress)]
    [(camera-view-center-animation? animation)
     (apply-camera-view-center-animation state animation progress)]
    [(camera-view-world-width-animation? animation)
     (apply-camera-view-world-width-animation state animation progress)]
    [(camera-view-follow-animation? animation)
     (apply-camera-view-follow-animation state animation progress)]
    [(camera-view-fit-animation? animation)
     (apply-camera-view-fit-animation state animation progress)]
    [(opacity-animation? animation)
     (apply-opacity-animation state animation progress)]
    [(path-morph-animation? animation)
     (apply-path-morph-animation state animation progress)]
    [(normalized-path-morph-animation? animation)
     (apply-normalized-path-morph-animation state animation progress)]
    [(transform-shape-animation? animation)
     (apply-transform-shape-animation state animation progress)]
    [(transform-matching-visuals-animation? animation)
     (apply-transform-matching-visuals-animation state animation progress)]
    [(transform-from-copy-animation? animation)
     (apply-transform-from-copy-animation state animation progress)]
    [(attention-animation? animation)
     (apply-attention-animation state animation progress)]
    [(grow-animation? animation)
     (apply-grow-animation state animation progress)]
    [(border-fill-animation? animation)
     (apply-border-fill-animation state animation progress)]
    [(formula-parts-transform-animation? animation)
     (apply-formula-parts-transform-animation state animation progress)]
    [(path-reveal-animation? animation)
     (apply-path-reveal-animation state animation progress)]
    [(relation-path-reveal-animation? animation)
     (apply-relation-path-reveal-animation state animation progress)]
    [(write-in-animation? animation)
     (apply-write-in-animation state
                               animation
                               progress
                               write-scene-rate-func)]
    [else
     (raise-argument-error
      'apply-compiled-animation
      "compiled animation"
      animation)]))

; apply-scalar-value-animation : scene-state? scalar-value-animation? finite-real?
;                                -> scene-state?
;;   Samples one named semantic value while preserving exact endpoints.
(define (apply-scalar-value-animation state animation progress)
  (define value
    (interpolate-value
     (scalar-value-animation-from animation)
     (scalar-value-animation-to animation)
     progress))
  (scene-state-value-set
   state
   (scalar-value-animation-target-id animation)
   value))

; apply-translation-animation : scene-state? translation-animation?
;                               finite-real? -> scene-state?
;;   Applies one compiled translation at progress.
(define (apply-translation-animation state animation progress)
  (define id
    (translation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-position
    visual
    (vec2-lerp (translation-animation-from animation)
               (translation-animation-to animation)
               progress))))

; apply-path-motion-animation : scene-state? path-motion-animation?
;                               finite-real? -> scene-state?
;;   Places one Visual at the requested total arc-length fraction.
(define (apply-path-motion-animation state animation progress)
  (define id
    (path-motion-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define fraction
    (real-lerp (path-motion-animation-start animation)
               (path-motion-animation-end animation)
               progress))
  (scene-state-update
   state
   id
   (visual-with-position
    visual
    (path-motion-position-at
     (path-motion-animation-path animation)
     fraction
     (path-motion-animation-start animation)
     (path-motion-animation-end animation)
     (path-motion-animation-normal-offset animation)))))

; apply-path-orientation-animation : scene-state? path-orientation-animation?
;                                    finite-real? -> scene-state?
;;   Rotates one affine Visual to the route's traversal tangent at progress.
(define (apply-path-orientation-animation state animation progress)
  (define id
    (path-orientation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define fraction
    (real-lerp (path-orientation-animation-start animation)
               (path-orientation-animation-end animation)
               progress))
  (define tangent
    (path-traversal-tangent-at
     (path-orientation-animation-path animation)
     fraction
     (path-orientation-animation-start animation)
     (path-orientation-animation-end animation)))
  (scene-state-update
   state
   id
   (visual-with-rotation
    visual
    (+ (atan (vec2-y tangent)
             (vec2-x tangent))
       (path-orientation-animation-rotation-offset animation)))))

; path-motion-position-at : path-geometry? finite-real? finite-real?
;                           finite-real? finite-real? -> vec2?
;;   Returns a route point plus one signed normal offset from traversal.
(define (path-motion-position-at path fraction start end normal-offset)
  (define point
    (path-geometry-point-at path fraction))
  (cond
    [(zero? normal-offset)
     point]
    [else
     (define tangent
       (path-traversal-tangent-at path fraction start end))
     (define left-normal
       (vec2 (- (vec2-y tangent))
             (vec2-x tangent)))
     (vec2+ point
            (vec2-scale normal-offset left-normal))]))

; path-traversal-tangent-at : path-geometry? finite-real? finite-real?
;                             finite-real? -> vec2?
;;   Returns a unit tangent pointing in the requested traversal direction.
(define (path-traversal-tangent-at path fraction start end)
  (define tangent
    (path-geometry-tangent-at path fraction))
  (if (< end start)
      (vec2-scale -1 tangent)
      tangent))

; apply-rotation-animation : scene-state? rotation-animation? finite-real?
;                            -> scene-state?
;;   Applies one compiled rotation at progress.
(define (apply-rotation-animation state animation progress)
  (define id
    (rotation-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-rotation
    visual
    (real-lerp (rotation-animation-from animation)
               (rotation-animation-to animation)
               progress))))

; apply-scaling-animation : scene-state? scaling-animation? finite-real?
;                           -> scene-state?
;;   Applies one compiled scale at progress.
(define (apply-scaling-animation state animation progress)
  (define id
    (scaling-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (visual-with-scale
    visual
    (vec2-lerp (scaling-animation-from animation)
               (scaling-animation-to animation)
               progress))))

; apply-affine-map-animation : scene-state? affine-map-animation?
;                              finite-real? -> scene-state?
;; Applies the identity-to-requested local map after the target's prior map.
;; The exact clip-start representation is retained at zero; the mapped endpoint
;; remains a semantic affine wrapper, so later nested requests compose without
;; rasterizing or hiding descendants.
(define (apply-affine-map-animation state animation progress)
  (if (zero? progress)
      state
      (let* ([id (affine-map-animation-target-id animation)]
             [progress-map
              (affine2-lerp identity-affine2
                            (affine-map-animation-map animation)
                            progress)]
             [combined-map
              (affine2-compose progress-map
                               (affine-map-animation-from-map animation))])
        (define mapped
          (affine-map (affine-map-animation-content animation)
                      combined-map))
        (scene-state-update
         state
         id
         (if (= (affine-map-animation-opacity animation) 1)
             mapped
             (visual-with-opacity
              mapped
              (affine-map-animation-opacity animation)))))))

; apply-pointwise-map-animation : scene-state? pointwise-map-animation?
;                                 finite-real? -> scene-state?
;; Preserves the caller's exact source Visual at the clip start. Subsequent
;; samples are ordinary world-coordinate path trees, so the nonlinear endpoint
;; remains inspectable rather than becoming a bitmap snapshot.
(define (apply-pointwise-map-animation state animation progress)
  (if (zero? progress)
      state
      (let* ([world-result
              (pointwise-map-visual
               (pointwise-map-animation-source animation)
               (pointwise-map-animation-map-point animation)
               progress
               #:samples (pointwise-map-animation-samples animation)
               #:adaptive? (pointwise-map-animation-adaptive? animation)
               #:tolerance (pointwise-map-animation-tolerance animation)
               #:max-depth (pointwise-map-animation-max-depth animation)
               #:discontinuities
               (pointwise-map-animation-discontinuity-mode animation))]
             [parent-map (pointwise-map-animation-parent-map animation)]
             [replacement
              (if (equal? parent-map identity-affine2)
                  world-result
                  (affine-map world-result
                              (or (affine2-invert parent-map)
                                  (raise-arguments-error
                                   'apply-pointwise
                                   "a nonsingular enclosing affine map"
                                   "parent-map" parent-map))))])
        (scene-state-update
         state
         (pointwise-map-animation-target-id animation)
         replacement))))

; apply-homotopy-map-animation : scene-state? homotopy-map-animation?
;                                finite-real? -> scene-state?
;; Retains the exact source at progress zero. At every later phase, map each
;; source point directly through H(p, alpha); passing progress 1 to the shared
;; pointwise mapper disables its endpoint blend while retaining phase-specific
;; adaptive subdivision and the existing discontinuity policy.
(define (apply-homotopy-map-animation state animation progress)
  (if (zero? progress)
      state
      (let* ([homotopy (homotopy-map-animation-homotopy animation)]
             [world-result
              (pointwise-map-visual
               (homotopy-map-animation-source animation)
               (lambda (point)
                 (homotopy point progress))
               1
               #:samples (homotopy-map-animation-samples animation)
               #:adaptive? (homotopy-map-animation-adaptive? animation)
               #:tolerance (homotopy-map-animation-tolerance animation)
               #:max-depth (homotopy-map-animation-max-depth animation)
               #:discontinuities
               (homotopy-map-animation-discontinuity-mode animation))]
             [parent-map (homotopy-map-animation-parent-map animation)]
             [replacement
              (if (equal? parent-map identity-affine2)
                  world-result
                  (affine-map world-result
                              (or (affine2-invert parent-map)
                                  (raise-arguments-error
                                   'apply-homotopy
                                   "a nonsingular enclosing affine map"
                                   "parent-map" parent-map))))])
        (scene-state-update
         state
         (homotopy-map-animation-target-id animation)
         replacement))))

; apply-stroke-width-animation : scene-state? stroke-width-animation?
;                                finite-real? -> scene-state?
;;   Applies one compiled cosmetic stroke-width transition at progress.
(define (apply-stroke-width-animation state animation progress)
  (define id
    (stroke-width-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define stroke-width
    (cond
      [(zero? progress)
       (stroke-width-animation-from animation)]
      [(= progress 1)
       (stroke-width-animation-to animation)]
      [else
       (real-lerp (stroke-width-animation-from animation)
                  (stroke-width-animation-to animation)
                  progress)]))
  (scene-state-update
   state
   id
   (replace-visual-stroke-width
    'scene-sample
    visual
    stroke-width)))

; apply-fill-color-animation : scene-state? fill-color-animation? finite-real?
;                              -> scene-state?
;;   Applies one semantic fill-paint transition while preserving exact endpoints.
(define (apply-fill-color-animation state animation progress)
  (define id
    (fill-color-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define paint
    (cond
      [(zero? progress)
       (fill-color-animation-from-paint animation)]
      [(= progress 1)
       (fill-color-animation-to-paint animation)]
      [else
       (paint-lerp (fill-color-animation-from-paint animation)
                   (fill-color-animation-to-paint animation)
                   progress)]))
  (scene-state-update
   state
   id
   (replace-visual-fill-color 'scene-sample visual paint)))

; apply-stroke-color-animation : scene-state? stroke-color-animation? finite-real?
;                                -> scene-state?
;;   Applies one semantic stroke-color transition while preserving exact endpoints.
(define (apply-stroke-color-animation state animation progress)
  (define id
    (stroke-color-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define color
    (cond
      [(zero? progress)
       (stroke-color-animation-from-spec animation)]
      [(= progress 1)
       (stroke-color-animation-to-spec animation)]
      [else
       (rgba-color-lerp (stroke-color-animation-from-color animation)
                        (stroke-color-animation-to-color animation)
                        progress)]))
  (scene-state-update
   state
   id
   (replace-visual-stroke-color 'scene-sample visual color)))

;; camera-with-view : camera? vec2? positive-real? -> camera?
;; Retains pixel dimensions and background while replacing the two animated
;; secondary-camera fields.
(define (camera-with-view camera center world-width)
  (make-camera #:width (camera-width camera)
               #:height (camera-height camera)
               #:world-width world-width
               #:center center
               #:background (camera-background camera)))

;; update-camera-view-camera : scene-state? symbol? camera? -> scene-state?
;; Updates only a top-level camera-view's immutable camera value.
(define (update-camera-view-camera state target-id camera)
  (define view (scene-state-ref state target-id))
  (unless (camera-view-visual? view)
    (raise-arguments-error
     'scene-sample
     "a camera-view Visual target"
     "visual-id" target-id
     "visual" view))
  (scene-state-update
   state
   target-id
   (camera-view-visual-with-camera view camera)))

; apply-camera-view-center-animation : scene-state?
;                                      camera-view-center-animation?
;                                      finite-real? -> scene-state?
;; Samples a secondary-camera centre while leaving its world width unchanged.
(define (apply-camera-view-center-animation state animation progress)
  (define target-id (camera-view-center-animation-target-id animation))
  (define view (scene-state-ref state target-id))
  (define camera (camera-view-visual-camera view))
  (define center
    (if (zero? progress)
        (camera-view-center-animation-from animation)
        (if (= progress 1)
            (camera-view-center-animation-to animation)
            (vec2-lerp (camera-view-center-animation-from animation)
                       (camera-view-center-animation-to animation)
                       progress))))
  (update-camera-view-camera
   state target-id (camera-with-view camera center (camera-world-width camera))))

; apply-camera-view-world-width-animation : scene-state?
;                                           camera-view-world-width-animation?
;                                           finite-real? -> scene-state?
;; Samples a secondary-camera visible width while retaining its centre.
(define (apply-camera-view-world-width-animation state animation progress)
  (define target-id (camera-view-world-width-animation-target-id animation))
  (define view (scene-state-ref state target-id))
  (define camera (camera-view-visual-camera view))
  (define world-width
    (if (zero? progress)
        (camera-view-world-width-animation-from animation)
        (if (= progress 1)
            (camera-view-world-width-animation-to animation)
            (real-lerp (camera-view-world-width-animation-from animation)
                       (camera-view-world-width-animation-to animation)
                       progress))))
  (update-camera-view-camera
   state target-id (camera-with-view camera (camera-center camera) world-width)))

; apply-camera-view-follow-animation : scene-state?
;                                      camera-view-follow-animation?
;                                      finite-real? -> scene-state?
;; Keeps a world target at its original offset in the inset. The target is
;; resolved from the state already sampled at this same clip time.
(define (apply-camera-view-follow-animation state animation progress)
  (if (zero? progress)
      state
      (let* ([target-id (camera-view-follow-animation-target-id animation)]
             [view (scene-state-ref state target-id)]
             [camera (camera-view-visual-camera view)]
             [followed
              (scene-state-resolved-world-ref
               state
               (camera-view-follow-animation-followed-target animation))])
        (when (frame-space-visual? followed)
          (raise-arguments-error
           'scene-sample
           "a world-space secondary-camera follow target"
           "target" (camera-view-follow-animation-followed-target animation)))
        (update-camera-view-camera
         state
         target-id
         (camera-with-view
          camera
          (vec2+ (visual-position followed)
                 (camera-view-follow-animation-offset animation))
          (camera-world-width camera))))))

; apply-camera-view-fit-animation : scene-state? camera-view-fit-animation?
;                                   finite-real? -> scene-state?
;; Samples a measured secondary-camera centre and width together.
(define (apply-camera-view-fit-animation state animation progress)
  (define target-id (camera-view-fit-animation-target-id animation))
  (define view (scene-state-ref state target-id))
  (define camera (camera-view-visual-camera view))
  (define center
    (if (zero? progress)
        (camera-view-fit-animation-center-from animation)
        (if (= progress 1)
            (camera-view-fit-animation-center-to animation)
            (vec2-lerp (camera-view-fit-animation-center-from animation)
                       (camera-view-fit-animation-center-to animation)
                       progress))))
  (define world-width
    (if (zero? progress)
        (camera-view-fit-animation-world-width-from animation)
        (if (= progress 1)
            (camera-view-fit-animation-world-width-to animation)
            (real-lerp (camera-view-fit-animation-world-width-from animation)
                       (camera-view-fit-animation-world-width-to animation)
                       progress))))
  (update-camera-view-camera
   state target-id (camera-with-view camera center world-width)))

; apply-opacity-animation : scene-state? opacity-animation? finite-real?
;                           -> scene-state?
;;   Applies one compiled global-opacity transition at progress.
(define (apply-opacity-animation state animation progress)
  (define id
    (opacity-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (replace-visual-opacity
    'scene-sample
    visual
    (real-lerp (opacity-animation-from animation)
               (opacity-animation-to animation)
               progress))))

; apply-path-morph-animation : scene-state? path-morph-animation?
;                              finite-real? -> scene-state?
;;   Applies one compatible local path interpolation at progress.
(define (apply-path-morph-animation state animation progress)
  (define id
    (path-morph-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (scene-state-update
   state
   id
   (path-visual-with-path
    visual
    (path-geometry-lerp
     (path-morph-animation-from animation)
     (path-morph-animation-to animation)
     progress))))

; apply-normalized-path-morph-animation : scene-state?
;                                          normalized-path-morph-animation?
;                                          finite-real?
;                                          -> scene-state?
;;   Applies a normalized path interpolation while preserving exact endpoints.
(define (apply-normalized-path-morph-animation state animation progress)
  (define id
    (normalized-path-morph-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define path
    (cond
      [(zero? progress)
       (normalized-path-morph-animation-source animation)]
      [(= progress 1)
       (normalized-path-morph-animation-destination animation)]
      [else
       (path-geometry-lerp
        (normalized-path-morph-animation-normalized-source animation)
        (normalized-path-morph-animation-normalized-destination animation)
        progress)]))
  (scene-state-update
   state
   id
   (path-visual-with-path visual path)))

; apply-transform-shape-animation : scene-state? transform-shape-animation?
;                                    finite-real? -> scene-state?
;; Hides the structural source only for interior samples and paints a temporary
;; pair of layers in front of the scene. Two styled layers make paint changes
;; cross-fade while their shared outline performs the geometric morph.
(define (apply-transform-shape-animation state animation progress)
  (define overlay-id
    (transform-shape-animation-overlay-id animation))
  (define without-prior-overlay
    (if (scene-state-has? state overlay-id)
        (scene-state-remove state overlay-id)
        state))
  (cond
    [(or (zero? progress) (= progress 1))
     without-prior-overlay]
    [else
     (define source
       (transform-shape-animation-source animation))
     (define destination
       (transform-shape-animation-destination animation))
     (define-values (source-layer destination-layer)
       (if (transform-shape-animation-normalized-source animation)
           (transform-shape-morph-layers animation progress)
           (values source destination)))
     (define hidden-source-state
       (scene-state-update
        without-prior-overlay
        (transform-shape-animation-source-id animation)
        (visual-with-opacity source 0)))
     (scene-state-add
      hidden-source-state
      (group
       (list
        (transient-visual
         (copy-overlay-child-id overlay-id 'source)
         (visual-with-opacity
          source-layer
          (* (visual-opacity source-layer) (- 1 progress))))
        (transient-visual
         (copy-overlay-child-id overlay-id 'destination)
         (visual-with-opacity
          destination-layer
          (* (visual-opacity destination-layer) progress))))
       #:id overlay-id))]))

; transform-shape-morph-layers : transform-shape-animation? finite-real?
;                                -> (values path-visual? path-visual?)
;; Samples one shared geometry but preserves the endpoint styles in separate
;; alpha layers. The structural endpoint remains the caller's exact destination
;; Visual, rather than a normalised path proxy.
(define (transform-shape-morph-layers animation progress)
  (define source
    (transform-shape-animation-source animation))
  (define destination
    (transform-shape-animation-destination animation))
  (define source-proxy
    (transform-shape-path-proxy source))
  (define destination-proxy
    (transform-shape-path-proxy destination))
  ;; The compiler only constructs geometric animations after both conversions
  ;; have succeeded. Retain an explicit check here so a malformed compiled
  ;; value cannot yield a renderer-specific failure.
  (unless (and source-proxy destination-proxy)
    (raise-arguments-error
     'transform-shape
     "compiled geometric path proxies"
     "source" source
     "destination" destination))
  (define geometry
    (path-geometry-lerp
     (transform-shape-animation-normalized-source animation)
     (transform-shape-animation-normalized-destination animation)
     progress))
  (define transform
    (affine-transform-lerp
     (visual-transform source-proxy)
     (visual-transform destination-proxy)
     progress))
  (values
   (visual-with-transform
    (path-visual-with-path source-proxy geometry)
    transform)
   (visual-with-transform
    (path-visual-with-path destination-proxy geometry)
    transform)))

; apply-transform-matching-visuals-animation
; : scene-state? transform-matching-visuals-animation? finite-real? -> scene-state?
;; Hides the original root only at interior samples and puts independently
;; matched leaves into one frontmost transient overlay. Keeping the exact roots
;; intact makes arbitrary frame evaluation and end-of-clip replacement as
;; deterministic as transform-shape.
(define (apply-transform-matching-visuals-animation state animation progress)
  (define overlay-id (transform-matching-visuals-animation-overlay-id animation))
  (define without-prior-overlay
    (if (scene-state-has? state overlay-id)
        (scene-state-remove state overlay-id)
        state))
  (cond
    [(or (zero? progress) (= progress 1)) without-prior-overlay]
    [else
     (define children
       (apply append
              (for/list ([spec
                          (in-list
                           (transform-matching-visuals-animation-specs animation))]
                         [index (in-naturals)])
                (visual-match-spec-overlay-layers spec overlay-id index progress))))
     (define source
       (transform-matching-visuals-animation-source animation))
     (define hidden-source-state
       (scene-state-update
        without-prior-overlay
        (transform-matching-visuals-animation-source-id animation)
        (visual-with-opacity source 0)))
     (scene-state-add hidden-source-state (group children #:id overlay-id))]))

;; A paired spec has two moving/fading layers. One-sided specs are the ordinary
;; stationary unmatched fade used by TransformMatchingShapes-like transitions.
(define (visual-match-spec-overlay-layers spec overlay-id index progress)
  (define source (visual-match-spec-source spec))
  (define destination (visual-match-spec-destination spec))
  (define source-layer-id
    (matching-overlay-child-id overlay-id index 'source))
  (define destination-layer-id
    (matching-overlay-child-id overlay-id index 'destination))
  (cond
    [(and source destination)
     (define-values (source-layer destination-layer)
       (visual-match-spec-layers spec progress))
     (list
      (transient-visual
       source-layer-id
       (visual-with-opacity
        source-layer
        (* (visual-opacity source-layer) (- 1 progress))))
      (transient-visual
       destination-layer-id
       (visual-with-opacity
        destination-layer
        (* (visual-opacity destination-layer) progress))))]
    [source
     (list
      (transient-visual
       source-layer-id
       (visual-with-opacity source (* (visual-opacity source) (- 1 progress)))))]
    [destination
     (list
      (transient-visual
       destination-layer-id
       (visual-with-opacity destination (* (visual-opacity destination) progress))))]
    [else '()]))

(define (matching-overlay-child-id overlay-id index role)
  (string->symbol
   (format "~a-~a-~a" overlay-id index role)))

(define (visual-match-spec-layers spec progress)
  (define source (visual-match-spec-source spec))
  (define destination (visual-match-spec-destination spec))
  (define transform
    (affine-transform-lerp (visual-transform source)
                           (visual-transform destination)
                           progress))
  (cond
    [(visual-match-spec-normalized-source spec)
     (define source-proxy (transform-shape-path-proxy source))
     (define destination-proxy (transform-shape-path-proxy destination))
     (unless (and source-proxy destination-proxy)
       (raise-arguments-error
        'transform-matching-visuals
        "compiled geometric path proxies"
        "source" source
        "destination" destination))
     (define geometry
       (path-geometry-lerp
        (visual-match-spec-normalized-source spec)
        (visual-match-spec-normalized-destination spec)
        progress))
     (values
      (visual-with-transform (path-visual-with-path source-proxy geometry) transform)
      (visual-with-transform (path-visual-with-path destination-proxy geometry) transform))]
    [else
     (values (visual-with-transform source transform)
             (visual-with-transform destination transform))]))

; apply-transform-from-copy-animation : scene-state?
;                                       transform-from-copy-animation?
;                                       finite-real? -> scene-state?
;; Adds a frontmost transient group only for interior samples.  Its child ids
;; are fresh transient wrappers, so source and destination composite trees may
;; reuse ordinary descendant identities. This lets every supported affine
;; Visual be copied without adding a general identity-replacement protocol.
(define (apply-transform-from-copy-animation state animation progress)
  (define overlay-id
    (transform-from-copy-animation-overlay-id animation))
  (define without-prior-overlay
    (if (scene-state-has? state overlay-id)
        (scene-state-remove state overlay-id)
        state))
  (cond
    [(or (zero? progress) (= progress 1))
     without-prior-overlay]
    [else
     (define source
       (transform-from-copy-animation-source animation))
     (define destination
       (transform-from-copy-animation-destination animation))
     (define route
       (transform-from-copy-animation-route animation))
     (define from-transform (visual-transform source))
     (define to-transform (visual-transform destination))
     (define moving-transform
       (affine-transform-with-translation
        (affine-transform-lerp from-transform to-transform progress)
        (formula-route-position-at
         route
         (affine-transform-translation from-transform)
         (affine-transform-translation to-transform)
         progress)))
     (define source-layer
       (visual-with-opacity
        (visual-with-transform source moving-transform)
        (* (visual-opacity source) (- 1 progress))))
     (define destination-layer
       (visual-with-opacity
        (visual-with-transform destination moving-transform)
        (* (visual-opacity destination) progress)))
     (scene-state-add
      without-prior-overlay
      (group (list (transient-visual
                    (copy-overlay-child-id overlay-id 'source)
                    source-layer)
                   (transient-visual
                    (copy-overlay-child-id overlay-id 'destination)
                    destination-layer))
             #:id overlay-id))]))

(define (copy-overlay-child-id overlay-id role)
  (string->symbol
   (string-append (symbol->string overlay-id)
                  "-"
                  (symbol->string role))))

; apply-attention-animation : scene-state? attention-animation? finite-real?
;                            -> scene-state?
;; Adds an emphasis outline measured from the fully sampled target for interior
;; samples only. Keeping it outside the target Visual makes attention safe to
;; combine with motion, resizing, and formula transitions in the same clip.
(define (apply-attention-animation state animation progress)
  (define overlay-id
    (attention-animation-overlay-id animation))
  (define without-prior-overlay
    (if (scene-state-has? state overlay-id)
        (scene-state-remove state overlay-id)
        state))
  (cond
    [(or (zero? progress) (= progress 1))
     without-prior-overlay]
    [else
     (define target-paths
       (attention-animation-target-paths animation))
     (for ([target-path (in-list target-paths)])
       (unless (scene-state-has? without-prior-overlay target-path)
         (raise-arguments-error
          'attention
          "a target Visual present at every requested selection path while sampled"
          "target-path" target-path)))
     (define targets
       (for/list ([target-path (in-list target-paths)])
         (scene-state-resolved-world-ref without-prior-overlay target-path)))
     (define target-box (renderer-layout-boxes targets))
     (unless target-box
       (raise-arguments-error
        'attention
        "a nonempty selection of renderer-measurable Visuals"
        "target-paths" target-paths))
     (define outline
       (make-attention-outline
        overlay-id
        target-box
        (attention-animation-padding animation)
        (attention-animation-color animation)
        (attention-animation-stroke-width animation)))
     (define sampled
       (case (attention-animation-kind animation)
         [(circumscribe)
          (define path-progress
            (cond
              [(< progress 1/3) (* 3 progress)]
              [(< progress 2/3) 1]
              [else (* 3 (- 1 progress))]))
          (path-visual-with-path
           outline
           (path-geometry-partial
            (path-visual-path outline)
            0
            path-progress))]
         [(indicate)
          (define pulse (sin (* pi progress)))
          (visual-with-opacity
           (visual-with-scale outline (+ 1 (* 1/8 pulse)))
           (* (visual-opacity outline) pulse))]
         [(flash)
         (make-flash-overlay
           overlay-id
           (renderer-layout-box-center target-box)
           (+ (attention-animation-padding animation)
              (/ (max (renderer-layout-box-width target-box)
                      (renderer-layout-box-height target-box))
                 2))
           (attention-animation-color animation)
           (attention-animation-stroke-width animation)
           progress)]
         [(focus-on)
          (define box target-box)
          (define base-radius
            (+ (attention-animation-padding animation)
               (/ (max (renderer-layout-box-width box)
                       (renderer-layout-box-height box))
                  2)))
          (visual-with-opacity
           (visual-with-scale
            (circle #:id overlay-id #:center (renderer-layout-box-center box)
                    #:radius base-radius #:fill #f
                    #:stroke (attention-animation-color animation)
                    #:stroke-width (attention-animation-stroke-width animation))
            (+ 1 (* 1/2 progress)))
           (- 1 progress))]
         [(show-passing-flash)
          (make-passing-flash
           overlay-id (car targets) progress
           (attention-animation-parameter animation)
           (attention-animation-color animation)
           (attention-animation-stroke-width animation))]
         [else
          (raise-argument-error
           'apply-attention-animation
           "supported attention kind"
           (attention-animation-kind animation))]))
     (scene-state-add without-prior-overlay sampled)]))

(define (make-flash-overlay id center radius color stroke-width progress)
  (define start-radius (* radius (+ 1/5 (* 3/5 progress))))
  (define end-radius (* radius (+ 2/5 (* 3/5 progress))))
  (visual-with-opacity
   (group
    (for/list ([index (in-range 8)])
      (define angle (* index (/ pi 4)))
      (define direction (vec2 (cos angle) (sin angle)))
      (line (vec2+ center (vec2-scale start-radius direction))
            (vec2+ center (vec2-scale end-radius direction))
            #:id (string->symbol (format "~a-ray-~a" id index))
            #:stroke color #:stroke-width stroke-width))
    #:id id)
   (- 1 progress)))

(define (make-passing-flash id target progress time-width color stroke-width)
  (unless (path-visual? target)
    (raise-arguments-error
     'show-passing-flash "a path Visual target" "visual" target))
  (define from (max 0 (- progress time-width)))
  (define to (min 1 progress))
  (make-path-visual
   (path-geometry-partial (path-visual-path target) from to)
   #:id id
   #:center (visual-position target)
   #:rotation (visual-rotation target)
   #:scale (visual-scale target)
   #:opacity (visual-opacity target)
   #:fill #f #:stroke color #:stroke-width stroke-width))

(define (grow-start-visual visual kind)
  (case kind
    [(center)
     (visual-with-scale visual (vec2-scale 1/1000 (visual-scale visual)))]
    [(arrow)
     (define start (arrow-visual-start visual))
     (define end (arrow-visual-end visual))
     (arrow start (vec2-lerp start end 1/1000)
            #:id (visual-id visual)
            #:stroke (arrow-visual-stroke visual)
            #:stroke-width (arrow-visual-stroke-width visual)
            #:tip-length (arrow-visual-tip-length visual)
            #:tip-width (arrow-visual-tip-width visual)
            #:start-tip? (arrow-visual-start-tip? visual)
            #:end-tip? (arrow-visual-end-tip? visual))]
    [else
     (raise-argument-error 'grow-start-visual "supported grow kind" kind)]))

(define (apply-grow-animation state animation progress)
  (define id (grow-animation-target-id animation))
  (define destination (grow-animation-destination animation))
  (define sampled
    (cond
      [(= progress 1) destination]
      [(eq? (grow-animation-kind animation) 'center)
       (define source (grow-animation-source animation))
       (visual-with-opacity
        (visual-with-scale
         destination
         (vec2-lerp (visual-scale source) (visual-scale destination) progress))
        (* (visual-opacity destination) progress))]
      [(eq? (grow-animation-kind animation) 'arrow)
       (define start (arrow-visual-start destination))
       (define end (arrow-visual-end destination))
       (arrow start (vec2-lerp start end (max 1/1000 progress))
              #:id id #:opacity (* (visual-opacity destination) progress)
              #:stroke (arrow-visual-stroke destination)
              #:stroke-width (arrow-visual-stroke-width destination)
              #:tip-length (arrow-visual-tip-length destination)
              #:tip-width (arrow-visual-tip-width destination)
              #:start-tip? (arrow-visual-start-tip? destination)
              #:end-tip? (arrow-visual-end-tip? destination))]
      [else
       (raise-argument-error 'grow-from-center "supported grow kind"
                             (grow-animation-kind animation))]))
  (scene-state-update state id sampled))

(define (apply-border-fill-animation state animation progress)
  (define id (border-fill-animation-target-id animation))
  (define visual (border-fill-animation-visual animation))
  (scene-state-update
   state id
   (if (= progress 1)
       visual
       (write-sample-path visual progress
                          (max 1 (path-visual-stroke-width visual))
                          'arc-length #f))))

; apply-formula-parts-transform-animation : scene-state?
;                                            formula-parts-transform-animation?
;                                            finite-real?
;                                            -> scene-state?
;;   Replaces assembly parts with exact endpoints or sampled transition layers.
(define (apply-formula-parts-transform-animation state animation progress)
  (define id
    (formula-parts-transform-animation-target-id animation))
  (define assembly
    (scene-state-ref state id))
  (check-formula-transform-target assembly)
  (scene-state-update
   state
   id
   (formula-assembly-visual-with-parts
    assembly
    (formula-transition-plan-sample-parts
     (formula-parts-transform-animation-plan animation)
     progress)
    #:source-map
    (formula-transition-plan-source-map-at
     (formula-parts-transform-animation-plan animation)
     progress))))

; apply-path-reveal-animation : scene-state? path-reveal-animation?
;                               finite-real? -> scene-state?
;;   Applies one compiled path-prefix reveal at progress.
(define (apply-path-reveal-animation state animation progress)
  (define id
    (path-reveal-animation-target-id animation))
  (define visual
    (scene-state-ref state id))
  (define visible-fraction
    (real-lerp (path-reveal-animation-from animation)
               (path-reveal-animation-to animation)
               progress))
  (scene-state-update
   state
   id
   (path-visual-with-path
    visual
    (path-geometry-partial
     (path-reveal-animation-path animation)
     0
     visible-fraction))))

;; apply-relation-path-reveal-animation : scene-state?
;;                                         relation-path-reveal-animation?
;;                                         finite-real? -> scene-state?
;; Stores a deferred effect definition.  The actual path is intentionally not
;; resolved here: ordinary animation sampling has no renderer/layout context,
;; and resolving now would freeze geometry before the final semantic/layout
;; pass for this same frame.
(define (apply-relation-path-reveal-animation state animation progress)
  (define id (relation-path-reveal-animation-target-id animation))
  (define stored (scene-state-ref state id))
  (define relation
    (if (relation-path-reveal-visual? stored)
        (relation-path-reveal-visual-relation stored)
        stored))
  (unless (relation-visual? relation)
    (raise-arguments-error
     'apply-relation-path-reveal-animation
     "a relation Visual target"
     "visual-id" id
     "visual" stored))
  (scene-state-update
   state id
   (make-relation-path-reveal-visual
    relation progress
    #:reverse? (relation-path-reveal-animation-reverse? animation))))

; apply-write-in-animation : scene-state? write-in-animation? finite-real?
;                           (-> finite-real? finite-real?) -> scene-state?
;; Samples the vector-only write proxy without changing the caller's endpoint.
(define (apply-write-in-animation state animation progress scene-rate-func)
  (define id
    (write-in-animation-target-id animation))
  (define plan
    (write-in-animation-plan animation))
  (cond
    ;; Preserve an unwrite's source object exactly at its first frame.  The
    ;; next sample uses the writable proxy while its outline begins to erase.
    [(and (write-in-animation-remove-at-end? animation)
          (zero? progress))
     (scene-state-update state id (write-plan-endpoint plan))]
    [else
     (scene-state-update
      state
      id
      (write-plan-sample plan
                         progress
                         #:scene-rate-func scene-rate-func
                         #:remove? (write-in-animation-remove-at-end? animation)))]))


;;;
;;; Animated Write Planning and Sampling
;;;

; make-write-plan : visual? symbol? (or/c false/c nonnegative-real?)
;                   nonnegative-real? symbol? boolean? procedure? -> write-plan?
;; Converts the requested endpoint to a path/group-only proxy and assigns each
;; leaf a normalized overlapping interval.  The default mirrors Manim's useful
;; small-object heuristic: min(0.2, 4/N).
(define (make-write-plan endpoint
                         order
                         requested-lag-ratio
                         outline-stroke-width
                         reveal
                         reverse?
                         rate-func)
  (define proxy
    (write-proxy-visual endpoint))
  (unless (eq? (visual-id proxy) (visual-id endpoint))
    (raise-arguments-error
     'write-in
     "a write-path adapter that preserves the Visual identity"
     "endpoint-id" (visual-id endpoint)
     "proxy-id" (visual-id proxy)))
  (define collected
    (write-collect-path-leaves proxy))
  (define ordered
    (case order
      [(document) collected]
      [(left-to-right)
       (sort collected
             (lambda (left right)
               (define left-position
                 (visual-position (write-leaf-visual left)))
               (define right-position
                 (visual-position (write-leaf-visual right)))
               (cond [(< (vec2-x left-position) (vec2-x right-position)) #t]
                     [(> (vec2-x left-position) (vec2-x right-position)) #f]
                     [else (> (vec2-y left-position) (vec2-y right-position))])))]))
  (define count (length ordered))
  (define lag-ratio
    (or requested-lag-ratio
        (if (zero? count)
            0
            (min 1/5 (/ 4 count)))))
  (define span
    (+ 1 (* (max 0 (sub1 count)) lag-ratio)))
  (define leaves
    (for/list ([leaf (in-list ordered)]
               [index (in-naturals)])
      (write-leaf
       (write-leaf-id leaf)
       (write-leaf-visual leaf)
       (/ (* index lag-ratio) span)
       (/ 1 span))))
  (write-plan endpoint
              proxy
              leaves
              outline-stroke-width
              reveal
              reverse?
              rate-func))

; write-proxy-visual : visual? -> (or/c path-visual? group-visual?)
;; Rebuilds a supported Visual tree as only groups and path Visuals.
(define (write-proxy-visual visual)
  (cond
    [(path-visual? visual) visual]
    [(circle-visual? visual) (write-circle-proxy visual)]
    [(rectangle-visual? visual) (write-rectangle-proxy visual)]
    [(group-visual? visual)
     (group-visual-with-children
      visual
      (for/list ([child (in-list (group-visual-children visual))])
        (write-proxy-visual child)))]
    [(formula-assembly-visual? visual)
     (write-proxy-visual (formula-assembly-visual-group visual))]
    [(write-path-source? visual)
     (write-proxy-visual (write-path-source->visual visual))]
    [else
     (raise-arguments-error
      'write-in
      "a path Visual, group of write-capable Visuals, supported SVG shape, or tagged formula"
      "visual-id" (visual-id visual)
      "visual" visual)]))

; write-collect-path-leaves : (or/c path-visual? group-visual?)
;;                            -> (listof write-leaf?)
;; Collects leaves in document order.  Resolved transforms are stored solely
;; for stable left-to-right ordering; sampling uses the untouched proxy tree.
(define (write-collect-path-leaves proxy)
  (define seen (make-hash))
  (define (collect visual)
    (cond
      [(path-visual? visual)
       (define id (visual-id visual))
       (when (hash-has-key? seen id)
         (raise-arguments-error
          'write-in
          "a write proxy with unique path identities"
          "duplicate-path-id" id))
       (hash-set! seen id #t)
       (list (write-leaf id visual 0 1))]
      [(group-visual? visual)
       (append-map collect (group-visual-resolved-children visual))]
      [else
       (raise-arguments-error
        'write-in
        "a path/group-only write proxy"
        "proxy-visual" visual)]))
  (collect proxy))

; write-plan-sample : write-plan? finite-real?
;                    [#:scene-rate-func (-> finite-real? finite-real?)]
;                    [#:remove? boolean?]
;                    -> visual?
;; Samples every leaf while retaining the proxy's complete group layout.
(define (write-plan-sample plan
                           progress
                           #:scene-rate-func [scene-rate-func linear]
                           #:remove? [remove? #f])
  (check-write-rate-func 'write-plan-sample scene-rate-func)
  (define chronological-leaves
    (if (write-plan-reverse? plan)
        (reverse (write-plan-leaves plan))
        (write-plan-leaves plan)))
  ;; The stored interval slots are in chronological order.  Pair them with the
  ;; traversal order above, so reversing a write starts the last leaf first.
  (define timing-slots
    (write-plan-leaves plan))
  (define progress-by-id
    (for/hash ([leaf (in-list chronological-leaves)]
               [slot (in-list timing-slots)])
      (define scheduled-progress
        (clamp-unit
         (/ (- progress (write-leaf-start slot))
            (write-leaf-duration slot))))
      ;; Manim applies the rate function after a submobject's stagger offset.
      ;; Animate's clip easing participates at that same local point, keeping
      ;; later leaves from being delayed by a globally eased clock.
      (define eased-progress
        (clamp-unit
         ((write-plan-rate-func plan)
          (clamp-unit (scene-rate-func scheduled-progress)))))
      (values
       (write-leaf-id leaf)
       (if remove?
           (- 1 eased-progress)
           eased-progress))))
  (write-sample-proxy
   (write-plan-proxy plan)
   progress-by-id
   (write-plan-outline-stroke-width plan)
   (write-plan-reveal plan)
   (write-plan-reverse? plan)))

(define (write-sample-proxy visual
                            progress-by-id
                            outline-stroke-width
                            reveal
                            reverse?)
  (cond
    [(path-visual? visual)
     (define local-progress
       (hash-ref
        progress-by-id
        (visual-id visual)
        (lambda ()
          (raise-arguments-error
           'write-in
           "a write schedule for every proxy path"
           "path-id" (visual-id visual)))))
     (write-sample-path visual
                        local-progress
                        outline-stroke-width
                        reveal
                        reverse?)]
    [(group-visual? visual)
     (group-visual-with-children
      visual
      (for/list ([child (in-list (group-visual-children visual))])
        (write-sample-proxy child
                            progress-by-id
                            outline-stroke-width
                            reveal
                            reverse?)))]
    [else
     (raise-argument-error 'write-in "path/group-only write proxy" visual)]))

; write-sample-path : path-visual? finite-real? nonnegative-real? symbol?
;                     boolean? -> path-visual?
;; Implements DrawBorderThenFill: phase one traces an outline prefix, phase two
;; holds the complete outline while it transitions to the target paint.
(define (write-sample-path target
                           local-progress
                           outline-stroke-width
                           reveal
                           reverse?)
  (define u (clamp-unit local-progress))
  (define outline-color (write-outline-color target))
  (define target-path
    (path-visual-path target))
  ;; Reversing controls the direction in which the outline is traced.  Do not
  ;; reverse the complete, painted path: a glyph can contain several closed
  ;; contours (for example, the counter in `a` or `b`), whose winding
  ;; directions are significant to some renderers.  Keeping the source
  ;; geometry during the paint phase also makes the proxy match the target
  ;; exactly as soon as it becomes filled.
  (define trace-path
    (if reverse?
        (path-geometry-reverse target-path)
        target-path))
  (cond
    [(<= u 1/2)
     (write-path-with-style
      target
      (write-partial-path trace-path 0 (* 2 u) reveal)
      #f
      outline-color
      outline-stroke-width)]
    [else
     (define paint-progress (* 2 (- u 1/2)))
     (write-path-with-style
      target
      target-path
      (write-fade-color (path-visual-fill target) paint-progress)
      (write-transition-stroke target outline-color paint-progress)
      (real-lerp outline-stroke-width
                 (if (path-visual-stroke target)
                     (path-visual-stroke-width target)
                     0)
                 paint-progress))]))

(define (write-partial-path geometry start end reveal)
  (case reveal
    [(bezier) (path-geometry-partial-by-curves geometry start end)]
    [(arc-length) (path-geometry-partial geometry start end)]
    [else
     (raise-argument-error
      'write-in
      "(or/c 'bezier 'arc-length)"
      reveal)]))

(define (write-path-with-style target geometry fill stroke stroke-width)
  (make-path-visual
   geometry
   #:id (visual-id target)
   #:center (visual-position target)
   #:rotation (visual-rotation target)
   #:scale (visual-scale target)
   #:opacity (visual-opacity target)
   #:fill fill
   #:stroke stroke
   #:stroke-width stroke-width))

(define (write-outline-color target)
  (cond [(color-spec? (path-visual-stroke target))
         (path-visual-stroke target)]
        [(color-spec? (path-visual-fill target))
         (path-visual-fill target)]
        [else "black"]))

(define (write-transition-stroke target outline-color progress)
  (define destination (path-visual-stroke target))
  (cond [(color-spec? destination)
         (write-color-lerp outline-color destination progress)]
        [(not destination)
         (write-fade-color outline-color (- 1 progress))]
        [(= progress 1) destination]
        [else outline-color]))

(define (write-fade-color color progress)
  (cond [(not color) #f]
        [(color-spec? color)
         (define rgba (color-spec->rgba-color color 'write-in))
         (rgba-color (rgba-color-red rgba)
                     (rgba-color-green rgba)
                     (rgba-color-blue rgba)
                     (* (rgba-color-alpha rgba) (clamp-unit progress)))]
        [(= progress 1) color]
        [else #f]))

(define (write-color-lerp from to progress)
  (cond [(and (color-spec? from) (color-spec? to))
         (rgba-color-lerp (color-spec->rgba-color from 'write-in)
                          (color-spec->rgba-color to 'write-in)
                          (clamp-unit progress))]
        [(= progress 1) to]
        [else from]))

;; Circle and rectangle Visuals occur in the useful semantic SVG subset.  They
;; are normalised to cubic/line paths for writing but restored exactly at end.
(define (write-circle-proxy visual)
  (define radius (circle-visual-radius visual))
  (define k 0.5522847498307936)
  (define (point x y) (vec2 (* radius x) (* radius y)))
  (make-path-visual
   (path-geometry
    (list
     (path-subpath
      (point 1 0)
      (list (cubic-bezier-path-segment (point 1 k) (point k 1) (point 0 1))
            (cubic-bezier-path-segment (point (- k) 1) (point -1 k) (point -1 0))
            (cubic-bezier-path-segment (point -1 (- k)) (point (- k) -1) (point 0 -1))
            (cubic-bezier-path-segment (point k -1) (point 1 (- k)) (point 1 0)))
      #t)))
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (circle-visual-fill visual)
   #:stroke (circle-visual-stroke visual)
   #:stroke-width (circle-visual-stroke-width visual)))

(define (write-rectangle-proxy visual)
  (define half-width (/ (rectangle-visual-width visual) 2))
  (define half-height (/ (rectangle-visual-height visual) 2))
  (make-path-visual
   (polygon-path
    (list (vec2 (- half-width) (- half-height))
          (vec2 half-width (- half-height))
          (vec2 half-width half-height)
          (vec2 (- half-width) half-height)))
   #:id (visual-id visual)
   #:center (visual-position visual)
   #:rotation (visual-rotation visual)
   #:scale (visual-scale visual)
   #:opacity (visual-opacity visual)
   #:fill (rectangle-visual-fill visual)
   #:stroke (rectangle-visual-stroke visual)
   #:stroke-width (rectangle-visual-stroke-width visual)))

; complete-compiled-animations : scene-state?
;                                (listof compiled-animation?)
;                                (-> finite-real? finite-real?)
;                                -> scene-state?
;;   Produces the structural endpoint after all animations complete.
(define (complete-compiled-animations state animations easing)
  (define sampled-state
    (apply-compiled-animations state animations 1 easing))
  (for/fold ([completed-state sampled-state])
            ([animation (in-list animations)])
    (finalize-compiled-animation completed-state animation)))

; finalize-compiled-animation : scene-state? compiled-animation? -> scene-state?
;;   Applies only the structural endpoint rule of one already-sampled animation.
;;   SCENE-AN uses this after all component values at a local boundary have been
;;   sampled, preserving historical simultaneous endpoint ordering.
(define (finalize-compiled-animation state animation)
  (unless (scene-state? state)
    (raise-argument-error
     'finalize-compiled-animation
     "scene-state?"
     state))
  (unless (compiled-animation? animation)
    (raise-argument-error
     'finalize-compiled-animation
     "compiled animation"
     animation))
  (cond
    [(and (opacity-animation? animation)
          (opacity-animation-remove-at-end? animation))
     (scene-state-remove
      state
      (opacity-animation-target-id animation))]
    [(and (opacity-animation? animation)
          (opacity-animation-force-to-at-end? animation))
     (define id
       (opacity-animation-target-id animation))
     (define visual
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (replace-visual-opacity
       'scene-play
       visual
       (opacity-animation-to animation)))]
    [(transform-shape-animation? animation)
     (define cleaned-state
       (if (scene-state-has?
            state
            (transform-shape-animation-overlay-id animation))
           (scene-state-remove
            state
            (transform-shape-animation-overlay-id animation))
           state))
     (scene-state-add
      (scene-state-remove
       cleaned-state
      (transform-shape-animation-source-id animation))
      (transform-shape-animation-destination animation))]
    [(transform-matching-visuals-animation? animation)
     (define cleaned-state
       (if (scene-state-has?
            state
            (transform-matching-visuals-animation-overlay-id animation))
           (scene-state-remove
            state
            (transform-matching-visuals-animation-overlay-id animation))
           state))
     (scene-state-add
      (scene-state-remove
       cleaned-state
       (transform-matching-visuals-animation-source-id animation))
      (transform-matching-visuals-animation-destination animation))]
    [(transform-from-copy-animation? animation)
     (define cleaned-state
       (if (scene-state-has?
            state
            (transform-from-copy-animation-overlay-id animation))
           (scene-state-remove
            state
            (transform-from-copy-animation-overlay-id animation))
           state))
     (scene-state-add
      cleaned-state
      (transform-from-copy-animation-destination animation))]
    [(attention-animation? animation)
     (if (scene-state-has? state (attention-animation-overlay-id animation))
         (scene-state-remove state (attention-animation-overlay-id animation))
         state)]
    [(formula-parts-transform-animation? animation)
     (define id
       (formula-parts-transform-animation-target-id animation))
     (define assembly
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (formula-assembly-visual-with-parts
       assembly
       (formula-transition-plan-destination-parts
        (formula-parts-transform-animation-plan animation))
       #:source-map
       (formula-transition-plan-source-map-at
        (formula-parts-transform-animation-plan animation)
        1)))]
    [(and (path-reveal-animation? animation)
          (path-reveal-animation-remove-at-end? animation))
     (scene-state-remove
      state
      (path-reveal-animation-target-id animation))]
    [(path-reveal-animation? animation)
     (define id
       (path-reveal-animation-target-id animation))
     (define visual
       (scene-state-ref state id))
     (scene-state-update
      state
      id
      (path-visual-with-path
      visual
      (path-reveal-animation-path animation)))]
    [(and (relation-path-reveal-animation? animation)
          (relation-path-reveal-animation-remove-at-end? animation))
     (scene-state-remove
      state
      (relation-path-reveal-animation-target-id animation))]
    [(relation-path-reveal-animation? animation)
     ;; Creation retains the relation definition itself, not the final concrete
     ;; path sampled for this particular frame. This preserves dynamic
     ;; dependencies for all later clips and random-access renders.
     (define id (relation-path-reveal-animation-target-id animation))
     (define stored (scene-state-ref state id))
     (scene-state-update
      state id
      (if (relation-path-reveal-visual? stored)
          (relation-path-reveal-visual-relation stored)
          stored))]
    [(write-in-animation? animation)
     (if (write-in-animation-remove-at-end? animation)
         (scene-state-remove state (write-in-animation-target-id animation))
         (scene-state-update
          state
          (write-in-animation-target-id animation)
          (write-plan-endpoint
           (write-in-animation-plan animation))))]
    [else
     state]))

; clamp-unit : any/c -> real?
;;   Validates value and clamps it to the closed unit interval.
(define (clamp-unit value)
  (unless (finite-real? value)
    (raise-arguments-error
     'animation-easing
     "an easing function must produce a finite real number"
     "result" value))
  (min 1 (max 0 value)))


;;;
;;; Validation
;;;

; check-numeric-animation-value : symbol? any/c -> void?
;; Validates the finite scalar domain intentionally supported by numerical
;; animation requests.  `finite-complex?` excludes a real number, so these two
;; cases cover each finite real or cartesian complex value exactly once.
(define (check-numeric-animation-value who value)
  (unless (or (finite-real? value) (finite-complex? value))
    (raise-argument-error
     who
     "finite real or finite complex number"
     value)))

; check-finite-real-value : symbol? any/c -> void?
;; Validates the real counter domain used by count-from and count-to.
(define (check-finite-real-value who value)
  (unless (finite-real? value)
    (raise-argument-error who "finite-real?" value)))

; check-path-motion-fraction : symbol? string? any/c -> void?
;;   Raises unless value is a finite real in the closed unit interval.
(define (check-path-motion-fraction who field-name value)
  (unless (and (finite-real? value)
               (<= 0 value 1))
    (raise-arguments-error
     who
     "path fractions must be finite reals in the closed unit interval"
     field-name value)))

; normalize-path-animation-source : symbol? any/c
;                                   -> (or/c path-geometry? symbol?)
;;   Converts one public path argument to immutable request data.
(define (normalize-path-animation-source who path)
  (cond
    [(path-geometry? path)
     path]
    [(path-visual? path)
     (visual-id path)]
    [(resolvable-visual? path)
     (visual-id path)]
    [(symbol? path)
     path]
    [else
     (raise-argument-error
      who
      "(or/c path-geometry? path-visual? resolvable-visual? symbol?)"
      path)]))

; resolve-path-animation-route : scene-state? visual?
;                                (or/c path-geometry? symbol?) symbol?
;                                finite-real? finite-real?
;                                -> path-geometry?
;;   Resolves and validates one continuous route in target coordinates.
(define (resolve-path-animation-route state target source operation start end)
  (define operation-name
    (symbol->string operation))
  (define path
    (cond
      [(path-geometry? source)
       source]
      [(symbol? source)
       (unless (scene-state-has? state source)
         (raise-arguments-error
          'scene-play
          (string-append operation-name
                         " requires its path Visual to be present at clip start")
          "path-visual-id" source))
       (define path-visual-value
         (scene-state-resolved-ref state source))
       (unless (path-visual? path-visual-value)
         (raise-arguments-error
          'scene-play
          (string-append operation-name " requires a path Visual route")
          "path-visual-id" source
          "visual" path-visual-value))
       (when (frame-space-visual? target)
         (raise-arguments-error
          'scene-play
          "a world-space path Visual cannot drive a frame-space target"
          "operation" operation
          "target-id" (visual-id target)
          "path-visual-id" source))
       (path-geometry-map-points
        (path-visual-path path-visual-value)
        (lambda (point)
          (affine-transform-apply-point
           (visual-transform path-visual-value)
           point)))]
      [else
       (raise-argument-error
        'resolve-path-animation-route
        "(or/c path-geometry? symbol?)"
        source)]))
  (check-path-animation-route path operation start end)
  path)

; check-path-animation-route : path-geometry? symbol? finite-real? finite-real?
;                              -> void?
;;   Requires one finite, positive-length, continuous subpath.
(define (check-path-animation-route path operation start end)
  (define operation-name
    (symbol->string operation))
  (define total-length
    (path-geometry-length path))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     'scene-play
     (string-append operation-name " requires a positive finite route length")
     "path-length" total-length
     "path" path))
  (define positive-subpath-count
    (for/sum ([subpath (in-list (path-geometry-subpaths path))])
      (if (positive? (path-subpath-length subpath)) 1 0)))
  (unless (= positive-subpath-count 1)
    (raise-arguments-error
     'scene-play
     (string-append operation-name
                    " requires one continuous positive-length subpath")
     "positive-subpath-count" positive-subpath-count
     "path" path))
  ;; Evaluate both requested endpoints now so transformed overflow or malformed
  ;; internal path data is rejected during clip compilation rather than sampling.
  (path-geometry-point-at path start)
  (path-geometry-point-at path end)
  (void))

; check-animation-scale : symbol? any/c -> void?
;;   Raises an argument error unless scale is positive and finite.
(define (check-animation-scale who scale)
  (unless (scale-factor? scale)
    (raise-argument-error
     who
     "positive finite real or vec2 with positive components"
     scale)))

; check-positive-finite-real : symbol? any/c -> void?
;; Validates positive secondary-camera widths and magnification factors.
(define (check-positive-finite-real who value)
  (unless (and (finite-real? value) (positive? value))
    (raise-argument-error who "positive finite real?" value)))

; check-camera-view-animation-target : symbol? any/c -> void?
;; Accepts a named view or a directly supplied camera-view Visual.
(define (check-camera-view-animation-target who target)
  (unless (or (symbol? target) (camera-view-visual? target))
    (raise-argument-error who "(or/c symbol? camera-view-visual?)" target))
  (void))

; camera-view-animation-target-id : (or/c symbol? camera-view-visual?) symbol?
;; Normalizes a direct camera-view target to its stable scene identity.
(define (camera-view-animation-target-id target who)
  (if (symbol? target)
      target
      (visual-target-id target who)))

; check-world-follow-target : symbol? any/c -> void?
;; Validates the public form; sampled-state resolution proves world-space later.
(define (check-world-follow-target who target)
  (unless (or (symbol? target) (visual-path? target) (visual? target))
    (raise-argument-error who "(or/c visual? symbol? visual-path?)" target))
  (when (and (visual? target) (frame-space-visual? target))
    (raise-arguments-error who "a world-space Visual follow target" "target" target))
  (visual-target-id target who)
  (void))

; check-affine-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports the requested affine component.
(define (check-affine-animation-target visual component)
  (unless (affine-visual? visual)
    (raise-arguments-error
     'scene-play
     "rotation and scaling require an affine Visual"
     "visual-id" (visual-id visual)
     "component" component
     "visual" visual)))


; check-scale-animation-endpoint : affine-visual? vec2? -> void?
;;   Checks that an affine Visual accepts a requested scale endpoint.
(define (check-scale-animation-endpoint visual scale)
  (define id
    (visual-id visual))
  (define result
    (visual-with-scale visual scale))
  (unless (and (visual? result)
               (affine-visual? result))
    (raise-arguments-error
     'scene-play
     "visual-with-scale must return an affine Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     'scene-play
     "visual-with-scale must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (unless (equal? (visual-scale result) scale)
    (raise-arguments-error
     'scene-play
     "visual-with-scale must install the requested scale"
     "visual-id" id
     "requested-scale" scale
     "result-scale" (visual-scale result)))
  (void))

; check-animation-opacity : symbol? any/c -> void?
;;   Raises an argument error unless opacity is in the closed unit interval.
(define (check-animation-opacity who opacity)
  (unless (opacity? opacity)
    (raise-argument-error
     who
     "finite real in [0, 1]"
     opacity)))

; check-animation-stroke-width : symbol? any/c -> void?
;;   Raises an argument error unless width is nonnegative and finite.
(define (check-animation-stroke-width who stroke-width)
  (unless (stroke-width? stroke-width)
    (raise-argument-error
     who
     "nonnegative finite real?"
     stroke-width)))

; check-stroke-width-request-target : symbol? any/c -> void?
;;   Validates a public stroke-width animation target argument.
(define (check-stroke-width-request-target who target)
  (unless (or (symbol? target)
              (visual-path? target)
              (and (visual? target)
                   (stroke-width-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? visual-path? (and/c visual? stroke-width-visual?))"
     target))
  (when (and (visual? target)
             (stroke-width-visual? target))
    (checked-visual-stroke-width who target)))

; check-stroke-width-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports valid semantic stroke width.
(define (check-stroke-width-animation-target visual operation)
  (unless (stroke-width-visual? visual)
    (raise-arguments-error
     'scene-play
     "stroke-width animation requires a stroke-width Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-stroke-width 'scene-play visual))

; checked-visual-stroke-width : symbol? stroke-width-visual? -> stroke-width?
;;   Returns visual stroke width after checking the protocol result.
(define (checked-visual-stroke-width who visual)
  (define stroke-width
    (visual-stroke-width visual))
  (unless (stroke-width? stroke-width)
    (raise-arguments-error
     who
     "a stroke-width Visual must return a nonnegative finite real"
     "visual" visual
     "stroke-width" stroke-width))
  stroke-width)

; replace-visual-stroke-width : symbol? stroke-width-visual? stroke-width?
;                               -> stroke-width-visual?
;;   Replaces stroke width and validates the resulting Visual protocol value.
(define (replace-visual-stroke-width who visual stroke-width)
  (check-animation-stroke-width who stroke-width)
  (define id
    (visual-id visual))
  (define result
    (visual-with-stroke-width visual stroke-width))
  (unless (and (visual? result)
               (stroke-width-visual? result))
    (raise-arguments-error
     who
     "visual-with-stroke-width must return a stroke-width Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-stroke-width must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-stroke-width
    (checked-visual-stroke-width who result))
  ;; Use equal? rather than numeric = here. The protocol promises to install
  ;; the requested semantic endpoint exactly, including exact/inexact numeric
  ;; representation. A custom setter that silently turns exact 7 into 7.0 must
  ;; therefore be rejected even though the two values are numerically equal.
  (unless (equal? result-stroke-width stroke-width)
    (raise-arguments-error
     who
     "visual-with-stroke-width must install the requested stroke width exactly"
     "requested-stroke-width" stroke-width
     "result-stroke-width" result-stroke-width))
  result)

; check-animation-color-spec : symbol? any/c -> void?
;;   Raises an argument error unless color is a supported semantic color spec.
(define (check-animation-color-spec who color)
  (unless (color-spec? color)
    (raise-argument-error who "color-spec?" color)))

; check-animation-paint : symbol? any/c -> void?
;;   Raises an argument error unless paint is a supported semantic fill paint.
(define (check-animation-paint who paint)
  (unless (paint? paint)
    (raise-argument-error who "paint?" paint)))

; check-fill-color-request-target : symbol? any/c -> void?
;;   Validates a public fill-color animation target argument.
(define (check-fill-color-request-target who target)
  (unless (or (symbol? target)
              (visual-path? target)
              (and (visual? target)
                   (fill-color-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? visual-path? (and/c visual? fill-color-visual?))"
     target))
  (when (and (visual? target)
             (fill-color-visual? target))
    (checked-visual-fill-color who target)))

; check-stroke-color-request-target : symbol? any/c -> void?
;;   Validates a public stroke-color animation target argument.
(define (check-stroke-color-request-target who target)
  (unless (or (symbol? target)
              (visual-path? target)
              (and (visual? target)
                   (stroke-color-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? visual-path? (and/c visual? stroke-color-visual?))"
     target))
  (when (and (visual? target)
             (stroke-color-visual? target))
    (checked-visual-stroke-color who target)))

; check-fill-color-animation-target : visual? symbol? -> void?
(define (check-fill-color-animation-target visual operation)
  (unless (fill-color-visual? visual)
    (raise-arguments-error
     'scene-play
     "fill-color animation requires a fill-color Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-fill-color 'scene-play visual))

; check-stroke-color-animation-target : visual? symbol? -> void?
(define (check-stroke-color-animation-target visual operation)
  (unless (stroke-color-visual? visual)
    (raise-arguments-error
     'scene-play
     "stroke-color animation requires a stroke-color Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-stroke-color 'scene-play visual))

; checked-visual-fill-color : symbol? fill-color-visual? -> paint?
(define (checked-visual-fill-color who visual)
  (define paint
    (visual-fill-color visual))
  (unless (paint? paint)
    (raise-arguments-error
     who
     "a fill-color Visual must return a supported semantic paint"
     "visual" visual
     "fill-color" paint))
  paint)

; checked-visual-stroke-color : symbol? stroke-color-visual? -> color-spec?
(define (checked-visual-stroke-color who visual)
  (define color
    (visual-stroke-color visual))
  (unless (color-spec? color)
    (raise-arguments-error
     who
     "a stroke-color Visual must return a supported color specification"
     "visual" visual
     "stroke-color" color))
  color)

; replace-visual-fill-color : symbol? fill-color-visual? paint?
;                             -> fill-color-visual?
(define (replace-visual-fill-color who visual color)
  (check-animation-paint who color)
  (define id (visual-id visual))
  (define result (visual-with-fill-color visual color))
  (unless (and (visual? result) (fill-color-visual? result))
    (raise-arguments-error
     who
     "visual-with-fill-color must return a fill-color Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-fill-color must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-color (checked-visual-fill-color who result))
  (unless (equal? result-color color)
    (raise-arguments-error
     who
     "visual-with-fill-color must install the requested fill color exactly"
     "requested-fill-color" color
     "result-fill-color" result-color))
  result)

; replace-visual-stroke-color : symbol? stroke-color-visual? color-spec?
;                               -> stroke-color-visual?
(define (replace-visual-stroke-color who visual color)
  (check-animation-color-spec who color)
  (define id (visual-id visual))
  (define result (visual-with-stroke-color visual color))
  (unless (and (visual? result) (stroke-color-visual? result))
    (raise-arguments-error
     who
     "visual-with-stroke-color must return a stroke-color Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-stroke-color must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-color (checked-visual-stroke-color who result))
  (unless (equal? result-color color)
    (raise-arguments-error
     who
     "visual-with-stroke-color must install the requested stroke color exactly"
     "requested-stroke-color" color
     "result-stroke-color" result-color))
  result)

; check-opacity-request-target : symbol? any/c -> void?
;;   Validates a public opacity-animation target argument.
(define (check-opacity-request-target who target)
  (unless (or (symbol? target)
              (visual-path? target)
              (and (visual? target)
                   (opacity-visual? target)))
    (raise-argument-error
     who
     "(or/c symbol? visual-path? (and/c visual? opacity-visual?))"
     target))
  (when (and (visual? target)
             (opacity-visual? target))
    (checked-visual-opacity who target)))

; check-opacity-visual-value : symbol? any/c -> void?
;;   Validates a complete Visual supplied to an opacity introduction request.
(define (check-opacity-visual-value who visual)
  (unless (and (visual? visual)
               (opacity-visual? visual))
    (raise-argument-error
     who
     "(and/c visual? opacity-visual?)"
     visual))
  (visual-target-id visual who)
  (checked-visual-opacity who visual))

; check-opacity-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual supports valid semantic opacity.
(define (check-opacity-animation-target visual operation)
  (unless (opacity-visual? visual)
    (raise-arguments-error
     'scene-play
     "opacity animation requires an opacity Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (checked-visual-opacity 'scene-play visual))

; checked-visual-opacity : symbol? (and/c visual? opacity-visual?) -> opacity?
;;   Returns visual opacity after checking the protocol result.
(define (checked-visual-opacity who visual)
  (define opacity
    (visual-opacity visual))
  (unless (opacity? opacity)
    (raise-arguments-error
     who
     "an opacity Visual must return a finite real in [0, 1]"
     "visual" visual
     "opacity" opacity))
  opacity)

; replace-visual-opacity : symbol? (and/c visual? opacity-visual?) opacity?
;                          -> (and/c visual? opacity-visual?)
;;   Replaces opacity and validates the resulting Visual protocol value.
(define (replace-visual-opacity who visual opacity)
  (check-animation-opacity who opacity)
  (define id
    (visual-id visual))
  (define result
    (visual-with-opacity visual opacity))
  (unless (and (visual? result)
               (opacity-visual? result))
    (raise-arguments-error
     who
     "visual-with-opacity must return an opacity Visual"
     "visual-id" id
     "result" result))
  (unless (eq? (visual-id result) id)
    (raise-arguments-error
     who
     "visual-with-opacity must preserve Visual identity"
     "expected-id" id
     "result-id" (visual-id result)))
  (define result-opacity
    (checked-visual-opacity who result))
  (unless (= result-opacity opacity)
    (raise-arguments-error
     who
     "visual-with-opacity must install the requested opacity"
     "requested-opacity" opacity
     "result-opacity" result-opacity))
  result)

; check-absent-introduction-target : scene-state? symbol? symbol? -> void?
;;   Raises an error when a structural introduction target is already present.
(define (check-absent-introduction-target state id operation)
  (when (scene-state-has? state id)
    (raise-arguments-error
     'scene-play
     "an introduction request requires a Visual identity absent from the scene"
     "visual-id" id
     "operation" operation)))

; check-formula-transform-target : visual? -> void?
;;   Raises an error unless visual is a semantic formula assembly.
(define (check-formula-transform-target visual)
  (unless (formula-assembly-visual? visual)
    (raise-arguments-error
     'scene-play
     "transform-formula-parts requires a formula assembly"
     "visual-id" (visual-id visual)
     "visual" visual)))

; anchor-formula-correspondence : formula-assembly-visual? formula-correspondence?
;                                 (or/c #f formula-part-match?)
;                                 (listof formula-part-match?)
;                                 -> formula-correspondence?
;;   Translates the complete destination layout so an anchor pair coincides
;;   with the current formula at clip compilation. Keeping this late makes a
;;   rewrite reliable after earlier transitions have repositioned the formula.
;;   Explicit stationary pairs then retain their own current transforms, which
;;   lets more than one formula part remain fixed when the target layout calls
;;   for a different local spacing.
(define (anchor-formula-correspondence current-source correspondence anchor stationary)
  (define anchored-correspondence
    (cond
      [(not anchor) correspondence]
      [else
       (define destination
         (formula-correspondence-destination correspondence))
       (define source-anchor
         (formula-part-formula
          (formula-assembly-visual-ref
           current-source
           (formula-part-match-source-name anchor))))
       (define destination-anchor
         (formula-part-formula
          (formula-assembly-visual-ref
           destination
           (formula-part-match-destination-name anchor))))
       (define shift
         (vec2- (visual-position source-anchor)
                (visual-position destination-anchor)))
       (define anchored-destination
         (formula-assembly-visual-with-parts
          destination
          (for/list ([part (in-list (formula-assembly-visual-parts destination))])
            (formula-part
             (formula-part-name part)
             (visual-with-position
              (formula-part-formula part)
              (vec2+ (visual-position (formula-part-formula part)) shift))))
          ;; Translation preserves every destination local identity and path.
          #:source-map (formula-assembly-visual-source-map destination)))
       (formula-correspondence
        (formula-correspondence-source correspondence)
        anchored-destination
        (formula-correspondence-matches correspondence))]))
  (if (null? stationary)
      anchored-correspondence
      (let* ([destination
              (formula-correspondence-destination anchored-correspondence)]
             [stationary-by-destination
              (for/hash ([match (in-list stationary)])
                (values (formula-part-match-destination-name match) match))]
             [fixed-destination
              (formula-assembly-visual-with-parts
               destination
               (for/list ([part (in-list (formula-assembly-visual-parts destination))])
                 (define match
                   (hash-ref stationary-by-destination (formula-part-name part) #f))
                 (if match
                     (let ([current-formula
                            (formula-part-formula
                             (formula-assembly-visual-ref
                              current-source
                              (formula-part-match-source-name match)))])
                       (formula-part
                        (formula-part-name part)
                        (visual-with-transform
                         (formula-part-formula part)
                         (visual-transform current-formula))))
                     part))
               ;; Stationary placement also preserves the exact part tree.
               #:source-map (formula-assembly-visual-source-map destination))])
        (formula-correspondence
         (formula-correspondence-source anchored-correspondence)
         fixed-destination
         (formula-correspondence-matches anchored-correspondence)))))

; check-path-morph-request-arguments : symbol? any/c any/c -> void?
;;   Validates one public path-morph request constructor call.
(define (check-path-morph-request-arguments who target destination)
  (unless (or (symbol? target)
              (visual-path? target)
              (path-visual? target))
    (raise-argument-error
     who
     "(or/c path-visual? symbol? visual-path?)"
     target))
  (unless (path-geometry? destination)
    (raise-argument-error who "path-geometry?" destination)))

; check-path-morph-target : visual? symbol? -> void?
;;   Raises an error unless visual is a built-in semantic path Visual.
(define (check-path-morph-target visual operation)
  (unless (path-visual? visual)
    (raise-arguments-error
     'scene-play
     (format "~a requires a path Visual" operation)
     "visual-id" (visual-id visual)
     "visual" visual)))

; check-path-animation-target : visual? symbol? -> void?
;;   Raises an error unless visual is a built-in semantic path Visual.
(define (check-path-animation-target visual operation)
  (unless (path-visual? visual)
    (raise-arguments-error
     'scene-play
     "Create and Uncreate require a path Visual"
     "visual-id" (visual-id visual)
     "operation" operation
     "visual" visual))
  (define path-length
    (path-geometry-length (path-visual-path visual)))
  (unless (finite-real? path-length)
    (raise-arguments-error
     'scene-play
     "Create and Uncreate require a finite path length"
     "visual-id" (visual-id visual)
     "operation" operation
     "path-length" path-length)))
