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
                                  timeline-source? scene-program-source?
                                  module-builder-source?)]
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

@defproc[(animate-project-render [project animate-project?]) render-spec?]{
Returns the immutable final-render specification stored in the project.
}

@defproc[(module-binding-source [module-path path-string?] [binding symbol?])
         module-binding-source?]{
Declares a reloadable source suited to project workers and persistent caches.
}

@defproc[(module-binding-source? [value any/c]) boolean?]{Recognizes a reloadable module binding source.}

@defproc[(module-builder-source
          [module-path path-string?]
          [binding symbol?]
          [#:options options hash? #hasheq()]
          [#:prepare prepare (or/c symbol? #f) #f]
          [#:seed seed source-build-seed? 0])
         module-builder-source?]{
Declares a restartable source that a fresh process can rebuild by loading one
module export. The @racket[binding] export accepts exactly a build context, a
copied immutable options map, and either @racket[#f] or the completed
preparation payload. @racket[#:prepare], when supplied, names an export that
accepts the context and options and returns @racket[source-preparation?].
Planning normalizes this declaration but does not load either export.
}

@defproc[(module-builder-source? [value any/c]) boolean?]{Recognizes a module-builder source.}
@defproc[(module-builder-source-module-path [source module-builder-source?]) path-string?]{Returns the declared module path.}
@defproc[(module-builder-source-binding [source module-builder-source?]) symbol?]{Returns the fixed builder export name.}
@defproc[(module-builder-source-options [source module-builder-source?]) immutable?]{Returns the copied immutable builder options map.}
@defproc[(module-builder-source-prepare [source module-builder-source?]) (or/c symbol? #f)]{Returns the optional preparer export name.}
@defproc[(module-builder-source-seed [source module-builder-source?]) source-build-seed?]{Returns the deterministic builder seed.}

@defproc[(source-build-seed? [value any/c]) boolean?]{
Recognizes an exact nonnegative seed accepted by the selected Racket CS
@racket[random-seed] API. The current accepted range is 0 through
@racket[#x7fffffff]; invalid seeds are rejected rather than truncated.
}

@defproc[(source-transfer-data? [value any/c]) boolean?]{
Recognizes the bounded acyclic data representation for builder options and
preparation values. It accepts finite reals, booleans, symbols, keywords,
characters, strings, bytes, pairs, vectors, and hashes, copying containers and
mutable leaves into immutable values. Procedures, ports, bitmap/native values,
cycles, and oversized or deeply nested values are rejected.
}

@defproc[(source-preparation
          [#:payload payload source-transfer-data? #f]
          [#:artifacts artifacts list? '()]
          [#:dependencies dependencies list? '()]
          [#:frame-reuse frame-reuse (or/c source-transfer-data? #f) #f]
          [#:diagnostics diagnostics hash? #hasheq()])
         source-preparation?]{
Creates immutable data returned by a module preparer. Payloads should be
versioned adapter data rather than a scene or callback. Large assets belong in
completed artifact files identified by the small artifact manifest.
}
@defproc[(source-preparation? [value any/c]) boolean?]{Recognizes completed shared source preparation.}
@defproc[(source-preparation-payload [value source-preparation?]) source-transfer-data?]{Returns the builder payload.}
@defproc[(source-preparation-artifacts [value source-preparation?]) list?]{Returns completed artifact descriptions.}
@defproc[(source-preparation-dependencies [value source-preparation?]) list?]{Returns additional declared source/input identities.}
@defproc[(source-preparation-frame-reuse [value source-preparation?]) (or/c source-transfer-data? #f)]{Returns optional domain-owned frame-reuse data.}
@defproc[(source-preparation-diagnostics [value source-preparation?]) hash?]{Returns immutable preparation evidence.}

@defproc[(source-build-context? [value any/c]) boolean?]{
Recognizes the immutable construction context supplied to module preparers and
builders. It contains only construction-relevant configuration; worker count,
PID, batch assignment, retry identity, and staging paths are intentionally
absent.
}
@defproc[(source-build-context-module-path [context source-build-context?]) string?]{Returns the normalized source location.}
@defproc[(source-build-context-binding [context source-build-context?]) symbol?]{Returns the selected builder binding.}
@defproc[(source-build-context-options [context source-build-context?]) immutable?]{Returns copied builder options.}
@defproc[(source-build-context-asset-base [context source-build-context?]) string?]{Returns the stable source-relative asset base.}
@defproc[(source-build-context-assets [context source-build-context?]) list?]{Returns normalized declared asset descriptors.}
@defproc[(source-build-context-width [context source-build-context?]) exact-positive-integer?]{Returns target raster width.}
@defproc[(source-build-context-height [context source-build-context?]) exact-positive-integer?]{Returns target raster height.}
@defproc[(source-build-context-camera-policy [context source-build-context?]) source-transfer-data?]{Returns the explicit or scene-camera construction policy.}
@defproc[(source-build-context-theme [context source-build-context?]) color-theme?]{Returns the complete selected colour theme snapshot.}
@defproc[(source-build-context-typography [context source-build-context?]) typography-theme?]{Returns the complete selected typography snapshot.}
@defproc[(source-build-context-fps [context source-build-context?]) exact-positive-integer?]{Returns the semantic frame rate.}
@defproc[(source-build-context-quality [context source-build-context?]) symbol?]{Returns the declared semantic quality setting.}
@defproc[(source-build-context-seed [context source-build-context?]) source-build-seed?]{Returns the scoped random seed.}
@defproc[(source-build-context-base-fingerprint [context source-build-context?]) string?]{Returns the pre-preparation construction identity. Worker count and worker mode do not affect it.}
@defproc[(source-build-context-preparation [context source-build-context?]) (or/c source-preparation? #f)]{Returns completed preparation for a builder, or @racket[#f] while a preparer runs.}

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
                      [#:worker-mode worker-mode (or/c 'auto 'in-process 'subprocess) 'auto]
                      [#:theme theme color-theme? animate-light-theme]
                      [#:typography typography typography-theme?
                                     animate-typography-theme])
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

@defproc[(render-spec-workers [specification render-spec?])
         exact-positive-integer?]{
Returns the requested worker capacity for final frame rendering.  This is a
capacity request, not a prediction of speedup or a guarantee that every worker
will start.
}

@defproc[(render-spec-worker-mode [specification render-spec?])
         (or/c 'auto 'in-process 'subprocess)]{
Returns the requested final-worker mode. In @racket['auto], a restartable
module source uses local execution for one worker and selects future
subprocess execution for more than one; direct in-memory sources with more
than one worker are rejected unless they explicitly choose @racket['in-process].
PR-A resolves this policy but does not yet start final-render worker processes.
}

@defproc[(resolve-render-worker-policy
          [source (or/c module-binding-source? module-builder-source?
                        scene-source? timeline-source? scene-program-source?)]
          [render render-spec?])
         render-worker-policy?]{
Purely resolves a source/render declaration into an execution policy. It rejects
unsupported subprocess combinations before a project loads a source or mutates
an output path. The initial subprocess policy accepts only software rendering,
the default renderer set, and bounded renderer options.
}
@defproc[(render-worker-policy? [value any/c]) boolean?]{Recognizes a pure worker-policy decision.}
@defproc[(render-worker-policy-requested-mode [policy render-worker-policy?]) (or/c 'auto 'in-process 'subprocess)]{Returns author intent.}
@defproc[(render-worker-policy-resolved-mode [policy render-worker-policy?]) (or/c 'in-process 'subprocess)]{Returns the selected executor kind.}
@defproc[(render-worker-policy-restartable? [policy render-worker-policy?]) boolean?]{Reports whether the source can be reconstructed from a declaration.}
@defproc[(render-worker-policy-reason [policy render-worker-policy?]) symbol?]{Returns the deterministic resolution reason.}

@defproc[(render-spec-theme [specification render-spec?]) color-theme?]{
Returns the complete immutable theme snapshot selected for final rendering.
The project plan records its canonical datum, appearance fingerprint, resolver
version, and provenance, so replay does not depend on a locally named palette.
}

@defproc[(render-spec-typography [specification render-spec?]) typography-theme?]{
Returns the immutable semantic text snapshot selected for final rendering. Its
canonical datum, appearance fingerprint, and resolver version participate in
project and section-cache identity because typography can change text geometry.
}

@defproc[(render-spec-with-theme [specification render-spec?]
                                 [theme color-theme?])
         render-spec?]{
Returns a copy with only the selected theme changed. This is useful for an
explicit command-line or build-system appearance override; raster dimensions,
renderers, worker policy, and quality remain unchanged.
}

@defproc[(render-spec-with-typography [specification render-spec?]
                                      [typography typography-theme?])
         render-spec?]{
Returns a copy with only the typography snapshot changed. This is explicit
render configuration; raw text constructors remain unaffected.
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
tools but does not render frames or create final artifacts.  For a
@racket[module-builder-source] with @racket[#:prepare], the preparer runs once
in this parent-side operation.  Its bounded payload and completed artifact
manifest are then verified when a fresh worker reconstructs the builder; a
worker does not invoke the preparer again.
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

@defproc[(prepared-project-source-build-context [prepared prepared-project?])
         (or/c source-build-context? #f)]{
Returns the context actually supplied to a module builder, or @racket[#f] for a
direct or module-value source.
}
@defproc[(prepared-project-source-preparation [prepared prepared-project?])
         (or/c source-preparation? #f)]{
Returns completed shared preparation retained for a module builder, if one was
declared.
}
@defproc[(prepared-project-input-manifest [prepared prepared-project?])
         immutable?]{
Returns the bounded local-input snapshot for a restartable module source.  The
executor checks the represented module/dependency and declared asset contents
before child startup, after child readiness, and before publication.  It is an
inspection value; callers should not treat it as an editable cache API.
}
@defproc[(prepared-project-preparation-manifest [prepared prepared-project?])
         (or/c immutable? #f)]{
Returns the parent-to-worker preparation handoff for a prepared module builder,
or @racket[#f] when no preparer was declared.  Path-bearing artifacts are
content-identified files under the source asset root; invalid or changed
artifacts cause execution to fail before a worker accepts final frames.
}
@defproc[(prepared-project-preparation-elapsed-milliseconds
          [prepared prepared-project?])
         nonnegative-real?]{
Returns the parent-observed elapsed time spent loading and preparing the
restartable source.  It is reported separately from worker startup and frame
rasterization.
}
@defproc[(prepared-project-worker-policy [prepared prepared-project?])
         render-worker-policy?]{Returns the policy resolved before source loading.}

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
