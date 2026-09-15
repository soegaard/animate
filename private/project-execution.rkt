#lang racket/base

;;;
;;; Project Render Execution
;;;

;; Executes an already prepared immutable project through the effectful PNG and
;; encoder adapters. Declaration normalization and source preparation remain in
;; animate/project, keeping this module out of headless planning workflows.


;;;
;;; Imports and Exports
;;;

(require racket/file
         racket/format
         racket/list
         racket/path
         racket/runtime-path
         racket/system
         file/sha1
         "../main.rkt"
         "../authoring.rkt"
         (only-in "../colors.rkt"
                  color-theme-fingerprint
                  theme->datum)
         (only-in "../typography.rkt"
                  typography-theme-fingerprint
                  typography-theme->datum)
         "../project.rkt"
         "../version.rkt"
         "3d/label-layout3d.rkt"
         "3d/label-layout-preparation3d.rkt"
         "3d/renderer3d.rkt"
         "process-frame-executor.rkt"
         "png-renderer.rkt"
         "render-frame-job.rkt"
         "render-job-plan.rkt"
         "render-preparation-lease.rkt"
         "render-preparation-manifest.rkt"
         "render-color-context.rkt"
         "render-typography-context.rkt"
         "render-worker-protocol.rkt"
         "section-renderer.rkt"
         "doctor.rkt"
         "video-assembly.rkt"
         "video-encoder.rkt")

(provide render-project!
         render-project-section!
         render-project-block!
         render-project-range!
         render-project-frame!
         execute-prepared-project!
         current-project-artifact-opener
         (struct-out project-frame-execution-diagnostics)
         project-frame-execution-diagnostics->datum
         (struct-out project-execution-report))

;; This is a runtime path rather than a `require`: ordinary project rendering
;; remains able to run on the software backend without loading racket/gui or
;; the optional `opengl` package.  The selected backend is loaded only in the
;; dynamic extent that owns an explicit OpenGL render.
(define-runtime-path opengl-renderer-module "../3d/opengl.rkt")


;;;
;;; Immutable Reports
;;;

(struct project-execution-report
  (plan artifact-paths elapsed-milliseconds rendered-frames reused-frames
        encoded-segments reused-segments audio-rebuilt? cache-events tools
        warnings diagnostics)
  #:transparent)

;; project-execution-report is deliberately serializable except for the
;; renderer diagnostics payload. It describes *what execution did*, instead of
;; exposing an implementation-owned prepared value as the primary result.

(struct project-frame-execution-diagnostics
  (mode requested-worker-capacity workers-started workers-completing
        requested-frame-count rendered-frame-count reused-frame-count
        source-frame-indices output-frame-indices elapsed-milliseconds paths
        native-diagnostics subprocess-report work-accounting)
  #:transparent)

;; project-frame-execution-diagnostics records the one frame execution path
;; selected for a project target.
;;  - mode is the already-resolved worker policy, never an inferred label.
;;  - requested-worker-capacity is authored capacity; started/completing are
;;    parent-observed counts. `workers-completing` is #f when the native PNG
;;    renderer has no corresponding per-worker completion identity.
;;  - source-frame-indices/output-frame-indices preserve target-to-local slots.
;;  - native-diagnostics/subprocess-report retain the implementation-specific
;;    reports without forcing ordinary callers to choose an execution backend.
;;  - work-accounting is an immutable, canonical stage/reuse breakdown that
;;    never counts materialized aliases as newly rasterized frames.

;; The opener is a render-side effect, deliberately absent from animate/project
;; and from immutable planning. Parameterizing it gives headless callers and
;; tests a way to decide how completed files should be presented without
;; changing the artifact's semantics.
(define current-project-artifact-opener
  (make-parameter
   (lambda (artifact) (default-project-artifact-opener artifact))
   (lambda (opener)
     (unless (procedure? opener)
       (raise-argument-error 'current-project-artifact-opener "procedure?" opener))
     opener)))

; project-work-accounting : prepared-project? ... -> immutable-hash?
;;   Produces canonical preparation, integrity, cache, reuse, and raster counts.
(define (project-work-accounting prepared
                                 #:persistent-cache-hits [persistent-cache-hits 0]
                                 #:aliases [aliases 0]
                                 #:representatives [representatives 0]
                                 #:rasterized [rasterized 0]
                                 #:materialized [materialized 0]
                                 #:input-verification-events
                                 [input-verification-events 0]
                                 #:input-verification-failures
                                 [input-verification-failures '()])
  (define preparation (prepared-project-source-preparation prepared))
  (define input-manifest (prepared-project-input-manifest prepared))
  (hasheq
   'source-preparation-performed? (and preparation #t)
   'source-preparation-reused? #f
   'preparation-elapsed-milliseconds
   (prepared-project-preparation-elapsed-milliseconds prepared)
   'preparation-artifacts-created
   (if preparation (length (source-preparation-artifacts preparation)) 0)
   'preparation-artifacts-reused 0
   'tracked-input-count
   (if input-manifest (length (hash-ref input-manifest 'entries)) 0)
   'input-manifest-identity
   (and input-manifest (render-input-manifest-identity input-manifest))
   'input-verification-events input-verification-events
   'input-verification-failures input-verification-failures
   'persistent-frame-cache-hits persistent-cache-hits
   'frame-reuse-aliases aliases
   'representative-raster-jobs representatives
   'frames-rasterized rasterized
   'materialized-output-frames materialized))


;;;
;;; Author-Facing Execution
;;;

; render-project! : animate-project? [#:target project-target?]
;;                   [#:directory path-string?] -> project-execution-report?
;;   Plans, prepares, and renders one declared project target.
(define (render-project! project
                         #:target [target (project-target-all)]
                         #:directory [directory (current-directory)]
                         #:prepared-label-layout [prepared-label-layout #f])
  (execute-prepared-project!
   (prepare-project!
    (plan-project project #:target target #:directory directory))
   #:prepared-label-layout prepared-label-layout))

; render-project-section! : animate-project? symbol? ... -> project-execution-report?
;;   Renders one named authored-timeline section through the project plan.
(define (render-project-section! project section-name
                                 #:directory [directory (current-directory)]
                                 #:prepared-label-layout [prepared-label-layout #f])
  (render-project! project
                   #:target (project-target-section section-name)
                   #:directory directory
                   #:prepared-label-layout prepared-label-layout))

; render-project-block! : animate-project? symbol? ... -> project-execution-report?
;;   Renders one named source-program block through the project plan.
(define (render-project-block! project block-name
                               #:directory [directory (current-directory)]
                               #:prepared-label-layout [prepared-label-layout #f])
  (render-project! project
                   #:target (project-target-block block-name)
                   #:directory directory
                   #:prepared-label-layout prepared-label-layout))

; render-project-range! : animate-project? real? real? ... -> project-execution-report?
;;   Renders a half-open scene-time range through the project plan.
(define (render-project-range! project start end
                               #:directory [directory (current-directory)]
                               #:prepared-label-layout [prepared-label-layout #f])
  (render-project! project
                   #:target (project-target-range start end)
                   #:directory directory
                   #:prepared-label-layout prepared-label-layout))

; render-project-frame! : animate-project? exact-nonnegative-integer? ...
;;                 -> project-execution-report?
;;   Renders one zero-based source frame through the project plan.
(define (render-project-frame! project frame-index
                               #:directory [directory (current-directory)]
                               #:prepared-label-layout [prepared-label-layout #f])
  (render-project! project
                   #:target (project-target-frame frame-index)
                   #:directory directory
                   #:prepared-label-layout prepared-label-layout))

; execute-prepared-project! : prepared-project?
;;                            [#:protected-frame-roots (listof path?)]
;;                            [#:open-after? boolean?]
;;                            -> project-execution-report?
;;   Lazily creates only the directories required by a prepared target, renders
;; locally numbered PNGs, and atomically installs the final video when needed.
(define (execute-prepared-project! prepared
                                   #:protected-frame-roots [protected-frame-roots '()]
                                   #:open-after? [open-after? #t]
                                   #:prepared-label-layout [prepared-label-layout #f])
  (unless (prepared-project? prepared)
    (raise-argument-error
     'execute-prepared-project! "prepared-project?" prepared))
  (unless (and (list? protected-frame-roots)
               (andmap path? protected-frame-roots))
    (raise-argument-error
     'execute-prepared-project! "(listof path?)" protected-frame-roots))
  (unless (boolean? open-after?)
    (raise-argument-error 'execute-prepared-project! "boolean?" open-after?))
  (unless (or (not prepared-label-layout)
              (prepared-label-layout3d? prepared-label-layout))
    (raise-argument-error
     'execute-prepared-project!
     "#f or prepared-label-layout3d? as #:prepared-label-layout"
     prepared-label-layout))
  (define started (current-inexact-monotonic-milliseconds))
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define output (animate-project-output project))
  (define render (animate-project-render project))
  (define paths (project-plan-path-plan plan))
  (define frame-root (project-path-plan-frames-root paths))
  (define primary (project-path-plan-primary paths))
  (when (and (output-spec-write-sections? output)
             (eq? (project-target-kind (project-plan-target plan)) 'all)
             (not (prepared-project-timeline prepared)))
    (raise-arguments-error
     'execute-prepared-project!
     "an authored timeline when #:write-sections? is requested"
     "source" (animate-project-source project)
     "write-sections?" #t))
  ;; Reject a request that the subprocess protocol cannot faithfully execute before creating a
  ;; frame cache directory, touching an old PNG, or starting a child process.
  ;; The policy was chosen during planning; this is the execution-side check
  ;; for the narrower final-frame protocol contract.
  (check-prepared-project-subprocess-capability!
   prepared prepared-label-layout)
  (check-overwrite-policy output primary)
  (define export-frames?
    (or (eq? (output-spec-format output) 'png-sequence)
        (output-spec-write-frame-sequence? output)))
  (when export-frames?
    (check-overwrite-policy output (project-path-plan-frame-sequence paths)))
  (make-directory* frame-root)
  (define-values (diagnostics reused-frames?)
    (render-or-reuse-prepared-frames prepared frame-root prepared-label-layout))
  (define frame-paths
    (project-frame-execution-diagnostics-paths diagnostics))
  (define-values (artifact audio-rebuilt? subtitle-path
                  encoded-segments reused-segments segment-cache-event)
    (case (output-spec-format output)
      [(png-sequence)
       (values primary #f #f 0 0
               (hasheq 'domain 'segments 'event 'not-applicable))]
      [(mp4)
       (install-project-mp4! prepared frame-root primary prepared-label-layout)]
      [else (error 'execute-prepared-project! "unreachable output format")]))
  (define exported-frame-sequence
    (and export-frames?
         (install-project-frame-sequence! prepared frame-root)))
  (define section-artifacts
    (if (and (output-spec-write-sections? output)
             (eq? (project-target-kind (project-plan-target plan)) 'all))
        (render-declared-project-sections!
         prepared
         #:protected-frame-roots (cons frame-root protected-frame-roots)
         #:prepared-label-layout prepared-label-layout)
        '()))
  (define open-warning
    (and open-after?
         (output-spec-open-after? output)
         (not ((current-project-artifact-opener) artifact))
         (format "could not open completed output artifact: ~a" artifact)))
  ;; Work for the requested target remains available through this report, even
  ;; when its footprint alone exceeds the persistent-cache budget.  Only
  ;; completed, inactive target directories are candidates for eviction.
  (define cache-budget-event
    (enforce-project-cache-budget!
     prepared frame-root #:protected-frame-roots protected-frame-roots))
  (define report
    (project-execution-report
     plan
    (hasheq 'primary artifact
             'frames frame-paths
             'frame-sequence exported-frame-sequence
             'sections section-artifacts
             'manifest (project-path-plan-manifest paths)
             'subtitles subtitle-path)
     (- (current-inexact-monotonic-milliseconds) started)
     (if reused-frames? 0 (length frame-paths))
     (if reused-frames? (length frame-paths) 0)
     encoded-segments reused-segments
     audio-rebuilt?
     (list (hasheq 'domain 'frames
                   'event (if reused-frames? 'reused 'rendered)
                   'count (length frame-paths))
           segment-cache-event
           cache-budget-event)
     (prepared-project-tool-identities prepared)
     (append (cacheability-reasons (prepared-project-cache-identities prepared))
             (if open-warning (list open-warning) '()))
     diagnostics))
  (write-project-execution-manifest! report (project-path-plan-manifest paths))
  report)

;; A complete authored project may request independently consumable outputs for
;; every named section. Each section is prepared with its own target (so frame
;; ranges, audio cues, subtitles, and cache identities retain their normal
;; semantics), but retains the enclosing all-target cache while it runs. This
;; prevents a small cache budget from invalidating the report that initiated the
;; section export.
(define (render-declared-project-sections! prepared
                                            #:protected-frame-roots protected-frame-roots
                                            #:prepared-label-layout [prepared-label-layout #f])
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define timeline (prepared-project-timeline prepared))
  (for/list ([name (in-list (timeline-section-names timeline))])
    (define section-plan
      (plan-project project #:target (project-target-section name)))
    (define section-report
      (execute-prepared-project!
       (prepare-project! section-plan)
       #:protected-frame-roots protected-frame-roots
       #:prepared-label-layout prepared-label-layout
       ;; One request to render an all-target project should open its primary
       ;; result once, not launch every independently written section.
       #:open-after? #f))
    (hasheq 'name name
            'artifact-paths (project-execution-report-artifact-paths section-report))))


;;;
;;; Rendering and Atomic Output
;;;

(define frame-cache-file-name ".animate-frame-cache.rktd")
(define segment-cache-file-name ".animate-segment-cache.rktd")
(define segment-cache-video-name "visual.mp4")

;; The project cache is organized as CACHE-ROOT / PROJECT-TARGET / DOMAIN.
;; A project result exposes the current target's frame paths, so capacity
;; enforcement must never delete that directory before the caller has consumed
;; the report. Completed sibling target directories are independent reusable
;; entries and can be evicted in oldest-modification-time order. A single
;; active target may exceed the cap; that is safer than returning dead paths.
(define (enforce-project-cache-budget! prepared active-frame-root
                                       #:protected-frame-roots [protected-frame-roots '()])
  (define project (project-plan-project (prepared-project-plan prepared)))
  (define cache (animate-project-cache project))
  (define policy (cache-spec-policy cache))
  (define maximum (cache-spec-max-bytes cache))
  (define root (cache-spec-root cache))
  ;; `path-only` produces a directory-form path while `directory-list` entries
  ;; are ordinary paths. Compare directory-form paths so active targets (and a
  ;; parent target producing declared section outputs) are never mistaken for
  ;; siblings merely because of a trailing separator.
  (define protected-roots
    (for/list ([frame-root (in-list (cons active-frame-root
                                          protected-frame-roots))])
      (path-only frame-root)))
  (cond
    [(not (memq policy '(read-write refresh)))
     (hasheq 'domain 'cache 'event 'not-written 'maximum-bytes maximum)]
    [(not (directory-exists? root))
     (hasheq 'domain 'cache 'event 'empty 'maximum-bytes maximum)]
    [else
     (define before (cache-directory-bytes root))
     (define candidates
       (sort
        (for/list ([candidate (in-list (directory-list root #:build? #t))]
                   #:when (and (directory-exists? candidate)
                               (not (member (path->directory-path candidate)
                                            protected-roots
                                            equal?))))
          candidate)
        <
        #:key cache-path-modification-seconds))
     (define-values (removed remaining)
       (let loop ([remaining-bytes before]
                  [pending candidates]
                  [removed '()])
         (cond
           [(or (<= remaining-bytes maximum) (null? pending))
            (values (reverse removed) remaining-bytes)]
           [else
            (define candidate (car pending))
            (define bytes (cache-directory-bytes candidate))
            ;; Cache roots are project-owned paths derived by plan-project;
            ;; this is a cache-maintenance effect, never an output deletion.
            (delete-directory/files candidate)
            (loop (max 0 (- remaining-bytes bytes))
                  (cdr pending)
                  (cons (hasheq 'path candidate 'bytes bytes) removed))])))
     (hasheq 'domain 'cache
             'event (if (null? removed) 'within-budget 'evicted)
             'maximum-bytes maximum
             'bytes-before before
             'bytes-after remaining
             'evicted removed)]))

(define (cache-path-modification-seconds path)
  (with-handlers ([exn:fail? (lambda (_error) +inf.0)])
    (file-or-directory-modify-seconds path)))

(define (cache-directory-bytes path)
  (with-handlers ([exn:fail? (lambda (_error) 0)])
    (cond
      [(file-exists? path) (file-size path)]
      [(directory-exists? path)
       (for/sum ([child (in-list (directory-list path #:build? #t))])
         (cache-directory-bytes child))]
      [else 0])))

;; Frame cache validity is intentionally conservative. Only a module-backed
;; source gets persistent reuse, and the key records the module's content hash,
;; frame grid, effective camera, renderer configuration, declared asset hashes,
;; and release identity. Encoder settings deliberately do not participate:
;; changing CRF or a preset must rebuild an encoded segment without needlessly
;; rasterizing the same PNG frames again. Direct scene values remain memory-only
;; because an arbitrary closure cannot be fingerprinted honestly.
(define (render-or-reuse-prepared-frames prepared frame-root prepared-label-layout)
  (define project (project-plan-project (prepared-project-plan prepared)))
  (define cache (animate-project-cache project))
  (define policy (cache-spec-policy cache))
  (define worker-policy (prepared-project-worker-policy prepared))
  (define source-frame-indices (prepared-project-target-frame-indices prepared))
  (define output-frame-indices
    (build-list (length source-frame-indices) values))
  (define key
    (and (cache-domain-enabled? cache 'frames)
         (project-frame-cache-key prepared prepared-label-layout)))
  (define expected-paths
    (project-local-frame-paths frame-root
                               (length (prepared-project-target-frame-indices prepared))))
  (define cache-path (build-path frame-root frame-cache-file-name))
  (define persistent-hit-output-indices
    (if (and key (memq policy '(read-only read-write)))
        (frame-cache-hit-output-indices cache-path key expected-paths)
        '()))
  (cond
    [(= (length persistent-hit-output-indices) (length expected-paths))
     (define native-diagnostics
       (render-diagnostics expected-paths (length expected-paths) 0 0 '()
                           0 0 0 animate-version animate-stage))
     ;; A valid persistent hit must not allocate an executor, even when the
     ;; newly requested mode would otherwise select subprocess workers.
     (values
      (project-frame-execution-diagnostics
       (render-worker-policy-resolved-mode worker-policy)
       (render-spec-workers (animate-project-render project))
       0 0
       (length expected-paths) 0 (length expected-paths)
       source-frame-indices output-frame-indices 0 expected-paths
       native-diagnostics #f
       (project-work-accounting prepared
                                #:persistent-cache-hits (length expected-paths)
                                #:materialized (length expected-paths)))
             #t)]
    [else
     (define diagnostics
       (render-prepared-frames
        prepared frame-root prepared-label-layout persistent-hit-output-indices))
     (when (and key (memq policy '(read-write refresh)))
       (write-frame-cache! cache-path key))
     (values diagnostics #f)]))

(define (render-prepared-frames prepared frame-root prepared-label-layout
                                persistent-hit-output-indices)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  (case (render-worker-policy-resolved-mode
         (prepared-project-worker-policy prepared))
    [(in-process)
     (render-prepared-frames/in-process!
      prepared frame-root prepared-label-layout)]
    [(subprocess)
     (render-prepared-frames/subprocess!
      prepared frame-root persistent-hit-output-indices)]
    [else
     (error 'render-prepared-frames "unreachable resolved worker mode")]))

; render-prepared-frames/in-process! : prepared-project? path-string?
;                                      (or/c prepared-label-layout3d? false/c)
;                                      -> project-frame-execution-diagnostics?
;;   Preserves the established local PNG renderer and normalizes its report.
(define (render-prepared-frames/in-process! prepared frame-root prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  (define native-diagnostics
    (call-with-project-renderer3d
     render
     (lambda ()
       (if (eq? (render-spec-renderers render) 'default)
           (keyword-apply
            render-frame-indices/report!
            '(#:camera #:clean? #:fps #:prepared-label-layout #:supersample #:theme #:typography #:workers)
            (list (project-render-camera prepared)
                  #t
                  (render-spec-fps render)
                  prepared-label-layout
                  (render-spec-supersample render)
                  (render-spec-theme render)
                  (render-spec-typography render)
                  (render-spec-workers render))
            (list (prepared-project-scene prepared)
                  (prepared-project-target-frame-indices prepared)
                  frame-root))
           (keyword-apply
            render-frame-indices/report!
            '(#:camera #:clean? #:fps #:prepared-label-layout #:renderers #:supersample #:theme #:typography #:workers)
            (list (project-render-camera prepared)
                  #t
                  (render-spec-fps render)
                  prepared-label-layout
                  (render-spec-renderers render)
                  (render-spec-supersample render)
                  (render-spec-theme render)
                  (render-spec-typography render)
                  (render-spec-workers render))
            (list (prepared-project-scene prepared)
                  (prepared-project-target-frame-indices prepared)
                  frame-root))))))
  (define source-frame-indices (prepared-project-target-frame-indices prepared))
  (project-frame-execution-diagnostics
   'in-process
   (render-spec-workers render)
   (render-diagnostics-workers native-diagnostics)
   #f
   (length source-frame-indices)
   (render-diagnostics-frame-count native-diagnostics)
   0
   source-frame-indices
   (build-list (length source-frame-indices) values)
   (render-diagnostics-elapsed-milliseconds native-diagnostics)
   (render-diagnostics-paths native-diagnostics)
   native-diagnostics
   #f
   (project-work-accounting
    prepared
    #:representatives (render-diagnostics-frame-count native-diagnostics)
    #:rasterized (render-diagnostics-frame-count native-diagnostics)
    #:materialized (render-diagnostics-frame-count native-diagnostics))))

; render-prepared-frames/subprocess! : prepared-project? path-string?
;                                      -> project-frame-execution-diagnostics?
;;   Executes final PNG jobs through the shared worker supervisor and publishes them
;;   into the established local project frame directory.
(define (render-prepared-frames/subprocess! prepared frame-root
                                             persistent-hit-output-indices)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  ;; Native rendering cleans only Animate-owned frame names before it starts.
  ;; The shared executor refuses to overwrite a slot, so preserve that exact
  ;; cache-miss lifecycle here without touching cache metadata or foreign files.
  (delete-project-old-frames! frame-root persistent-hit-output-indices)
  (define source (prepared-project->render-worker-source prepared))
  (define reuse-plan (prepared-project->frame-reuse-plan prepared))
  (define lease-manager (make-preparation-lease-manager))
  (define lease
    (acquire-preparation-lease!
     lease-manager (prepared-project-preparation-manifest prepared)))
  (define report
    (dynamic-wind
     void
     (lambda ()
       (render-final-frame-jobs!
        source
        (prepared-project->final-render-jobs prepared)
        frame-root
        #:workers (render-spec-workers render)
        #:input-manifest (prepared-project-input-manifest prepared)
        #:reuse-plan reuse-plan
        #:persistent-cache-output-indices persistent-hit-output-indices))
     (lambda () (release-preparation-lease! lease))))
  (project-frame-execution-diagnostics
   'subprocess
   (render-spec-workers render)
   (process-frame-execution-report-workers-started report)
   (process-frame-execution-report-workers-completing report)
   (process-frame-execution-report-requested-frame-count report)
   (process-frame-execution-report-completed-frame-count report)
   0
   (process-frame-execution-report-source-frame-indices report)
   (process-frame-execution-report-output-frame-indices report)
   (process-frame-execution-report-elapsed-milliseconds report)
   (process-frame-execution-report-output-paths report)
   #f
   report
   (project-work-accounting
    prepared
    #:persistent-cache-hits
    (process-frame-execution-report-persistent-cache-hit-count report)
    #:aliases (process-frame-execution-report-frame-reuse-alias-count report)
    #:representatives
    (process-frame-execution-report-representative-frame-count report)
    #:rasterized (process-frame-execution-report-rasterized-frame-count report)
    #:materialized (process-frame-execution-report-materialized-frame-count report)
    #:input-verification-events
    (process-frame-execution-report-input-verification-events report)
    #:input-verification-failures
    (process-frame-execution-report-input-verification-failures report))))

; check-prepared-project-subprocess-capability! : prepared-project?
;                                                  (or/c prepared-label-layout3d? false/c)
;                                                  -> void?
;;   Rejects final-render inputs that cannot be consumed by the current worker
;;   before project execution creates or replaces any output.
(define (check-prepared-project-subprocess-capability!
         prepared prepared-label-layout)
  (define policy (prepared-project-worker-policy prepared))
  (when (eq? (render-worker-policy-resolved-mode policy) 'subprocess)
    (define project
      (project-plan-project (prepared-project-plan prepared)))
    (define render (animate-project-render project))
    (unless (eq? (render-spec-renderers render) 'default)
      (raise-arguments-error
       'execute-prepared-project!
       "the default renderer set for subprocess final rendering"
       "renderers" (render-spec-renderers render)))
    (unless (eq? (render-spec-renderer3d render) 'software)
      (raise-arguments-error
       'execute-prepared-project!
       "the software renderer for subprocess final rendering"
       "renderer3d" (render-spec-renderer3d render)))
    (unless (empty-immutable-renderer-options?
             (render-spec-renderer-options render))
      (raise-arguments-error
       'execute-prepared-project!
       "an empty immutable renderer-options map for subprocess final rendering"
       "renderer-options" (render-spec-renderer-options render)))
    (when prepared-label-layout
      (raise-arguments-error
       'execute-prepared-project!
       "no prepared label layout for subprocess final rendering until a worker-side consumer exists"
       "prepared-label-layout" prepared-label-layout))
    ;; These conversions are the protocol's actual semantic acceptance tests;
    ;; do them before `make-directory*` below rather than discovering an
    ;; unsupported camera or source snapshot after a child is launched.
    (camera->final-render-datum (project-render-camera prepared))
    (theme->datum (render-spec-theme render))
    (typography-theme->datum (render-spec-typography render))
    (prepared-project->render-worker-source prepared))
  (void))

; empty-immutable-renderer-options? : any/c -> boolean?
;;   Recognizes the deliberately empty custom-renderer input currently accepted.
(define (empty-immutable-renderer-options? value)
  (and (immutable? value) (hash? value) (zero? (hash-count value))))

; prepared-project->render-worker-source : prepared-project? -> render-worker-source?
;;   Converts one normalized restartable declaration into the shared source
;;   protocol without serializing the parent Scene or duplicating the loader.
(define (prepared-project->render-worker-source prepared)
  (define project
    (project-plan-project (prepared-project-plan prepared)))
  (define source (animate-project-source project))
  (cond
    [(module-binding-source? source)
     (render-worker-module-value-source
      (normalized-module-path-string (module-binding-source-module-path source))
      (module-binding-source-binding source))]
    [(module-builder-source? source)
     (define context (prepared-project-source-build-context prepared))
     (unless context
       (raise-arguments-error
        'prepared-project->render-worker-source
        "a source-build context retained by module-builder preparation"
        "source" source))
     (render-worker-module-builder-source
      (normalized-module-path-string (module-builder-source-module-path source))
      (module-builder-source-binding source)
      (module-builder-source-options source)
      (module-builder-source-prepare source)
      (module-builder-source-seed source)
      (render-worker-build-context
       (source-build-context-asset-base context)
       (source-build-context-assets context)
       (source-build-context-width context)
       (source-build-context-height context)
       (source-build-context-camera-policy context)
       (theme->datum (source-build-context-theme context))
       (typography-theme->datum (source-build-context-typography context))
       (source-build-context-fps context)
       (source-build-context-quality context)
       (source-build-context-seed context)
       (source-build-context-base-fingerprint context))
      (prepared-project-preparation-manifest prepared))]
    [else
     (raise-arguments-error
      'prepared-project->render-worker-source
      "a module-binding-source or module-builder-source"
      "source" source)]))

; normalized-module-path-string : path-string? -> string?
;;   Freezes the exact absolute source location sent to a child worker.
(define (normalized-module-path-string value)
  (path->string (path->complete-path value)))

; prepared-project->final-render-jobs : prepared-project?
;                                       -> (listof final-render-frame-job?)
;;   Builds one request per selected source frame with canonical local output
;;   slots. Shared builder preparation remains at source-load scope through the
;;   verified manifest, never in a per-frame carrier.
(define (prepared-project->final-render-jobs prepared)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  (define source-fingerprint (prepared-project-source-fingerprint prepared))
  (define session-id (prepared-project-session-id prepared))
  (define camera (project-render-camera prepared))
  (for/list ([source-index
              (in-list (prepared-project-target-frame-indices prepared))]
             [output-index (in-naturals)])
    (make-final-render-frame-job
     session-id source-fingerprint 0 output-index source-index output-index
     (render-spec-fps render)
     #:camera camera
     #:supersample (render-spec-supersample render)
     #:theme-datum (theme->datum (render-spec-theme render))
     #:typography-datum (typography-theme->datum (render-spec-typography render))
     #:renderer-kind 'default
     #:renderer-inputs #hasheq())))

; prepared-project->frame-reuse-plan : prepared-project?
;                                     -> (or/c render-frame-reuse-plan? false/c)
;;   Restricts an optional domain witness to this selected target without inspecting scenes.
(define (prepared-project->frame-reuse-plan prepared)
  (define preparation (prepared-project-source-preparation prepared))
  (define context (prepared-project-source-build-context prepared))
  (cond
    [(and preparation
          context
          (source-preparation-frame-reuse preparation))
     (make-render-frame-reuse-plan
      (prepared-project-target-frame-indices prepared)
      (source-build-context-base-fingerprint context)
      (datum->frame-reuse-witness
       (source-preparation-frame-reuse preparation)))]
    [else #f]))

; prepared-project-source-fingerprint : prepared-project? -> immutable-hash?
;;   Produces execution identity for one restartable source without changing
;;   the persistent project frame-cache key or transferring a live Scene.
(define (prepared-project-source-fingerprint prepared)
  (define project
    (project-plan-project (prepared-project-plan prepared)))
  (define source (animate-project-source project))
  (cond
    [(module-binding-source? source)
     (hasheq 'kind 'module-binding
             'module-path
             (normalized-module-path-string
              (module-binding-source-module-path source))
             'binding (module-binding-source-binding source)
             'input-manifest
             (and (prepared-project-input-manifest prepared)
                  (render-input-manifest-identity
                   (prepared-project-input-manifest prepared))))]
    [(module-builder-source? source)
     (define context (prepared-project-source-build-context prepared))
     (hasheq 'kind 'module-builder
             'module-path
             (normalized-module-path-string
              (module-builder-source-module-path source))
             'binding (module-builder-source-binding source)
             'options (module-builder-source-options source)
             'prepare (module-builder-source-prepare source)
             'seed (module-builder-source-seed source)
             'build-context-fingerprint
             (and context (source-build-context-base-fingerprint context))
             'input-manifest
             (and (prepared-project-input-manifest prepared)
                  (render-input-manifest-identity
                   (prepared-project-input-manifest prepared)))
             'preparation-manifest
             (and (prepared-project-preparation-manifest prepared)
                  (render-preparation-manifest-identity
                   (prepared-project-preparation-manifest prepared))))]
    [else
     (raise-arguments-error
      'prepared-project-source-fingerprint
      "a restartable project source"
      "source" source)]))

; prepared-project-session-id : prepared-project? -> string?
;;   Allocates a bounded process-session label unrelated to cache identity.
(define (prepared-project-session-id prepared)
  (define project
    (project-plan-project (prepared-project-plan prepared)))
  (format "project-~a-~a"
          (animate-project-id project)
          (gensym 'render)))

; delete-project-old-frames! : path-string? (listof exact-nonnegative-integer?) -> void?
;;   Removes stale canonical slots while preserving verified persistent frame hits.
(define (delete-project-old-frames! directory preserved-output-indices)
  (when (directory-exists? directory)
    (for ([entry (in-list (directory-list directory))])
      (define text (path->string entry))
      (define match (regexp-match #px"^frame-([0-9]{6,})\\.png$" text))
      (when (and match
                 (not (member (string->number (cadr match))
                              preserved-output-indices)))
        (delete-file (build-path directory entry)))))
  (void))

;; A renderer selection belongs to the project declaration, whereas the
;; retained renderer instance belongs to one render operation.  In particular,
;; do not put the live OpenGL owner, context, or GLuints in `render-spec`.
;; Frame workers inherit this parameterization when they are created, and the
;; renderer's own context host serializes every OpenGL call.
(define (call-with-project-renderer3d render thunk)
  (define declaration (render-spec-renderer3d render))
  (cond
    [(eq? declaration 'software) (thunk)]
    [else
     ;; The renderer creates the owned context below.  That concrete operation
     ;; is the capability test: a `raco test` worker can have a GUI-capable
     ;; runtime while `find-system-path` still calls its executable "racket".
     ;; A launcher-name guard would reject that valid process before the backend
     ;; can give its useful context-creation diagnostic.
     (define renderer-predicate
       (dynamic-require opengl-renderer-module 'opengl-renderer3d-spec?))
     (unless (renderer-predicate declaration)
       (raise-arguments-error
        'render-project!
        "an opengl-renderer3d-spec declaration"
        "renderer3d" declaration))
     (when (> (render-spec-workers render) 1)
       (raise-arguments-error
        'render-project!
        "#:workers 1 for the first serialized OpenGL project backend"
        "workers" (render-spec-workers render)
        "hint"
        "OpenGL calls for one context are serialized; use one renderer process"))
     (define make-renderer
       (dynamic-require opengl-renderer-module 'opengl-renderer3d))
     (define release-renderer!
       (dynamic-require opengl-renderer-module 'opengl-renderer3d-release!))
     (define renderer (make-renderer declaration))
     (dynamic-wind
      void
      (lambda ()
        (parameterize ([current-view3d-renderer3d renderer])
          (thunk)))
      (lambda () (release-renderer! renderer)))]))

(define (project-frame-cache-key prepared prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define source (animate-project-source project))
  (define input-manifest (prepared-project-input-manifest prepared))
  (and (eq? (cacheability-mode (prepared-project-cache-identities prepared))
            'persistent)
       input-manifest
       (list 'animate-project-frame-cache-v5
             animate-version animate-stage
             ;; The execution manifest verifies every declared local input,
             ;; including narration. Frame reuse deliberately projects that
             ;; snapshot to the inputs capable of changing pixels: audio must
             ;; not invalidate otherwise valid PNGs.
             (render-input-manifest-visual-identity input-manifest)
             (and (module-builder-source? source)
                  (prepared-project-preparation-manifest prepared)
                  (render-preparation-manifest-identity
                   (prepared-project-preparation-manifest prepared)))
             (project-frame-render-identity prepared prepared-label-layout))))

; render-input-manifest-visual-identity : render-input-manifest? -> string?
;;   Derives a deterministic PNG-input identity while retaining audio only for
;;   session integrity checks and later audio assembly, never frame reuse.
(define (render-input-manifest-visual-identity manifest)
  (unless (render-input-manifest? manifest)
    (raise-argument-error
     'render-input-manifest-visual-identity "render-input-manifest?" manifest))
  (define visual-datum
    (hasheq
     'schema 'animate-render-visual-inputs-v1
     'entries
     (for/list ([entry (in-list (hash-ref manifest 'entries))]
                #:unless (eq? (hash-ref entry 'role) 'audio))
       entry)
     ;; Runtime/loader identity affects source reconstruction and remains a
     ;; visual input even though its key is not a file path.
     'runtime (hash-ref manifest 'runtime)))
  (sha1 (open-input-string (format "~s" (stable-cache-datum visual-datum)))))

;; This identity contains only inputs that can affect a rendered frame. It is
;; intentionally distinct from the project plan and encoder identity: output
;; names, MP4 options, audio options, and cache-directory paths must not turn a
;; valid PNG sequence into a cache miss.
(define (project-frame-render-identity prepared prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define render (animate-project-render (project-plan-project plan)))
  (hasheq
   'frame-grid
   (hasheq 'fps (render-spec-fps render)
           'indices (prepared-project-target-frame-indices prepared))
   'raster
   (hasheq 'width (render-spec-width render)
           'height (render-spec-height render)
           'supersample (render-spec-supersample render)
           'quality (render-spec-quality render))
   'camera (stable-cache-datum (project-render-camera prepared))
   ;; The default Pict renderer includes the deterministic opaque-triangle
   ;; backend from SCENE-3D-C.  Name it explicitly: a cached frame is never
   ;; reused across an implementation whose depth/culling semantics changed.
   'renderer (hasheq 'selection (stable-cache-datum (render-spec-renderers render))
                     'software-3d "opaque-triangle-zbuffer-v1"
                     ;; An OpenGL declaration is an explicit part of the
                     ;; raster identity.  Its live vendor/context fingerprint
                     ;; is intentionally not available during pure planning;
                     ;; static selection still prevents an accidental reuse of
                     ;; software PNGs for an OpenGL render (or vice versa).
                     'three-dimensional
                     (stable-cache-datum (render-spec-renderer3d render)))
   'renderer-options (stable-cache-datum (render-spec-renderer-options render))
   ;; A theme can change every token-backed pixel. Retain its complete datum
   ;; for auditable cache manifests and its appearance fingerprint for compact
   ;; equality; provenance stays visible without becoming appearance identity.
   'color-theme
   (hasheq 'datum (theme->datum (render-spec-theme render))
           'appearance-fingerprint
           (color-theme-fingerprint (render-spec-theme render))
           'resolver-version render-color-resolver-version)
   ;; Text roles can affect line breaks and treatment bounds, so typography is
   ;; mandatory even with an author-supplied source cache key.
   'typography-theme
   (hasheq 'datum (typography-theme->datum (render-spec-typography render))
           'appearance-fingerprint
           (typography-theme-fingerprint (render-spec-typography render))
           'resolver-version render-typography-resolver-version)
   ;; A prepared table changes selected placement boxes, so it is part of the
   ;; PNG identity even though its computation happens before worker creation.
   ;; Convert only its immutable primitive contents to a readable datum; cache
   ;; validation compares this data but never reconstructs the table.
   'prepared-label-layout
   (prepared-label-layout-cache-datum prepared-label-layout)
   'semantic-render-schema 'scene-to-pict-to-bitmap-v2))

(define (prepared-label-layout-cache-datum prepared-layout)
  (and prepared-layout
       (hasheq
        'frames (vector->list (prepared-label-layout3d-frames prepared-layout))
        'switch-penalty (prepared-label-layout3d-switch-penalty prepared-layout)
        'movement-penalty (prepared-label-layout3d-movement-penalty prepared-layout)
        'placements
        (for/list ([layout (in-vector (prepared-label-layout3d-layouts prepared-layout))])
          (for/list ([candidate (in-list (label-layout3d-placements layout))])
            (hasheq
             'item-id (label-layout-candidate3d-item-id candidate)
             'direction (label-layout-candidate3d-direction candidate)
             'box (vector->list (label-layout-candidate3d-box candidate))
             'leader? (label-layout-candidate3d-leader? candidate)
             'cost (label-layout-candidate3d-cost candidate)))))))

;; Convert user-provided renderer configuration into a read/write-safe cache
;; datum. Procedures deliberately print with their process identity, which can
;; cause a conservative miss but cannot accidentally reuse a frame rendered by
;; a different opaque renderer. Hash keys are sorted so immutable option maps
;; produce one stable representation regardless of insertion order.
(define (stable-cache-datum value)
  (cond
    [(hash? value)
     (cons
      'hash
      (sort
       (for/list ([(key entry) (in-hash value)])
         (cons (stable-cache-datum key) (stable-cache-datum entry)))
       string<?
       #:key (lambda (entry) (format "~s" (car entry)))))]
    [(pair? value)
     (cons (stable-cache-datum (car value))
           (stable-cache-datum (cdr value)))]
    [(vector? value)
     (list->vector (for/list ([entry (in-vector value)])
                     (stable-cache-datum entry)))]
    [(path? value) (path->string value)]
    ;; Printed primitive/transparent structure data is sufficient here only
    ;; because an unprintable custom renderer becomes a different string and
    ;; therefore a safe cache miss. The persistent cache never needs to
    ;; reconstruct this value; it compares the immutable datum read from disk.
    [else (format "~s" value)]))

(define (project-local-frame-paths directory count)
  (for/list ([index (in-range count)])
    (build-path directory (format "frame-~a.png" (~r index #:min-width 6 #:pad-string "0")))))

(define (frame-cache-valid? path key expected-paths)
  (and (file-exists? path)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (and (equal? (call-with-input-file path read) key)
              (andmap file-exists? expected-paths)))))

; frame-cache-hit-output-indices : path? any/c immutable-list?
;                                  -> immutable-list?
;;   Finds verified existing slots for one current target before worker sizing.
(define (frame-cache-hit-output-indices path key expected-paths)
  (if (and (file-exists? path)
           (with-handlers ([exn:fail? (lambda (_error) #f)])
             (equal? (call-with-input-file path read) key)))
      (for/list ([expected-path (in-list expected-paths)]
                 [output-index (in-naturals)]
                 #:when (file-exists? expected-path))
        output-index)
      '()))

(define (write-frame-cache! path key)
  (call-with-output-file path
    (lambda (out) (write key out) (newline out))
    #:exists 'truncate/replace)
  (void))

;; Cache domains are opt-in filters over a project-wide policy.  A disabled
;; domain still permits the requested render; it merely prevents that domain
;; from persisting or reusing artefacts.  This makes it possible to refresh
;; encoder output while retaining valid PNG frames, or to turn off only media
;; caching while leaving formula compilation alone.
(define (cache-domain-enabled? cache domain)
  (and (member domain (cache-spec-domains cache)) #t))

;; A visual MP4 segment is keyed separately from its PNG sequence.  The frame
;; identity deliberately excludes codec settings, while this identity includes
;; every video-encoder choice that can change the compressed byte stream.
;; Audio and subtitle settings do not appear: they are remuxed after a visual
;; segment is obtained, so narration edits never invalidate visual encoding.
(define (project-segment-cache-key prepared prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define encoder (animate-project-encoder project))
  (define frame-key (project-frame-cache-key prepared prepared-label-layout))
  (and frame-key
       (list 'animate-project-segment-cache-v1
             animate-version animate-stage
             frame-key
             (hasheq 'container 'mp4
                     'codec (encoder-spec-codec encoder)
                     'pixel-format (encoder-spec-pixel-format encoder)
                     'options (stable-cache-datum (encoder-spec-options encoder))
                     'fast-start? (encoder-spec-fast-start? encoder)
                     'fps (render-spec-fps (animate-project-render project))
                     'ffmpeg (stable-cache-datum
                              (project-tool-identities-ffmpeg
                               (prepared-project-tool-identities prepared)))))))

(define (segment-cache-valid? key segment-path key-path)
  (and key
       (file-exists? segment-path)
       (file-exists? key-path)
       (with-handlers ([exn:fail? (lambda (_error) #f)])
         (equal? (call-with-input-file key-path read) key))))

(define (cache-key-directory-name key)
  ;; The full readable key remains in its sidecar for diagnostics. Its digest
  ;; only selects a filesystem-safe namespace, allowing several encoder
  ;; profiles for the same PNG frames to coexist rather than evicting one
  ;; another whenever an author compares CRF or preset values.
  (sha1 (open-input-string (format "~s" key))))

(define (write-segment-cache! segment-root segment-path key-path source-path key)
  ;; Stage both files next to their final cache locations. `rename` is atomic
  ;; on this filesystem, so an interrupted encoder can at worst leave an
  ;; ignored partial file—not an apparently valid cache entry.
  (make-directory* segment-root)
  (define segment-partial (build-path segment-root ".visual.partial.mp4"))
  (define key-partial (build-path segment-root ".animate-segment-cache.partial.rktd"))
  (when (file-exists? segment-partial) (delete-file segment-partial))
  (when (file-exists? key-partial) (delete-file key-partial))
  (copy-file source-path segment-partial #t)
  (rename-file-or-directory segment-partial segment-path #t)
  (call-with-output-file key-partial
    (lambda (out) (write key out) (newline out))
    #:exists 'truncate/replace)
  (rename-file-or-directory key-partial key-path #t)
  (void))

;; Returns a temporary visual input suitable for muxing, plus execution and
;; cache accounting. The temporary copy is always distinct from a persistent
;; cache segment: final assembly may freely move or delete it without harming
;; later renders.
(define (obtain-project-visual-segment! prepared frame-root visual-temporary prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define cache (animate-project-cache project))
  (define policy (cache-spec-policy cache))
  (define paths (project-plan-path-plan plan))
  (define key
    (and (cache-domain-enabled? cache 'segments)
         (project-segment-cache-key prepared prepared-label-layout)))
  (define segments-root (project-path-plan-segments-root paths))
  (define segment-root
    (and key (build-path segments-root (cache-key-directory-name key))))
  (define segment-path
    (and segment-root (build-path segment-root segment-cache-video-name)))
  (define key-path
    (and segment-root (build-path segment-root segment-cache-file-name)))
  (cond
    [(and (memq policy '(read-only read-write))
          (segment-cache-valid? key segment-path key-path))
     (copy-file segment-path visual-temporary #t)
     (values visual-temporary 0 1
             (hasheq 'domain 'segments 'event 'reused 'count 1))]
    [else
     (define render (animate-project-render project))
     (define encoder (animate-project-encoder project))
     (encode-mp4!
      frame-root visual-temporary
      #:fps (render-spec-fps render)
      #:codec (encoder-spec-codec encoder)
      #:pixel-format (encoder-spec-pixel-format encoder)
      #:options (encoder-spec-options encoder)
      #:fast-start? (encoder-spec-fast-start? encoder))
     (when (and key (memq policy '(read-write refresh)))
       (write-segment-cache! segment-root segment-path key-path visual-temporary key))
     (values visual-temporary 1 0
             (hasheq 'domain 'segments
                     'event (if key 'encoded 'encoded-without-persistent-cache)
                     'count 1))]))

(define (project-render-camera prepared)
  (define plan (prepared-project-plan prepared))
  (define render (animate-project-render (project-plan-project plan)))
  (or (render-spec-camera render)
      (let ([scene-camera (scene-current-camera (prepared-project-scene prepared))])
        (make-camera
         #:width (render-spec-width render)
         #:height (render-spec-height render)
         #:world-width (camera-world-width scene-camera)
         #:center (camera-center scene-camera)
         #:background (camera-background scene-camera)))))

(define (install-project-mp4! prepared frame-root primary prepared-label-layout)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  (define encoder (animate-project-encoder project))
  (define temporary (project-path-plan-temporary (project-plan-path-plan plan)))
  (make-directory* (or (path-only primary) (current-directory)))
  (when (file-exists? temporary)
    (delete-file temporary))
  (define timeline (prepared-project-timeline prepared))
  (define full-timeline?
    (eq? (project-target-kind (project-plan-target plan)) 'all))
  (define visual-temporary
    (build-path (or (path-only primary) (current-directory))
                (format ".~a.visual.partial.mp4" (output-spec-name (animate-project-output project)))))
  (when (file-exists? visual-temporary)
    (delete-file visual-temporary))
  (define-values (visual-input encoded-segments reused-segments segment-cache-event)
    (obtain-project-visual-segment!
     prepared frame-root visual-temporary prepared-label-layout))
  (define subtitle-path
    (and timeline full-timeline?
         (pair? (authored-timeline-subtitles timeline))
         (let ([path (project-path-plan-subtitles (project-plan-path-plan plan))])
           (make-directory* (or (path-only path) (current-directory)))
           (write-subtitles! timeline path)
           path)))
  (define audio-rebuilt?
    (and timeline full-timeline?
         (or (pair? (authored-timeline-audio-cues timeline)) subtitle-path)))
  (cond
    [audio-rebuilt?
     (mux-authored-video! timeline visual-input temporary
                         #:subtitle-file subtitle-path)]
    [else
     ;; Preserve a cached segment for later output assembly. Even an uncached
     ;; temporary is copied here rather than moved so this branch has the same
     ;; ownership rules as the audio-mux branch.
     (copy-file visual-input temporary #t)])
  (when (file-exists? visual-temporary)
    (delete-file visual-temporary))
  (rename-file-or-directory temporary primary #t)
  (values primary (and audio-rebuilt? #t) subtitle-path
          encoded-segments reused-segments segment-cache-event))

; project-frame-execution-diagnostics->datum : project-frame-execution-diagnostics?
;                                               -> immutable-hash?
;;   Produces the serializable execution facts retained in a project manifest
;;   and command result without exposing live renderer or process objects.
(define (project-frame-execution-diagnostics->datum diagnostics)
  (unless (project-frame-execution-diagnostics? diagnostics)
    (raise-argument-error
     'project-frame-execution-diagnostics->datum
     "project-frame-execution-diagnostics?"
     diagnostics))
  (hasheq
   'mode (project-frame-execution-diagnostics-mode diagnostics)
   'requested-worker-capacity
   (project-frame-execution-diagnostics-requested-worker-capacity diagnostics)
   'workers-started
   (project-frame-execution-diagnostics-workers-started diagnostics)
   'workers-completing
   (project-frame-execution-diagnostics-workers-completing diagnostics)
   'requested-frame-count
   (project-frame-execution-diagnostics-requested-frame-count diagnostics)
   'rendered-frame-count
   (project-frame-execution-diagnostics-rendered-frame-count diagnostics)
   'reused-frame-count
   (project-frame-execution-diagnostics-reused-frame-count diagnostics)
   'work-accounting
   (project-frame-execution-diagnostics-work-accounting diagnostics)
   'elapsed-milliseconds
   (project-frame-execution-diagnostics-elapsed-milliseconds diagnostics)
   'frame-map
   (for/list ([source-index
               (in-list
                (project-frame-execution-diagnostics-source-frame-indices
                 diagnostics))]
              [output-index
               (in-list
                (project-frame-execution-diagnostics-output-frame-indices
                 diagnostics))])
     (hasheq 'source-frame-index source-index
             'output-frame-index output-index))
   'subprocess
   (and (project-frame-execution-diagnostics-subprocess-report diagnostics)
        (process-frame-execution-report->datum
         (project-frame-execution-diagnostics-subprocess-report diagnostics)))))

; process-frame-execution-report->datum : process-frame-execution-report?
;                                          -> immutable-hash?
;;   Narrows a closed final-frame report to manifest-safe process and cleanup evidence.
(define (process-frame-execution-report->datum report)
  (hasheq
   'worker-pids (process-frame-execution-report-worker-pids report)
   'worker-resource-statuses
   (process-frame-execution-report-worker-resource-statuses report)
   'startup-milliseconds
   (process-frame-execution-report-startup-milliseconds report)
   'worker-timings
   (process-frame-execution-report-worker-timings report)
   'raster-execution-milliseconds
   (process-frame-execution-report-raster-execution-milliseconds report)
   'publication-milliseconds
   (process-frame-execution-report-publication-milliseconds report)
   'elapsed-milliseconds
   (process-frame-execution-report-elapsed-milliseconds report)
   'canceled? (process-frame-execution-report-canceled? report)
   'persistent-cache-hits
   (process-frame-execution-report-persistent-cache-hit-count report)
   'frame-reuse-aliases
   (process-frame-execution-report-frame-reuse-alias-count report)
   'representative-raster-jobs
   (process-frame-execution-report-representative-frame-count report)
   'frames-rasterized
   (process-frame-execution-report-rasterized-frame-count report)
   'materialized-output-frames
   (process-frame-execution-report-materialized-frame-count report)
   'input-verification-events
   (process-frame-execution-report-input-verification-events report)
   'input-verification-failures
   (process-frame-execution-report-input-verification-failures report)
   'assignments
   (for/list ([assignment
               (in-list (process-frame-execution-report-assignments report))])
     (hasheq 'source-frame-index
             (process-frame-assignment-source-frame-index assignment)
             'output-frame-index
             (process-frame-assignment-output-frame-index assignment)
             'request-id (process-frame-assignment-request-id assignment)
             'worker-pid (process-frame-assignment-worker-pid assignment)
             'elapsed-milliseconds
             (process-frame-assignment-elapsed-milliseconds assignment)))))

;; The manifest is a machine-readable immutable datum next to cache artefacts.
;; It makes a completed output independently inspectable without asking the
;; preview process to retain state.
(define (write-project-execution-manifest! report path)
  (make-directory* (or (path-only path) (current-directory)))
  (call-with-output-file
   path
   (lambda (out)
     (write
      (hasheq 'plan (project-plan->datum (project-execution-report-plan report))
              'artifact-paths (project-execution-report-artifact-paths report)
              'elapsed-milliseconds (project-execution-report-elapsed-milliseconds report)
              'rendered-frames (project-execution-report-rendered-frames report)
              'reused-frames (project-execution-report-reused-frames report)
              'encoded-segments (project-execution-report-encoded-segments report)
              'reused-segments (project-execution-report-reused-segments report)
              'audio-rebuilt? (project-execution-report-audio-rebuilt? report)
              'cache-events (project-execution-report-cache-events report)
              'frame-execution
              (project-frame-execution-diagnostics->datum
               (project-execution-report-diagnostics report))
              'warnings (project-execution-report-warnings report))
      out)
     (newline out))
   #:exists 'truncate/replace)
  path)

(define (check-overwrite-policy output primary)
  (when (and (path-exists? primary)
             (eq? (output-spec-overwrite-policy output) 'error))
    (raise-arguments-error
     'execute-prepared-project!
     "an absent output artifact or overwrite policy 'replace"
     "primary-output" primary
     "overwrite-policy" (output-spec-overwrite-policy output))))

(define (path-exists? path)
  (or (file-exists? path) (directory-exists? path)))

;; Opening a result is intentionally best effort. A render has already
;; completed successfully when this is called, so a missing desktop launcher,
;; a headless session, or a rejected launch becomes a report warning rather
;; than an exception that misrepresents the output as failed.
(define (default-project-artifact-opener artifact)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (case (system-type 'os)
      [(macosx) (open-with-executable "open" artifact)]
      [(unix) (open-with-executable "xdg-open" artifact)]
      ;; `explorer.exe` opens both ordinary files and directories without the
      ;; shell-specific quoting rules required by Windows' `start` command.
      [(windows) (open-with-executable "explorer.exe" artifact)]
      [else #f])))

(define (open-with-executable command artifact)
  (define executable (find-executable-path command))
  (and executable
       (system* executable (path->string artifact))))

;; Materializing PNGs is deliberately separate from rasterization. The rendered
;; frames remain in their target-specific cache directory, while an author
;; receives a portable sequence below the declared output root. Copy into a
;; private sibling first, so an observer never sees a half-populated sequence.
(define (install-project-frame-sequence! prepared frame-root)
  (define plan (prepared-project-plan prepared))
  (define paths (project-plan-path-plan plan))
  (define destination (project-path-plan-frame-sequence paths))
  (define temporary (project-path-plan-temporary-frame-sequence paths))
  (define count (length (prepared-project-target-frame-indices prepared)))
  (when (path-exists? temporary)
    ;; This hidden path is generated by the current plan, never selected by the
    ;; author. A stale partial result is not a valid output artefact.
    (delete-directory/files temporary))
  (make-directory* temporary)
  (for ([source-path (in-list (project-local-frame-paths frame-root count))])
    (copy-file source-path
               (build-path temporary (file-name-from-path source-path))))
  (install-output-directory! temporary destination)
  destination)

(define (install-output-directory! temporary destination)
  (define parent (or (path-only destination) (current-directory)))
  (define leaf (file-name-from-path destination))
  (define backup
    (build-path parent (string-append "." (path->string leaf) ".backup")))
  (cond
    [(not (path-exists? destination))
     (rename-file-or-directory temporary destination #t)]
    [else
     ;; Directory replacement is a two-rename swap. Retain the old complete
     ;; output until the new complete temporary directory is installed, then
     ;; restore it if the second rename fails.
     (when (path-exists? backup)
       (delete-directory/files backup))
     (rename-file-or-directory destination backup #t)
     (with-handlers
         ([exn:fail?
           (lambda (error)
             (when (path-exists? backup)
               (rename-file-or-directory backup destination #t))
             (raise error))])
       (rename-file-or-directory temporary destination #t)
       (when (path-exists? backup)
         (delete-directory/files backup)))]))
