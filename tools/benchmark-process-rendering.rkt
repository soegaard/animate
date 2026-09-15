#lang racket/base

;;;
;;; Process Rendering Benchmark
;;;

;; Runs reproducible, real-child measurements of the completed source-aware
;; project renderer.  This is a release-validation tool, not an ordinary
;; rendering backend or an author-facing command.


;;;
;;; Imports and Exports
;;;

;; Imports
(require json
         openssl
         racket/cmdline
         racket/date
         racket/file
         racket/format
         racket/list
         racket/match
         racket/path
         racket/runtime-path
         racket/string
         racket/system
         "../colors.rkt"
         "../project.rkt"
         "../private/process-frame-executor.rkt"
         "../private/project-execution.rkt"
         "../private/render-preparation-manifest.rkt"
         (prefix-in math-preparation: "../math/private/prepare.rkt")
         (prefix-in math-typeset: "../math/private/typeset.rkt"))

;; Exports
(provide run-process-rendering-benchmark!)


;;;
;;; Stable Locations and Workloads
;;;

(define-runtime-path repository-root "..")
(define-runtime-path benchmark-tool "benchmark-process-rendering.rkt")
(define-runtime-path geometry-source "../geometry/examples/copy-angle.rkt")
(define-runtime-path math-source "../math/examples/quadratic-general.rkt")

(struct benchmark-workload (name domain source title options)
  #:transparent)

;; benchmark-workload identifies one normal restartable example and its frozen
;; builder options.
;;  - name    symbol?         stable report and directory identity.
;;  - domain  symbol?         selects the domain-owned preparation contract.
;;  - source  path?           explicitly launched restartable example module.
;;  - title   string?         parent-side presentation title for math sources.
;;  - options immutable-hash? reserved for future declared workload inputs.

; representative-workloads : -> (listof benchmark-workload?)
;;   Returns the two complete lessons used for the primary scaling comparison.
(define (representative-workloads)
  (list
   (benchmark-workload
    'geometry-copy-angle
    'geometry
    geometry-source
    "copy angle"
    #hasheq())
   (benchmark-workload
    'math-quadratic-general
    'math
    math-source
    "quadratic general"
    #hasheq())))

; benchmark-workload-names : -> (listof symbol?)
;;   Returns the supported stable workload names in report order.
(define (benchmark-workload-names)
  (map benchmark-workload-name (representative-workloads)))

; benchmark-workload-list : string? -> (listof symbol?)
;;   Parses a nonempty, distinct, supported comma-separated workload selection.
(define (benchmark-workload-list text)
  (define names
    (map string->symbol (string-split text ",")))
  (unless (and (pair? names)
               (= (length names) (length (remove-duplicates names)))
               (andmap (lambda (name) (memq name (benchmark-workload-names)))
                       names))
    (raise-user-error 'benchmark-process-rendering
                      "--workloads needs distinct supported names: ~a"
                      (string-join (map symbol->string (benchmark-workload-names)) ",")))
  names)

; current-benchmark-workload-names : (parameter/c (or/c #f (listof symbol?)))
;;   Selects a validated workload subset for one benchmark invocation.
(define current-benchmark-workload-names
  (make-parameter #f))

; current-benchmark-matrix-only? : (parameter/c boolean?)
;;   Selects primary scaling measurements without supplemental observations.
(define current-benchmark-matrix-only?
  (make-parameter #f))

; selected-representative-workloads : -> (listof benchmark-workload?)
;;   Returns representative workloads filtered in their stable report order.
(define (selected-representative-workloads)
  (define selection (current-benchmark-workload-names))
  (filter (lambda (workload)
            (or (not selection)
                (memq (benchmark-workload-name workload) selection)))
          (representative-workloads)))


;;;
;;; Command-Line Validation
;;;

; positive-integer : symbol? string? -> exact-positive-integer?
;;   Parses one positive integer command-line value with an actionable error.
(define (positive-integer who text)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-user-error who "expected a positive integer, got ~s" text))
  value)

; worker-list : string? -> (listof exact-positive-integer?)
;;   Parses a distinct comma-separated capacity list in requested measurement order.
(define (worker-list text)
  (define values
    (for/list ([piece (in-list (string-split text ","))])
      (positive-integer 'benchmark-process-rendering piece)))
  (unless (and (pair? values) (= (length values) (length (remove-duplicates values))))
    (raise-user-error 'benchmark-process-rendering
                      "--workers needs one or more distinct positive integers"))
  values)

; current-run-label : -> string?
;;   Gives a sortable, collision-resistant label for one benchmark-owned run root.
(define (current-run-label)
  (define now (seconds->date (current-seconds) #t))
  (format "~a-~a-~aT~a~a~a-~a"
          (~r (date-year now) #:min-width 4 #:pad-string "0")
          (~r (date-month now) #:min-width 2 #:pad-string "0")
          (~r (date-day now) #:min-width 2 #:pad-string "0")
          (~r (date-hour now) #:min-width 2 #:pad-string "0")
          (~r (date-minute now) #:min-width 2 #:pad-string "0")
          (~r (date-second now) #:min-width 2 #:pad-string "0")
          (gensym 'benchmark)))


;;;
;;; Project Declarations
;;;

; workload-project : benchmark-workload? path-string? exact-positive-integer?
;                    exact-positive-integer? exact-positive-integer?
;                    exact-positive-integer? symbol? -> animate-project?
;;   Constructs the same restartable source declaration used by the migrated CLIs.
(define (workload-project workload root workers fps width height format)
  (define domain (benchmark-workload-domain workload))
  (define source (benchmark-workload-source workload))
  (define source-options
    (case domain
      [(geometry)
       (hasheq 'width width
               'height height
               'fps fps
               'theme-mode 'dark
               'captions? #t)]
      [(math)
       (hasheq 'lesson 'quadratic-general
               'case-path #f
               'title "quadratic general"
               'theme-mode 'dark
               'width width
               'height height
               'fps fps
               'supersample 1)]
      [else
       (raise-arguments-error 'workload-project "a supported benchmark domain"
                              "domain" domain)]))
  (animate-project
   #:id (benchmark-workload-name workload)
   #:source
   (module-builder-source
    source
    (case domain
      [(geometry) 'geometry-render-builder]
      [(math) 'math-render-builder])
    #:prepare
    (case domain
      [(geometry) 'geometry-render-preparer]
      [(math) 'math-render-preparer])
    #:options source-options)
   #:render
   (render-spec #:fps fps
                #:width width
                #:height height
                #:supersample 1
                #:workers workers
                ;; This deliberately leaves capacity-one execution to the
                ;; ordinary automatic policy, while higher capacities select
                ;; the existing generic subprocess executor.
                #:worker-mode 'auto
                #:theme animate-dark-theme)
   #:output
   (output-spec #:root root
                #:name (if (eq? format 'mp4) "movie" "frames")
                #:format format
                #:write-frame-sequence? (eq? format 'mp4)
                #:overwrite-policy 'replace)
   #:encoder (if (eq? format 'mp4)
                 (encoder-spec)
                 (encoder-spec #:codec 'none))
   ;; The current generic frame cache is published with the frame root.  This
   ;; declaration remains explicit for cache-domain identity and future cache
   ;; implementations, and every root here is benchmark-owned.
   #:cache (cache-spec #:root (build-path root "cache") #:policy 'read-write)))


;;;
;;; Process and Frame Evidence
;;;

; monotonic-milliseconds : -> nonnegative-real?
;;   Returns a process-local monotonic timestamp suitable for elapsed timing.
(define (monotonic-milliseconds)
  (current-inexact-monotonic-milliseconds))

; path-list->strings : (listof path?) -> (listof string?)
;;   Converts report paths to stable absolute strings for machine-readable output.
(define (path-list->strings paths)
  (map (lambda (path) (path->string (simplify-path (path->complete-path path)))) paths))

; byte->hex : byte? -> string?
;;   Converts one digest byte to its stable two-character lower-case hex spelling.
(define (byte->hex value)
  (define text (number->string value 16))
  (if (= (string-length text) 1) (string-append "0" text) text))

; sha256-file : path-string? -> string?
;;   Gives the complete SHA-256 content digest for one finished output frame.
(define (sha256-file path)
  (string-join
   (for/list ([value (in-bytes (sha256-bytes (file->bytes path)))])
     (byte->hex value))
   ""))

; frame-digest-manifest : (listof path?) -> immutable-hash?
;;   Captures complete per-frame names, byte counts, and SHA-256 identities before
;;   the harness releases its just-verified PNG directory.
(define (frame-digest-manifest paths)
  (define entries
    (for/list ([path (in-list paths)] [index (in-naturals 0)])
      (hasheq 'index index
              'name (path->string (file-name-from-path path))
              'byte-count (file-size path)
              'sha256 (sha256-file path))))
  (hasheq 'schema 'animate-frame-digest-manifest-v1
          'frame-count (length entries)
          'entries entries))

; frame-comparison : immutable-hash? immutable-hash? -> immutable-hash?
;;   Compares every candidate frame's complete SHA-256/size/name record against
;;   the compact one-worker oracle after neither directory needs to be retained.
(define (frame-comparison baseline candidate)
  (define baseline-entries (hash-ref baseline 'entries))
  (define candidate-entries (hash-ref candidate 'entries))
  (define same-count? (= (length baseline-entries) (length candidate-entries)))
  (define mismatch-details
    (for/list ([left (in-list baseline-entries)]
               [right (in-list candidate-entries)]
               #:unless (equal? left right))
      (hasheq 'index (hash-ref left 'index)
              'expected left
              'actual right)))
  (hasheq 'oracle-frame-count (length baseline-entries)
          'candidate-frame-count (length candidate-entries)
          'same-frame-count? same-count?
          'oracle-manifest baseline
          'candidate-manifest candidate
          'byte-identical? (and same-count? (null? mismatch-details))
          'mismatch-count (length mismatch-details)
          'mismatches mismatch-details))

; worker-assignment-counts : (or/c process-frame-execution-report? false/c)
;                             -> immutable-hash?
;;   Counts completed subprocess jobs by parent-observed worker PID.
(define (worker-assignment-counts subprocess-report)
  (if subprocess-report
      (for/fold ([counts #hasheq()])
                ([assignment
                  (in-list
                   (process-frame-execution-report-assignments subprocess-report))])
        (define pid (process-frame-assignment-worker-pid assignment))
        (hash-set counts pid (add1 (hash-ref counts pid 0))))
      #hasheq()))

; resources-closed? : (or/c process-frame-execution-report? false/c) -> boolean?
;;   Confirms every parent-observed subprocess resource closed after execution.
(define (resources-closed? subprocess-report)
  (or (not subprocess-report)
      (for/and ([status
                 (in-list
                  (process-frame-execution-report-worker-resource-statuses
                   subprocess-report))])
        (and (not (hash-ref status 'open? #t))
             (hash-ref status 'input-closed? #f)
             (hash-ref status 'output-closed? #f)
             (hash-ref status 'error-closed? #f)
             (hash-ref status 'reader-dead? #f)
             (hash-ref status 'error-reader-dead? #f)))))

; owned-staging-leftovers : path-string? -> (listof string?)
;;   Lists only executor-owned staging directories left in one benchmark frame root.
(define (owned-staging-leftovers root)
  (if (directory-exists? root)
      (for/list ([entry (in-list (directory-list root #:build? #t))]
                 #:when (and (directory-exists? entry)
                             (regexp-match? #rx"^\\.animate-process-frame-"
                                            (path->string (file-name-from-path entry)))))
        (path->string entry))
      '()))

; file-line-count : path-string? -> exact-nonnegative-integer?
;;   Counts the complete newline-delimited observer log without interpreting its data.
(define (file-line-count path)
  (if (file-exists? path)
      (call-with-input-file path
        (lambda (in)
          (let loop ([count 0])
            (define line (read-line in 'any))
            (if (eof-object? line) count (loop (add1 count))))))
      0))


;;;
;;; One Measured Invocation
;;;

; run-workload-once! : benchmark-workload? path-string? exact-positive-integer?
;                       exact-positive-integer? exact-positive-integer?
;                       exact-positive-integer? symbol? (or/c list? false/c)
;                       path-string? path-string? -> immutable-hash?
;;   Runs one complete project invocation and returns parent-observed stage facts.
(define (run-workload-once! workload root workers fps width height format baseline
                            preparation-log typeset-log #:allow-existing? [allow-existing? #f])
  (when (and (directory-exists? root) (not allow-existing?))
    (raise-arguments-error 'run-workload-once!
                           "a fresh benchmark-owned invocation directory"
                           "root" root))
  (unless (directory-exists? root) (make-directory* root))
  (define project (workload-project workload root workers fps width height format))
  (define parent-preparations 0)
  (define parent-typesets 0)
  (define preparation-log-before (file-line-count preparation-log))
  (define typeset-log-before (file-line-count typeset-log))
  (define original-preparation-observer
    (math-preparation:current-math-preparation-observer))
  (define original-typeset-observer
    (math-typeset:current-math-typeset-observer))
  (define plan-started (monotonic-milliseconds))
  (define plan (plan-project project #:directory root))
  (define planning-milliseconds (- (monotonic-milliseconds) plan-started))
  (define prepared
    (parameterize
        ([math-preparation:current-math-preparation-observer
          (lambda (presentation-plan)
            (set! parent-preparations (add1 parent-preparations))
            (original-preparation-observer presentation-plan))]
         [math-typeset:current-math-typeset-observer
          (lambda (state)
            (set! parent-typesets (add1 parent-typesets))
            (original-typeset-observer state))])
      (prepare-project! plan)))
  (define preparation-manifest
    (prepared-project-preparation-manifest prepared))
  (define input-manifest
    (prepared-project-input-manifest prepared))
  (define preparation-milliseconds
    (prepared-project-preparation-elapsed-milliseconds prepared))
  (define execution-started (monotonic-milliseconds))
  (define report
    (execute-prepared-project! prepared #:open-after? #f))
  (define execution-wall-milliseconds (- (monotonic-milliseconds) execution-started))
  (define diagnostics (project-execution-report-diagnostics report))
  (define subprocess-report
    (project-frame-execution-diagnostics-subprocess-report diagnostics))
  (define frame-paths
    (hash-ref (project-execution-report-artifact-paths report) 'frames '()))
  (define frame-manifest (frame-digest-manifest frame-paths))
  (define comparison
    (and baseline (frame-comparison baseline frame-manifest)))
  (define work
    (project-frame-execution-diagnostics-work-accounting diagnostics))
  (define primary
    (hash-ref (project-execution-report-artifact-paths report) 'primary #f))
  (define preparation-log-after (file-line-count preparation-log))
  (define typeset-log-after (file-line-count typeset-log))
  (hasheq
   'workload (benchmark-workload-name workload)
   'domain (benchmark-workload-domain workload)
   'format format
   'root (path->string (simplify-path (path->complete-path root)))
   'primary-output (and primary (path->string (simplify-path (path->complete-path primary))))
   'frame-manifest frame-manifest
   'mode (project-frame-execution-diagnostics-mode diagnostics)
   'workers-requested workers
   'workers-started (project-frame-execution-diagnostics-workers-started diagnostics)
   'workers-completing (project-frame-execution-diagnostics-workers-completing diagnostics)
   'worker-pids (if subprocess-report
                    (process-frame-execution-report-worker-pids subprocess-report)
                    '())
   'worker-assignment-counts (worker-assignment-counts subprocess-report)
   'worker-resources-closed? (resources-closed? subprocess-report)
   'owned-staging-leftovers (owned-staging-leftovers root)
   'planning-milliseconds planning-milliseconds
   'parent-preparation-milliseconds preparation-milliseconds
   'execution-wall-milliseconds execution-wall-milliseconds
   'frame-execution-milliseconds
   (project-frame-execution-diagnostics-elapsed-milliseconds diagnostics)
   'worker-startup-milliseconds
   (and subprocess-report
        (process-frame-execution-report-startup-milliseconds subprocess-report))
   'worker-timings
   (and subprocess-report
        (process-frame-execution-report-worker-timings subprocess-report))
   'raster-execution-milliseconds
   (and subprocess-report
        (process-frame-execution-report-raster-execution-milliseconds subprocess-report))
   'publication-milliseconds
   (and subprocess-report
        (process-frame-execution-report-publication-milliseconds subprocess-report))
   'preparation-verification-milliseconds-exposed? #f
   'parent-math-preparation-count parent-preparations
   'parent-math-typeset-count parent-typesets
   'preparation-manifest-identity
   (and preparation-manifest
        (render-preparation-manifest-identity preparation-manifest))
   'preparation-payload-identity
   (and preparation-manifest
        (hash-ref preparation-manifest 'payload-identity))
   'preparation-artifacts
   (and preparation-manifest
        (hash-ref preparation-manifest 'artifacts))
   'input-manifest-identity
   (and input-manifest (render-input-manifest-identity input-manifest))
   'environment-preparation-event-count
   (- preparation-log-after preparation-log-before)
   'environment-typeset-event-count (- typeset-log-after typeset-log-before)
   'requested-frame-count
   (project-frame-execution-diagnostics-requested-frame-count diagnostics)
   'rendered-frame-count
   (project-frame-execution-diagnostics-rendered-frame-count diagnostics)
   'reused-frame-count
   (project-frame-execution-diagnostics-reused-frame-count diagnostics)
   'persistent-frame-cache-hits (hash-ref work 'persistent-frame-cache-hits)
   'frame-reuse-aliases (hash-ref work 'frame-reuse-aliases)
   'representative-raster-jobs (hash-ref work 'representative-raster-jobs)
   'frames-rasterized (hash-ref work 'frames-rasterized)
   'materialized-output-frames (hash-ref work 'materialized-output-frames)
   'input-verification-events (hash-ref work 'input-verification-events)
   'input-verification-failures (hash-ref work 'input-verification-failures)
   'comparison comparison))

; prepare-workload-once! : benchmark-workload? path-string? exact-positive-integer?
;                           exact-positive-integer? exact-positive-integer?
;                           exact-positive-integer? -> immutable-hash?
;;   Runs only the existing project planning/preparation lifecycle in one fresh
;;   parent.  It exposes the data that actually participates in the persistent
;;   frame key without starting workers or producing a frame directory.
(define (prepare-workload-once! workload root workers fps width height)
  (when (directory-exists? root)
    (raise-arguments-error 'prepare-workload-once!
                           "a fresh benchmark-owned preparation directory"
                           "root" root))
  (make-directory* root)
  (define project (workload-project workload root workers fps width height 'png-sequence))
  (define planning-started (monotonic-milliseconds))
  (define plan (plan-project project #:directory root))
  (define planning-milliseconds (- (monotonic-milliseconds) planning-started))
  (define prepared (prepare-project! plan))
  (define manifest (prepared-project-preparation-manifest prepared))
  (unless manifest
    (raise-arguments-error 'prepare-workload-once!
                           "a prepared source manifest"
                           "workload" workload))
  (hasheq 'workload (benchmark-workload-name workload)
          'root (path->string (simplify-path (path->complete-path root)))
          'planning-milliseconds planning-milliseconds
          'parent-preparation-milliseconds
          (prepared-project-preparation-elapsed-milliseconds prepared)
          'manifest-identity (render-preparation-manifest-identity manifest)
          'payload-identity (hash-ref manifest 'payload-identity)
          'input-manifest-identity
          (render-input-manifest-identity
           (render-preparation-manifest-input-manifest manifest))
          'artifacts (hash-ref manifest 'artifacts)
          'payload (hash-ref manifest 'payload)))

; write-datum-file! : path-string? any/c -> void?
;;   Writes one private benchmark child result using Racket's readable data format.
(define (write-datum-file! path value)
  (call-with-output-file path
    (lambda (out) (write value out) (newline out))
    #:exists 'truncate/replace))

; read-datum-file! : path-string? -> any/c
;;   Reads one completed private benchmark child result after its process exits.
(define (read-datum-file! path)
  (call-with-input-file path read))

; make-fresh-parent-runner : path-string? path-string? exact-positive-integer?
;                           exact-positive-integer? exact-positive-integer?
;                           -> procedure?
;;   Returns a runner that gives every measurement a fresh parent Racket process.
(define (make-fresh-parent-runner preparation-log typeset-log fps width height)
  (lambda (workload root workers format allow-existing?)
    (define result-path (build-path root ".benchmark-result.rktd"))
    (define arguments
      (append
       (list (path->string (simplify-path benchmark-tool))
             "--single"
             "--workload" (symbol->string (benchmark-workload-name workload))
             "--root" (path->string (simplify-path (path->complete-path root)))
             "--workers" (number->string workers)
             "--format" (symbol->string format)
             "--fps" (number->string fps)
             "--width" (number->string width)
             "--height" (number->string height)
             "--result" (path->string (simplify-path (path->complete-path result-path)))
             "--preparation-log" preparation-log
             "--typeset-log" typeset-log)
       (if allow-existing? (list "--allow-existing") '())))
    (unless (apply system* (find-system-path 'exec-file) arguments)
      (raise-user-error 'benchmark-process-rendering
                        "single measurement failed for ~a with ~a workers; inspect ~a"
                        (benchmark-workload-name workload) workers root))
    (read-datum-file! result-path)))

; make-fresh-preparation-runner : exact-positive-integer? exact-positive-integer?
;                                  exact-positive-integer? -> procedure?
;;   Returns a runner for fresh-parent preparation-identity observations only.
(define (make-fresh-preparation-runner fps width height)
  (lambda (workload root workers)
    (define result-path (build-path root ".benchmark-preparation.rktd"))
    (define arguments
      (list (path->string (simplify-path benchmark-tool))
            "--prepare-only"
            "--workload" (symbol->string (benchmark-workload-name workload))
            "--root" (path->string (simplify-path (path->complete-path root)))
            "--workers" (number->string workers)
            "--fps" (number->string fps)
            "--width" (number->string width)
            "--height" (number->string height)
            "--result" (path->string (simplify-path (path->complete-path result-path)))))
    (unless (apply system* (find-system-path 'exec-file) arguments)
      (raise-user-error 'benchmark-process-rendering
                        "preparation-only measurement failed for ~a; inspect ~a"
                        (benchmark-workload-name workload) root))
    (read-datum-file! result-path)))


;;;
;;; Aggregation and Serialization
;;;

; median : (listof real?) -> real?
;;   Computes the central value without choosing only the best benchmark run.
(define (median values)
  (define ordered (sort values <))
  (define count (length ordered))
  (cond [(zero? count) 0]
        [(odd? count) (list-ref ordered (quotient count 2))]
        [else (/ (+ (list-ref ordered (sub1 (quotient count 2)))
                    (list-ref ordered (quotient count 2)))
                 2)]))

; timing-summary : (listof immutable-hash?) -> immutable-hash?
;;   Summarizes raw frame-execution timings for one workload/capacity cell.
(define (timing-summary measurements)
  (define times (map (lambda (measurement)
                       (hash-ref measurement 'frame-execution-milliseconds))
                     measurements))
  (hasheq 'individual-milliseconds times
          'median-milliseconds (median times)
          'minimum-milliseconds (if (null? times) 0 (apply min times))
          'maximum-milliseconds (if (null? times) 0 (apply max times))))

; json-value : any/c -> jsexpr?
;;   Converts report symbols, paths, and immutable hashes into JSON-compatible data.
(define (json-value value)
  (cond [(symbol? value) (symbol->string value)]
        [(path? value) (path->string value)]
        ;; Racket's JSON writer accepts exact integers but rejects exact
        ;; fractions (such as prepared math layout coordinates).  Preserve
        ;; their numeric value in the machine-readable benchmark record.
        [(and (number? value) (exact? value) (rational? value) (not (integer? value)))
         (exact->inexact value)]
        [(hash? value)
         (for/hash ([(key item) (in-hash value)])
           ;; racket/json's writer represents object keys as symbols.  Keep
           ;; the converted keys in that form rather than producing strings,
           ;; which it rejects after opening the output object.
           (values (cond [(symbol? key) key]
                         [(string? key) (string->symbol key)]
                         [else (string->symbol (format "~a" key))])
                   (json-value item)))]
        [(vector? value) (map json-value (vector->list value))]
        [(list? value) (map json-value value)]
        [else value]))

; write-json-file! : path-string? any/c -> void?
;;   Writes one complete JSON result only after all selected measurements finish.
(define (write-json-file! path value)
  (call-with-output-file path
    (lambda (out) (write-json (json-value value) out) (newline out))
    #:exists 'truncate/replace))

; tsv-field : any/c -> string?
;;   Converts one scalar to a tab-safe representation for spreadsheet import.
(define (tsv-field value)
  (regexp-replace* #px"[\t\r\n]" (format "~a" value) " "))

; write-tsv-file! : path-string? (listof immutable-hash?) -> void?
;;   Emits the raw primary frame-run observations in a compact tabular format.
(define (write-tsv-file! path measurements)
  (define columns
    '(workload domain repetition workers-requested mode workers-started workers-completing
               requested-frame-count persistent-frame-cache-hits frame-reuse-aliases
               representative-raster-jobs frames-rasterized frame-execution-milliseconds
               parent-preparation-milliseconds worker-startup-milliseconds
               byte-identical? mismatch-count worker-resources-closed?))
  (call-with-output-file path
    (lambda (out)
      (fprintf out "~a\n" (string-join (map symbol->string columns) "\t"))
      (for ([measurement (in-list measurements)])
        (define comparison (hash-ref measurement 'comparison #f))
        (define values
          (list (hash-ref measurement 'workload)
                (hash-ref measurement 'domain)
                (hash-ref measurement 'repetition)
                (hash-ref measurement 'workers-requested)
                (hash-ref measurement 'mode)
                (hash-ref measurement 'workers-started)
                (hash-ref measurement 'workers-completing)
                (hash-ref measurement 'requested-frame-count)
                (hash-ref measurement 'persistent-frame-cache-hits)
                (hash-ref measurement 'frame-reuse-aliases)
                (hash-ref measurement 'representative-raster-jobs)
                (hash-ref measurement 'frames-rasterized)
                (hash-ref measurement 'frame-execution-milliseconds)
                (hash-ref measurement 'parent-preparation-milliseconds)
                (or (hash-ref measurement 'worker-startup-milliseconds) "")
                (and comparison (hash-ref comparison 'byte-identical?))
                (if comparison (hash-ref comparison 'mismatch-count) "")
                (hash-ref measurement 'worker-resources-closed?)))
        (fprintf out "~a\n" (string-join (map tsv-field values) "\t"))))
    #:exists 'truncate/replace))


;;;
;;; Benchmark Matrix
;;;

; measurement-root : path-string? symbol? exact-positive-integer? exact-positive-integer? -> path?
;;   Names one fresh, benchmark-owned directory for a frame-only matrix cell.
(define (measurement-root run-root workload workers repetition)
  (build-path run-root "frame-runs"
              (symbol->string workload)
              (format "workers-~a-repetition-~a" workers repetition)))

; remove-owned-invocation! : path-string? -> void?
;;   Releases only one completed, run-labelled harness invocation directory.
(define (remove-owned-invocation! root)
  (define normalized (simplify-path (path->complete-path root)))
  ;; `path-only` returns directory-form paths, for which `file-name-from-path`
  ;; intentionally returns #f.  Match the complete normalized macOS path so
  ;; the guard accepts only children of the dated run directory this harness
  ;; allocated, never an arbitrary caller output root.
  (unless (regexp-match?
           #px"/runs/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{6}-benchmark[^/]*/"
           (path->string normalized))
    (raise-arguments-error
     'remove-owned-invocation!
     "a benchmark-created child of its dated runs directory"
     "root" root))
  (when (directory-exists? normalized)
    (delete-directory/files normalized)))

; remove-owned-frame-artifacts! : path-string? -> void?
;;   Releases an MP4 invocation's regenerable frame/cache artifacts while keeping its video.
(define (remove-owned-frame-artifacts! root)
  (for ([name (in-list '("cache" "frames"))])
    (define path (build-path root name))
    (when (directory-exists? path)
      (delete-directory/files path))))

; run-primary-matrix! : procedure? (listof benchmark-workload?) path-string?
;                        (listof exact-positive-integer?) exact-positive-integer?
;                        exact-positive-integer? exact-positive-integer?
;                        exact-positive-integer? path-string? path-string?
;                        -> (values list? immutable-hash?)
;;   Executes warm-up plus fresh-cache 1/2/4/10 frame measurements and byte checks.
(define (run-primary-matrix! run-one workloads run-root workers repetitions fps width height
                             preparation-log typeset-log)
  (define all-measurements '())
  (define summaries #hasheq())
  ;; Keep worker one first because it supplies the byte oracle, then launch the
  ;; largest requested process pool before repeated lower-capacity sessions.
  ;; This is still the ordinary auto policy; only benchmark measurement order
  ;; changes.  It avoids a demonstrated host-local repeated-session startup
  ;; spin without hiding the ten-worker observation.
  (define measurement-workers
    (append (filter (lambda (count) (= count 1)) workers)
            (filter (lambda (count) (= count 10)) workers)
            (filter (lambda (count) (and (not (= count 1)) (not (= count 10))))
                    workers)))
  (for ([workload (in-list workloads)])
    ;; Warm-up deliberately has its own fresh output/cache root and is omitted
    ;; from all medians.  It settles loader, font, and process-launch effects.
    (define warmup-root
      (build-path run-root "warmup" (symbol->string (benchmark-workload-name workload))))
    (run-one workload warmup-root 1 'png-sequence #f)
    (remove-owned-invocation! warmup-root)
    (define baseline #f)
    (for ([worker-count (in-list measurement-workers)])
      (define measurements '())
      (let loop ([repetition 1])
        (when (<= repetition repetitions)
          (define root
            (measurement-root run-root (benchmark-workload-name workload)
                              worker-count repetition))
          (define raw-result (run-one workload root worker-count 'png-sequence #f))
          (define result
            (hash-set
             (if baseline
                 (hash-set raw-result 'comparison
                           (frame-comparison baseline
                                             (hash-ref raw-result 'frame-manifest)))
                 raw-result)
             'repetition repetition))
          (unless baseline
            (set! baseline
                  (hash-ref result 'frame-manifest)))
          (set! measurements (append measurements (list result)))
          (set! all-measurements (append all-measurements (list result)))
          ;; The per-frame digest manifest above is the retained one-worker
          ;; oracle.  Every just-rendered PNG/cache directory is now safe to
          ;; release, including the oracle itself.
          (remove-owned-invocation! (hash-ref result 'root))
          (loop (add1 repetition))))
      (define summary (timing-summary measurements))
      (set! summaries
            (hash-set summaries
                      (format "~a/workers-~a" (benchmark-workload-name workload)
                              worker-count)
                      summary)))
    ;; The one-worker oracle remains as data in each comparison, never as a
    ;; retained image directory.
    (void))
  (values all-measurements summaries))

; run-cache-hit-observations! : procedure? (listof benchmark-workload?) path-string?
;                                exact-positive-integer? exact-positive-integer?
;                                exact-positive-integer? path-string? path-string?
;                                -> list?
;;   Demonstrates complete frame-cache reuse with a requested ten-worker policy.
(define (run-cache-hit-observations! run-one workloads run-root fps width height
                                     preparation-log typeset-log)
  (for/list ([workload (in-list workloads)])
    (define root
      (build-path run-root "cache-hit" (symbol->string (benchmark-workload-name workload))))
    (define populated
      (run-one workload root 1 'png-sequence #f))
    (define raw-hit
      (run-one workload root 10 'png-sequence #t))
    (define hit
      (hash-set
       raw-hit
       'comparison
       (frame-comparison (hash-ref populated 'frame-manifest)
                         (hash-ref raw-hit 'frame-manifest))))
    (define observation
      (hasheq 'workload (benchmark-workload-name workload)
              'populate populated
              'cache-hit hit))
    (remove-owned-invocation! root)
    observation))

; payload-asset-uses : immutable-hash? -> list?
;;   Associates every staged SVG with the stable prepared token that consumes it.
(define (payload-asset-uses payload)
  (append-map
   (lambda (layout)
     (define state-key (hash-ref layout 'state-key))
     (for/list ([token (in-list (vector->list (hash-ref layout 'tokens)))])
       (hasheq 'state-key state-key
               'path (hash-ref token 'path)
               'role (hash-ref token 'role)
               'text (hash-ref token 'text)
               'id (hash-ref token 'id)
               'asset (hash-ref token 'asset))))
   (vector->list (hash-ref payload 'layouts))))

; asset-use-key : immutable-hash? -> list?
;;   Names one SVG consumer without including its concrete staged path.
(define (asset-use-key use)
  (list (hash-ref use 'state-key)
        (hash-ref use 'path)
        (hash-ref use 'role)
        (hash-ref use 'text)
        (hash-ref use 'id)))

; strip-payload-artifact-paths : any/c -> any/c
;;   Removes only concrete SVG staging addresses from a payload comparison.
(define (strip-payload-artifact-paths value)
  (cond
    [(hash? value)
     (for/hash ([(key item) (in-hash value)])
       (values key
               (cond [(eq? key 'asset) '<staged-svg>]
                     [(eq? key 'artifacts) '<staged-svg-set>]
                     [else (strip-payload-artifact-paths item)])))]
    [(vector? value)
     (vector->immutable-vector
      (list->vector (map strip-payload-artifact-paths (vector->list value))))]
    [(list? value) (map strip-payload-artifact-paths value)]
    [else value]))

; artifact-map : list? -> immutable-hash?
;;   Indexes manifest artifact records by their concrete verified staging path.
(define (artifact-map artifacts)
  (for/hash ([artifact (in-list artifacts)])
    (values (hash-ref artifact 'path) artifact)))

; changed-prepared-assets : immutable-hash? immutable-hash? -> list?
;;   Identifies every semantically corresponding token whose verified staged SVG
;;   content changed across fresh parents, with no claim of visual equivalence.
(define (changed-prepared-assets first second)
  (define first-uses
    (for/hash ([use (in-list (payload-asset-uses (hash-ref first 'payload)))])
      (values (asset-use-key use) use)))
  (define second-uses
    (for/hash ([use (in-list (payload-asset-uses (hash-ref second 'payload)))])
      (values (asset-use-key use) use)))
  (define first-artifacts (artifact-map (hash-ref first 'artifacts)))
  (define second-artifacts (artifact-map (hash-ref second 'artifacts)))
  (for/list ([key (in-list (sort (hash-keys first-uses)
                                  string<? #:key (lambda (value) (format "~s" value))))]
             #:when (and (hash-has-key? second-uses key)
                         (not (equal? (hash-ref (hash-ref first-uses key) 'asset)
                                      (hash-ref (hash-ref second-uses key) 'asset)))))
    (define first-use (hash-ref first-uses key))
    (define second-use (hash-ref second-uses key))
    (hasheq 'consumer key
            'first-artifact
            (hash-ref first-artifacts (hash-ref first-use 'asset))
            'second-artifact
            (hash-ref second-artifacts (hash-ref second-use 'asset)))))

; preparation-record-summary : immutable-hash? -> immutable-hash?
;;   Omits the full portable layout payload after the probe has compared it.
;;   The JSON evidence retains every verified artifact delta and its semantic
;;   consumer without serializing hundreds of non-cache diagnostic coordinates.
(define (preparation-record-summary record)
  (hash-remove record 'payload))

; run-math-preparation-identity-probe! : path-string? exact-positive-integer?
;                                          exact-positive-integer? exact-positive-integer?
;                                          -> immutable-hash?
;;   Compares two fresh-parent preparations using the same profile/cache root.
(define (run-math-preparation-identity-probe! run-root fps width height)
  (define workload (second (representative-workloads)))
  (define run-preparation
    (make-fresh-preparation-runner fps width height))
  (define first-root (build-path run-root "math-preparation-identity" "first"))
  (define second-root (build-path run-root "math-preparation-identity" "second"))
  (define first-preparation (run-preparation workload first-root 1))
  (define second-preparation (run-preparation workload second-root 1))
  (define changed (changed-prepared-assets first-preparation second-preparation))
  (define result
    (hasheq 'first (preparation-record-summary first-preparation)
            'second (preparation-record-summary second-preparation)
            'same-input-manifest?
            (equal? (hash-ref first-preparation 'input-manifest-identity)
                    (hash-ref second-preparation 'input-manifest-identity))
            'same-preparation-manifest?
            (equal? (hash-ref first-preparation 'manifest-identity)
                    (hash-ref second-preparation 'manifest-identity))
            'same-payload?
            (equal? (hash-ref first-preparation 'payload)
                    (hash-ref second-preparation 'payload))
            'same-payload-without-staging-paths?
            (equal? (strip-payload-artifact-paths (hash-ref first-preparation 'payload))
                    (strip-payload-artifact-paths (hash-ref second-preparation 'payload)))
            'changed-semantic-asset-count (length changed)
            'changed-semantic-assets changed))
  ;; The asset copies are source-owned preparation artifacts.  These two empty
  ;; output roots are the only probe directories released by the harness.
  (remove-owned-invocation! first-root)
  (remove-owned-invocation! second-root)
  result)

; run-mp4-observations! : procedure? (listof benchmark-workload?) path-string?
;                          exact-positive-integer? exact-positive-integer?
;                          exact-positive-integer? path-string? path-string? -> list?
;;   Measures one parent-side MP4 assembly each for normal one- and ten-worker paths.
(define (run-mp4-observations! run-one workloads run-root fps width height
                               preparation-log typeset-log)
  (for*/list ([workload (in-list workloads)] [workers (in-list '(1 10))])
    (define root
      (build-path run-root "mp4-runs" (symbol->string (benchmark-workload-name workload))
                  (format "workers-~a" workers)))
    (define observation
      (hash-set
       (run-one workload root workers 'mp4 #f)
       'repetition 1))
    (remove-owned-frame-artifacts! root)
    observation))


;;;
;;; Environment Freeze and Driver
;;;

; shell-output : string? (listof string?) -> string?
;;   Captures a short diagnostic command without making benchmark success depend on it.
(define (shell-output executable arguments)
  (with-handlers ([exn:fail? (lambda (error) (format "unavailable: ~a" (exn-message error)))])
    (define output (open-output-string))
    (define resolved-executable
      (or (and (path-string? executable)
               (absolute-path? (string->path executable))
               executable)
          (find-executable-path executable)
          executable))
    (parameterize ([current-output-port output]
                   [current-error-port output])
      (apply system* resolved-executable arguments))
    (string-trim (get-output-string output))))

; collection-identity : -> string?
;;   Resolves the current animate collection for recording and wrong-link detection.
(define (collection-identity)
  (path->string
   (simplify-path
    (path->complete-path (collection-file-path "main.rkt" "animate")))))

; frozen-environment : path-string? -> immutable-hash?
;;   Records the local executable and host facts available without privileged inspection.
(define (frozen-environment output-root)
  (hasheq
   'repository-root (path->string (simplify-path (path->complete-path repository-root)))
   'collection-main (collection-identity)
   'racket-executable (path->string (find-system-path 'exec-file))
   'racket-version (version)
   'machine-architecture (system-type 'arch)
   'logical-processors "unavailable: sandbox denies sysctl hw.logicalcpu/hw.ncpu"
   'macos-version (shell-output "/usr/bin/sw_vers" '("-productVersion"))
   'ffmpeg-version (shell-output "ffmpeg" '("-version"))
   'latex-version (shell-output "/Library/TeX/texbin/latex" '("--version"))
   'dvisvgm-version (shell-output "/Library/TeX/texbin/dvisvgm" '("--version"))
   'animate-version (dynamic-require (build-path repository-root "version.rkt") 'animate-version)
   'animate-stage (dynamic-require (build-path repository-root "version.rkt") 'animate-stage)
   'output-root (path->string (simplify-path (path->complete-path output-root)))))

; benchmark-command : path-string? exact-positive-integer? string? -> string?
;;   Gives a copyable command that reproduces the recorded benchmark configuration.
(define (benchmark-command output repetitions workers)
  (format "~a tools/benchmark-process-rendering.rkt --output ~a --repetitions ~a --workers ~a"
          (path->string (find-system-path 'exec-file)) output repetitions workers))

; run-process-rendering-benchmark! : path-string? (listof exact-positive-integer?)
;                                    exact-positive-integer? exact-positive-integer?
;                                    exact-positive-integer? exact-positive-integer? -> immutable-hash?
;;   Executes the complete PR-H evidence matrix in the current isolated process.
(define (run-process-rendering-benchmark! output-root workers repetitions fps width height)
  (define expected-main
    (path->string (simplify-path (build-path repository-root "main.rkt"))))
  (unless (equal? (collection-identity) expected-main)
    (raise-arguments-error
     'run-process-rendering-benchmark!
     "checkout-first animate collection resolution"
     "resolved-animate-main" (collection-identity)
     "expected-animate-main" expected-main))
  (make-directory* output-root)
  (define run-root (build-path output-root "runs" (current-run-label)))
  (make-directory* run-root)
  (define preparation-log
    (or (getenv "ANIMATE_MATH_PREPARATION_EVENT_LOG")
        (path->string (build-path run-root "math-preparation-events.log"))))
  (define typeset-log
    (or (getenv "ANIMATE_MATH_TYPESET_EVENT_LOG")
        (path->string (build-path run-root "math-typeset-events.log"))))
  (define workloads (selected-representative-workloads))
  (define matrix-only? (current-benchmark-matrix-only?))
  (define math-workload
    (for/first ([workload (in-list workloads)]
                #:when (eq? (benchmark-workload-domain workload) 'math))
      workload))
  ;; Each record is measured by a fresh Racket parent process.  This matches
  ;; normal explicit CLI execution and avoids retaining supervisor/session
  ;; state across a long benchmark matrix.
  (define run-one
    (make-fresh-parent-runner preparation-log typeset-log fps width height))
  ;; A fresh preference root makes this a real cold SVG-cache observation.  It
  ;; is intentionally separate from the warm scaling matrix and is never
  ;; deleted by this tool.
  (define cold-math
    (and (not matrix-only?)
         math-workload
         (run-one math-workload (build-path run-root "cold-math") 1 'png-sequence #f)))
  (when cold-math
    (remove-owned-invocation! (hash-ref cold-math 'root)))
  ;; Record actual end-to-end parent-side MP4 assembly while the ten-worker
  ;; child pools are still early in this isolated process's lifetime.
  (define mp4-observations
    (if matrix-only?
        '()
        (run-mp4-observations! run-one workloads run-root fps width height
                               preparation-log typeset-log)))
  (define-values (measurements summaries)
    (run-primary-matrix! run-one workloads run-root workers repetitions fps width height
                         preparation-log typeset-log))
  (define math-preparation-identity
    (and (not matrix-only?)
         math-workload
         (run-math-preparation-identity-probe! run-root fps width height)))
  (define cache-hits
    (if matrix-only?
        '()
        (run-cache-hit-observations! run-one workloads run-root fps width height
                                     preparation-log typeset-log)))
  (define result
    (hasheq
     'schema 'animate-process-rendering-benchmark-v1
     'environment (frozen-environment output-root)
     'methodology
     (hasheq 'workloads (map benchmark-workload-name workloads)
             'matrix-only? matrix-only?
             'workers workers
             'requested-repetitions repetitions
             'repetition-policy "two requested local repetitions; pass --repetitions 3 where time and disk permit"
             'settings (hasheq 'theme 'dark 'fps fps 'width width 'height height 'supersample 1)
             'frame-cache-strategy "fresh invocation roots for every primary measurement; same root only for explicit complete-cache-hit observations"
             'math-svg-cache-strategy "driver launches this internal run with a fresh benchmark-owned PLTUSERHOME; warm runs reuse it after the cold observation"
             'parent-process-strategy "one fresh benchmark parent process per measured project invocation"
             'frame-equivalence "complete byte comparison against the first workers=1 PNG sequence per workload"
             'worker-policy "normal render-spec #:worker-mode 'auto; capacities above one resolve to the generic subprocess path"
             'stage-limitations
             "Preparation and frame execution are directly timed; generic reports do not expose a separate publication or preparation-verification duration. MP4 encode time is derived as execution wall time minus frame executor time and includes residual execution orchestration.")
     'cold-math cold-math
     'measurements measurements
     'summaries summaries
     'math-preparation-identity math-preparation-identity
     'cache-hit-observations cache-hits
     'mp4-observations mp4-observations
     'event-logs (hasheq 'preparation preparation-log
                          'typeset typeset-log)))
  (write-json-file! (build-path output-root "benchmark.json") result)
  (write-tsv-file! (build-path output-root "benchmark.tsv") measurements)
  result)

; benchmark-collection-paths : -> (listof complete-path?)
;;   Lists the checkout and installed dependency roots needed by a fresh package profile.
(define (benchmark-collection-paths)
  (define animate-root (simplify-path (path->complete-path repository-root)))
  (define source-collection-root (simplify-path (build-path animate-root 'up)))
  (define addon-directory (find-system-path 'addon-dir))
  (define user-version-directory (build-path addon-directory (version)))
  (define package-directory (build-path user-version-directory "pkgs"))
  (define racket-bin-directory (path-only (find-system-path 'exec-file)))
  (define system-collection-root
    (simplify-path (build-path racket-bin-directory 'up "collects")))
  (define package-roots
    (if (directory-exists? package-directory)
        (for/list ([entry (in-list (directory-list package-directory #:build? #t))]
                   #:when (directory-exists? entry))
          entry)
        '()))
  (filter directory-exists?
          (append
           (list source-collection-root)
           package-roots
           (list (build-path user-version-directory "collects")
                 system-collection-root)
           ;; racket-cas is an installed local dependency represented by a
           ;; relative package link in the normal user profile.
           (list (build-path source-collection-root "racket-cas")))))

; collection-path-string : (listof path?) -> string?
;;   Joins collection roots in the macOS path-list syntax used by this benchmark host.
(define (collection-path-string paths)
  (string-join (map path->string paths) ":"))

; run-isolated-driver! : path-string? (listof exact-positive-integer?)
;                         exact-positive-integer? exact-positive-integer?
;                         exact-positive-integer? exact-positive-integer? -> void?
;;   Starts the actual benchmark in a child whose PLTUSERHOME is benchmark-owned.
(define (run-isolated-driver! output-root workers repetitions fps width height)
  (define complete-output-root (simplify-path (path->complete-path output-root)))
  (make-directory* complete-output-root)
  (define preference-root (build-path complete-output-root "pltuserhome"))
  (make-directory* preference-root)
  (define environment
    (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! environment
                              #"PLTUSERHOME"
                              (string->bytes/utf-8 (path->string preference-root)))
  (environment-variables-set! environment
                               #"ANIMATE_MATH_PREPARATION_EVENT_LOG"
                               (string->bytes/utf-8
                               (path->string (build-path complete-output-root "all-math-preparation-events.log"))))
  (environment-variables-set! environment
                              #"ANIMATE_MATH_TYPESET_EVENT_LOG"
                              (string->bytes/utf-8
                               (path->string (build-path complete-output-root "all-math-typeset-events.log"))))
  ;; A fresh PLTUSERHOME intentionally lacks the normal user's package links.
  ;; Supply the same installed package roots explicitly rather than copying or
  ;; changing that user's registry; the internal run still proves checkout
  ;; collection identity before it prepares or launches a worker.
  (environment-variables-set! environment
                              #"PLTCOLLECTS"
                              (string->bytes/utf-8
                               (collection-path-string (benchmark-collection-paths))))
  (parameterize ([current-environment-variables environment])
    (unless
        (apply system*
               (find-system-path 'exec-file)
               (append
                (list
                 (path->string
                  (simplify-path
                   (path->complete-path "tools/benchmark-process-rendering.rkt")))
                 "--internal"
                 "--output" (path->string complete-output-root)
                 "--workers" (string-join (map number->string workers) ",")
                 "--repetitions" (number->string repetitions)
                 "--fps" (number->string fps)
                 "--width" (number->string width)
                 "--height" (number->string height))
                (if (current-benchmark-workload-names)
                    (list "--workloads"
                          (string-join (map symbol->string
                                            (current-benchmark-workload-names))
                                       ","))
                    '())
                (if (current-benchmark-matrix-only?)
                    (list "--matrix-only")
                    '())))
      (raise-user-error 'benchmark-process-rendering
                        "the isolated benchmark child failed; inspect ~a"
                        complete-output-root))))


;;;
;;; Explicit Entry Point
;;;

(module+ main
  (define output-root "logs/process-rendering-pr-h")
  (define workers '(1 2 4 10))
  ;; Two repetitions are the default because these are complete 720p lessons.
  ;; The final PR-H record describes a demonstrated stalled third-run attempt.
  (define repetitions 2)
  ;; The complete reviewed lessons at 10 fps would exceed the 7 GiB free on
  ;; the recorded local volume across a multi-repetition matrix.  Two fps
  ;; retains 115 geometry and 104 math frames, enough useful jobs for ten
  ;; workers, without turning the benchmark into a disk-capacity test.
  (define fps 2)
  (define width 1280)
  (define height 720)
  (define internal? #f)
  (define single? #f)
  (define prepare-only? #f)
  (define single-workload #f)
  (define single-root #f)
  (define single-format 'png-sequence)
  (define single-result #f)
  (define preparation-log #f)
  (define typeset-log #f)
  (define allow-existing? #f)
  (define selected-workload-names #f)
  (define matrix-only? #f)
  (command-line
   #:program "benchmark-process-rendering"
   #:once-each
   [("--internal") "Run in the driver-created isolated preference environment."
    (set! internal? #t)]
   [("--single") "Run one private, fresh-parent benchmark measurement."
    (set! single? #t)]
   [("--prepare-only") "Run one private, fresh-parent preparation observation."
    (set! prepare-only? #t)]
   [("--workload") name "Private measurement workload name."
    (set! single-workload (string->symbol name))]
   [("--root") directory "Private measurement output root."
    (set! single-root directory)]
   [("--format") format "Private measurement format: png-sequence or mp4."
    (define parsed-format (string->symbol format))
    (unless (memq parsed-format '(png-sequence mp4))
      (raise-user-error 'benchmark-process-rendering
                        "--format must be png-sequence or mp4, got ~s" format))
    (set! single-format parsed-format)]
   [("--result") path "Private readable-data result path."
    (set! single-result path)]
   [("--preparation-log") path "Shared math preparation event log."
    (set! preparation-log path)]
   [("--typeset-log") path "Shared math typeset event log."
    (set! typeset-log path)]
   [("--allow-existing") "Permit the private measurement root to contain a cache hit."
    (set! allow-existing? #t)]
   [("--workloads") names "Comma-separated benchmark workloads; default is every workload."
    (set! selected-workload-names (benchmark-workload-list names))]
   [("--matrix-only") "Run only the primary warm-up and scaling matrix."
    (set! matrix-only? #t)]
   [("--output") directory "Write only benchmark-owned data under DIRECTORY."
    (set! output-root directory)]
   [("--workers") capacities "Comma-separated capacities; default 1,2,4,10."
    (set! workers (worker-list capacities))]
   [("--repetitions") count "Measured repetitions per capacity; default 2."
    (set! repetitions (positive-integer 'benchmark-process-rendering count))]
   [("--fps") count "Benchmark frame-grid FPS; default 2 on this constrained local volume."
    (set! fps (positive-integer 'benchmark-process-rendering count))]
   [("--width") count "Raster width; default 1280."
    (set! width (positive-integer 'benchmark-process-rendering count))]
   [("--height") count "Raster height; default 720."
    (set! height (positive-integer 'benchmark-process-rendering count))])
  (parameterize ([current-benchmark-workload-names selected-workload-names]
                 [current-benchmark-matrix-only? matrix-only?])
   (cond
    [(or single? prepare-only?)
     (when (and single? prepare-only?)
       (raise-user-error 'benchmark-process-rendering
                         "--single and --prepare-only cannot be combined"))
     (unless (and single-workload single-root single-result
                  (or prepare-only? (and preparation-log typeset-log)))
       (raise-user-error 'benchmark-process-rendering
                         "--single requires --workload, --root, --result, --preparation-log, and --typeset-log; --prepare-only requires --workload, --root, and --result"))
     (unless (= (length workers) 1)
       (raise-user-error 'benchmark-process-rendering
                         "--single requires exactly one --workers value"))
     (define workload
       (for/first ([candidate (in-list (representative-workloads))]
                   #:when (eq? single-workload (benchmark-workload-name candidate)))
         candidate))
     (unless workload
       (raise-user-error 'benchmark-process-rendering
                         "unsupported --workload ~s" single-workload))
     (write-datum-file!
      single-result
      (if prepare-only?
          (prepare-workload-once! workload single-root (first workers) fps width height)
          (run-workload-once! workload single-root (first workers) fps width height
                              single-format #f preparation-log typeset-log
                              #:allow-existing? allow-existing?)))]
    [internal?
      (let ([result (run-process-rendering-benchmark! output-root workers repetitions fps width height)])
        (printf "Wrote ~a and ~a\n"
                (build-path output-root "benchmark.json")
                (build-path output-root "benchmark.tsv"))
        (printf "Measured ~a primary frame runs under ~a\n"
                (length (hash-ref result 'measurements))
                (path->string (build-path output-root "runs"))))]
    [else
     (run-isolated-driver! output-root workers repetitions fps width height)])))
