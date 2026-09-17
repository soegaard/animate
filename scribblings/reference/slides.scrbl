#lang scribble/manual
@(require (for-label racket/base racket/contract
                     (only-in pict pict?)
                     (only-in animate
                              scene? scene-duration visual?
                              color-spec? typography-theme? text-style?)
                     (only-in animate/authoring authored-timeline?)
                     (only-in animate/colors color-theme?)
                     animate/slides animate/slides/pict animate/slides/scene
                     animate/slides/render animate/slides/math
                     animate/slides/geometry animate/slides/project
                     animate/slides/gallery))

@title[#:tag "reference-slides"]{Slides}

This chapter documents the public slide modules. It describes implemented
operations, not proposed syntax. For a first lesson, see @secref["guide-slides"].
For short examples, see @secref["cookbook-slide-tasks"].

Unless stated otherwise, lengths are world units and durations are seconds.
Numbers used for positions and times must be finite. IDs are nonempty interned
symbols. Descriptions are immutable; preparation and rendering are explicit.
Private struct fields and wire-format records are not public constructors.

@local-table-of-contents[]

@declare-exporting[
 animate/slides
 #:use-sources
 (animate/slides/private/appearance
  animate/slides/private/layout
  animate/slides/private/model
  animate/slides/private/data
  animate/slides/private/semantic-model
  animate/slides/private/syntax
  animate/slides/main)]

@section[#:tag "reference-slide-construction"]{Slide descriptions and content}

@defform[(slide option ... [slot-name slot-option ... content] ...)]{
Creates a slide description. Put all slide keywords before the slot clauses.
The keywords are those of @racket[make-slide], except @racket[#:slots]. Slot
keywords are those of @racket[slot-content]. Slot names are literal identifiers.
Unknown, duplicate, and missing required slots are errors.}

@defproc[(make-slide [#:id id symbol? 'slide]
                     [#:layout chosen-layout (or/c symbol? layout?) 'blank]
                     [#:slots slots (or/c hash? list?) (hash)]
                     [#:theme theme (or/c #f slide-theme?) #f]
                     [#:notes notes string? ""]) slide?]{
The procedural slide constructor. Supply a hash or association list from slot
names to content or @racket[slot-content] wrappers. A false theme inherits the
conversion or storyboard theme. Notes do not become visible slide text.}

@defproc[(slot-content [content any/c]
                       [#:key key (or/c #f symbol?) #f]
                       [#:align align (or/c #f 'left 'center 'right) #f]
                       [#:valign valign (or/c #f 'top 'center 'bottom) #f]
                       [#:fit fit (or/c #f 'contain 'cover 'natural) #f]) any/c]{
Wraps content with slot options. False options inherit the layout choice. A
nonfalse continuity key must be unique within the slide. It names the same
concept across slides, independently of the slot's role.}

@defproc[(paragraph-content [text string?]
                            [#:role role (or/c #f symbol?) #f]
                            [#:align align (or/c #f 'left 'center 'right) #f]) content?]{
Declares text to measure later. A plain string already adopts the slot's text
role. Use this form to override the role or line alignment. Text wraps at its
selected size; it is not silently shrunk. This is not the native
@tt{paragraph} constructor.}

@defform[(bullets option ... [item-name content] ...)]{
Creates named text items. The optional @racket[#:ordered?] defaults to false.
Item names are literal identifiers and must be unique. Select an item with a
path such as @racket['(body check)]. Items currently accept strings and
@racket[paragraph-content], not arbitrary nested figures.}

@defproc[(make-bullets [entries list?] [#:ordered? ordered? boolean? #f]) content?]{
The procedural form of @racket[bullets]. Each entry is a pair made with
@racket[cons]: an item symbol and its content.}

@defproc[(pict-content [picture-or-factory any/c]
                       [#:fit fit (or/c 'contain 'cover 'natural) 'contain]) content?]{
Wraps a Pict or a one-argument factory. A factory receives a content context during
preparation. It must be deterministic and tolerate measurements at different
widths. Pict drawing units use 100 units per slide authoring unit before fitting.
An opaque Pict does not expose inner semantic parts.}

@defform[(image-content path option ...)]{
Declares an image path, with optional @racket[#:fit] (default @racket['contain])
and @racket[#:asset-base]. The syntax captures its source module's directory as
the default asset base. Without a source module, use a complete path or explicit
base. Images are read at preparation, not by constructing the description.}

@section[#:tag "reference-slide-appearance"]{Themes and formats}

@defproc[(slide-format [#:id id symbol?] [#:width width real?]
                       [#:height height real?]) slide-format?]{
Creates a format with positive finite width and height.}

@defthing[widescreen slide-format?]{The 16-by-9 format.}
@defthing[standard slide-format?]{The 12-by-9 format.}
@defthing[portrait slide-format?]{The 9-by-16 format.}
@defthing[square-format slide-format?]{The 12-by-12 format.}

@defproc[(slide-theme [#:id id symbol?]
                      [#:extends parent (or/c #f slide-theme?) #f]
                      [#:colors colors (or/c #f color-theme?) #f]
                      [#:typography typography (or/c #f typography-theme?) #f]
                      [#:spacing spacing hash? (hash)]
                      [#:decorations decorations hash? (hash)]) slide-theme?]{
Combines the existing color and typography systems with layout spacing and
decoration. Missing settings inherit from the parent. Without a parent, colors
use the native light theme and typography uses the lecture slide roles.
Overrides are copied into complete descriptions.}

@defthing[lecture-light slide-theme?]{The default light slide theme.}
@defthing[lecture-dark slide-theme?]{The default dark slide theme.}

@defproc[(theme-spacing [theme slide-theme?] [key-or-number (or/c symbol? real?)]) real?]{
Returns a named spacing value or the supplied nonnegative literal.}
@defproc[(role-style [theme slide-theme?] [role symbol?]) text-style?]{
Returns the native text style for a slide typography role.}

Default spacing includes @tt{safe-x = 0.65}, @tt{safe-y = 0.50},
@tt{section-gap = 0.35}, @tt{column-gap = 0.60}, @tt{bullet-gap = 0.23},
@tt{paragraph-gap = 0.25}, @tt{footer-height = 0.35},
@tt{subtitle-height = 0.85}, @tt{title-band = 1.20},
@tt{caption-band = 0.85}, and @tt{math-minimum-scale = 0.70}.
Band tokens do not force built-in text to a fixed height; text is measured.
Custom nonnegative numeric spacing tokens are allowed. The minimum math scale
must lie in [0,1].

Decoration keys are @tt{title-rule?} and @tt{footer-rule?}, both false by default.
Other decoration keys are errors. The slide lecture typography differs from the
core native typography theme; use its actual roles rather than copying a native
font-size table.

@section[#:tag "reference-slide-layouts"]{Layouts and regions}

@defproc[(layout-names) list?]{Returns the built-in layout names.}
@defproc[(layout-ref [name-or-layout (or/c symbol? layout?)]) layout?]{
Resolves a catalogue name or returns the supplied layout. Unknown names are errors.}

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Layout} @bold{Required} @bold{Optional})
  (list @tt{title} "title" "subtitle")
  (list @tt{section} "title" "subtitle")
  (list @tt{title+body} "title, body" "none")
  (list @tt{title+two-column} "title, left, right" "none")
  (list @tt{title+figure} "title, figure" "body")
  (list @tt{figure+caption} "figure" "caption")
  (list @tt{figure-full} "figure" "none")
  (list @tt{equation-focus} "equation" "annotation")
  (list @tt{equation+explanation} "equation, body" "title")
  (list @tt{theorem} "title, statement" "body")
  (list @tt{quote} "quote" "attribution")
  (list @tt{blank} "none" "content"))]

All built-ins also permit a footer. Hidden content retains its region.
An omitted body in @tt{title+figure} releases room to the figure.
Portrait two-column text stacks at natural heights with a section gap.
@tt{equation-focus} groups its equation and annotation into one centered block.

@defproc[(slot-spec [name symbol?] [#:required? required? boolean? #f]
                    [#:role role symbol? 'body]) slot-spec?]{
Declares one custom slot and its typography role.}

@defproc[(layout [#:id id symbol?] [#:slots slots (listof slot-spec?)]
                 [#:arrange wide-tree any/c] [#:standard standard-tree any/c #f]
                 [#:portrait portrait-tree any/c #f]
                 [#:fallback fallback (or/c #f 'wide) #f]) layout?]{
Creates a custom box layout. Every supplied tree must name every declared region
exactly once. The shared footer cannot be declared as a custom region. Standard
format can use the wide tree; portrait needs its own tree. Other formats require
a supported variant or explicit wide fallback.}

@defproc[(region [name symbol?] [#:basis basis (or/c real? 'content) 0]
                 [#:grow grow real? 0] [#:align align (or/c 'left 'center 'right) 'left]
                 [#:valign valign (or/c 'top 'center 'bottom) 'top]
                 [#:padding padding real? 0] [#:min minimum real? 0]
                 [#:max maximum real? +inf.0]) any/c]{
Creates a named region. Basis, grow, padding, and minimum are nonnegative.
Maximum is at least minimum, with positive infinity permitted.}

@defproc[(hbox [#:basis basis (or/c real? 'content) 0] [#:grow grow real? 0]
               [#:gap gap (or/c real? symbol?) 'column-gap]
               [#:padding padding real? 0] [#:min minimum real? 0]
               [#:max maximum real? +inf.0] [child any/c] ...) any/c]{
Arranges children left to right. Numeric gaps are nonnegative; a symbol names a
theme spacing value. The other allocation rules are the same as for regions.}

@defproc[(vbox [#:basis basis (or/c real? 'content) 0] [#:grow grow real? 0]
               [#:gap gap (or/c real? symbol?) 'section-gap]
               [#:padding padding real? 0] [#:min minimum real? 0]
               [#:max maximum real? +inf.0] [child any/c] ...) any/c]{
Arranges children top to bottom. @racket['content] asks for natural measured size;
positive grow weights divide remaining space. These boxes do not run a general
constraint solver.}

@section[#:tag "reference-slide-clips"]{Clips, beats, and narration}

@defproc[(build-slide [slide slide?] [#:initial initial any/c 'visible]
                      [#:poster poster any/c 'end]
                      [#:motion motion (or/c #f 'normal 'reduced) #f]
                      [beat beat?] ...) slide-clip?]{
Adds timed beats to a slide. Initial visibility is @racket['visible],
@racket['hidden], or a list of selectors. Beat names are unique. Ordinary
embedded content starts at local time zero. A @racket[content-state] stays at
its selected checkpoint.}

@defproc[(hold-slide [slide slide?] [#:duration duration real?]) slide-clip?]{
Makes a positive-duration clip holding the slide and its embedded poster states.
A plain slide is not itself a valid storyboard shot.}

@defproc[(beat [name symbol?] [#:duration duration (or/c #f real?) #f]
               [#:narration voice (or/c #f narration?) #f]
               [#:tail-hold tail-hold real? 0] [action slide-action?] ...) beat?]{
Creates an interval. Supply a positive explicit duration or narration. With
narration and no explicit duration, its length is the larger of narration end
and action end, plus the nonnegative tail hold. An explicit duration must fit
that span. Beats run in order; actions within one beat run concurrently.}

A clip poster can be @racket['start], @racket['end], a nonnegative time, or a
named beat boundary such as @racket['(explain end)]. Visibility changes persist;
emphasis returns to the base scale. Overlapping writes to the same property,
including conflicting parent/child visibility, are errors.

@defform[(narration text option ...)]{
Uses the arguments of @racket[make-narration], but captures its source module's
directory as the default asset base. It does not generate speech.}

@defproc[(make-narration [text string?]
                         [#:audio audio (or/c #f path-string?) #f]
                         [#:draft-duration draft-duration (or/c #f real?) #f]
                         [#:at at real? 0] [#:source-start source-start real? 0]
                         [#:duration duration (or/c #f real?) #f]
                         [#:captions captions any/c #f]
                         [#:asset-base asset-base (or/c #f path-string?) #f]) narration?]{
Supply exactly one of an audio path and a positive silent-draft duration.
Preparation inspects recordings with ffprobe. Trimming is explicit and applies
to recordings only. Nonnegative @racket[#:at] delays the narration inside its
beat, not the visual actions.}

Captions are an ordered, nonoverlapping list of @tt{(list start end text)}
relative to the selected recording interval. False derives captions from the
text; an empty list suppresses them. Captions must fit their interval. Relative
paths used by the procedure need an explicit base.

@section[#:tag "reference-slide-actions"]{Slot actions}

Selectors are a slot symbol or a nonempty symbol path, such as
@racket['(body check)]. They are resolved against the prepared content.
Times and durations below are finite and nonnegative.

@defproc[(reveal-slot [selector any/c] [#:at at real? 0]
                      [#:duration duration real? 0.4]
                      [#:effect effect (or/c 'fade 'instant) 'fade]) slide-action?]{
Makes selected content visible without changing the reserved layout space.}
@defproc[(conceal-slot [selector any/c] [#:at at real? 0]
                       [#:duration duration real? 0.4]
                       [#:effect effect (or/c 'fade 'instant) 'fade]) slide-action?]{
Hides selected content without removing its region.}
@defproc[(emphasize-slot [selector any/c] [#:at at real? 0]
                         [#:duration duration real? 0.8]
                         [#:scale scale real? 1.08]) slide-action?]{
Applies a temporary scale pulse, then restores the base scale. Scale is positive.
No extra layout space is allocated for the pulse.}
@defproc[(replace-content [slot any/c] [content any/c] [#:at at real? 0]
                          [#:duration duration real? 0.4]
                          [#:effect effect (or/c 'crossfade 'instant) 'crossfade]) slide-action?]{
Replaces one complete slot. All replacement alternatives are measured before
playback. It does not perform an algebraic rewrite or infer glyph matches.}
@defproc[(play-content [slot any/c] [#:at at real? 0] [#:from from any/c #f]
                       [#:to to any/c 'end] [#:duration duration (or/c #f real?) #f]
                       [#:retime retime (or/c #f 'stretch) #f]) slide-action?]{
Advances one animated component in a complete slot. False from resumes its
previous local time. An explicit from resets it. To accepts a time, start/end,
or an adapter cue. The natural duration is to minus from. A different duration
requires explicit stretch; backwards playback and stretching imported audio
are not supported. Reveal/conceal never advance this clock by themselves.}

@section[#:tag "reference-slide-transitions"]{Storyboards and transitions}

@defproc[(storyboard [#:id id symbol? 'storyboard]
                     [#:theme theme slide-theme? lecture-light]
                     [#:format format slide-format? widescreen]
                     [#:motion motion (or/c 'normal 'reduced) 'normal]
                     [#:subtitles? subtitles? boolean? #t]
                     [entry any/c] ...) storyboard?]{
Orders clips and bridges. A storyboard starts and ends with a shot. Occurrence
IDs are unique. Adjacent shots imply a cut; consecutive transitions are errors.
Subtitles are separate authored-timeline media, not burned into the usual Pict.}
@defproc[(storyboard-shot [occurrence-id symbol?] [clip slide-clip?]) any/c]{
Names one use of a clip in a storyboard. The same clip can be used again under a
different occurrence ID.}
@defproc[(storyboard-cut) slide-transition?]{Creates a zero-duration transition.}

@defproc[(slide-transition [#:effect effect symbol? 'crossfade]
                           [#:duration duration real? 0.6]
                           [#:keys keys (listof symbol?) '()]
                           [#:direction direction (or/c #f 'left 'right 'up 'down) #f]
                           [#:easing easing symbol? 'linear]
                           [#:scale scale (or/c #f real?) #f]
                           [#:color color (or/c #f color-spec?) #f]
                           [#:depth depth (or/c #f 'auto 'slot 'semantic) #f]) slide-transition?]{
Creates a positive-duration bridge. The duration adds to the video rather than
overlapping either clip. The valid effects and their options are listed below.
Inapplicable options are errors, not ignored hints.}

@tabular[#:sep @hspace[2]
 (list
  (list @bold{Effect} @bold{Behavior})
  (list @tt{crossfade} "Fade the outgoing content out and incoming content in.")
  (list @tt{match} "Match selected keys; other content crossfades.")
  (list @tt{push} "Move both compositions by one canvas extent.")
  (list @tt{wipe} "Keep both stationary and move a reveal boundary.")
  (list @tt{cover} "Move the destination over the stationary source.")
  (list @tt{uncover} "Move the source away from the stationary destination.")
  (list @tt{zoom} "Grow source and destination with a crossfade.")
  (list @tt{fade-through} "Fade to an opaque intermediate color, then from it."))]

Direction applies only to push, wipe, cover, and uncover; its default is left.
Leftward travel brings the incoming composition from the right. These four
effects require opaque endpoint backgrounds. They include backgrounds,
decorations, and existing crops, not only content leaves.

Easing is one of @racket['linear], @racket['smooth] (cubic smoothstep),
@racket['ease-in], @racket['ease-out], or @racket['ease-in-out] (quadratic).
These are @bold{symbols for the slide API}. They are not core rate-function
constructors: native @tt{scene-play} may instead take @tt{(smooth)}.

Scale applies only to zoom and lies strictly between 0 and 1; default 0.85.
The source grows from 1 to its reciprocal; the destination grows from scale to 1.
Color applies only to fade-through; default black. It resolves under the
destination theme and must be opaque. The solid intermediate frame occurs at
eased progress one half, not necessarily halfway in clock time.

Keys and depth apply to match. Missing, ambiguous, or wholly invisible keyed
endpoints fail. Auto depth uses named-part matching or supported checkpoint
replay where available, then falls back to compatible whole-asset matching or
crossfade. Slot depth disables the recursive/replay mechanisms. Semantic depth
requires supported correspondence for the requested keys and rejects unsupported
domain relationships. It still permits defined create/remove/replacement
behavior within a supported named group.

Clip clocks stay at the outgoing endpoint and incoming start. A matched pair of
compatible @racket[content-state] values deliberately replays its child interval
through the bridge. This is the exception, not automatic playback of both clips.

Reduced storyboard motion replaces match, push, wipe, cover, uncover, and zoom
with same-duration/easing crossfades. Cuts and fade-through retain their behavior.
Per-clip reduced motion separately suppresses emphasis scaling and uses instant
slot visibility changes without changing beat intervals. It does not replace
arbitrary embedded animation choreography.

@section[#:tag "reference-semantic-content"]{Named children and frozen checkpoints}

@defproc[(semantic-part [id symbol?] [content any/c]
                        [#:x x real? 0] [#:y y real? 0]
                        [#:width width real?] [#:height height real?]
                        [#:align align (or/c 'left 'center 'right) 'center]
                        [#:valign valign (or/c 'top 'center 'bottom) 'center]
                        [#:fit fit (or/c 'contain 'natural) 'contain]) semantic-part?]{
Names one child's rectangle inside a group. X and y are top-left coordinates;
y increases downwards. Width and height are positive. A group checks that each
child rectangle stays inside its viewport.}

@defproc[(semantic-group [#:width width real?] [#:height height real?]
                         [part semantic-part?] ...) semantic-group?]{
Creates a positive-sized group with at least one part. Sibling IDs are unique.
Groups can nest; identity is the full child path. Declaration order and visible
text do not decide correspondence. Different siblings may overlap.}

Matched child placements compose with the matched parent placement. Surviving
names move, changed appearances crossfade within their moving rectangle, and
created/removed children fade. This is not a general text or geometry morph.

@defproc[(content-state [content content?] [#:at at any/c]
                        [#:viewport viewport list? '(16 9)]) content-state?]{
Freezes math, geometry, or native Scene content at a time or domain cue. Viewport
is a pair of positive finite dimensions. Both corresponding checkpoints need a
compatible shared source and viewport for domain replay. This content remains
fixed during a held or built shot.}

A poster chooses how ordinary content is previewed; a content state fixes what
that content shows. Those are different operations. State replay is visual-only:
imported media is rejected rather than duplicated or stretched. Narrate outside
that replay or author media explicitly in the parent. Unrelated formulas and
independently realized constructions do not establish a replay interval merely
because their slot keys agree.

@section[#:tag "reference-slide-output"]{Pict and Scene conversion}

@subsection[#:tag "reference-slide-pict-output"]{Pict output}
@declare-exporting[
 animate/slides/pict
 #:use-sources
 (animate/slides/private/text
  animate/slides/pict)]

@defproc[(slide->pict [source any/c] [#:at at any/c #f]
                      [#:theme theme (or/c #f slide-theme?) #f]
                      [#:format format (or/c #f slide-format?) #f]
                      [#:size size any/c #f]
                      [#:fit fit (or/c 'error 'letterbox) 'error]
                      [#:debug debug list? '()]) pict?]{
Converts a slide, clip, context-bound reference, or compatible prepared value.
A plain slide is fully populated. A clip defaults to its poster; at selects a
numeric time or named beat boundary.}
@defproc[(storyboard->pict [source any/c] [#:at at any/c 'end]
                           [#:size size any/c #f]
                           [#:fit fit (or/c 'error 'letterbox) 'error]
                           [#:debug debug list? '()]) pict?]{
Samples a whole storyboard at a numeric time or start/end.}
@defproc[(storyboard->picts [source any/c] [#:size size any/c #f]
                            [#:fit fit (or/c 'error 'letterbox) 'error]
                            [#:debug debug list? '()]) (listof pict?)]{
Returns one poster per shot, in storyboard order.}

@defproc*[([(content-width [value any/c]) real?]
           [(content-height [value any/c]) real?]
           [(content-theme [value any/c]) slide-theme?]
           [(content-format [value any/c]) slide-format?])]{
Returns the dimensions, theme, or format from a Pict-content factory context.
Intrinsic measurement can supply a provisional height.}

@defproc[(content-color [context any/c] [role symbol?]) any/c]{
Resolves a drawing color for a Pict factory from its provided context.}

Size is false or a list of two positive exact pixel counts. False uses 80 pixels
per world unit. An aspect mismatch is an error unless letterbox is explicit.
Debug flags are slots, safe-area, and baselines. Ordinary output excludes the
separate narration-subtitle track. In-memory content can resolve automatically;
content needing file/tool effects requires explicit preparation first.

@subsection[#:tag "reference-slide-scene-output"]{Scene and timeline output}
@declare-exporting[
 animate/slides/scene
 #:use-sources
 (animate/slides/private/scene-output
  animate/slides/scene)]

@defproc[(slide->scene [source any/c]
                       [#:theme theme (or/c #f slide-theme?) #f]
                       [#:format format (or/c #f slide-format?) #f]
                       [#:size size any/c #f]
                       [#:fit fit (or/c 'error 'letterbox) 'error]) scene?]{
Returns an ordinary native Scene. A plain slide has duration zero. A clip retains
its authored duration. Output size and fitting follow the Pict rules.}
@defproc[(storyboard->scene [source any/c] [#:size size any/c #f]
                            [#:fit fit (or/c 'error 'letterbox) 'error]) scene?]{
Converts the visual storyboard without its separate media tracks.}
@defproc[(storyboard->timeline [source any/c] [#:size size any/c #f]
                               [#:fit fit (or/c 'error 'letterbox) 'error]) authored-timeline?]{
Also retains sections, beat cues, narration, subtitles, and explicitly imported
child media in the ordinary authored timeline.}
@defproc[(scene-slot-id [selector any/c]) symbol?]{
Encodes a native slot ID. Use a slot symbol for a single slide, or a shot/slot
path for a storyboard. Do not depend on the private encoded spelling.}
@defproc[(scene-slot-ref [scene scene?] [selector any/c]
                         [#:at at real? (scene-duration scene)]) visual?]{
Returns the resolved native slot group at that time. At the clip endpoint it can
receive ordinary native animation. This does not expose arbitrary inner formula
or geometry IDs as outer Scene paths.}

@section[#:tag "reference-slide-domain-content"]{Native, mathematical, and geometry content}

@subsection[#:tag "reference-slide-native-content"]{Native Scene content}
@declare-exporting[
 animate/slides/scene
 #:use-sources
 (animate/slides/private/scene-output
  animate/slides/scene)]

@defproc[(scene-content [source (or/c scene? authored-timeline?)]
                        [#:fit fit (or/c 'contain 'cover 'natural) 'contain]
                        [#:poster poster any/c 'end]
                        [#:media media (or/c #f 'visual-only 'import) #f]
                        [#:background? background? boolean? #f]) content?]{
Embeds a native Scene or timeline. Its camera defines the viewport. Its
background is transparent unless enabled. A timeline with media requires an
explicit import or visual-only policy. Native resource preparation remains the
source author's responsibility.}
@defproc[(visual-content [visual visual?]
                         [#:fit fit (or/c 'contain 'cover 'natural) 'contain]
                         [#:width width (or/c #f real?) #f]
                         [#:height height (or/c #f real?) #f]) content?]{
Wraps one native Visual. Positive dimensions can provide the envelope instead
of measuring it.}

Imported media runs only while its child clock advances. Audio must use bounded
cues. Partial trimming through faded cue envelopes and overlapping parent/child
subtitles are rejected instead of silently changing their meaning.

@subsection[#:tag "reference-slide-math-content"]{Mathematical content}
@declare-exporting[
 animate/slides/math
 #:use-sources
 (animate/slides/math)]

@defproc[(math-content [plan any/c] [#:poster poster any/c 'end]
                       [#:fit fit (or/c 'contain 'natural) 'contain]
                       [#:aspect aspect real? 16/9]) content?]{
Wraps a mathematical presentation plan, not an arbitrary expression. Aspect is
a positive preferred ratio for intrinsic measurement. Preparation still uses
the actual slot region. Cues come from native compiled step boundaries.}

Step cues can be @tt{(step-name start)} or @tt{(step-name end)}; qualify with a
segment index when names repeat. Existing domain context headings and working-row
margins remain inside the viewport. Mathematical foreground/background colors
must resolve to opaque colors. Fitting below the theme's minimum math scale fails.

@subsection[#:tag "reference-slide-geometry-content"]{Geometry content}
@declare-exporting[
 animate/slides/geometry
 #:use-sources
 (animate/slides/geometry)]

@defproc[(geometry-content [program-or-timeline any/c]
                           [#:poster poster any/c 'end]
                           [#:fit fit (or/c 'contain 'natural) 'contain]
                           [#:aspect aspect real? 16/9]) content?]{
Wraps a construction program or a ready timeline. Aspect is a positive preferred
ratio. Preparation freezes its geometry, annotation layout, styles, reveal data,
and timing. A ready timeline keeps its supplied realization.}

Geometry supports the module-backed worker route. Workers reconstruct samplers
from parent-prepared data without realizing the construction or placing labels
again. Explicit realization in module-level user code can still repeat when that
module is loaded in workers; the adapter cannot remove arbitrary source effects.

@section[#:tag "reference-slide-inspection"]{Preparation and inspection}

@subsection[#:tag "reference-slide-preparation"]{Preparation}
@declare-exporting[
 animate/slides/render
 #:use-sources
 (animate/slides/private/prepare
  animate/slides/private/semantic-plan
  animate/slides/render)]

@defproc[(prepare-slide! [source any/c]
                         [#:theme theme (or/c #f slide-theme?) #f]
                         [#:format format (or/c #f slide-format?) #f]
                         [#:asset-base asset-base (or/c #f path-string?) #f]) any/c]{
Measures and freezes a slide or clip, loading images, probing recordings, and
preparing supported domain content as needed. It does not render the final video.}
@defproc[(prepare-storyboard! [source any/c]
                              [#:asset-base asset-base (or/c #f path-string?) #f]) prepared-storyboard?]{
Prepares shots, matching, timing, and media for a whole storyboard. A prepared
value is tied to its theme and format; change the description and prepare again.}
@defproc[(prepared-duration [source any/c]) real?]{
Returns the duration of prepared slide content. A prepared plain slide has zero
duration.}
@defproc[(storyboard-match-report [source any/c]) list?]{
Returns actual planned matching data. Prefer a prepared storyboard so this does
not need to resolve anything. Each report records from/to, depth, reduced-motion
policy, and matches. This is not a prediction based on unmeasured source.}

@defproc*[([(prepared-slide? [value any/c]) boolean?]
           [(prepared-slide-clip? [value any/c]) boolean?]
           [(prepared-storyboard? [value any/c]) boolean?])]{
Tests whether a value is one of the public prepared slide values.}

@subsection[#:tag "reference-slide-inspection-helpers"]{Inspection helpers}
@declare-exporting[
 animate/slides
 #:use-sources
 (animate/slides/private/appearance
  animate/slides/private/layout
  animate/slides/private/model
  animate/slides/private/data
  animate/slides/private/semantic-model
  animate/slides/private/syntax
  animate/slides/main)]
@defproc[(storyboard-ref [source any/c] [occurrence-id symbol?]) any/c]{
Returns a shot with inherited storyboard context, or its prepared counterpart.
Use this instead of an isolated card when investigating storyboard layout.}
@defproc[(storyboard-with-theme [board storyboard?] [theme slide-theme?]) storyboard?]{
Returns a new description with the requested theme.}
@defproc[(storyboard-with-format [board storyboard?] [format slide-format?]) storyboard?]{
Returns a new description with the requested format.}
@defproc[(slide-ref [slide slide?] [slot symbol?]) any/c]{
Returns a slot's content without its options wrapper.}
@defproc[(check-storyboard [source any/c]) list?]{
Reports declaration/preparation diagnostics. It does not invoke external tools
or turn an unprepared declaration into measured output. Fatal validation occurs
in constructors or preparation.}

Slide exceptions expose a code, semantic path, and details. Domain exceptions
retain their own types. No automatic font-fallback or effective-resolution
advisories are supplied; absence of a diagnostic is not evidence of good type.

@section[#:tag "reference-slide-project"]{Project sources}
@declare-exporting[
 animate/slides/project
 #:use-sources
 (animate/slides/project)]

@defform[(storyboard-source module-path binding option ...)]{
Declares the exported storyboard to load. It accepts the keywords of
@racket[make-storyboard-source] and captures its declaring module's directory as
the default asset base. Construction alone starts neither an encoder nor workers.}
@defproc[(make-storyboard-source [module-path path-string?] [binding symbol?]
                                 [#:asset-base asset-base (or/c #f path-string?) #f]
                                 [#:seed seed exact-integer? 0]) any/c]{
Returns a native module-builder source. A programmatic relative path requires
an explicit base. The render project's color and typography choices must agree
with the storyboard. Parent-prepared text, math, and geometry are transferred
through the normal verified project preparation route.}

Prepared artifacts are data, not a promise of persistent frame-cache reuse.
Workers need compatible source, Racket, and fonts. No font binaries are
transferred. Arbitrary renderer factories and arbitrary closures are not made
portable by this API. @tt{slides/render-example.rkt} configures the ordinary
runner from an exported @tt{film}; it avoids duplicating those theme settings.

@section[#:tag "reference-slide-gallery"]{Gallery catalogue}
@declare-exporting[
 animate/slides/gallery
 #:use-sources
 (animate/slides/gallery)]

@defthing[slide-gallery-entries list?]{The ordered gallery catalogue.}
@defthing[slide-gallery-categories list?]{The categories: layouts, transitions, integration.}
@defproc[(select-slide-gallery-entries [#:entries entries (or/c #f list?) #f]
                                      [#:category category (or/c #f symbol?) #f]) list?]{
Selects entries without rendering. Explicit IDs must be nonempty, duplicate-free,
and known. Their order is preserved. A category combined with IDs must contain
every selected entry.}
@defproc[(make-slide-gallery [#:entries entries (or/c #f list?) #f]
                             [#:category category (or/c #f symbol?) #f]
                             [#:theme theme slide-theme? lecture-light]
                             [#:format format slide-format? widescreen]
                             [#:motion motion (or/c 'normal 'reduced) 'normal]) storyboard?]{
Builds a storyboard from selected examples. Preparation and output remain
separate. Listing does not typeset math or realize geometry. The CLI is documented
in @secref["reference-gallery-cli"].}

@defproc[(slide-gallery-entry? [value any/c]) boolean?]{
Tests whether a value is a gallery entry.}

@defproc*[([(slide-gallery-entry-id [value slide-gallery-entry?]) symbol?]
           [(slide-gallery-entry-category [value slide-gallery-entry?]) symbol?]
           [(slide-gallery-entry-title [value slide-gallery-entry?]) string?]
           [(slide-gallery-entry-description [value slide-gallery-entry?]) string?]
           [(slide-gallery-entry-requirements [value slide-gallery-entry?]) list?]
           [(slide-gallery-entry-example [value slide-gallery-entry?]) string?]
           [(slide-gallery-entry-source [value slide-gallery-entry?]) string?])]{
Returns the entry's catalogue metadata.}

@section[#:tag "reference-slide-accessors"]{Core predicates and read-only accessors}

These operations inspect values; they do not prepare or render them.

@declare-exporting[
 animate/slides
 #:use-sources
 (animate/slides/private/appearance
  animate/slides/private/layout
  animate/slides/private/model
  animate/slides/private/data
  animate/slides/private/semantic-model
  animate/slides/private/syntax
  animate/slides/main)]

@defproc*[([(slide? [value any/c]) boolean?]
           [(content? [value any/c]) boolean?]
           [(slide-format? [value any/c]) boolean?]
           [(slide-theme? [value any/c]) boolean?]
           [(layout? [value any/c]) boolean?]
           [(slot-spec? [value any/c]) boolean?]
           [(slide-clip? [value any/c]) boolean?]
           [(beat? [value any/c]) boolean?]
           [(slide-action? [value any/c]) boolean?]
           [(narration? [value any/c]) boolean?]
           [(storyboard? [value any/c]) boolean?]
           [(slide-transition? [value any/c]) boolean?]
           [(semantic-group? [value any/c]) boolean?]
           [(semantic-part? [value any/c]) boolean?]
           [(content-state? [value any/c]) boolean?]
           [(diagnostic? [value any/c]) boolean?]
           [(exn:fail:slides? [value any/c]) boolean?])]{
Tests whether a value has the indicated public type.}

@defproc*[([(slide-id [value slide?]) symbol?]
           [(slide-layout [value slide?]) layout?]
           [(slide-slots [value slide?]) hash?]
           [(slide-appearance [value slide?]) (or/c #f slide-theme?)]
           [(slide-notes [value slide?]) string?]
           [(slide-format-id [value slide-format?]) symbol?]
           [(slide-format-width [value slide-format?]) real?]
           [(slide-format-height [value slide-format?]) real?]
           [(slide-theme-id [value slide-theme?]) symbol?]
           [(slide-theme-colors [value slide-theme?]) color-theme?]
           [(slide-theme-typography [value slide-theme?]) typography-theme?]
           [(slide-theme-spacing [value slide-theme?]) hash?]
           [(slide-theme-decorations [value slide-theme?]) hash?]
           [(layout-id [value layout?]) symbol?]
           [(layout-slots [value layout?]) list?]
           [(slot-spec-name [value slot-spec?]) symbol?]
           [(slot-spec-required? [value slot-spec?]) boolean?]
           [(slot-spec-role [value slot-spec?]) symbol?]
           [(slide-clip-slide [value slide-clip?]) slide?]
           [(beat-name [value beat?]) symbol?]
           [(storyboard-id [value storyboard?]) symbol?]
           [(storyboard-theme [value storyboard?]) slide-theme?]
           [(storyboard-format [value storyboard?]) slide-format?]
           [(storyboard-motion [value storyboard?]) symbol?]
           [(storyboard-subtitles? [value storyboard?]) boolean?]
           [(slide-transition-effect [value slide-transition?]) symbol?]
           [(slide-transition-duration [value slide-transition?]) real?]
           [(slide-transition-keys [value slide-transition?]) list?]
           [(slide-transition-direction [value slide-transition?]) (or/c #f symbol?)]
           [(slide-transition-easing [value slide-transition?]) symbol?]
           [(slide-transition-scale [value slide-transition?]) (or/c #f real?)]
           [(slide-transition-color [value slide-transition?]) (or/c #f color-spec?)]
           [(slide-transition-depth [value slide-transition?]) symbol?]
           [(diagnostic-severity [value diagnostic?]) symbol?]
           [(diagnostic-code [value diagnostic?]) symbol?]
           [(diagnostic-path [value diagnostic?]) list?]
           [(diagnostic-message [value diagnostic?]) string?]
           [(diagnostic-details [value diagnostic?]) any/c]
           [(exn:fail:slides-code [value exn:fail:slides?]) symbol?]
           [(exn:fail:slides-path [value exn:fail:slides?]) list?]
           [(exn:fail:slides-details [value exn:fail:slides?]) any/c])]{
Returns the named field. Treat any returned private wrapper values as opaque.}
