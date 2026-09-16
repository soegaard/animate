#lang racket/base

;; Private representations. Public constructors validate and copy their inputs;
;; mutable preparation caches never escape in these values.
(provide (all-defined-out))

(struct format-value (id width height) #:transparent)
(struct theme-value (id colors typography spacing decorations) #:transparent)
(struct slot-spec-value (name required? role) #:transparent)
(struct layout-node (kind name children basis grow gap align valign padding minimum maximum) #:transparent)
(struct layout-value (id slots wide standard portrait fallback) #:transparent)
(struct content-value (kind payload options) #:transparent)
(struct slot-value (content key align valign fit) #:transparent)
(struct slide-value (id layout slots theme notes) #:transparent)
(struct narration-value (text audio draft-duration at source-start duration captions asset-base) #:transparent)
(struct action-value (kind target at duration effect payload options) #:transparent)
(struct beat-value (name duration narration tail actions) #:transparent)
(struct clip-value (slide initial poster motion beats hold?) #:transparent)
(struct shot-value (id clip) #:transparent)
(struct transition-value (effect duration keys) #:transparent)
(struct storyboard-value (id theme format motion subtitles? entries) #:transparent)
(struct contextual-value (source theme format subtitle-height motion) #:transparent)

;; Positive-down authoring coordinates. Pixel size is deliberately not part of
;; layout identity. Geometry is measured at a fixed 100 pixels per world unit.
(struct box-value (x y width height) #:transparent)
(struct content-context-value (theme format box asset-base effects?) #:transparent)
(struct diagnostic (severity code path message details) #:transparent)
(struct exn:fail:slides exn:fail (code path details) #:transparent)

;; An asset owns a fixed geometry envelope. Its value is either a Pict or a
;; native bundle; native preparation/sampling lives in the optional adapter.
(struct asset (kind value width height baseline duration poster cues identity metadata) #:transparent)
(struct prepared-leaf (path box asset key clip) #:transparent)
(struct prepared-slot (name box variants key source) #:transparent)
(struct prepared-slide-value (source theme format subtitle-height slots diagnostics motion) #:transparent)
(struct event (kind target start duration from to effect variant) #:transparent)
(struct prepared-beat (name start duration narration) #:transparent)
(struct prepared-narration (text audio start duration source-start captions) #:transparent)
(struct prepared-clip-value (slide events beats duration initial poster hold?) #:transparent)
(struct prepared-shot (id clip start) #:transparent)
(struct prepared-bridge (from to transition start) #:transparent)
(struct prepared-storyboard-value (source shots bridges duration diagnostics) #:transparent)

;; Render commands are a shared, renderer-neutral snapshot, not another scene
;; renderer. Both adapters consume these exact rectangles, alphas, and times.
(struct frame-leaf (path box asset time opacity scale key clip) #:transparent)
(struct frame-value (format background leaves slots safe-box decorations) #:transparent)

(struct placement (box align valign) #:transparent)
(struct native-bundle (scene camera colors typography cues identity hidden-ids) #:transparent)
