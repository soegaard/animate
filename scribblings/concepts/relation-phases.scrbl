#lang scribble/manual
@(require (for-label racket/base animate))

@title[#:tag "concept-relation-phases"]{Objects that depend on other objects}

Some objects should follow others. A label may follow a moving point. An
altitude may depend on the vertices of a triangle. A background box may need
the measured size of its text.

A @racket[relation-visual] declares such a dependency. It says which inputs it
uses, so Animate can calculate it from the requested scene state. It is not
an instruction to mutate the previous frame.

There are two phases. A @bold{semantic relation} uses sampled scene values and
object identities. A @bold{layout relation} also needs measurements from the
renderer, so it is resolved after ordinary sampling.

Use a semantic relation for a point determined by other points. Use a layout
relation for a box whose size depends on rendered text. The distinction is about
when the necessary information is available.

The declaration also states its output structure and whether its result can be
cached. The reference gives the exact dependency and cache rules. A fixed slide
layout normally needs neither a new relation nor a per-frame layout pass.
