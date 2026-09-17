#lang scribble/manual
@(require (for-label racket/base
                     racket/class
                     racket/contract
                     racket/draw
                     racket/generic
                     racket/math
                     (only-in pict pict?)
                     animate
                     animate/authoring
                     animate/preview
                     animate/render
                     animate/project
                     animate/experimental)
          "../../version.rkt")

@title[#:tag "animations" #:style 'toc]{Animation requests}

@declare-exporting[animate #:use-sources (animate/main)]

Animation constructor procedures return immutable request values. A request
stores a target identity and a requested endpoint or relative change. The
request is compiled against the scene's current state when @racket[scene-play]
is called.

A target can be a Visual value, its top-level symbol identity, or a nonempty
@racket[visual-path?]. A path follows built-in group children and is a direct
animation target; child transforms remain local to their containing group.


Choose a chapter by the change you want to make. Each chapter keeps the
complete signatures, defaults, and restrictions.

@local-table-of-contents[]

@include-section["animation-motion.scrbl"]
@include-section["animation-appearance.scrbl"]
@include-section["animation-enter-leave.scrbl"]
@include-section["animation-emphasis.scrbl"]
@include-section["animation-paths.scrbl"]
@include-section["animation-path-correspondence.scrbl"]
@include-section["animation-shapes.scrbl"]
@include-section["animation-text.scrbl"]
@include-section["animation-values.scrbl"]
@include-section["animation-camera.scrbl"]
@include-section["animation-timing.scrbl"]
@include-section["animation-easing.scrbl"]
@include-section["animation-other.scrbl"]
