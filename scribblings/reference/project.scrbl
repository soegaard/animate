#lang scribble/manual

@(require (for-label racket/base
                     animate
                     animate/authoring
                     (except-in animate/colors tan)
                     animate/project
                     animate/render
                     animate/3d
                     animate/3d/render
                     animate/3d/opengl))

@title[#:tag "reference-project"]{Projects and Final Rendering}

@declare-exporting[animate/project #:use-sources (animate/project)]

An @racket[animate-project?] is the one immutable declaration shared by final
rendering and project preview.  It separates a pure configuration plan from
effectful preparation and execution.

@defproc[(animate-project
          [#:id id symbol?]
          [#:source source (or/c module-binding-source? scene-source?
                                  timeline-source? scene-program-source?)]
          [#:render render render-spec? (render-spec)]
          [#:preview preview preview-spec? (preview-spec)]
          [#:output output output-spec? (output-spec)]
          [#:encoder encoder encoder-spec? (encoder-spec)]
          [#:cache cache cache-spec? (cache-spec)]
          [#:assets assets (listof project-asset?) '()]
          [#:metadata metadata hash? #hasheq()])
         animate-project?]{

Creates one immutable project declaration.  The constructor snapshots lists
and hashes, so later caller mutation cannot change the project.
}

@defproc[(animate-project? [value any/c]) boolean?]{Recognizes an immutable project declaration.}

@defproc[(module-binding-source [module-path path-string?] [binding symbol?])
         module-binding-source?]{
Declares a reloadable source suited to project workers and persistent caches.
}

@defproc[(module-binding-source? [value any/c]) boolean?]{Recognizes a reloadable module binding source.}

@defproc[(scene-source [scene scene?]) scene-source?]{
Declares an in-memory Scene source for local planning and preview.
}

@defproc[(scene-source? [value any/c]) boolean?]{Recognizes a direct Scene source.}

@defproc[(timeline-source [timeline authored-timeline?]) timeline-source?]{
Declares an in-memory authored timeline source.
}

@defproc[(timeline-source? [value any/c]) boolean?]{Recognizes a direct timeline source.}

@defproc[(scene-program-source [program scene-program?]) scene-program-source?]{
Declares an in-memory source-program source.
}

@defproc[(scene-program-source? [value any/c]) boolean?]{Recognizes a direct source-program source.}

@defproc[(render-spec [#:fps fps exact-positive-integer? 30]
                      [#:width width exact-positive-integer? 1280]
                      [#:height height exact-positive-integer? 720]
                      [#:renderer3d renderer3d any/c 'software]
                      [#:supersample supersample exact-positive-integer? 1]
                      [#:workers workers exact-positive-integer? 1]
                      [#:theme theme color-theme? animate-light-theme])
         render-spec?]{
Describes final raster quality.  Renderer and camera fields have defaults too;
see @racket[render-spec] in the contract reference for the complete set.
@racket[#:renderer3d] is @racket['software] by default. Passing an explicit
@racket[opengl-renderer3d-spec] selects the optional Racket/OpenGL backend for
final project rendering; it requires Racket 9.3 @exec{gracket} and
@racket[#:workers 1]. OpenGL is not loaded merely by constructing this immutable
project declaration.}
}

@defproc[(render-spec? [value any/c]) boolean?]{Recognizes a final-render configuration.}

@defproc[(render-spec-theme [specification render-spec?]) color-theme?]{
Returns the complete immutable theme snapshot selected for final rendering.
The project plan records its canonical datum, appearance fingerprint, resolver
version, and provenance, so replay does not depend on a locally named palette.
}

@defproc[(render-spec-with-theme [specification render-spec?]
                                 [theme color-theme?])
         render-spec?]{
Returns a copy with only the selected theme changed. This is useful for an
explicit command-line or build-system appearance override; raster dimensions,
renderers, worker policy, and quality remain unchanged.
}

@defproc[(preview-spec [#:fps fps exact-positive-integer? 30]
                       [#:pixel-scale pixel-scale positive? 1]
                       [#:cache-megabytes cache-megabytes exact-positive-integer? 512]
                       [#:prefetch prefetch exact-nonnegative-integer? 3]
                       [#:audio? audio? boolean? #f])
         preview-spec?]{
Describes preview quality, a 512 MiB default bitmap-cache budget, and optional
audio monitoring.
}

@defproc[(preview-spec? [value any/c]) boolean?]{Recognizes a preview configuration.}

The @racket[raco animate] command accepts the global prefix options
@tt{--theme animate-light}, @tt{--theme animate-dark}, or
@tt{--theme-file PATH} before @tt{plan}, @tt{render}, or @tt{preview}. The two options are mutually exclusive. A theme file
contains the versioned datum accepted by @racket[datum->theme]; it is read as
data rather than evaluated. Its digest and decoded snapshot become part of the
prepared render identity, so workers never reread the file midway through a
render.

@defproc[(output-spec [#:root root path-string? "media"]
                      [#:name name string? "animation"]
                      [#:format format (or/c 'mp4 'png-sequence) 'mp4]
                      [#:overwrite-policy overwrite-policy (or/c 'error 'replace) 'error])
         output-spec?]{
Declares final artifact naming.  Planning determines exact artifact paths
without creating their parent directories.
}

@defproc[(output-spec? [value any/c]) boolean?]{Recognizes an output declaration.}

@defproc[(encoder-spec [#:codec codec symbol? 'h264]
                       [#:pixel-format pixel-format symbol? 'yuv420p]
                       [#:options options hash? #hasheq()]
                       [#:audio-codec audio-codec symbol? 'aac]
                       [#:audio-options audio-options hash? #hasheq()]
                       [#:fast-start? fast-start? boolean? #t])
         encoder-spec?]{
Declares video and audio encoder settings independently of frame rendering.
}

@defproc[(encoder-spec? [value any/c]) boolean?]{Recognizes a video/audio encoder declaration.}

@defproc[(cache-spec [#:root root path-string? ".animate-cache"]
                     [#:policy policy symbol? 'read-write]
                     [#:max-bytes max-bytes exact-nonnegative-integer? (* 1024 1024 1024)]
                     [#:domains domains (listof symbol?) '(formula frames segments audio waveform source-program)])
         cache-spec?]{
Declares domain-specific cache policy.  Encoder settings affect segment
caches, not frame caches; audio changes do not invalidate visual frames.
}

@defproc[(cache-spec? [value any/c]) boolean?]{Recognizes a cache declaration.}

@defproc[(project-asset [path path-string?]
                        [#:role role symbol? 'visual]
                        [#:metadata metadata hash? #hasheq()])
         project-asset?]{Declares a visual, audio, formula, or author-defined asset.}

@defproc[(project-asset? [value any/c]) boolean?]{Recognizes a declared project asset.}

@defproc[(project-target-section [name symbol?]) project-target?]{Selects one authored section.}
@defthing[project-target-all project-target?]{Selects the complete declared source.}
@defproc[(project-target? [value any/c]) boolean?]{Recognizes a project target.}
@defproc[(plan-project [project animate-project?]
                       [#:target target project-target? (project-target-all)]
                       [#:directory directory path-string? (current-directory)])
         project-plan?]{

Normalizes the declaration and produces exact output/cache paths without
reading source files, locating tools, creating directories, or rendering.
}

@defproc[(project-plan? [value any/c]) boolean?]{Recognizes an immutable pure project plan.}

@defproc[(prepare-project! [plan project-plan?]) prepared-project?]{

Loads the declared source, validates its type and selected target, fingerprints
inputs/tools, and determines frame indices.  Preparation may read files and
tools but does not render frames or create final artifacts.
}

@defproc[(prepare-project-label-layout3d
          [project animate-project?]
          [#:view view-id symbol?]
          [#:frames frames (or/c #f (listof exact-nonnegative-integer?)) #f]
          [#:target target project-target? (project-target-all)]
          [#:switch-penalty switch-penalty nonnegative-real? 0]
          [#:movement-penalty movement-penalty nonnegative-real? 0])
         prepared-label-layout3d?]{
Prepares one @racket[view3d]'s projected-label trajectory using the project
target's source-frame grid, output camera, raster dimensions, renderer list,
and supersampling policy.  With @racket[#:frames #f], it uses the selected
target's frames.  The immutable result is safe to share read-only with render
workers.  Pass it to a project render operation as
@racket[#:prepared-label-layout]; its selected placement boxes become part of
the frame-cache identity.

This is an explicit preparation operation: ordinary project rendering keeps
direct per-frame layout unless the author supplies a table.  Preparation
measures 2D templates without constructing an optional live OpenGL renderer.}

@defproc[(prepared-project? [value any/c]) boolean?]{Recognizes an effectfully prepared but unrendered project.}

@defproc[(check-project! [plan project-plan?]) project-check-report?]{
Prepares a project only far enough to validate its declared source, assets,
tools, target, and renderer capabilities.  It writes no frames or output
artifacts.  The immutable report separates required failures from optional
warnings, so it is suitable for a command-line or preview diagnosis.
}
@defproc[(project-check-report? [value any/c]) boolean?]{Recognizes an
immutable project-validation report.}

@defproc[(project-plan->datum [plan project-plan?]) immutable-hash?]{
Returns a serializable inspection representation of a pure plan.
}

Use @racket[execute-prepared-project!] from @racketmodname[animate/render] to
run a prepared plan.  It produces an immutable execution report after frame
rendering, encoding, and optional media assembly, and installs final artifacts
atomically.

@bold{Limitation:} direct Scene, timeline, and program sources may contain
arbitrary procedures.  They are valid for an in-memory session but cannot have
an honest persistent fingerprint unless the author supplies an explicit key.
