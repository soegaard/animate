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
         racket/system
         file/sha1
         "../main.rkt"
         "../authoring.rkt"
         "../project.rkt"
         "../version.rkt"
         "png-renderer.rkt"
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
         (struct-out project-execution-report))


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


;;;
;;; Author-Facing Execution
;;;

; render-project! : animate-project? [#:target project-target?]
;;                   [#:directory path-string?] -> project-execution-report?
;;   Plans, prepares, and renders one declared project target.
(define (render-project! project
                         #:target [target (project-target-all)]
                         #:directory [directory (current-directory)])
  (execute-prepared-project!
   (prepare-project!
    (plan-project project #:target target #:directory directory))))

; render-project-section! : animate-project? symbol? ... -> project-execution-report?
;;   Renders one named authored-timeline section through the project plan.
(define (render-project-section! project section-name
                                 #:directory [directory (current-directory)])
  (render-project! project
                   #:target (project-target-section section-name)
                   #:directory directory))

; render-project-block! : animate-project? symbol? ... -> project-execution-report?
;;   Renders one named source-program block through the project plan.
(define (render-project-block! project block-name
                               #:directory [directory (current-directory)])
  (render-project! project
                   #:target (project-target-block block-name)
                   #:directory directory))

; render-project-range! : animate-project? real? real? ... -> project-execution-report?
;;   Renders a half-open scene-time range through the project plan.
(define (render-project-range! project start end
                               #:directory [directory (current-directory)])
  (render-project! project
                   #:target (project-target-range start end)
                   #:directory directory))

; render-project-frame! : animate-project? exact-nonnegative-integer? ...
;;                 -> project-execution-report?
;;   Renders one zero-based source frame through the project plan.
(define (render-project-frame! project frame-index
                               #:directory [directory (current-directory)])
  (render-project! project
                   #:target (project-target-frame frame-index)
                   #:directory directory))

; execute-prepared-project! : prepared-project?
;;                            [#:protected-frame-roots (listof path?)]
;;                            [#:open-after? boolean?]
;;                            -> project-execution-report?
;;   Lazily creates only the directories required by a prepared target, renders
;; locally numbered PNGs, and atomically installs the final video when needed.
(define (execute-prepared-project! prepared
                                   #:protected-frame-roots [protected-frame-roots '()]
                                   #:open-after? [open-after? #t])
  (unless (prepared-project? prepared)
    (raise-argument-error
     'execute-prepared-project! "prepared-project?" prepared))
  (unless (and (list? protected-frame-roots)
               (andmap path? protected-frame-roots))
    (raise-argument-error
     'execute-prepared-project! "(listof path?)" protected-frame-roots))
  (unless (boolean? open-after?)
    (raise-argument-error 'execute-prepared-project! "boolean?" open-after?))
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
  (check-overwrite-policy output primary)
  (define export-frames?
    (or (eq? (output-spec-format output) 'png-sequence)
        (output-spec-write-frame-sequence? output)))
  (when export-frames?
    (check-overwrite-policy output (project-path-plan-frame-sequence paths)))
  (make-directory* frame-root)
  (define-values (diagnostics reused-frames?)
    (render-or-reuse-prepared-frames prepared frame-root))
  (define frame-paths
    (render-diagnostics-paths diagnostics))
  (define-values (artifact audio-rebuilt? subtitle-path
                  encoded-segments reused-segments segment-cache-event)
    (case (output-spec-format output)
      [(png-sequence)
       (values primary #f #f 0 0
               (hasheq 'domain 'segments 'event 'not-applicable))]
      [(mp4)
       (install-project-mp4! prepared frame-root primary)]
      [else (error 'execute-prepared-project! "unreachable output format")]))
  (define exported-frame-sequence
    (and export-frames?
         (install-project-frame-sequence! prepared frame-root)))
  (define section-artifacts
    (if (and (output-spec-write-sections? output)
             (eq? (project-target-kind (project-plan-target plan)) 'all))
        (render-declared-project-sections!
         prepared
         #:protected-frame-roots (cons frame-root protected-frame-roots))
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
                                            #:protected-frame-roots protected-frame-roots)
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
(define (render-or-reuse-prepared-frames prepared frame-root)
  (define project (project-plan-project (prepared-project-plan prepared)))
  (define cache (animate-project-cache project))
  (define policy (cache-spec-policy cache))
  (define key
    (and (cache-domain-enabled? cache 'frames)
         (project-frame-cache-key prepared)))
  (define expected-paths
    (project-local-frame-paths frame-root
                               (length (prepared-project-target-frame-indices prepared))))
  (define cache-path (build-path frame-root frame-cache-file-name))
  (cond
    [(and key
          (memq policy '(read-only read-write))
          (frame-cache-valid? cache-path key expected-paths))
     (values (render-diagnostics expected-paths (length expected-paths) 0 0 '()
                                 0 0 0 animate-version animate-stage)
             #t)]
    [else
     (define diagnostics (render-prepared-frames prepared frame-root))
     (when (and key (memq policy '(read-write refresh)))
       (write-frame-cache! cache-path key))
     (values diagnostics #f)]))

(define (render-prepared-frames prepared frame-root)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define render (animate-project-render project))
  (if (eq? (render-spec-renderers render) 'default)
      (keyword-apply
       render-frame-indices/report!
       '(#:camera #:clean? #:fps #:supersample #:workers)
       (list (project-render-camera prepared)
             #t
             (render-spec-fps render)
             (render-spec-supersample render)
             (render-spec-workers render))
       (list (prepared-project-scene prepared)
             (prepared-project-target-frame-indices prepared)
             frame-root))
      (keyword-apply
       render-frame-indices/report!
       '(#:camera #:clean? #:fps #:renderers #:supersample #:workers)
       (list (project-render-camera prepared)
             #t
             (render-spec-fps render)
             (render-spec-renderers render)
             (render-spec-supersample render)
             (render-spec-workers render))
       (list (prepared-project-scene prepared)
             (prepared-project-target-frame-indices prepared)
             frame-root))))

(define (project-frame-cache-key prepared)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define source (animate-project-source project))
  (and (module-binding-source? source)
       (let ([module-path (module-binding-source-module-path source)])
         (and (file-exists? module-path)
              (list 'animate-project-frame-cache-v2
                    animate-version animate-stage
                    (call-with-input-file module-path sha1)
                    (project-frame-render-identity prepared)
                    ;; Audio belongs to the later mix/mux stage. Its source
                    ;; bytes must not turn a semantically identical scene
                    ;; frame into a cache miss; visual and formula assets do.
                    (for/list ([asset (in-list (animate-project-assets project))]
                               #:unless (eq? (project-asset-role asset) 'audio))
                      (list (project-asset-path asset)
                            (and (file-exists? (project-asset-path asset))
                                 (call-with-input-file (project-asset-path asset) sha1)))))))))

;; This identity contains only inputs that can affect a rendered frame. It is
;; intentionally distinct from the project plan and encoder identity: output
;; names, MP4 options, audio options, and cache-directory paths must not turn a
;; valid PNG sequence into a cache miss.
(define (project-frame-render-identity prepared)
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
   'renderer (stable-cache-datum (render-spec-renderers render))
   'renderer-options (stable-cache-datum (render-spec-renderer-options render))
   'semantic-render-schema 'scene-to-pict-to-bitmap-v1))

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
(define (project-segment-cache-key prepared)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define encoder (animate-project-encoder project))
  (define frame-key (project-frame-cache-key prepared))
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
(define (obtain-project-visual-segment! prepared frame-root visual-temporary)
  (define plan (prepared-project-plan prepared))
  (define project (project-plan-project plan))
  (define cache (animate-project-cache project))
  (define policy (cache-spec-policy cache))
  (define paths (project-plan-path-plan plan))
  (define key
    (and (cache-domain-enabled? cache 'segments)
         (project-segment-cache-key prepared)))
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

(define (install-project-mp4! prepared frame-root primary)
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
    (obtain-project-visual-segment! prepared frame-root visual-temporary))
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
