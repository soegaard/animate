#lang racket/base

;;;
;;; Immutable Animation Projects
;;;

;; Defines normalized project declarations and their two-stage preparation
;; pipeline. Planning is pure; preparation may load a declared source and
;; inspect capabilities, but neither operation renders or writes an artifact.


;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/list
         racket/match
         racket/path
         racket/string
         "authoring.rkt"
         "main.rkt"
         "private/3d/renderer3d.rkt"
         "private/doctor.rkt"
         "private/ffmpeg-capabilities.rkt"
         "version.rkt")

(provide animate-project
         animate-project?
         animate-project-id
         animate-project-source
         animate-project-render
         animate-project-preview
         animate-project-output
         animate-project-encoder
         animate-project-cache
         animate-project-assets
         animate-project-metadata
         module-binding-source
         module-binding-source?
         module-binding-source-module-path
         module-binding-source-binding
         scene-source
         scene-source?
         scene-source-scene
         timeline-source
         timeline-source?
         timeline-source-timeline
         scene-program-source
         scene-program-source?
         scene-program-source-program
         render-spec
         render-spec?
         render-spec-fps
         render-spec-width
         render-spec-height
         render-spec-camera
         render-spec-renderers
         render-spec-renderer-options
         render-spec-supersample
         render-spec-workers
         render-spec-quality
         preview-spec
         preview-spec?
         preview-spec-fps
         preview-spec-pixel-scale
         preview-spec-supersample
         preview-spec-cache-megabytes
         preview-spec-prefetch
         preview-spec-worker-mode
         preview-spec-quality-policy
         preview-spec-audio?
         output-spec
         output-spec?
         output-spec-root
         output-spec-name
         output-spec-format
         output-spec-write-sections?
         output-spec-write-frame-sequence?
         output-spec-overwrite-policy
         output-spec-open-after?
         encoder-spec
         encoder-spec?
         encoder-spec-codec
         encoder-spec-pixel-format
         encoder-spec-options
         encoder-spec-audio-codec
         encoder-spec-audio-options
         encoder-spec-fast-start?
         cache-spec
         cache-spec?
         cache-spec-root
         cache-spec-policy
         cache-spec-max-bytes
         cache-spec-domains
         project-asset
         project-asset?
         project-asset-path
         project-asset-role
         project-asset-metadata
         project-target-all
         project-target-section
         project-target-block
         project-target-range
         project-target-frame
         project-target?
         project-target-kind
         project-target-value
         project-target-start
         project-target-end
         (struct-out cacheability)
         (struct-out project-path-plan)
         project-path-plan-cache-domain-root
         (struct-out project-plan)
         (struct-out project-tool-identities)
         (struct-out prepared-project)
         (struct-out renderer3d-capability-set)
         (struct-out renderer-capabilities)
         (struct-out project-check-report)
         normalize-project
         plan-project
         prepare-project!
         check-project!
         project-plan->datum
         prepared-project->datum
         write-project-plan)


;;;
;;; Immutable Declarations
;;;

(struct animate-project-value
  (id source render preview output encoder cache assets metadata)
  #:transparent
  #:constructor-name make-animate-project)

;; animate-project-value collects all declarations needed for a preview or
;; final output. The public constructor copies and validates mutable inputs.

(define animate-project? animate-project-value?)
(define animate-project-id animate-project-value-id)
(define animate-project-source animate-project-value-source)
(define animate-project-render animate-project-value-render)
(define animate-project-preview animate-project-value-preview)
(define animate-project-output animate-project-value-output)
(define animate-project-encoder animate-project-value-encoder)
(define animate-project-cache animate-project-value-cache)
(define animate-project-assets animate-project-value-assets)
(define animate-project-metadata animate-project-value-metadata)

(struct module-binding-source-value (module-path binding)
  #:transparent
  #:constructor-name make-module-binding-source)

(struct scene-source-value (value)
  #:transparent
  #:constructor-name make-scene-source)

(struct timeline-source-value (value)
  #:transparent
  #:constructor-name make-timeline-source)

(struct scene-program-source-value (value)
  #:transparent
  #:constructor-name make-scene-program-source)

(define module-binding-source? module-binding-source-value?)
(define module-binding-source-module-path module-binding-source-value-module-path)
(define module-binding-source-binding module-binding-source-value-binding)
(define scene-source? scene-source-value?)
(define scene-source-scene scene-source-value-value)
(define timeline-source? timeline-source-value?)
(define timeline-source-timeline timeline-source-value-value)
(define scene-program-source? scene-program-source-value?)
(define scene-program-source-program scene-program-source-value-value)

(struct render-spec-value
  (fps width height camera renderers renderer-options supersample workers quality)
  #:transparent
  #:constructor-name make-render-spec)

(define render-spec? render-spec-value?)
(define render-spec-fps render-spec-value-fps)
(define render-spec-width render-spec-value-width)
(define render-spec-height render-spec-value-height)
(define render-spec-camera render-spec-value-camera)
(define render-spec-renderers render-spec-value-renderers)
(define render-spec-renderer-options render-spec-value-renderer-options)
(define render-spec-supersample render-spec-value-supersample)
(define render-spec-workers render-spec-value-workers)
(define render-spec-quality render-spec-value-quality)

(struct preview-spec-value
  (fps pixel-scale supersample cache-megabytes prefetch worker-mode quality-policy audio?)
  #:transparent
  #:constructor-name make-preview-spec)

(define preview-spec? preview-spec-value?)
(define preview-spec-fps preview-spec-value-fps)
(define preview-spec-pixel-scale preview-spec-value-pixel-scale)
(define preview-spec-supersample preview-spec-value-supersample)
(define preview-spec-cache-megabytes preview-spec-value-cache-megabytes)
(define preview-spec-prefetch preview-spec-value-prefetch)
(define preview-spec-worker-mode preview-spec-value-worker-mode)
(define preview-spec-quality-policy preview-spec-value-quality-policy)
(define preview-spec-audio? preview-spec-value-audio?)

(struct output-spec-value
  (root name format write-sections? write-frame-sequence? overwrite-policy open-after?)
  #:transparent
  #:constructor-name make-output-spec)

(define output-spec? output-spec-value?)
(define output-spec-root output-spec-value-root)
(define output-spec-name output-spec-value-name)
(define output-spec-format output-spec-value-format)
(define output-spec-write-sections? output-spec-value-write-sections?)
(define output-spec-write-frame-sequence? output-spec-value-write-frame-sequence?)
(define output-spec-overwrite-policy output-spec-value-overwrite-policy)
(define output-spec-open-after? output-spec-value-open-after?)

(struct encoder-spec-value
  (codec pixel-format options audio-codec audio-options fast-start?)
  #:transparent
  #:constructor-name make-encoder-spec)

(define encoder-spec? encoder-spec-value?)
(define encoder-spec-codec encoder-spec-value-codec)
(define encoder-spec-pixel-format encoder-spec-value-pixel-format)
(define encoder-spec-options encoder-spec-value-options)
(define encoder-spec-audio-codec encoder-spec-value-audio-codec)
(define encoder-spec-audio-options encoder-spec-value-audio-options)
(define encoder-spec-fast-start? encoder-spec-value-fast-start?)

(struct cache-spec-value (root policy max-bytes domains)
  #:transparent
  #:constructor-name make-cache-spec)

(define cache-spec? cache-spec-value?)
(define cache-spec-root cache-spec-value-root)
(define cache-spec-policy cache-spec-value-policy)
(define cache-spec-max-bytes cache-spec-value-max-bytes)
(define cache-spec-domains cache-spec-value-domains)

(struct project-asset-value (path role metadata)
  #:transparent
  #:constructor-name make-project-asset)

(define project-asset? project-asset-value?)
(define project-asset-path project-asset-value-path)
(define project-asset-role project-asset-value-role)
(define project-asset-metadata project-asset-value-metadata)

(struct project-target (kind value start end)
  #:transparent)

;; project-target selects the portion of a prepared source to preview or emit.
;; Ranges are half-open times, and frame indices are zero based.

(struct cacheability (mode reasons explicit-key)
  #:transparent)

;; cacheability distinguishes persistent reuse from memory-only and disabled
;; work. reasons is an immutable list explaining the classification.


;;;
;;; Public Constructors
;;;

; animate-project : #:id symbol? #:source source-specification? ... -> animate-project?
;;   Creates one immutable project declaration with current authoring defaults.
(define (animate-project #:id id
                         #:source source
                         #:render [render (render-spec)]
                         #:preview [preview (preview-spec)]
                         #:output [output (output-spec)]
                         #:encoder [encoder (encoder-spec)]
                         #:cache [cache (cache-spec)]
                         #:assets [assets '()]
                         #:metadata [metadata #hasheq()])
  (check-symbol 'animate-project id)
  (check-source 'animate-project source)
  (check-specification 'animate-project render render-spec?)
  (check-specification 'animate-project preview preview-spec?)
  (check-specification 'animate-project output output-spec?)
  (check-specification 'animate-project encoder encoder-spec?)
  (check-specification 'animate-project cache cache-spec?)
  (unless (and (list? assets) (andmap project-asset? assets))
    (raise-argument-error 'animate-project "list of project-asset?" assets))
  (unless (hash? metadata)
    (raise-argument-error 'animate-project "hash?" metadata))
  (make-animate-project id source render preview output encoder cache
                        (append assets '())
                        (immutable-hash-snapshot metadata)))

; module-binding-source : path-string? symbol? -> module-binding-source?
;;   Declares a reloadable module binding for restartable projects and workers.
(define (module-binding-source module-path binding)
  (unless (path-string? module-path)
    (raise-argument-error 'module-binding-source "path-string?" module-path))
  (check-symbol 'module-binding-source binding)
  (make-module-binding-source module-path binding))

; scene-source : scene? -> scene-source?
;;   Declares a directly supplied immutable Scene for a local interactive use.
(define (scene-source value)
  (unless (scene? value)
    (raise-argument-error 'scene-source "scene?" value))
  (make-scene-source value))

; timeline-source : authored-timeline? -> timeline-source?
;;   Declares a directly supplied authored timeline.
(define (timeline-source value)
  (unless (authored-timeline? value)
    (raise-argument-error 'timeline-source "authored-timeline?" value))
  (make-timeline-source value))

; scene-program-source : scene-program? -> scene-program-source?
;;   Declares a directly supplied source-block program for local planning.
(define (scene-program-source value)
  (unless (scene-program? value)
    (raise-argument-error 'scene-program-source "scene-program?" value))
  (make-scene-program-source value))

; render-spec : ... -> render-spec?
;;   Describes target raster dimensions and deterministic rendering options.
(define (render-spec #:fps [fps 30]
                     #:width [width 1280]
                     #:height [height 720]
                     #:camera [camera #f]
                     #:renderers [renderers 'default]
                     #:renderer-options [renderer-options #hasheq()]
                     #:supersample [supersample 1]
                     #:workers [workers 1]
                     #:quality [quality 'final])
  (check-positive-integer 'render-spec "fps" fps)
  (check-positive-integer 'render-spec "width" width)
  (check-positive-integer 'render-spec "height" height)
  (check-positive-integer 'render-spec "supersample" supersample)
  (check-positive-integer 'render-spec "workers" workers)
  (unless (or (eq? renderers 'default) (list? renderers))
    (raise-argument-error 'render-spec "'default or list?" renderers))
  (unless (hash? renderer-options)
    (raise-argument-error 'render-spec "hash?" renderer-options))
  (unless (memq quality '(draft final))
    (raise-argument-error 'render-spec "'draft or 'final" quality))
  (make-render-spec fps width height camera
                    (if (list? renderers) (append renderers '()) renderers)
                    (immutable-hash-snapshot renderer-options)
                    supersample workers quality))

; preview-spec : ... -> preview-spec?
;;   Describes preview resolution, cache budget, isolation mode, and audio intent.
(define (preview-spec #:fps [fps 30]
                      #:pixel-scale [pixel-scale 1]
                      #:supersample [supersample 1]
                      #:cache-megabytes [cache-megabytes 128]
                      #:prefetch [prefetch 3]
                      #:worker-mode [worker-mode 'in-process]
                      #:quality-policy [quality-policy 'adaptive]
                      #:audio? [audio? #f])
  (check-positive-integer 'preview-spec "fps" fps)
  (unless (and (real? pixel-scale) (positive? pixel-scale))
    (raise-argument-error 'preview-spec "positive real?" pixel-scale))
  (check-positive-integer 'preview-spec "supersample" supersample)
  (check-positive-integer 'preview-spec "cache-megabytes" cache-megabytes)
  (unless (exact-nonnegative-integer? prefetch)
    (raise-argument-error 'preview-spec "exact-nonnegative-integer?" prefetch))
  (unless (memq worker-mode '(in-process subprocess))
    (raise-argument-error 'preview-spec "'in-process or 'subprocess" worker-mode))
  (unless (memq quality-policy '(fixed adaptive))
    (raise-argument-error 'preview-spec "'fixed or 'adaptive" quality-policy))
  (unless (boolean? audio?)
    (raise-argument-error 'preview-spec "boolean?" audio?))
  (make-preview-spec fps pixel-scale supersample cache-megabytes prefetch
                     worker-mode quality-policy audio?))

; output-spec : ... -> output-spec?
;;   Declares deterministic output naming and explicit replacement behavior.
(define (output-spec #:root [root "media"]
                     #:name [name "animation"]
                     #:format [format 'mp4]
                     #:write-sections? [write-sections? #f]
                     #:write-frame-sequence? [write-frame-sequence? #f]
                     #:overwrite-policy [overwrite-policy 'error]
                     #:open-after? [open-after? #f])
  (unless (path-string? root)
    (raise-argument-error 'output-spec "path-string?" root))
  (unless (and (string? name) (positive? (string-length name)))
    (raise-argument-error 'output-spec "nonempty string?" name))
  (unless (memq format '(mp4 png-sequence))
    (raise-argument-error 'output-spec "'mp4 or 'png-sequence" format))
  (unless (and (boolean? write-sections?) (boolean? write-frame-sequence?)
               (boolean? open-after?))
    (raise-argument-error 'output-spec "boolean output flags" #f))
  (unless (memq overwrite-policy '(error replace))
    (raise-argument-error 'output-spec "'error or 'replace" overwrite-policy))
  (make-output-spec root (string->immutable-string name) format
                    write-sections? write-frame-sequence?
                    overwrite-policy open-after?))

; encoder-spec : ... -> encoder-spec?
;;   Describes a video encoder separately from the frame-rendering declaration.
(define (encoder-spec #:codec [codec 'h264]
                      #:pixel-format [pixel-format 'yuv420p]
                      #:options [options #hasheq()]
                      #:audio-codec [audio-codec 'aac]
                      #:audio-options [audio-options #hasheq()]
                      #:fast-start? [fast-start? #t])
  (for ([field (in-list (list codec pixel-format audio-codec))])
    (check-symbol 'encoder-spec field))
  (unless (and (hash? options) (hash? audio-options))
    (raise-argument-error 'encoder-spec "hash option maps" #f))
  (unless (boolean? fast-start?)
    (raise-argument-error 'encoder-spec "boolean?" fast-start?))
  (make-encoder-spec codec pixel-format (immutable-hash-snapshot options)
                     audio-codec (immutable-hash-snapshot audio-options) fast-start?))

;; These names are intentionally closed.  A typo in a declaration must not
;; silently create a cache domain that execution never reads or writes.
(define cache-domain-names
  '(formula frames segments audio waveform source-program))

; cache-spec : ... -> cache-spec?
;;   Declares independent cache domains and their persistent reuse policy.
(define (cache-spec #:root [root ".animate-cache"]
                    #:policy [policy 'read-write]
                    #:max-bytes [max-bytes (* 1024 1024 1024)]
                    #:domains [domains '(formula frames segments audio waveform source-program)])
  (unless (path-string? root)
    (raise-argument-error 'cache-spec "path-string?" root))
  (unless (memq policy '(off read-only read-write refresh))
    (raise-argument-error
     'cache-spec "'off, 'read-only, 'read-write, or 'refresh" policy))
  (unless (exact-nonnegative-integer? max-bytes)
    (raise-argument-error 'cache-spec "exact-nonnegative-integer?" max-bytes))
  (unless (and (list? domains)
               (andmap (lambda (domain) (memq domain cache-domain-names)) domains)
               (null? (duplicate-values domains)))
    (raise-arguments-error
     'cache-spec
     "a duplicate-free list of known cache domains"
     "domains" domains
     "known-domains" cache-domain-names))
  (make-cache-spec root policy max-bytes (append domains '())))

; project-asset : path-string? [#:role symbol?] [#:metadata hash?] -> project-asset?
;;   Declares a readable visual, audio, formula, or author-defined project asset.
(define (project-asset path #:role [role 'visual] #:metadata [metadata #hasheq()])
  (unless (path-string? path)
    (raise-argument-error 'project-asset "path-string?" path))
  (check-symbol 'project-asset role)
  (unless (hash? metadata)
    (raise-argument-error 'project-asset "hash?" metadata))
  (make-project-asset path role (immutable-hash-snapshot metadata)))

(define (project-target-all)
  (project-target 'all #f #f #f))

(define (project-target-section name)
  (check-symbol 'project-target-section name)
  (project-target 'section name #f #f))

(define (project-target-block name)
  (check-symbol 'project-target-block name)
  (project-target 'block name #f #f))

(define (project-target-range start end)
  (check-time-range 'project-target-range start end)
  (project-target 'range #f start end))

(define (project-target-frame frame-index)
  (unless (exact-nonnegative-integer? frame-index)
    (raise-argument-error
     'project-target-frame "exact-nonnegative-integer?" frame-index))
  (project-target 'frame frame-index #f #f))


;;;
;;; Pure Normalization and Planning
;;;

; normalize-project : animate-project? [#:directory path-string?] -> animate-project?
;;   Copies collection fields, resolves declared relative paths, and checks all
;; configuration-only cross-field constraints without reading the filesystem.
(define (normalize-project project #:directory [directory (current-directory)])
  (unless (animate-project? project)
    (raise-argument-error 'normalize-project "animate-project?" project))
  (unless (path-string? directory)
    (raise-argument-error 'normalize-project "path-string?" directory))
  (define base-directory
    (simplify-path (path->complete-path directory)))
  (define source
    (normalize-source (animate-project-source project) base-directory))
  (define output
    (normalize-output (animate-project-output project) base-directory))
  (define cache
    (normalize-cache (animate-project-cache project) base-directory))
  (define assets
    (normalize-assets (animate-project-assets project) base-directory))
  (check-normalized-cross-fields project source output assets)
  (make-animate-project
   (animate-project-id project)
   source
   (animate-project-render project)
   (animate-project-preview project)
   output
   (animate-project-encoder project)
   cache
   assets
   (hash-set (immutable-hash-snapshot (animate-project-metadata project))
             'project-directory
             base-directory)))

; plan-project : animate-project? [#:target project-target?]
;;                [#:directory path-string?] -> project-plan?
;;   Produces exact deterministic locations and configuration without I/O.
(define (plan-project project
                      #:target [target (project-target-all)]
                      #:directory [directory (current-directory)])
  (unless (project-target? target)
    (raise-argument-error 'plan-project "project-target?" target))
  (define normalized
    (normalize-project project #:directory directory))
  (define paths
    (make-project-path-plan normalized target))
  (project-plan normalized target
                (source-plan-for (animate-project-source normalized))
                paths
                (animate-project-render normalized)
                (animate-project-encoder normalized)
                (animate-project-cache normalized)))

(struct project-path-plan
  (primary temporary frames-root sections-root segments-root formula-root
           audio-root waveform-root subtitles frame-sequence
           temporary-frame-sequence manifest log)
  #:transparent)

;; project-path-plan contains exact potential locations. Planning creates none
;; of these paths; execution owns directory creation and atomic replacement.

; project-path-plan-cache-domain-root : project-path-plan? symbol? -> path?
;;   Returns an exact target-specific cache directory without creating it.  The
;;   source-program directory has no renderer-specific work yet, but reserving
;;   an inspectable location keeps all declared cache domains addressable by
;;   planning and by `raco animate cache clear --domain`.
(define (project-path-plan-cache-domain-root paths domain)
  (unless (project-path-plan? paths)
    (raise-argument-error
     'project-path-plan-cache-domain-root "project-path-plan?" paths))
  (unless (memq domain cache-domain-names)
    (raise-arguments-error
     'project-path-plan-cache-domain-root "a known cache domain"
     "domain" domain
     "known-domains" cache-domain-names))
  (case domain
    [(frames) (project-path-plan-frames-root paths)]
    [(segments) (project-path-plan-segments-root paths)]
    [(formula) (project-path-plan-formula-root paths)]
    [(audio) (project-path-plan-audio-root paths)]
    [(waveform) (project-path-plan-waveform-root paths)]
    [(source-program)
     (build-path (or (path-only (project-path-plan-formula-root paths))
                     (current-directory))
                 "source-program")]))

(struct project-plan
  (project target source-plan path-plan renderer-plan encoder-plan cache-plan)
  #:transparent)

;; project-plan is the target-independent normalization plus exact path choices.

(define (make-project-path-plan project target)
  (define output (animate-project-output project))
  (define cache (animate-project-cache project))
  (define root (output-spec-root output))
  (define cache-root (cache-spec-root cache))
  (define name (output-spec-name output))
  (define extension
    (case (output-spec-format output)
      [(mp4) ".mp4"]
      [(png-sequence) ""]
      [else (error 'make-project-path-plan "unreachable output format")]))
  (define target-name (project-target->path-fragment target))
  ;; The target is part of an output identity, not merely a cache identity.
  ;; Without this suffix, `render-project!` and `render-project-section!` can
  ;; silently compete for the same final name even though they contain
  ;; different frames.  The all-project target retains the author-supplied
  ;; canonical name; every narrower target is independently inspectable.
  (define output-name
    (if (eq? (project-target-kind target) 'all)
        name
        (format "~a-~a" name target-name)))
  (define cache-id
    (format "~a-~a" (symbol->string (animate-project-id project)) target-name))
  (define primary
    (build-path root (string-append output-name extension)))
  (define temporary
    (build-path root (format ".~a.partial~a" output-name extension)))
  ;; A PNG-sequence target always materializes cached frames at its primary
  ;; output. MP4 targets keep their primary as a video file and reserve an
  ;; independent optional frame-sequence export directory.
  (define frame-sequence
    (if (eq? (output-spec-format output) 'png-sequence)
        primary
        (build-path root (format "~a-frames" output-name))))
  (define temporary-frame-sequence
    (if (eq? (output-spec-format output) 'png-sequence)
        temporary
        (build-path root (format ".~a-frames.partial" output-name))))
  (project-path-plan
   primary
   temporary
   (build-path cache-root cache-id "frames")
   (build-path cache-root cache-id "sections")
   (build-path cache-root cache-id "segments")
   (build-path cache-root cache-id "formula")
   (build-path cache-root cache-id "audio")
   (build-path cache-root cache-id "waveform")
   (build-path cache-root cache-id "subtitles.srt")
   frame-sequence
   temporary-frame-sequence
   (build-path cache-root cache-id "manifest.rktd")
   (build-path cache-root cache-id "execution.log")))

(define (source-plan-for source)
  (cond
    [(module-binding-source? source)
     (hasheq 'kind 'module-binding
             'module-path (module-binding-source-module-path source)
             'binding (module-binding-source-binding source))]
    [(scene-source? source) (hasheq 'kind 'direct-scene)]
    [(timeline-source? source) (hasheq 'kind 'direct-timeline)]
    [(scene-program-source? source) (hasheq 'kind 'direct-program)]
    [else (error 'source-plan-for "unreachable source kind")]))


;;;
;;; Effectful Preparation and Checks
;;;

(struct project-tool-identities (doctor ffmpeg)
  #:transparent)

(struct prepared-project
  (plan source-value scene timeline program target-frame-indices tool-identities
        cache-identities diagnostics)
  #:transparent)

;; prepared-project is the non-rendering result of loading the source and
;; resolving a selected target. It never contains output files or frame bitmaps.

; prepare-project! : project-plan? -> prepared-project?
;;   Loads the declared source, resolves its target frame indices, and records
;; tool/cache identities without writing any artifact.
(define (prepare-project! plan)
  (unless (project-plan? plan)
    (raise-argument-error 'prepare-project! "project-plan?" plan))
  (define source-value
    (load-project-source (animate-project-source (project-plan-project plan))))
  (define-values (scene timeline program)
    (source-value->components source-value))
  (define target-indices
    (resolve-target-frame-indices
     (project-plan-target plan)
     scene timeline program
     (render-spec-fps (project-plan-renderer-plan plan))))
  (define doctor-report
    (collect-doctor-report))
  ;; Tool version probing belongs to effectful preparation rather than the
  ;; lightweight environment doctor.  A PNG-only project does not depend on an
  ;; encoder and therefore need not launch ffmpeg at all.
  (define tools
    (project-tool-identities
     doctor-report
     (and (eq? (output-spec-format
                (animate-project-output (project-plan-project plan)))
               'mp4)
          (ffmpeg-tool-identity doctor-report))))
  (define cache-info
    (cacheability-for-source (animate-project-source (project-plan-project plan))))
  (prepared-project plan source-value scene timeline program target-indices
                    tools cache-info
                    (hasheq 'release-version animate-version
                            'release-stage animate-stage
                            'frame-count (length target-indices))))

;; renderer3d-capability-set comes from the backend-neutral spatial renderer
;; protocol.  Keeping project validation on that exact type prevents a project
;; declaration from claiming a facility which its selected renderer cannot
;; report through `renderer3d-capabilities`.

(struct renderer-capabilities
  (paths text gradients clipping secondary-camera visible-ink-bounds perspective depth-buffer three-dimensional)
  #:transparent)

;; renderer-capabilities lets validation ask for semantic facilities rather
;; than inspect a concrete Pict renderer class.  `three-dimensional` is the
;; nested renderer3d-capability-set declaration above.

(struct project-check-report (ok? requirements warnings failures tools)
  #:transparent)

;; project-check-report separates missing required capabilities from optional
;; warnings, making a headless project diagnosis usable in a CLI or preview.

; check-project! : project-plan? -> project-check-report?
;;   Prepares a project, checks required local capabilities, and writes nothing.
(define (check-project! plan)
  (unless (project-plan? plan)
    (raise-argument-error 'check-project! "project-plan?" plan))
  (define preparation
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (project-check-report #f '() '()
                                             (list (exn-message error)) #f))])
      (prepare-project! plan)))
  (if (project-check-report? preparation)
      preparation
      (let* ([project (project-plan-project plan)]
             [doctor (project-tool-identities-doctor
                      (prepared-project-tool-identities preparation))]
             [requirements
              (append
               (if (eq? (output-spec-format (animate-project-output project)) 'mp4)
                   '(ffmpeg)
                   '()))]
             [missing
              (for/list ([requirement (in-list requirements)]
                         #:unless (doctor-has-capability? doctor requirement))
                (format "required capability is unavailable: ~a" requirement))]
             [asset-failures
              (for/list ([asset (in-list (animate-project-assets project))]
                         #:unless (readable-file? (project-asset-path asset)))
                (format "declared asset is not a readable file: ~a"
                        (project-asset-path asset)))]
             [encoder-failures
              (if (and (eq? (output-spec-format (animate-project-output project))
                            'mp4)
                       (doctor-has-capability? doctor 'ffmpeg))
                  (let* ([encoder (animate-project-encoder project)]
                         [ffmpeg (doctor-capability-detail
                                  (doctor-report-ffmpeg doctor))])
                    (append
                     (if (ffmpeg-encoder-available?
                          ffmpeg (encoder-spec-codec encoder))
                         '()
                         (list
                          (format "FFmpeg does not provide requested video encoder: ~a"
                                  (encoder-spec-codec encoder))))
                     (if (ffmpeg-pixel-format-available?
                          ffmpeg (encoder-spec-pixel-format encoder))
                         '()
                         (list
                          (format "FFmpeg does not provide requested pixel format: ~a"
                                  (encoder-spec-pixel-format encoder))))))
                  '())]
             ;; A project check must not create directories or probe by writing
             ;; a temporary file: preparation is deliberately diagnostic-only.
             ;; Instead inspect the target directory, or the nearest existing
             ;; ancestor when the declared root will be created during render.
             [output-failures
              (if (directory-writable-or-creatable?
                   (output-spec-root (animate-project-output project)))
                  '()
                  (list
                   (format "output root is not writable or creatable: ~a"
                           (output-spec-root (animate-project-output project)))))]
             [cache-failures
              (if (directory-writable-or-creatable?
                   (cache-spec-root (animate-project-cache project)))
                  '()
                  (list
                   (format "cache root is not writable or creatable: ~a"
                           (cache-spec-root (animate-project-cache project)))))]
             [warnings
              (append
               (if (eq? (cacheability-mode
                          (prepared-project-cache-identities preparation))
                         'persistent)
                   '()
                   (cacheability-reasons
                    (prepared-project-cache-identities preparation)))
               ;; FFplay is an optional convenience backend.  A project can
               ;; still prepare its reusable WAV proxy and show a waveform
               ;; without it, so rejecting a visual preview here would make
               ;; an optional monitor incorrectly part of project validity.
               (if (and (preview-spec-audio? (animate-project-preview project))
                        (not (doctor-has-capability? doctor 'ffplay)))
                   '("ffplay is unavailable; audio playback is disabled but the visual preview remains usable")
                   '()))]
             [failures (append missing asset-failures encoder-failures
                               output-failures cache-failures)])
        (project-check-report (null? failures) requirements warnings failures doctor))))


;;;
;;; Serializable Inspection
;;;

; project-plan->datum : project-plan? -> immutable-hash?
;;   Produces an output-free, serializable view suitable for a CLI plan command.
(define (project-plan->datum plan)
  (unless (project-plan? plan)
    (raise-argument-error 'project-plan->datum "project-plan?" plan))
  (define paths (project-plan-path-plan plan))
  (hasheq
   'release (hasheq 'version animate-version 'stage animate-stage)
   'id (animate-project-id (project-plan-project plan))
   'target (project-target->datum (project-plan-target plan))
   'source (project-plan-source-plan plan)
   'paths
   (hasheq 'primary (project-path-plan-primary paths)
           'temporary (project-path-plan-temporary paths)
           'frame-sequence (project-path-plan-frame-sequence paths)
           'temporary-frame-sequence
           (project-path-plan-temporary-frame-sequence paths)
           'frames-root (project-path-plan-frames-root paths)
           'sections-root (project-path-plan-sections-root paths)
           'segments-root (project-path-plan-segments-root paths)
           'formula-root (project-path-plan-formula-root paths)
           'audio-root (project-path-plan-audio-root paths)
           'waveform-root (project-path-plan-waveform-root paths)
           'source-program-root
           (project-path-plan-cache-domain-root paths 'source-program)
           'manifest (project-path-plan-manifest paths))))

; prepared-project->datum : prepared-project? -> immutable-hash?
;;   Produces source/target diagnostics without serializing arbitrary Scene data.
(define (prepared-project->datum prepared)
  (unless (prepared-project? prepared)
    (raise-argument-error 'prepared-project->datum "prepared-project?" prepared))
  (hash-set
   (project-plan->datum (prepared-project-plan prepared))
   'prepared
   (hasheq 'frame-indices (prepared-project-target-frame-indices prepared)
           'cacheability (cacheability->datum
                          (prepared-project-cache-identities prepared))
           'diagnostics (prepared-project-diagnostics prepared))))

; write-project-plan : project-plan? path-string? -> path-string?
;;   Writes a single readable datum for an external tool or release artifact.
(define (write-project-plan plan output-file)
  (unless (path-string? output-file)
    (raise-argument-error 'write-project-plan "path-string?" output-file))
  (call-with-output-file
   output-file
   (lambda (output)
     (write (project-plan->datum plan) output)
     (newline output))
   #:exists 'truncate/replace)
  output-file)


;;;
;;; Internal Normalization and Source Loading
;;;

;; Project declarations must snapshot option and metadata maps without
;; changing their contents. `hash-copy-clear` preserves a table's kind but
;; intentionally drops every entry, which is appropriate for an accumulator
;; but disastrous for an encoder profile such as #hasheq((crf . "18")).
;; Preserve the caller's equality discipline while producing an immutable map
;; that cannot later be mutated through the original declaration.
(define (immutable-hash-snapshot value)
  (cond
    [(hash-eq? value)
     (for/hasheq ([(key entry) (in-hash value)])
       (values key entry))]
    [(hash-eqv? value)
     (for/hasheqv ([(key entry) (in-hash value)])
       (values key entry))]
    [else
     (for/hash ([(key entry) (in-hash value)])
       (values key entry))]))

(define (normalize-source source base-directory)
  (cond
    [(module-binding-source? source)
     (make-module-binding-source
      (normalize-path (module-binding-source-module-path source) base-directory)
      (module-binding-source-binding source))]
    [else source]))

(define (normalize-output output base-directory)
  (make-output-spec
   (normalize-path (output-spec-root output) base-directory)
   (output-spec-name output)
   (output-spec-format output)
   (output-spec-write-sections? output)
   (output-spec-write-frame-sequence? output)
   (output-spec-overwrite-policy output)
   (output-spec-open-after? output)))

(define (normalize-cache cache base-directory)
  (make-cache-spec
   (normalize-path (cache-spec-root cache) base-directory)
   (cache-spec-policy cache)
   (cache-spec-max-bytes cache)
   (cache-spec-domains cache)))

(define (normalize-assets assets base-directory)
  (define normalized
    (for/list ([asset (in-list assets)])
      (make-project-asset
       (normalize-path (project-asset-path asset) base-directory)
       (project-asset-role asset)
       (project-asset-metadata asset))))
  (define duplicates
    (duplicate-values (map project-asset-path normalized)))
  (when (pair? duplicates)
    (raise-arguments-error
     'normalize-project
     "project asset paths must be unique"
     "duplicate-path" (car duplicates)))
  (append normalized '()))

(define (normalize-path path-value base-directory)
  (simplify-path
   (path->complete-path path-value base-directory)))

(define (check-normalized-cross-fields project source output assets)
  (when (and (eq? (output-spec-format output) 'png-sequence)
             (not (eq? (encoder-spec-codec (animate-project-encoder project)) 'none)))
    ;; A PNG sequence never invokes an encoder; force the declaration to say so.
    (raise-arguments-error
     'normalize-project
     "PNG sequence output requires encoder codec 'none"
     "output-format" (output-spec-format output)
     "encoder-codec" (encoder-spec-codec (animate-project-encoder project))))
  (when (and (preview-spec-audio? (animate-project-preview project))
             (not (or (timeline-source? source)
                      (module-binding-source? source)
                      (ormap (lambda (asset)
                               (eq? (project-asset-role asset) 'audio))
                             assets))))
    (raise-arguments-error
     'normalize-project
     "audio preview requires an authored timeline, module source, or audio asset"
     "preview-audio?" #t)))

(define (load-project-source source)
  (cond
    [(module-binding-source? source)
     (dynamic-require (module-binding-source-module-path source)
                      (module-binding-source-binding source))]
    [(scene-source? source) (scene-source-scene source)]
    [(timeline-source? source) (timeline-source-timeline source)]
    [(scene-program-source? source) (scene-program-source-program source)]
    [else (error 'load-project-source "unreachable source kind")]))

(define (source-value->components source-value)
  (cond
    [(scene? source-value)
     (values source-value #f #f)]
    [(authored-timeline? source-value)
     (values (authored-timeline-scene source-value) source-value #f)]
    [(scene-program? source-value)
     (define compiled (compile-scene-program source-value))
     (values (compiled-scene-program-scene compiled) #f source-value)]
    [(compiled-scene-program? source-value)
     (values (compiled-scene-program-scene source-value)
             #f
             (compiled-scene-program-program source-value))]
    [else
     (raise-arguments-error
      'prepare-project!
      "a scene?, authored-timeline?, scene-program?, or compiled-scene-program? binding"
      "source-value" source-value)]))

(define (resolve-target-frame-indices target scene timeline program fps)
  (define total-frame-count (scene-frame-count scene #:fps fps))
  (case (project-target-kind target)
    [(all) (build-list total-frame-count values)]
    [(section)
     (unless timeline
       (raise-arguments-error
        'prepare-project!
        "an authored timeline for a section target"
        "target" target))
     (timeline-section-frame-indices timeline (project-target-value target) #:fps fps)]
    [(block)
     (unless program
       (raise-arguments-error
        'prepare-project!
        "a scene program for a block target"
        "target" target))
     (define compiled (compile-scene-program program))
     (define start (compiled-program-block-start compiled (project-target-value target)))
     (define end (compiled-program-block-end compiled (project-target-value target)))
     (frame-indices-for-range start end fps total-frame-count)]
    [(range)
     (frame-indices-for-range (project-target-start target)
                              (project-target-end target)
                              fps total-frame-count)]
    [(frame)
     (define frame-index (project-target-value target))
     (unless (< frame-index total-frame-count)
       (raise-arguments-error
        'prepare-project!
        "a frame index within the source scene"
        "frame-index" frame-index
        "frame-count" total-frame-count))
     (list frame-index)]
    [else (error 'resolve-target-frame-indices "unreachable target kind")]))

(define (frame-indices-for-range start end fps frame-count)
  (for/list ([index (in-range (min frame-count (ceiling->exact (* end fps))))]
             #:when (>= index (ceiling->exact (* start fps))))
    index))

(define (cacheability-for-source source)
  (if (module-binding-source? source)
      (cacheability 'persistent '() #f)
      (cacheability 'memory-only
                    '("direct values may contain opaque procedures; declare a module binding or explicit cache key for persistent reuse")
                    #f)))

(define (doctor-has-capability? doctor requirement)
  (case requirement
    [(ffmpeg) (doctor-capability-available? (doctor-report-ffmpeg doctor))]
    [(ffplay) (doctor-capability-available? (doctor-report-ffplay doctor))]
    [else #t]))

;; file-or-directory-permissions is an advisory, side-effect-free capability
;; check.  It cannot see every ACL or network-volume restriction, so execution
;; still reports an ordinary file-system error if the environment changes after
;; checking.  Its job is to reject the common and otherwise surprising cases:
;; a file used as a directory root, a read-only existing root, or an ancestor
;; from which no declared root can be created.
(define (readable-file? path)
  (and (file-exists? path)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (member 'read (file-or-directory-permissions path)))))

(define (directory-writable-or-creatable? directory)
  (cond
    [(file-exists? directory) #f]
    [(directory-exists? directory)
     (directory-writable? directory)]
    [else
     (define ancestor (nearest-existing-ancestor directory))
     (and ancestor (directory-writable? ancestor))]))

(define (nearest-existing-ancestor path)
  (let loop ([candidate (path->complete-path path)])
    (cond
      [(or (file-exists? candidate) (directory-exists? candidate)) candidate]
      [else
       (define parent (path-only candidate))
       (and parent
            (not (equal? parent candidate))
            (loop parent))])))

(define (directory-writable? directory)
  (and (directory-exists? directory)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (define permissions (file-or-directory-permissions directory))
         ;; Creating an output/cache child needs both directory write and
         ;; traversal permission.  The latter matters for a non-empty root.
         (and (member 'write permissions)
              (member 'execute permissions)))))

(define (project-target->path-fragment target)
  (case (project-target-kind target)
    [(all) "all"]
    [(section block) (safe-path-fragment (symbol->string (project-target-value target)))]
    [(range) (safe-path-fragment
              (format "range-~a-~a" (project-target-start target)
                      (project-target-end target)))]
    [(frame) (format "frame-~a" (project-target-value target))]
    [else (error 'project-target->path-fragment "unreachable target kind")]))

;; Encode every non-portable character instead of merely replacing it.  That
;; gives output paths a deterministic one-to-one relationship with authored
;; section/block names: `a/b` and `a?b` cannot collide after normalization.
(define (safe-path-fragment text)
  (define encoded
    (for/list ([character (in-string text)])
      (if (or (ascii-alphanumeric? character)
              (memq character '(#\- #\_ #\.)))
          (string character)
          (format "_~x_" (char->integer character)))))
  (if (null? encoded) "empty" (apply string-append encoded)))

(define (ascii-alphanumeric? character)
  (or (and (char<=? #\a character) (char<=? character #\z))
      (and (char<=? #\A character) (char<=? character #\Z))
      (and (char<=? #\0 character) (char<=? character #\9))))

(define (project-target->datum target)
  (hasheq 'kind (project-target-kind target)
          'value (project-target-value target)
          'start (project-target-start target)
          'end (project-target-end target)))

(define (cacheability->datum value)
  (hasheq 'mode (cacheability-mode value)
          'reasons (cacheability-reasons value)
          'explicit-key (cacheability-explicit-key value)))

(define (duplicate-values values)
  (let loop ([remaining values] [seen (hash)] [duplicates '()])
    (cond
      [(null? remaining) (reverse duplicates)]
      [(hash-has-key? seen (car remaining))
       (loop (cdr remaining) seen (cons (car remaining) duplicates))]
      [else
       (loop (cdr remaining) (hash-set seen (car remaining) #t) duplicates)])))

(define (ceiling->exact value)
  (define rounded (ceiling value))
  (if (exact-integer? rounded) rounded (inexact->exact rounded)))


;;;
;;; Validation
;;;

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-source who value)
  (unless (or (module-binding-source? value)
              (scene-source? value)
              (timeline-source? value)
              (scene-program-source? value))
    (raise-argument-error
     who
     "module-binding-source?, scene-source?, timeline-source?, or scene-program-source?"
     value)))

(define (check-specification who value predicate)
  (unless (predicate value)
    (raise-arguments-error who "a project specification" "value" value)))

(define (check-positive-integer who field value)
  (unless (exact-positive-integer? value)
    (raise-arguments-error who "exact-positive-integer?" field value)))

(define (check-time-range who start end)
  (unless (and (finite-real? start) (finite-real? end)
               (<= 0 start) (< start end))
    (raise-arguments-error who "a nonnegative half-open time range"
                           "start" start "end" end)))
