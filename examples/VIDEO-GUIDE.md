# Example Video Guide

Rendered MP4 files live in the local sibling directory
[`../rendered-examples/`](../rendered-examples/). They are generated artifacts
and intentionally excluded from Git.

All 100 visual examples below have been rendered locally. Temporary PNG frames
are kept in the repository-local `tmp/` directory and discarded after encoding. The formula and full-fidelity
SVG examples were rendered with the local Racket 9.3 runtime; the remaining
examples use the standard Racket runtime.

## Foundations

| Video | What to look for |
| --- | --- |
| [moving-circle](../rendered-examples/moving-circle.mp4) | A single circle moving smoothly across the scene. |
| [moving-shapes](../rendered-examples/moving-shapes.mp4) | Several basic shapes moving and transforming together. |
| [fading-visuals](../rendered-examples/fading-visuals.mp4) | Fade-in and fade-out opacity transitions. |
| [creating-paths](../rendered-examples/creating-paths.mp4) | Paths being progressively drawn with `create`. |
| [transforming-shapes](../rendered-examples/transforming-shapes.mp4) | Shape-to-shape transformation with interpolation. |
| [grouped-visuals](../rendered-examples/grouped-visuals.mp4) | A composed group moving as one Visual. |
| [custom-renderer](../rendered-examples/custom-renderer.mp4) | A third-party cross-shaped Visual rendered by a custom Pict renderer. |

## Timing, composition, and style

| Video | What to look for |
| --- | --- |
| [local-animation-timing](../rendered-examples/local-animation-timing.mp4) | A child animation placed within its own local time interval. |
| [successive-animations](../rendered-examples/successive-animations.mp4) | Motion clips running one after another. |
| [parallel-animation-groups](../rendered-examples/parallel-animation-groups.mp4) | Several requests sharing one time span. |
| [lagged-start-animations](../rendered-examples/lagged-start-animations.mp4) | A staggered cascade of starts. |
| [duration-scaled-compositions](../rendered-examples/duration-scaled-compositions.mp4) | Nested clips sped up or slowed down by duration scaling. |
| [animating-stroke-width](../rendered-examples/animating-stroke-width.mp4) | Lines changing cosmetic stroke thickness. |
| [animating-colors](../rendered-examples/animating-colors.mp4) | Fill and stroke colors interpolating independently. |
| [unified-style-transitions](../rendered-examples/unified-style-transitions.mp4) | Fill, stroke, width, and opacity changing in one style request. |

## Paths and morphing

| Video | What to look for |
| --- | --- |
| [path-shapes](../rendered-examples/path-shapes.mp4) | Circles, rectangles, lines, and polygons represented as paths. |
| [curved-paths](../rendered-examples/curved-paths.mp4) | Cubic Bézier curves and smooth sampled geometry. |
| [path-following](../rendered-examples/path-following.mp4) | A Visual following a geometric route. |
| [path-orientation-and-offsets](../rendered-examples/path-orientation-and-offsets.mp4) | Tangent-facing motion and normal offsets along a path. |
| [joined-offset-paths](../rendered-examples/joined-offset-paths.mp4) | Continuous offset paths joined through corners. |
| [reversed-and-cyclic-paths](../rendered-examples/reversed-and-cyclic-paths.mp4) | Reversed traversal and alternate closed-path starting points. |
| [morphing-paths](../rendered-examples/morphing-paths.mp4) | A basic compatible path morph. |
| [normalized-morphs](../rendered-examples/normalized-morphs.mp4) | Morphing after deterministic path normalization. |
| [automatic-morph-correspondence](../rendered-examples/automatic-morph-correspondence.mp4) | Closed shapes aligned automatically before morphing. |
| [compound-morph-correspondence](../rendered-examples/compound-morph-correspondence.mp4) | Correspondence across compound closed paths. |
| [open-morph-correspondence](../rendered-examples/open-morph-correspondence.mp4) | Automatic alignment of open paths. |
| [open-compound-morph-correspondence](../rendered-examples/open-compound-morph-correspondence.mp4) | Correspondence across multi-subpath open paths. |
| [mixed-compound-morph-correspondence](../rendered-examples/mixed-compound-morph-correspondence.mp4) | Automatic pairing of mixed open and closed subpaths. |
| [topology-changing-morphs](../rendered-examples/topology-changing-morphs.mp4) | Parts appearing or disappearing during a path morph. |
| [anchored-topology-changing-morphs](../rendered-examples/anchored-topology-changing-morphs.mp4) | Explicit anchors controlling topology-changing births and deaths. |
| [penalized-topology-changing-morphs](../rendered-examples/penalized-topology-changing-morphs.mp4) | Topology pairing influenced by numerical penalties. |
| [per-subpath-topology-anchors](../rendered-examples/per-subpath-topology-anchors.mp4) | Separate birth/death anchors for individual subpaths. |
| [per-subpath-topology-penalties](../rendered-examples/per-subpath-topology-penalties.mp4) | Separate topology penalties for individual subpaths. |
| [per-pair-match-penalties](../rendered-examples/per-pair-match-penalties.mp4) | Fine-grained pair costs steering automatic correspondence. |

## Camera, layout, and coordinate tools

| Video | What to look for |
| --- | --- |
| [arrows-and-axes](../rendered-examples/arrows-and-axes.mp4) | Styled Cartesian axes, ticks, and arrows. |
| [number-lines-and-grid](../rendered-examples/number-lines-and-grid.mp4) | Number-line and grid decorations. |
| [camera-pan-and-zoom](../rendered-examples/camera-pan-and-zoom.mp4) | Camera movement and changing world scale. |
| [camera-framing-and-following](../rendered-examples/camera-framing-and-following.mp4) | Camera fit and follow behavior around content. |
| [fixed-overlays-and-callouts](../rendered-examples/fixed-overlays-and-callouts.mp4) | Frame-fixed labels and callouts over world motion. |
| [relative-layout](../rendered-examples/relative-layout.mp4) | Renderer-aware relative positioning around Visuals. |

## Text, formulas, data, and reactive scenes

| Video | What to look for |
| --- | --- |
| [text-visuals](../rendered-examples/text-visuals.mp4) | Plain-text faces, anchors, scale, and rotation. |
| [formula-visuals](../rendered-examples/formula-visuals.mp4) | LaTeX formulas with semantic positioning and style. |
| [named-formula-parts](../rendered-examples/named-formula-parts.mp4) | A formula assembly exposing stable named pieces. |
| [transforming-formula-parts](../rendered-examples/transforming-formula-parts.mp4) | Rearrange an equation, then swap its sides using matched formula parts. |
| [derived-visuals](../rendered-examples/derived-visuals.mp4) | Visual geometry derived from sampled scalar state. |
| [dependency-driven-geometry](../rendered-examples/dependency-driven-geometry.mp4) | One derived Visual reading another’s resolved geometry. |
| [function-graphs](../rendered-examples/function-graphs.mp4) | Function sampling and graph creation on axes. |
| [parametric-data-plots](../rendered-examples/parametric-data-plots.mp4) | Parametric curves and plotted observation data. |
| [markers-scatter-areas](../rendered-examples/markers-scatter-areas.mp4) | Point markers, scatter plots, and filled chart areas. |

## Later roadmap stages

These are dedicated videos for the roadmap capabilities added after the
original example set. The existing `named-formula-parts`,
`transforming-formula-parts`, and `function-graphs` videos above already cover
SCENE-BD, SCENE-BE, and SCENE-BK.

| Video | What to look for |
| --- | --- |
| [generic-interpolable-values](../rendered-examples/generic-interpolable-values.mp4) | **SCENE-AY:** a derived dot reads and interpolates a vector position and an RGBA color. |
| [parameter-handles](../rendered-examples/parameter-handles.mp4) | **SCENE-AZ:** immutable parameter handles drive a moving, recolored dot. |
| [derived-groups](../rendered-examples/derived-groups.mp4) | **SCENE-BA:** a parameter changes the number of stable-ID children in a derived group. |
| [nested-addressing](../rendered-examples/nested-addressing.mp4) | **SCENE-BB:** a halo follows a planet resolved through the nested `system/planet` path. |
| [nested-child-animation](../rendered-examples/nested-child-animation.mp4) | **SCENE-BC:** individual children of one group move and restyle by nested path. |
| [automatic-formula-matching](../rendered-examples/automatic-formula-matching.mp4) | **SCENE-BF:** automatic correspondence reorders terms, adds a function name, then replaces it while unchanged parts persist. |
| [svg-subpart-animation](../rendered-examples/svg-subpart-animation.mp4) | **SCENE-BG/BI:** semantic SVG import exposes `rocket` subparts for independent style and scale animation. |
| [bitmap-image-visual](../rendered-examples/bitmap-image-visual.mp4) | **SCENE-BH:** a bitmap image participates in normal motion, rotation, scale, and opacity animation. |
| [logarithmic-axes](../rendered-examples/logarithmic-axes.mp4) | **SCENE-BJ:** evenly spaced decades, logarithmic labels, and an identity graph on log–log axes. |
| [implicit-curves](../rendered-examples/implicit-curves.mp4) | **SCENE-BL:** sampled zero contours draw a circle and hyperbola directly from equations. |
| [vector-fields](../rendered-examples/vector-fields.mp4) | **SCENE-BM:** arrows sample the rotational field \((-y, x)\). |
| [derived-function-graphs](../rendered-examples/derived-function-graphs.mp4) | **SCENE-BN:** a sine graph is resampled from an animated amplitude parameter. |
| [renderer-resources](../rendered-examples/renderer-resources.mp4) | **SCENE-BO/BP:** one full-fidelity SVG moves while renderer-resource diagnostics report reuse (222 hits, 3 misses). |
| [render-diagnostics](../rendered-examples/render-diagnostics.mp4) | **SCENE-BQ/BR:** three dots converge while frames render with four workers and report cache diagnostics (74 hits, 1 miss). |
| [tagged-formula-transitions](../rendered-examples/tagged-formula-transitions.mp4) | **SCENE-BS:** one TeX layout first shows subtracting \(a^2\) from both sides, then simplifies to \(b^2=c^2-a^2\) with matched SVG fragments. |
| [solving-linear-equation](../rendered-examples/solving-linear-equation.mp4) | **Tagged formulas:** solve \(2x+1=5\) through subtraction and division while the equals sign remains fixed. |
| [animated-write](../rendered-examples/animated-write.mp4) | **SCENE-BU:** a semantic SVG rocket and tagged TeX equation write by Bézier-curve order, transition from outline to fill, then the equation unwrites in reverse. |
| [glyph-outline-morph](../rendered-examples/glyph-outline-morph.mp4) | **SCENE-BZ:** subtracting \(2b\) from both sides morphs a compatible \(+\) into \(-\), while newly introduced terms cross-fade. |
| [compound-glyph-outline-morph](../rendered-examples/compound-glyph-outline-morph.mp4) | **SCENE-CA:** multiplying an inequality by \(-1\) moves terms and morphs the multi-contour \(\leq\) relation into \(\geq\). |
| [nested-transform-from-copy](../rendered-examples/nested-transform-from-copy.mp4) | **SCENE-CB:** an independently moving copy of the imported rocket's nested window leaves the original window in place. |
| [named-layout-anchors](../rendered-examples/named-layout-anchors.mp4) | **SCENE-CC:** one nine-point layout vocabulary positions captions at measured panel anchors. |
| [nested-live-attachments](../rendered-examples/nested-live-attachments.mp4) | **SCENE-CD:** a badge and callout leader remain attached to a moving nested SVG window. |
| [nested-attention](../rendered-examples/nested-attention.mp4) | **SCENE-CE:** renderer-measured outlines circumscribe and pulse a nested SVG window. |
| [structured-formula-derivation](../rendered-examples/structured-formula-derivation.mp4) | **SCENE-CF:** an explicit three-step equation reduction pauses to explain each rewrite. |
| [general-shape-transform](../rendered-examples/general-shape-transform.mp4) | **SCENE-CG:** a rectangle morphs into a circle, while a composite diagram uses the automatic cross-fade fallback. |
| [explanatory-camera-focus](../rendered-examples/explanatory-camera-focus.mp4) | **SCENE-CH:** the camera frames a nested rocket window together with the explanatory note, then restores the overview. |
| [perimeter-shape-morph](../rendered-examples/perimeter-shape-morph.mp4) | **SCENE-CJ:** matching cardinal perimeter anchors makes a square round evenly into a circle. |
| [live-attention-follow](../rendered-examples/live-attention-follow.mp4) | **SCENE-CK:** circumscribe and a callout leader follow a card while it moves and scales. |
| [stationary-formula-derivation](../rendered-examples/stationary-formula-derivation.mp4) | **SCENE-CL:** an anchored derivation explicitly keeps selected formula parts stationary. |
| [live-anchor-constraints](../rendered-examples/live-anchor-constraints.mp4) | **SCENE-CM:** a label's selected edge follows a moving, rotating, scaling card's live rendered-box corner. |
| [dynamic-endpoint-geometry](../rendered-examples/dynamic-endpoint-geometry.mp4) | **SCENE-CN:** moving triangle vertices keep their three sides and a corner-anchored altitude arrow connected. |
| [mathematical-annotations](../rendered-examples/mathematical-annotations.mp4) | **SCENE-CO:** a deforming right triangle retains a right-angle mark, angle arc, base brace/label, and a nested live enclosure. |
| [secant-to-tangent](../rendered-examples/secant-to-tangent.mp4) | **SCENE-CP:** a parameter shrinks a secant construction until it approaches the numeric tangent. |
| [adaptive-plotting](../rendered-examples/adaptive-plotting.mp4) | **SCENE-CQ:** midpoint subdivision captures a high-frequency sine curve and leaves reciprocal branches separated at their pole. |
| [formula-styling](../rendered-examples/formula-styling.mp4) | **SCENE-CR:** named terms keep their semantic colours while `2x + 3 = 7` is rewritten around a fixed equals sign. |
| [multiline-rich-text](../rendered-examples/multiline-rich-text.mp4) | **SCENE-CS:** a wrapped, styled explanatory paragraph remains readable beside a fixed-equals algebra rewrite. |
| [matrices-and-tables](../rendered-examples/matrices-and-tables.mp4) | **SCENE-CT:** independently addressable matrix rows/cells and a grid table use normal nested targeting, attention, and copy animations. |
| [traced-cycloid](../rendered-examples/traced-cycloid.mp4) | **SCENE-CU:** a rolling point’s cycloid is deterministically reconstructed from an animated phase parameter, without frame-history state. |
| [composable-camera-movements](../rendered-examples/composable-camera-movements.mp4) | **SCENE-CV:** a camera pan succeeds into a parallel moving-point follow and zoom, using the same composition tree as Visual animation. |
| [authoring-sections](../rendered-examples/authoring-sections.mp4) | **SCENE-CW:** named opening, derivation, and conclusion sections share one global frame grid while a playhead and cue markers show their production metadata. |
| [graphs-and-networks](../rendered-examples/graphs-and-networks.mp4) | **SCENE-CX:** named vertices rearrange while directed edges and their labels are regenerated from the sampled endpoint positions. |
| [semantic-nested-affine-transforms](../rendered-examples/semantic-nested-affine-transforms.mp4) | **SCENE-DK:** a whole linear-algebra diagram is sheared, then its named unit square is independently reflected and recoloured without rasterizing the enclosing group. |
| [serializable-rate-functions](../rendered-examples/serializable-rate-functions.mp4) | **SCENE-DL:** linear, smooth, rush-into, and there-and-back-with-pause use named callable values that can also participate in automatic authored-section cache keys. |
| [boolean-path-geometry](../rendered-examples/boolean-path-geometry.mp4) | **SCENE-DM:** two overlapping cubic disks become ordinary union, intersection, difference, and XOR path geometry. |
| [adaptive-ode-trajectory](../rendered-examples/adaptive-ode-trajectory.mp4) | **SCENE-DN:** a time-dependent projectile follows adaptive RK45 dense output and stops at a downward ground-contact event. |
| [zoom-camera-inset](../rendered-examples/zoom-camera-inset.mp4) | **SCENE-DO:** the same live orbit diagram appears in a panning overview and a frame-fixed close-up rendered by a second camera. |
| [graph-layouts-and-curved-edges](../rendered-examples/graph-layouts-and-curved-edges.mp4) | **SCENE-DP:** a layered directed graph uses parallel curved arrows, a self-loop, and weighted strokes that all remain live while a vertex moves. |
| [robust-pointwise-maps](../rendered-examples/robust-pointwise-maps.mp4) | **SCENE-DQ:** adaptive samples bend a complex grid under \(z^2\), while a reciprocal pole splits into two visible branches rather than a false connecting chord. |
| [mathematical-effects](../rendered-examples/mathematical-effects.mp4) | **SCENE-DS:** live flash, focus, and a moving path trace precede a reversible wiggle and three exact-Visual introduction effects. |
| [probability-and-statistics](../rendered-examples/probability-and-statistics.mp4) | **SCENE-DT:** ordinary named groups make individual chart bars, sample-space cells, probability branches, box-plot parts, and error bars directly animatable. |
| [layout-finishing](../rendered-examples/layout-finishing.mp4) | **SCENE-DV:** measured render boxes align text baselines, separate cards, distribute markers, and pull a Visual back inside the frame. |

## Non-video example

`animated-values.rkt` is deliberately console-only: it prints sampled scalar
values and phases rather than rendering Visuals, so it has no MP4 counterpart.
