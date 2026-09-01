# Example Video Guide

Rendered MP4 files live in the local sibling directory
[`../rendered-examples/`](../rendered-examples/). They are generated artifacts
and intentionally excluded from Git.

All 49 visual examples below have been rendered locally. Rendering used two
concurrent jobs with two frame workers each; temporary PNG chunks were kept in
`/tmp` and discarded after encoding.

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
| [transforming-formula-parts](../rendered-examples/transforming-formula-parts.mp4) | Explicit correspondence between formula parts. |
| [derived-visuals](../rendered-examples/derived-visuals.mp4) | Visual geometry derived from sampled scalar state. |
| [dependency-driven-geometry](../rendered-examples/dependency-driven-geometry.mp4) | One derived Visual reading another’s resolved geometry. |
| [function-graphs](../rendered-examples/function-graphs.mp4) | Function sampling and graph creation on axes. |
| [parametric-data-plots](../rendered-examples/parametric-data-plots.mp4) | Parametric curves and plotted observation data. |
| [markers-scatter-areas](../rendered-examples/markers-scatter-areas.mp4) | Point markers, scatter plots, and filled chart areas. |

## Non-video example

`animated-values.rkt` is deliberately console-only: it prints sampled scalar
values and phases rather than rendering Visuals, so it has no MP4 counterpart.
