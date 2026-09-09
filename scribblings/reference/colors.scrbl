#lang scribble/manual

@(require (for-label (except-in racket/base tan)
                     animate
                     (except-in animate/colors
                                rgba-color
                                rgba-color?
                                color-spec?
                                rgba-color-lerp)))

@title[#:tag "reference-colors"]{Colors}

@defmodule[animate/colors]

@racketmodname[animate/colors] provides literal colors plus immutable palette,
role, categorical-series, mix, and alpha specifications. A palette or role token is a description
of a color to resolve under an explicit immutable theme; it is not a drawing
color. Existing literal color strings such as @racket["teal"] keep their
literal meaning.

@defproc[(literal-color-spec? [value any/c]) boolean?]{
Returns @racket[#t] for an @racket[rgba-color] or a supported literal color
string. It does not treat a palette key string as a token.
}

@defproc[(rgb-color [red (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [green (and/c finite-real? (>=/c 0) (<=/c 255))]
                    [blue (and/c finite-real? (>=/c 0) (<=/c 255))])
         rgba-color?]{
Creates an opaque literal sRGB color. It is a fixed color rather than a
palette or theme reference, so it resolves identically in every theme.
}

@defproc[(palette-color [key symbol?]) color-token?]{
Constructs an immutable reference to a canonical lowercase, hyphenated palette
key. The family and neutral aliases documented below normalize to their
canonical entries. A custom canonical key is allowed; the selected theme
validates whether it has a supplied swatch. The key must be a nonempty
interned symbol; uninterned and unreadable symbols are rejected because their
identity cannot survive a theme-file or worker boundary.
}

@defproc[(role-color [key symbol?]) color-token?]{
Constructs an immutable reference to a nonempty semantic role key. Use it for a
custom role; the @racket[theme-...] bindings below are the standard roles. The
key must be a nonempty interned symbol for the same portable-data reason as a
palette key.
}

@defproc[(series-color [index exact-nonnegative-integer?]) color-token?]{
Constructs a stable zero-based categorical-series reference. It does not use a
mutable ``next color'' counter. At resolution, the selected theme's nonempty
series is indexed with explicit wraparound, so @racket[(series-color 8)] has
the same category as @racket[(series-color 0)] for the built-in eight-color
series. Use a stable dataset/category order to choose indexes.
}

@defproc[(color-token? [value any/c]) boolean?]{
Recognizes a palette, semantic-role, or categorical-series color token.
}

@defproc[(color-token-kind [token color-token?]) (or/c 'palette 'role 'series)]{
Returns the token namespace.
}

@defproc[(color-token-key [token color-token?]) symbol?]{
Returns the token's normalized palette key or semantic-role key. Passing a
categorical-series token raises an argument error; use
@racket[series-color-index] for that kind.
}

@defproc[(series-color? [value any/c]) boolean?]{Recognizes a categorical-series token.}
@defproc[(series-color-index [token series-color?]) exact-nonnegative-integer?]{
Returns the original authored index, before resolution applies the selected
theme's explicit wraparound.
}

@defproc[(color-expression? [value any/c]) boolean?]{
Recognizes an unresolved color mix or alpha expression.
}

@defproc[(color-mix [from color-spec?]
                    [to color-spec?]
                    [amount (and/c finite-real? (>=/c 0) (<=/c 1))]
                    [#:space space (or/c 'srgb 'srgb-linear 'oklab) 'srgb-linear]
                    [#:alpha-mode alpha-mode (or/c 'premultiplied 'straight)
                                   'premultiplied])
         color-spec?]{
Builds an unresolved mix. At amount zero or one it returns the exact normalized
endpoint. At interior values it retains palette and role tokens for an explicit
theme resolver. @racket['srgb] is encoded-component interpolation;
@racket['srgb-linear], the default, is linear-light interpolation. Both honor
the selected alpha policy. @racket['oklab] uses Oklab conversion and, when
needed, a deterministic fixed-lightness/fixed-hue chroma reduction into sRGB.
@racket[rgba-color-lerp] remains the existing explicit componentwise numerical
helper.
}

@defproc[(color-with-alpha [color color-spec?]
                           [alpha (and/c finite-real? (>=/c 0) (<=/c 1))])
         color-spec?]{
Builds an unresolved expression that replaces the resolved color's alpha, or
folds an all-literal result immediately.
}

@defproc[(color-opacity [color color-spec?]
                        [factor (and/c finite-real? (>=/c 0) (<=/c 1))])
         color-spec?]{
Builds an unresolved expression that multiplies the resolved color's alpha.
An identity multiplier returns the normalized source directly.
}

@section{Color Scales}

@defproc[(color-scale [#:stops stops list?]
                      [#:space space (or/c 'srgb 'srgb-linear 'oklab) 'srgb-linear]
                      [#:outside outside (or/c 'clamp 'error) 'clamp])
         color-scale?]{
Creates an immutable map from an already normalized finite scalar coordinate
to a color specification. A scale does not inspect plot data or establish a
data domain. Its stops must be ordered and use offsets in @racket[0] through
@racket[1]. Equal adjacent offsets are a hard discontinuity; querying that
offset selects the final stop at the offset. This release supports clamp and
error policies for a coordinate outside the stop domain.
}

@defproc[(color-scale? [value any/c]) boolean?]{Recognizes a color scale.}
@defproc[(color-scale-stops [scale color-scale?]) vector?]{Returns normalized stops in authored order.}
@defproc[(color-scale-space [scale color-scale?]) symbol?]{Returns the declared interpolation space.}
@defproc[(color-scale-outside [scale color-scale?]) symbol?]{Returns its outside-domain policy.}
@defproc[(color-scale-at [scale color-scale?] [coordinate finite-real?]) color-spec?]{
Samples a scale while retaining a token or color expression until an explicit
theme resolves it. At an exact endpoint it returns that normalized stop color.
Lookup uses a logarithmic upper-bound search, so the final member of a run of
equal offsets wins without changing hard-stop semantics.
}

@defproc[(sequential-color-scale [#:minimum minimum finite-real?]
                                 [#:maximum maximum finite-real?]
                                 [#:low low color-spec? aqua-d]
                                 [#:high high color-spec? gold-d]
                                 [#:missing missing color-spec? theme-muted]
                                 [#:space space (or/c 'srgb 'srgb-linear 'oklab) 'oklab]
                                 [#:outside outside (or/c 'clamp 'error) 'clamp])
         scientific-color-scale?]{
Creates a scalar scale with an explicit data domain, missing-data color, and
out-of-domain policy. Low-to-high ordering is authored and does not reverse
when a theme changes.
}

@defproc[(diverging-color-scale [#:minimum minimum finite-real?]
                                [#:maximum maximum finite-real?]
                                [#:midpoint midpoint finite-real?]
                                [#:low low color-spec? aqua-d]
                                [#:middle middle color-spec? gray-b]
                                [#:high high color-spec? red-d]
                                [#:missing missing color-spec? theme-muted]
                                [#:space space (or/c 'srgb 'srgb-linear 'oklab) 'oklab]
                                [#:outside outside (or/c 'clamp 'error) 'clamp])
         scientific-color-scale?]{
Creates a three-stop scalar scale. @racket[midpoint] must be within the
declared domain and has data meaning; use this form only when that center is
meaningful.
}

@defproc[(scientific-color-scale? [value any/c]) boolean?]{Recognizes a scalar scale with an explicit domain policy.}
@defproc[(scientific-color-scale-kind [scale scientific-color-scale?]) (or/c 'sequential 'diverging)]{Returns the recipe kind.}
@defproc[(scientific-color-scale-minimum [scale scientific-color-scale?]) finite-real?]{Returns the declared data minimum.}
@defproc[(scientific-color-scale-maximum [scale scientific-color-scale?]) finite-real?]{Returns the declared data maximum.}
@defproc[(scientific-color-scale-midpoint [scale scientific-color-scale?]) (or/c #f finite-real?)]{Returns the meaningful center, or @racket[#f] for a sequential scale.}
@defproc[(scientific-color-scale-missing [scale scientific-color-scale?]) color-spec?]{Returns the retained missing-data color.}
@defproc[(scientific-color-scale-outside [scale scientific-color-scale?]) (or/c 'clamp 'error)]{Returns the explicit out-of-domain policy.}
@defproc[(scientific-color-scale-at [scale scientific-color-scale?] [value any/c]) color-spec?]{
Maps a finite scalar from the declared domain. A non-finite value returns the
recorded missing-data color rather than choosing an endpoint.
}

@defthing[color-spec-schema-version exact-positive-integer?]{
The version number carried by @racket[color-spec->datum] values.
}

@defproc[(color-spec->datum [color color-spec?]) any/c]{
Produces a readable, versioned datum. For example, a palette reference is
written as @racket['(animate-color-spec 1 (palette aqua-c))]. Serialization
uses finite output-node and atom-size budgets, so a shared expression graph
cannot expand without bound into this tree-shaped external format.
}

@defproc[(datum->color-spec [datum any/c]
                            [#:maximum-depth maximum-depth exact-positive-integer? 64])
         color-spec?]{
Reads one bounded versioned color datum without evaluating it. Malformed,
unsupported-version, cyclic, and excessive-depth inputs raise an exception.
}

@section{Palettes and Themes}

A palette is a complete immutable table from palette keys to literal RGBA
swatches. A theme owns one complete palette snapshot and maps semantic role
keys to authored color specifications. Both are pure values: resolution always
takes a theme explicitly and no mutable process-wide current theme exists.

Every symbol that becomes portable color data---palette/theme IDs, palette and
role keys, palette-group IDs, and symbol-valued provenance---must be a nonempty
interned symbol. Process-local uninterned and unreadable symbols are rejected
rather than silently interned, since distinct same-spelling keys could otherwise
merge after a file or worker round trip. Strings remain supported for display
names and provenance.

@defthing[color-palette-schema-version exact-positive-integer?]{
The version number used by palette data read and written by this release.
}

@defproc[(color-palette [#:id id symbol?]
                        [#:colors colors hash?]
                        [#:extends parent (or/c #f color-palette?) #f]
                        [#:display-name display-name string? (symbol->string id)]
                        [#:version version exact-positive-integer? 1]
                        [#:groups groups (or/c #f list?) #f]
                        [#:provenance provenance (or/c #f symbol? string?) #f])
         color-palette?]{
Creates a complete immutable palette. Palette values must be literal colors;
tokens and expressions belong in themes. A root palette supplies every standard
palette key. A child palette copies its parent snapshot, then overrides the
given canonical keys. Fixed literal names such as @racket[white] cannot be
overridden through a palette.
}

@defproc[(color-palette? [value any/c]) boolean?]{Recognizes a palette.}
@defproc[(color-palette-id [palette color-palette?]) symbol?]{Returns its stable identifier.}
@defproc[(color-palette-display-name [palette color-palette?]) string?]{Returns its display metadata.}
@defproc[(color-palette-version [palette color-palette?]) exact-positive-integer?]{Returns its data version.}
@defproc[(color-palette-provenance [palette color-palette?]) (or/c #f symbol? string?)]{
Returns non-appearance provenance metadata.
}

@defproc[(palette-ref [palette color-palette?] [key symbol?]) rgba-color?]{
Returns the literal swatch for a canonical palette key or a documented alias.
An unknown key raises an exception rather than choosing a fallback color.
}
@defproc[(palette-keys [palette color-palette?]) (listof symbol?)]{
Returns the complete deterministic key order: the standard catalog first,
then custom keys in canonical symbol order. The order does not depend on the
parent-extension history used to construct an otherwise equal palette.
}
@defproc[(palette-groups [palette color-palette?]) list?]{
Returns ordered @racket[(list group-id keys)] metadata for swatch browsers.
}
@defproc[(palette->datum [palette color-palette?]) any/c]{
Produces a complete readable versioned palette datum. Output has the same
finite node and atom-size limits used by complete theme export.
}
@defproc[(datum->palette [datum any/c]) color-palette?]{
Reads one complete palette datum without evaluating it. It rejects malformed
schema versions and duplicate keys, including aliases that normalize to the
same palette entry.
}

@defthing[color-theme-schema-version exact-positive-integer?]{
The version number used by complete theme data read and written by this release.
}

@defproc[(color-theme [#:id id symbol?]
                      [#:palette palette (or/c #f color-palette?) #f]
                      [#:roles roles hash? (hash)]
                      [#:extends parent (or/c #f color-theme?) #f]
                      [#:display-name display-name string? (symbol->string id)]
                      [#:series series (or/c #f list?) #f]
                      [#:provenance provenance (or/c #f symbol? string?) #f])
         color-theme?]{
Creates a complete immutable theme snapshot. Standard roles are required for a
root theme. A child copies its parent palette and roles, then applies supplied
overrides. Role dependencies are resolved and validated at construction; direct
or indirect cycles and missing role/token references are errors. Role and
series definitions may refer to literals, palette tokens, roles, and
expressions, but not @racket[series-color]: a categorical series token becomes
valid only after the complete theme series has been constructed. Theme
definitions are bounded to 10,000 roles or series entries and expression depth
64. Validation and resolution memoize shared expression nodes within one
operation and enforce a distinct-node budget, so invalid external data cannot
create an unbounded dependency walk.
}

@defproc[(color-theme? [value any/c]) boolean?]{Recognizes a complete theme.}
@defproc[(color-theme-id [theme color-theme?]) symbol?]{Returns its stable identifier.}
@defproc[(color-theme-display-name [theme color-theme?]) string?]{Returns its display metadata.}
@defproc[(color-theme-palette [theme color-theme?]) color-palette?]{Returns its complete palette snapshot.}
@defproc[(color-theme-provenance [theme color-theme?]) (or/c #f symbol? string?)]{
Returns non-appearance provenance metadata.
}
@defproc[(theme-ref [theme color-theme?] [role-key symbol?]) color-spec?]{
Returns the normalized authored specification for a role, rather than its
resolved value.
}
@defproc[(theme-role-keys [theme color-theme?]) (listof symbol?)]{
Returns role keys in deterministic order.
}
@defproc[(theme-series [theme color-theme?]) (listof rgba-color?)]{
Returns the resolved categorical series snapshot. The built-in themes contain
eight entries. @racket[series-color] resolves against this snapshot by explicit
wraparound; a theme with an empty series can still be used for ordinary roles,
but resolving a series token raises an error.
}
@defproc[(color-theme-fingerprint [theme color-theme?]) bytes?]{
Returns a deterministic appearance identity based on the complete palette,
resolved roles, and resolved series. Display names and provenance do not alter
this fingerprint. Equal appearances have equal fingerprints regardless of hash
insertion order, palette-extension history, or ordinary printer preferences;
series order remains significant.
}
@defproc[(theme->datum [theme color-theme?]) any/c]{
Produces a complete readable versioned theme datum. One shared finite budget
covers the palette, group membership, role expressions, categorical series,
and metadata atoms, so splitting a large declaration across those sections
does not bypass the export limit.
}
@defproc[(datum->theme [datum any/c]) color-theme?]{
Reads one complete theme datum without evaluating it. It rejects malformed
schema versions and duplicate role declarations before constructing a hash.
}
@defproc[(resolve-color [color color-spec?] [theme color-theme?]) rgba-color?]{
Resolves a literal, palette token, role token, categorical-series token, or supported expression under
the supplied immutable theme. It is the only COLOR-B operation that turns a
themeable value into a concrete RGBA color.
}

@section{Inspection and Diagnostics}

@defproc[(inspect-color [color color-spec?]
                        [theme color-theme?]
                        [#:owner-path owner-path (or/c #f (listof symbol?)) #f]
                        [#:style-field style-field (or/c #f symbol?) #f])
         immutable-hash?]{
Returns a pure explanation of one authored color under one explicit theme. Its
keys include @racket['authored] (a versioned color datum), @racket['kind],
@racket['canonical-token], @racket['role-resolution-chain],
@racket['resolved-hex], @racket['resolved-rgba], @racket['effective-alpha],
@racket['theme-id], @racket['theme-fingerprint],
@racket['interpolation-space], @racket['owner-path], and
@racket['style-field]. Palette aliases are normalized when a token is made, so
the canonical token is retained and @racket['alias-used] is @racket[#f].

The effective alpha belongs to the resolved color. It is distinct from a
Visual's separate opacity, and in three dimensions it is the material input to
lighting rather than an observed lit pixel.
}

@defproc[(color-inspection? [value any/c]) boolean?]{
Recognizes the immutable report returned by @racket[inspect-color].
}

@defproc[(rgba-color->hex [color rgba-color?]) string?]{
Formats a resolved color as uppercase @tt{#RRGGBBAA}. The alpha channel is
always included so a copied literal is unambiguous.
}

@defproc[(color-contrast-ratio [foreground rgba-color?]
                                [background rgba-color?]) positive-real?]{
Computes pairwise relative-luminance contrast after compositing the foreground
over an opaque background. A translucent background is rejected because this
procedure has no canvas against which to composite it. This is a review aid,
not a claim that every rendered video meets an accessibility standard.
}

@defproc[(color-theme-diagnostics
          [theme color-theme?]
          [#:ordinary-text-pairs ordinary-text-pairs
                                  (listof (cons/c symbol? symbol?))
                                  '((foreground . background))]
          [#:graphic-pairs graphic-pairs (listof (cons/c symbol? symbol?))
                            '((axis . background) (accent . background))]
          [#:minimum-series-contrast minimum-series-contrast
                                      (and/c finite-real? positive?) 3]
          [#:canvas canvas (or/c #f rgba-color?) #f])
         (listof immutable-hash?)]{
Returns deterministic reports for requested role-pair contrast, nonmonotonic
declared standard shade ramps, empty categorical series, and low-contrast
category pairs. A custom five-item palette group is categorical metadata, not
an implicit light-to-dark ramp declaration.
Ordinary text is reviewed against a 4.5:1 target and meaningful graphics
against 3:1. Missing palette entries, invalid aliases, cyclic roles, and
expression-resolution failures are rejected when a palette, theme, or color
datum is constructed; no renderer silently repairs them. A color that needs
gamut mapping during Oklab interpolation remains deterministic, but the
resolved value is always the value this API reports.

If a requested background or the theme background is translucent, a supplied
opaque @racket[canvas] gives the compositing basis. Without one, the valid theme
still returns a @racket['contrast-undetermined] report instead of being treated
as malformed. Returned invalid-datum reports retain a bounded immutable summary
of input, never the caller's mutable datum. Categorical-series comparisons use
a fixed review budget. Their warning rows are followed by a
@racket['categorical-series-summary] report containing possible and examined
pair counts, found and retained warning counts, and a @racket['truncated?] flag.
An incomplete bounded review is a warning even when every examined pair passed;
the omitted pairs have not been checked.
}

@defproc[(color-theme-datum-diagnostics [datum any/c])
         (listof immutable-hash?)]{
Reads a complete external theme datum without evaluating it. A valid datum
returns the ordinary theme diagnostics. A malformed declaration returns one
error report, classifying missing entries, invalid palette-key spelling, and
cyclic role declarations when the constructor can identify them.
}

@defproc[(color-resolution-diagnostics [color color-spec?] [theme color-theme?])
         (listof immutable-hash?)]{
Returns a pure success report or an error report for one authored field under
one explicit theme. It is useful for reporting a failed token or expression
resolution without trying to render a substitute color.
}

@deftogether[
 (@defthing[animate-palette color-palette?]
  @defthing[animate-palette-checksum bytes?]
  @defthing[animate-light-theme color-theme?]
  @defthing[animate-dark-theme color-theme?])]{
The built-in version-one numerical Animate palette, its deterministic SHA-1
review checksum, and complete light/dark role snapshots. The palette table is
literal data; the two themes deliberately use explicit role assignments.
}

@section{Palette Tokens}

The eight canonical hue ramps use @racket[a] for the lightest and @racket[e]
for the darkest shade. The un-suffixed family names are aliases for their
@racket[-c] tokens.

@deftogether[
 (@defthing[blue-a color-token?] @defthing[blue-b color-token?]
  @defthing[blue-c color-token?] @defthing[blue-d color-token?]
  @defthing[blue-e color-token?] @defthing[blue color-token?])]{Blue palette tokens.}
@deftogether[
 (@defthing[aqua-a color-token?] @defthing[aqua-b color-token?]
  @defthing[aqua-c color-token?] @defthing[aqua-d color-token?]
  @defthing[aqua-e color-token?] @defthing[aqua color-token?])]{Aqua palette tokens.}
@deftogether[
 (@defthing[green-a color-token?] @defthing[green-b color-token?]
  @defthing[green-c color-token?] @defthing[green-d color-token?]
  @defthing[green-e color-token?] @defthing[green color-token?])]{Green palette tokens.}
@deftogether[
 (@defthing[yellow-a color-token?] @defthing[yellow-b color-token?]
  @defthing[yellow-c color-token?] @defthing[yellow-d color-token?]
  @defthing[yellow-e color-token?] @defthing[yellow color-token?])]{Yellow palette tokens.}
@deftogether[
 (@defthing[gold-a color-token?] @defthing[gold-b color-token?]
  @defthing[gold-c color-token?] @defthing[gold-d color-token?]
  @defthing[gold-e color-token?] @defthing[gold color-token?])]{Gold palette tokens.}
@deftogether[
 (@defthing[red-a color-token?] @defthing[red-b color-token?]
  @defthing[red-c color-token?] @defthing[red-d color-token?]
  @defthing[red-e color-token?] @defthing[red color-token?])]{Red palette tokens.}
@deftogether[
 (@defthing[maroon-a color-token?] @defthing[maroon-b color-token?]
  @defthing[maroon-c color-token?] @defthing[maroon-d color-token?]
  @defthing[maroon-e color-token?] @defthing[maroon color-token?])]{Maroon palette tokens.}
@deftogether[
 (@defthing[purple-a color-token?] @defthing[purple-b color-token?]
  @defthing[purple-c color-token?] @defthing[purple-d color-token?]
  @defthing[purple-e color-token?] @defthing[purple color-token?])]{Purple palette tokens.}

@deftogether[
 (@defthing[gray-a color-token?] @defthing[gray-b color-token?]
  @defthing[gray-c color-token?] @defthing[gray-d color-token?]
  @defthing[gray-e color-token?] @defthing[lighter-gray color-token?]
  @defthing[light-gray color-token?] @defthing[gray color-token?]
  @defthing[dark-gray color-token?] @defthing[darker-gray color-token?])]{
Neutral tokens. The five longer names are aliases for @racket[gray-a] through
@racket[gray-e], respectively.
}

@deftogether[
 (@defthing[pink color-token?] @defthing[light-pink color-token?]
  @defthing[orange color-token?] @defthing[light-brown color-token?]
  @defthing[dark-brown color-token?] @defthing[gray-brown color-token?])]{
Familiar auxiliary palette tokens.
}

@deftogether[
 (@defthing[blush color-token?] @defthing[peach color-token?]
  @defthing[apricot color-token?] @defthing[tan color-token?]
  @defthing[cocoa color-token?] @defthing[taupe color-token?])]{
Warm Naturals palette tokens.
}

@section{Semantic Role Tokens}

@deftogether[
 (@defthing[theme-background color-token?] @defthing[theme-foreground color-token?]
  @defthing[theme-muted color-token?] @defthing[theme-axis color-token?]
  @defthing[theme-grid color-token?] @defthing[theme-surface color-token?]
  @defthing[theme-surface-edge color-token?] @defthing[theme-accent color-token?]
  @defthing[theme-highlight color-token?] @defthing[theme-selection color-token?]
  @defthing[theme-warning color-token?] @defthing[theme-success color-token?]
  @defthing[theme-error color-token?])]{
Standard semantic role references. Their safe @racket[theme-] prefix avoids
shadowing ordinary Racket bindings such as @racket[error].
}

@section{Fixed Literal Endpoints}

@deftogether[
 (@defthing[black rgba-color?] @defthing[white rgba-color?]
  @defthing[pure-red rgba-color?] @defthing[pure-green rgba-color?]
  @defthing[pure-blue rgba-color?] @defthing[pure-cyan rgba-color?]
  @defthing[pure-magenta rgba-color?] @defthing[pure-yellow rgba-color?])]{
Opaque fixed sRGB endpoints. These are literals, not palette tokens, and are
therefore never changed by a future theme.
}
