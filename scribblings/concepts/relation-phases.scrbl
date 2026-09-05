#lang scribble/manual

@(require (for-label (except-in racket/base angle string-copy) animate))

@title[#:tag "concept-relation-phases"]{Relation Phases}

A @racket[relation-visual] is a first-class immutable declaration of a visual
that depends on scene values, visual identities, or renderer-measured layout.
Semantic relations resolve from sampled scene data; layout relations resolve
only after ordinary sampling, so they can use a renderer's measured boxes.

Relations have explicit dependencies, phase, structure, and cacheability. This
makes a live label or altitude inspectable instead of hiding a mutable updater.
