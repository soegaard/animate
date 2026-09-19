#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate/main
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@; Animate Visuals reference revision R1 (20260919).
@title[#:tag "visuals" #:style 'toc]{Visuals}


@declare-exporting[animate/main]


This reference is organized by the kind of Visual or operation being
looked up. A Visual is semantic scene data; its identity and placement are
separate from the Pict used to render it. The basic protocols and groups are in
@secref["ref-visuals-protocols"].

The short examples on these pages use @racketmodname[animate] and inspect model
values. They do not invoke TeX or write rendered frames. Each page is independent;
it does not depend on definitions from an earlier page.

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Look up} @bold{Contents})
  (list @secref["ref-visuals-protocols"]
        "Identity, local placement, immutable updates, optional style protocols, and ordered group children.")
  (list @secref["ref-visuals-shapes"]
        "Circles, rectangles, local path geometry, polygons, and the mathematical shape catalogue.")
  (list @secref["ref-visuals-images"]
        "Lazy bitmap and full-SVG rendering, versus immediate import into addressable semantic children.")
  (list @secref["ref-visuals-text"]
        "Plain text, paragraphs, rich spans, font options, wrapping, and text anchors.")
  (list @secref["ref-visuals-typography"]
        "Role-based text, explicit overrides, treatments, and immutable typography snapshots.")
  (list @secref["ref-visuals-numeric"]
        "String formatters, static numeric labels, parameter-driven displays, and rolling digit slots.")
  (list @secref["ref-visuals-matrices"]
        "Cell naming and sizing, number planes, vector arrows, basis vectors, and matrix-action diagrams.")
  (list @secref["ref-visuals-formulas"]
        "LaTeX model values, jointly typeset tagged fragments, source-mapped formulas, and glyph leaves.")
  (list @secref["ref-visuals-formula-parts"]
        "Manually placed parts, part lookup and styling, and explicit or automatic correspondences.")
  (list @secref["ref-visuals-formula-matching"]
        "Source ranges, selections, match plans, motion routes, anchored rewrites, and derivation steps.")
  (list @secref["ref-visuals-axes"]
        "Arrow endpoints and tips, numeric ranges, linear or logarithmic axes, and coordinate conversion.")
  (list @secref["ref-visuals-annotations"]
        "Endpoint descriptions, connecting lines and arrows, angle marks, braces, and surrounding boxes.")
  (list @secref["ref-visuals-complex-polar"]
        "Conversions, coordinate planes, domain colors, complex maps, and polar graphs.")
  (list @secref["ref-visuals-plots"]
        "Interpolation, implicit contours and fields, sampled or adaptive function graphs, parametric curves, and ordered data.")
  (list @secref["ref-visuals-calculus"]
        "Graph points and labels, projections, secants and tangents, areas, Riemann rectangles, and explicit phase traces.")
  (list @secref["ref-visuals-ode"]
        "State spaces, fixed RK4 and adaptive RK45 preparation, events, trajectory lookup, streamlines, and flow particles.")
  (list @secref["ref-visuals-relations"]
        "Declared dependencies, semantic versus measured-layout resolution, cacheability, reports, and following anchors.")
 )]

@local-table-of-contents[]

@include-section["visuals-protocols.scrbl"]
@include-section["visuals-shapes.scrbl"]
@include-section["visuals-images.scrbl"]
@include-section["visuals-text.scrbl"]
@include-section["visuals-typography.scrbl"]
@include-section["visuals-numeric.scrbl"]
@include-section["visuals-matrices.scrbl"]
@include-section["visuals-formulas.scrbl"]
@include-section["visuals-formula-parts.scrbl"]
@include-section["visuals-formula-matching.scrbl"]
@include-section["visuals-axes.scrbl"]
@include-section["visuals-annotations.scrbl"]
@include-section["visuals-complex-polar.scrbl"]
@include-section["visuals-plots.scrbl"]
@include-section["visuals-calculus.scrbl"]
@include-section["visuals-ode.scrbl"]
@include-section["visuals-relations.scrbl"]
