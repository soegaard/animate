#lang racket/base

;;;
;;; Visual Animation
;;;

;; Provides the documented SCENE-AW API for semantic Visuals, animated cameras,
;; coordinate-aware plots, renderer-aware layout, immutable timelines,
;; deterministic frame sampling, PNG output, and optional MP4 encoding.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "private/affine-transform.rkt"
         "private/arrow-visual.rkt"
         "private/axes-visual.rkt"
         "private/animation.rkt"
         "private/camera-animation.rkt"
         "private/camera-framing.rkt"
         "private/camera.rkt"
         "private/color-style.rkt"
         "private/coordinate-series.rkt"
         "private/derived-visual.rkt"
         "private/derived-plot.rkt"
         "private/formula-part-transition.rkt"
         "private/formula-parts-visual.rkt"
         "private/formula-visual.rkt"
         "private/tagged-formula.rkt"
         "private/frame-space.rkt"
         "private/function-graph.rkt"
         "private/frame-renderer.rkt"
         "private/geometry.rkt"
         "private/group-visual.rkt"
         "private/image-visual.rkt"
         "private/implicit-curve.rkt"
         "private/interpolation.rkt"
         "private/path-geometry.rkt"
         "private/parameter.rkt"
         "private/parametric-data-plot.rkt"
         "private/pict-adapter.rkt"
         "private/pict-renderer.rkt"
         "private/png-renderer.rkt"
         "private/relative-layout.rkt"
         "private/scene-state.rkt"
         "private/scene.rkt"
         "private/svg-import.rkt"
         "private/svg-image-visual.rkt"
         "private/text-visual.rkt"
         "private/video-encoder.rkt"
         "private/vector-field.rkt"
         "private/visual-model.rkt")

;; Exports
(provide
 ;; Geometry
 (struct-out vec2)
 finite-real?
 origin
 real-lerp
 vec2+
 vec2-
 vec2-scale
 vec2*
 vec2-lerp
 interpolable?
 interpolate-value

 ;; Scene value parameters
 parameter
 scene-parameter?
 parameter-id
 parameter-initial-value

 ;; Semantic colors
 (struct-out rgba-color)
 rgb-color
 color-spec?
 color-spec->rgba-color
 rgba-color-lerp

 ;; Path geometry
 (struct-out line-path-segment)
 (struct-out cubic-bezier-path-segment)
 (struct-out path-subpath)
 (struct-out path-geometry)
 path-segment?
 empty-path-geometry
 path-geometry-empty?
 path-subpath-points
 path-geometry-subpath-points
 path-geometry-map-points
 path-geometry-translate
 path-geometry-reverse
 path-geometry->cubic
 path-geometry-morph-normalizable?
 path-geometry-align-for-morph
 path-geometry-align-open-for-morph
 path-geometry-align-open-compound-for-morph
 path-geometry-align-mixed-compound-for-morph
 path-geometry-prepare-topology-changing-morph
 path-geometry-align-compound-for-morph
 path-geometry-normalize-for-morph
 path-geometry-morph-compatible?
 path-geometry-lerp
 path-geometry-bounds
 path-geometry-center
 path-subpath-length
 path-geometry-length
 path-geometry-point-at
 path-geometry-tangent-at
 path-geometry-normal-at
 path-geometry-offset
 path-geometry-partial
 path-geometry-cycle-start
 polyline-path
 polygon-path
 cubic-bezier-path

 ;; Affine transforms
 affine-transform?
 affine-transform-translation
 affine-transform-rotation
 affine-transform-scale
 make-affine-transform
 identity-affine-transform
 scale-factor?
 scale-factor->vec2
 affine-transform-with-translation
 affine-transform-with-rotation
 affine-transform-with-scale
 affine-transform-lerp
 affine-transform-apply-vector
 affine-transform-apply-point

 ;; Camera
 camera?
 camera-width
 camera-height
 camera-world-width
 camera-center
 camera-background
 make-camera
 default-camera
 camera-scale
 camera-world-height
 camera-length->pixels
 camera-world->pixel
 camera-pan-to
 camera-pan-to-request?
 camera-pan-by
 camera-pan-by-request?
 camera-zoom-to
 camera-zoom-to-request?
 camera-zoom-by
 camera-zoom-by-request?
 camera-follow
 camera-follow-request?
 camera-fit-request?
 camera-fit-layout-box
 camera-fit-visuals
 camera-fit-scene

 ;; Frame-space overlays and callouts
 frame-space-visual?
 frame-space-visual-frame-width
 frame-space-camera
 fixed-in-frame
 fixed-in-frame-visual?
 fixed-in-frame-visual-content
 callout
 callout-visual?
 callout-visual-content
 callout-visual-target
 callout-visual-connector-stroke
 callout-visual-connector-width

 ;; Pure derived Visuals
 derived-visual
 derived-visual?
 derived-context?
 derived-context-value-has?
 derived-context-value-ref
 derived-context-visual-has?
 derived-context-visual-ref

 ;; Visual model
 gen:visual
 visual?
 visual-id
 visual-position
 visual-with-position
 visual-path?
 visual-target-path
 gen:affine-visual
 affine-visual?
 visual-transform
 visual-with-transform
 visual-rotation
 visual-scale
 visual-with-rotation
 visual-with-scale
 gen:opacity-visual
 opacity-visual?
 opacity?
 visual-opacity
 visual-with-opacity
 gen:stroke-width-visual
 stroke-width-visual?
 stroke-width?
 visual-stroke-width
 visual-with-stroke-width
 gen:fill-color-visual
 fill-color-visual?
 visual-fill-color
 visual-with-fill-color
 gen:stroke-color-visual
 stroke-color-visual?
 visual-stroke-color
 visual-with-stroke-color
 circle
 circle-visual?
 circle-visual-radius
 circle-visual-fill
 circle-visual-stroke
 circle-visual-stroke-width
 rectangle
 rectangle-visual?
 rectangle-visual-width
 rectangle-visual-height
 rectangle-visual-fill
 rectangle-visual-stroke
 rectangle-visual-stroke-width
 make-path-visual
 path-visual?
 path-visual-path
 path-visual-fill
 path-visual-stroke
 path-visual-stroke-width
 path-visual-with-path
 line
 polygon
 image
 image-visual?
 image-visual-source
 image-visual-width
 image-visual-height
 svg-image
 svg-image-visual?
 svg-image-visual-source
 svg-image-visual-width
 svg-image-visual-height
 svg->visual
 group
 group-visual?
 group-visual-children
 group-visual-with-children
 text-font-family?
 text-font-style?
 text-font-weight?
 text-horizontal-alignment?
 text-vertical-alignment?
 plain-text
 text-visual?
 text-visual-content
 text-visual-font-size
 text-visual-font-face
 text-visual-font-family
 text-visual-font-style
 text-visual-font-weight
 text-visual-color
 text-visual-horizontal-alignment
 text-visual-vertical-alignment
 text-visual-with-content
 formula-mode?
 latex-option?
 latex-formula
 formula-visual?
 formula-visual-source
 formula-visual-mode
 formula-visual-font-size
 formula-visual-preamble
 formula-visual-document-class-options
 formula-visual-preview-options
 formula-visual-horizontal-alignment
 formula-visual-vertical-alignment
 formula-visual-with-source
 formula-arc
 formula-arc?
 formula-arc-angle
 formula-relative-path
 formula-relative-path?
 formula-relative-path-geometry
 formula-route?
 formula-part-path
 formula-part-path?
 formula-part-path-source-name
 formula-part-path-destination-name
 formula-part-path-route
 formula-part-copy
 formula-part-copy?
 formula-part-copy-source-name
 formula-part-copy-destination-name
 formula-part-copy-route
 (struct-out formula-fragment)
 tagged-formula
 math-tex
 glyph-tex
 tagged-formula-fragment-visual?
 tagged-formula-fragment-visual-svg-source
 (struct-out formula-part)
 latex-formula-part
 formula-assembly
 formula-assembly-visual?
 formula-assembly-visual-parts
 formula-assembly-visual-with-parts
 formula-assembly-visual-part-names
 formula-assembly-visual-has-part?
 formula-assembly-visual-ref
 (struct-out formula-part-match)
 (struct-out formula-correspondence)
 formula-correspondence-auto
 formula-correspondence-unmatched-source-names
 formula-correspondence-unmatched-destination-names
 transform-matching-tex

 ;; Arrows and axes
 arrow
 arrow-visual?
 arrow-visual-length
 arrow-visual-stroke
 arrow-visual-stroke-width
 arrow-visual-tip-length
 arrow-visual-tip-width
 arrow-visual-start-tip?
 arrow-visual-end-tip?
 arrow-visual-start
 arrow-visual-end
 arrow-visual-point-at
 (struct-out axis-range)
 axis-range-contains?
 axis-range-tick-values
 axis-scale?
 axes
 axes-visual?
 axes-visual-x-range
 axes-visual-y-range
 axes-visual-x-scale
 axes-visual-y-scale
 axes-visual-x-log-base
 axes-visual-y-log-base
 axes-visual-x-length
 axes-visual-y-length
 axes-visual-stroke
 axes-visual-stroke-width
 axes-visual-tick-size
 axes-visual-tip-length
 axes-visual-tip-width
 axes-visual-x-tip?
 axes-visual-y-tip?
 axes-x-unit-length
 axes-y-unit-length
 axes-coordinates->point
 axes-point->coordinates

 ;; Coordinate curves and plots
 curve-interpolation?
 (struct-out parameter-range)
 sample-function-path
 function-graph
 derived-function-graph
 sample-parametric-path
 parametric-curve
 data-series-path
 data-plot
 vector-field
 sample-implicit-path
 implicit-curve

 ;; Relative layout
 (struct-out layout-box)
 layout-horizontal-alignment?
 layout-vertical-alignment?
 layout-box-width
 layout-box-height
 layout-box-center
 visual-layout-box
 visuals-layout-box
 visual-align-horizontal
 visual-align-vertical
 visual-place-above
 visual-place-below
 visual-place-left-of
 visual-place-right-of
 visuals-center-at
 arrange-visuals-horizontally
 arrange-visuals-vertically

 ;; Immutable scene state
 scene-state?
 empty-scene-state
 scene-state-count
 scene-state-has?
 scene-state-ref
 scene-state-visuals-in-drawing-order
 scene-state-resolved-ref
 scene-state-resolved-visuals-in-drawing-order
 scene-state-value-has?
 scene-state-value-ref

 ;; Animation and timeline
 value-to
 value-to-request?
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
 transform-from-copy
 transform-from-copy-request?
 circumscribe
 circumscribe-request?
 indicate
 indicate-request?
 transform-formula-parts
 transform-formula-parts-request?
 transform-matching-formula
 transform-matching-glyphs
 rewrite-formula
 create
 create-request?
 uncreate
 uncreate-request?
 write-in
 write-in-request?
 unwrite
 unwrite-request?
 linear
 timed
 timed-animation-request?
 succession
 succession-animation-request?
 animation-group
 animation-group-animation-request?
 lagged-start
 lagged-start-animation-request?
 style-to
 style-to-animation-request?
 scene?
 make-scene
 scene-add
 scene-remove
 scene-ref
 scene-visual-at
 scene-set-value
 scene-remove-value
 scene-value-at
 scene-current-value
 scene-set-camera
 scene-play
 scene-wait
 scene-sample
 scene-camera-at
 scene-duration
 scene-current-state
 scene-current-camera
 scene-clip-count

 ;; Pict renderer protocol
 gen:pict-renderer
 pict-renderer?
 pict-renderer-supports?
 pict-renderer-render
 pict-renderer-list?
 default-pict-renderers

 ;; Pict and frame conversion
 visual->pict
 scene-state->pict
 scene->pict
 scene-frame-count
 frame-index->time
 scene-frame->bitmap

 ;; External output
 render-frames!
 render-frames/report!
 render-diagnostics
 render-diagnostics?
 render-diagnostics-paths
 render-diagnostics-frame-count
 render-diagnostics-workers
 render-diagnostics-elapsed-milliseconds
 render-diagnostics-frame-milliseconds
 render-diagnostics-cache-hits
 render-diagnostics-cache-misses
 render-diagnostics-cache-evictions
 encode-mp4!)


;; SCENE-T number lines and coordinate decorations
(require "private/number-line-visual.rkt"
         "private/coordinate-decoration.rkt")

(provide
 (except-out
  (all-from-out "private/number-line-visual.rkt")
  number-line-visual->path-visual)
 (all-from-out "private/coordinate-decoration.rkt"))


;; SCENE-V point markers, scatter plots, and filled coordinate areas
(require "private/point-marker-visual.rkt"
         "private/scatter-area-plot.rkt")

(provide
 (except-out
  (all-from-out "private/point-marker-visual.rkt")
  point-marker-visual->visual)
 (all-from-out "private/scatter-area-plot.rkt"))
