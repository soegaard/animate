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

@(require "../private/reference-examples.rkt")

@; Animate Visuals reference revision R1 (20260919).
@title[#:tag "ref-visuals-complex-polar"]{Complex and Polar Visuals}


@declare-exporting[animate/main]


Complex and polar helpers convert ordinary numeric values into semantic
points or Visuals. Plane constructors create static group trees; complex
transformation requests map sampled world geometry. The individual contracts
state the accepted domains and discontinuity policies.

See also @secref["ref-visuals-axes"], @secref["ref-visuals-plots"].

@local-table-of-contents[]

@(define reference-eval (make-visuals-reference-eval))

@section[#:tag "complex-and-polar"]{Complex and Polar Coordinates}

Complex-coordinate operations use ordinary Racket complex numbers and convert
only at the drawing boundary. Polar-coordinate operations follow the same
approach for polar values and paths. Both planes are normal immutable group trees, not special scene types.

@defproc[(complex->point [value complex?]) vec2?]{
Returns @racket[(vec2 (real-part value) (imag-part value))]. Both components
must be finite reals.
}

@defproc[(point->complex [point vec2?]) complex?]{
Returns the ordinary Racket complex number whose real and imaginary parts are
the x and y components of @racket[point].
}

@; visuals-reference-r1 example: complex-polar-1
Complex components and point coordinates round-trip without a renderer.

@examples[#:eval reference-eval
  (eval:check (point->complex (complex->point 3+4i)) 3+4i)
]


@defproc[(complex-domain-color
          [value complex?]
          [#:saturation saturation (real-in 0 1) 3/4]
          [#:brightness brightness (real-in 0 1) 4/5]
          [#:radial? radial? boolean? #t])
         rgba-color?]{
Returns an opaque semantic colour whose hue is the argument of @racket[value].
When @racket[#:radial?] is true, its brightness also increases smoothly with
the modulus. This is a pure colour helper; it does not create a renderer-only
pixel effect.
}

@defproc[(complex-domain-coloring
          [function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:x-min x-min finite-real? -3]
          [#:x-max x-max finite-real? 3]
          [#:y-min y-min finite-real? -2]
          [#:y-max y-max finite-real? 2]
          [#:columns columns exact-positive-integer? 24]
          [#:rows rows exact-positive-integer? 16]
          [#:saturation saturation (real-in 0 1) 3/4]
          [#:brightness brightness (real-in 0 1) 4/5]
          [#:radial? radial? boolean? #t]
          [#:opacity opacity (real-in 0 1) 1])
         group-visual?]{
Samples @racket[function] once at the centre of each rectangular complex cell
and returns a normal group of coloured rectangle Visuals. The function must
return finite complex values. Each cell has a stable name derived from
@racket[id], so the result remains ordinary semantic scene content rather than
a continuous raster shader.
}

@defproc[(complex-plane
          [#:id id symbol?]
          [#:x-range x-range axis-range? (axis-range -4 4 1)]
          [#:y-range y-range axis-range? (axis-range -3 3 1)]
          [#:x-length x-length (and/c finite-real? positive?) 8]
          [#:y-length y-length (and/c finite-real? positive?) 6]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:grid? grid? boolean? #t]
          [#:labels? labels? boolean? #t]
          [#:grid-stroke grid-stroke any/c "lightsteelblue"]
          [#:grid-stroke-width grid-stroke-width
                               (and/c finite-real? (>=/c 0)) 1]
          [#:axes-stroke axes-stroke any/c "navy"]
          [#:axes-stroke-width axes-stroke-width
                               (and/c finite-real? (>=/c 0)) 2]
          [#:label-font-size label-font-size
                              (and/c finite-real? positive?) 1/4]
          [#:label-color label-color any/c "navy"])
         group-visual?]{

Builds a Cartesian complex plane. Its direct @racket['coordinates] child is a
@racket[number-plane] tree; when @racket[#:labels?] is true, direct
@racket['real-axis] and @racket['imaginary-axis] text leaves label Re and Im.
The numeric labels are static construction-time labels.
}

@defproc[(apply-complex-function
          [target (or/c visual? symbol? visual-path?)]
          [function (procedure-arity-includes/c 1)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'error])
         apply-pointwise-request?]{

Creates @racket[apply-pointwise] with each sampled world point converted by
@racket[point->complex], passed to @racket[function], then converted back with
@racket[complex->point]. The function must return a complex number with finite
real and imaginary parts at every retained sampled point. The default strict
@racket['error] discontinuity policy makes an accidental bad function result
fail visibly. Use @racket['split] for an intentional pole or excluded domain:
failed samples then break the path rather than adding a long connecting chord.
This API does not infer branch cuts or normalize by an axes' numeric coordinate
scale.
}

@defproc[(apply-complex-homotopy
          [target (or/c visual? symbol? visual-path?)]
          [homotopy (procedure-arity-includes/c 2)]
          [#:samples samples exact-positive-integer? 24]
          [#:adaptive? adaptive? boolean? #t]
          [#:tolerance tolerance (and/c finite-real? positive?) 1/32]
          [#:max-depth max-depth exact-nonnegative-integer? 8]
          [#:discontinuities discontinuities (or/c 'split 'error) 'error])
         apply-homotopy-request?]{

Creates @racket[apply-homotopy] with each source point converted by
@racket[point->complex], passed together with the current local phase to
@racket[homotopy], and converted back with @racket[complex->point]. The
homotopy must return a finite complex value at every retained sample. Its
strict default discontinuity policy matches @racket[apply-complex-function];
choose @racket['split] for an intentional pole or excluded domain.
}

@defproc[(polar-coordinate? [value any/c]) boolean?]{
Recognizes an immutable reading returned by @racket[point->polar].
}

@defproc[(polar-coordinate-radius [value polar-coordinate?])
         (and/c finite-real? (>=/c 0))]{
Returns the nonnegative radius of a polar reading.
}

@defproc[(polar-coordinate-angle [value polar-coordinate?]) finite-real?]{
Returns the angle of a polar reading in radians.
}

@defproc[(polar->point [radius finite-real?] [angle finite-real?]) vec2?]{
Returns @racket[(vec2 (* radius (cos angle)) (* radius (sin angle)))]. A
signed radius is accepted, which lets @racket[polar-graph] express conventional
rose curves.
}

@defproc[(point->polar [point vec2?]) polar-coordinate?]{
Returns a nonnegative-radius reading. The angle uses @racket[atan]'s interval
@tt{[-pi, pi]}; the origin is assigned angle zero.
}

@defproc[(polar-plane
          [#:id id symbol?]
          [#:radii radii (listof (and/c finite-real? positive?)) '(1 2 3)]
          [#:angles angles (listof finite-real?) (list 0 (/ pi 4) (/ pi 2))]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale (and/c finite-real? positive?) 1]
          [#:labels? labels? boolean? #t]
          [#:stroke stroke any/c "steelblue"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 2]
          [#:grid-stroke grid-stroke any/c "lightsteelblue"]
          [#:grid-stroke-width grid-stroke-width
                               (and/c finite-real? (>=/c 0)) 1]
          [#:label-font-size label-font-size
                              (and/c finite-real? positive?) 1/4]
          [#:label-color label-color any/c "navy"])
         group-visual?]{

Builds a static polar grid. Its direct children are named @racket['rings] and
@racket['rays], plus @racket['labels] when requested. Ring children use
@tt{ring-0}, @tt{ring-1}, and so on; ray children use @tt{ray-0}, @tt{ray-1},
and so on. Labels are deliberately static and may overlap for dense choices.
}

@defproc[(polar-graph
          [radius-function (procedure-arity-includes/c 1)]
          [#:id id symbol?]
          [#:start start finite-real? 0]
          [#:end end finite-real? (* 2 pi)]
          [#:samples samples (and/c exact-integer? (>=/c 2)) 240]
          [#:center center vec2? origin]
          [#:rotation rotation finite-real? 0]
          [#:scale scale scale-factor? 1]
          [#:opacity opacity opacity? 1]
          [#:stroke stroke any/c "crimson"]
          [#:stroke-width stroke-width (and/c finite-real? (>=/c 0)) 3]
          [#:fill fill any/c #f])
         path-visual?]{

Evenly samples @racket[(radius-function theta)] from @racket[start] through
@racket[end] and returns an ordinary open path. Each result must be a finite
real, but it may be negative. Sampling is uniform in angle, not adaptive or
arc-length parameterized.
}

@(close-eval reference-eval)
