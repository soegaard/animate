#lang racket/base

;; Immutable compiler, realization and presentation records. Field order is
;; part of the inspectable v0.1 API; all collections produced by the compiler
;; are immutable. Local builder mutation never escapes into a sampled frame.
(provide (struct-out geometry-node) (struct-out geometry-action)
         (struct-out geometry-step) (struct-out geometry-timing) (struct-out geometry-check)
         (struct-out geometry-program) (struct-out construction-helper)
         (struct-out geometry-view) (struct-out geometry-realization)
         (struct-out presentation) (struct-out geometry-event)
         (struct-out geometry-cue) (struct-out geometry-timeline)
         (struct-out geometry-appearance) (struct-out geometry-frame))

;; node: stable name, inferred type, expression datum, provenance, given?, public?.
(struct geometry-node (id type expression origin given? public?) #:transparent)
;; action: kind, ordered targets, optional nested actions/steps.
(struct geometry-action (kind targets payload) #:transparent)
;; step: optional narration string, ordered actions, and optional timing overrides.
(struct geometry-step (narration actions timing) #:transparent)
;; timing: opening pause, narration read delay, default action duration, and pause after a step.
(struct geometry-timing (opening-pause read-delay action-duration step-pause) #:transparent)
;; check: Boolean expression and useful source provenance.
(struct geometry-check (expression origin) #:transparent)
;; program: name, topologically ordered nodes, steps, initial actions,
;; mathematical preconditions, post-realization assertions, layout clauses, per-object style clauses,
;; timing policy, public result ids, and definition source location.
(struct geometry-program (name nodes steps initial checks assertions layout styles timing results source) #:transparent)
;; helper: name, ordered (name . type) inputs, declared result types, checked body.
(struct construction-helper (name parameters result-types program) #:transparent)
;; view: Cartesian centre, world width, aspect ratio, fractional safe margin.
(struct geometry-view (center width aspect margin) #:transparent)
;; realization: abstract program, immutable id->value table, fixed view,
;; selected free values, and diagnostics about the finite deterministic search.
(struct geometry-realization (program values view choices diagnostics) #:transparent)
;; presentation: object shown?, label enabled?, deemphasized?.
(struct presentation (shown? label? secondary?) #:transparent)
;; event: start/end seconds, simultaneous actions, before/after state snapshots.
(struct geometry-event (start end actions before after) #:transparent)
;; cue: narration span in seconds and text (also usable for subtitles).
(struct geometry-cue (start end text) #:transparent)
;; timeline: realized construction, geometry theme, events, narration cues,
;; initial/final presentation maps and total duration in seconds.
(struct geometry-timeline (realization theme events cues initial final duration) #:transparent)
;; appearance: show opacity, label opacity, curve reveal fraction,
;; continuous secondary-style weight, and transient highlight amount.
(struct geometry-appearance (opacity label-opacity reveal secondary highlight) #:transparent)
;; frame: sampled time, immutable per-id appearances, current narration.
(struct geometry-frame (time appearances narration) #:transparent)
