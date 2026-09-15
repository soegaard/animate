#lang racket/base

;;;
;;; Shared Preparation Process Tests
;;;

;; Exercises PR-E's parent-owned preparation manifest with real Racket worker
;; processes.  The temporary module deliberately records preparer and builder
;; invocations separately, so process count is not mistaken for preparation.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         racket/file
         racket/list
         racket/path
         "../private/process-frame-executor.rkt"
         "../private/project-execution.rkt"
         "../private/render-preparation-lease.rkt"
         "../private/render-preparation-manifest.rkt"
         "../private/render-source-model.rkt"
         "../project.rkt")


;;;
;;; Temporary Module Fixture
;;;

; write-preparation-source! : path? -> path?
;;   Writes a restartable builder whose preparer publishes one checked artifact.
(define (write-preparation-source! source-directory)
  (define helper-path (build-path source-directory "helper.rkt"))
  (define module-path (build-path source-directory "shared preparation source.rkt"))
  (call-with-output-file helper-path
    (lambda (output)
      (display "#lang racket/base\n(provide fixture-fill)\n(define fixture-fill \"tomato\")\n"
               output))
    #:exists 'truncate/replace)
  (call-with-output-file module-path
    (lambda (output)
      (display
       (string-append
        "#lang racket/base\n"
        "(require animate/project animate/main racket/file racket/path \"helper.rkt\")\n"
        "(provide prepare-source build-source)\n"
        "(define (record! context tag)\n"
        "  (call-with-output-file (build-path (source-build-context-asset-base context) \"observations.log\")\n"
        "    (lambda (out) (displayln tag out)) #:exists 'append))\n"
        "(define (prepare-source context options)\n"
        "  (record! context \"prepare\")\n"
        "  (define artifact (build-path (source-build-context-asset-base context) \"prepared-layout.txt\"))\n"
        "  (call-with-output-file artifact (lambda (out) (display \"shared-layout-v1\" out)) #:exists 'truncate/replace)\n"
        "  (define reuse\n"
        "    (and (hash-ref options 'reuse? #f)\n"
        "         (hasheq 'schema 'animate-frame-reuse-witness-v1\n"
        "                 'base-fingerprint (source-build-context-base-fingerprint context)\n"
        "                 'representatives '((1 0) (3 2) (5 4) (7 6)))))\n"
        "  (source-preparation #:payload #hasheq((layout . shared))\n"
        "                      #:artifacts (list (hasheq 'path (path->string artifact) 'role 'layout))\n"
        "                      #:frame-reuse reuse\n"
        "                      #:diagnostics #hasheq((persistent-cache-eligible? . #t))))\n"
        "(define (build-source context options payload)\n"
        "  (record! context \"build\")\n"
        "  (unless (and payload (equal? (hash-ref payload 'layout #f) 'shared))\n"
        "    (error 'build-source \"missing parent preparation payload: ~s\" payload))\n"
        "  (unless (equal? (file->string (build-path (source-build-context-asset-base context) \"prepared-layout.txt\")) \"shared-layout-v1\")\n"
        "    (error 'build-source \"prepared artifact was not verified\"))\n"
        "  (scene-wait (scene-add (make-scene)\n"
        "                         (circle #:id 'prepared-dot #:radius 1 #:fill fixture-fill)) 4))\n")
       output))
    #:exists 'truncate/replace)
  module-path)

; make-preparation-project : path? path? exact-positive-integer? boolean? -> animate-project?
;;   Declares a controlled subprocess project with an optional generic reuse witness.
(define (make-preparation-project root module-path workers reuse?)
  (animate-project
   #:id 'shared-preparation
   #:source
   (module-builder-source module-path 'build-source
                          #:prepare 'prepare-source
                          #:options (hasheq 'reuse? reuse?)
                          #:seed 23)
   #:render (render-spec #:fps 2 #:width 80 #:height 50
                         #:workers workers #:worker-mode 'subprocess)
   #:output (output-spec #:root (build-path root "media")
                          #:name "shared-preparation"
                          #:format 'png-sequence
                          #:overwrite-policy 'replace)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root (build-path root "cache")
                       #:policy 'read-write)))

; observation-count : path? string? -> exact-nonnegative-integer?
;;   Counts one parent/worker lifecycle observation in fixture output.
(define (observation-count source-directory tag)
  (define path (build-path source-directory "observations.log"))
  (if (file-exists? path)
      (length (filter (lambda (line) (equal? line tag))
                      (file->lines path)))
      0))


;;;
;;; Real Process and Integrity Cases
;;;

(module+ test
  (define root (make-temporary-file "animate-shared-preparation-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define source-directory (build-path root "source Ω"))
     (make-directory* source-directory)
     (define module-path (write-preparation-source! source-directory))

     ;; One optional preparer runs exactly once for each complete render, while
     ;; builder construction remains parent plus one generation per child.
     (for ([workers (in-list '(1 2 4))])
       (define trial-root (build-path root (format "workers-~a" workers)))
       (define report
         (render-project!
          (make-preparation-project trial-root module-path workers #f)
          #:directory trial-root))
       (check-equal?
        (project-frame-execution-diagnostics-workers-started
         (project-execution-report-diagnostics report))
        workers))
     (check-equal? (observation-count source-directory "prepare") 3)
     ;; One parent builder plus the configured child generations per run.
     (check-equal? (observation-count source-directory "build") 10)

     ;; An explicitly eligible builder manifest can reuse the complete existing
     ;; frame set. The second run changes only worker capacity, still prepares
     ;; to validate identity, launches no workers, and adds no child builder.
     (define cache-root (build-path root "persistent-cache"))
     (define first-cache-report
       (render-project!
        (make-preparation-project cache-root module-path 1 #f)
        #:directory cache-root))
     (define builders-after-first (observation-count source-directory "build"))
     (define second-cache-report
       (render-project!
        (make-preparation-project cache-root module-path 4 #f)
        #:directory cache-root))
     (check-equal?
      (project-frame-execution-diagnostics-workers-started
       (project-execution-report-diagnostics second-cache-report))
      0)
     (check-equal? (observation-count source-directory "build")
                   (add1 builders-after-first))
     (check-equal?
      (hash-ref
       (project-frame-execution-diagnostics-work-accounting
        (project-execution-report-diagnostics second-cache-report))
       'persistent-frame-cache-hits)
      8)

     ;; A valid cache manifest can satisfy some slots ahead of worker sizing;
     ;; only the missing slot reaches a real child process on this third pass.
     (delete-file
      (list-ref
       (project-frame-execution-diagnostics-paths
        (project-execution-report-diagnostics first-cache-report))
       3))
     (define partial-cache-report
       (render-project!
        (make-preparation-project cache-root module-path 4 #f)
        #:directory cache-root))
     (define partial-subprocess-report
       (project-frame-execution-diagnostics-subprocess-report
        (project-execution-report-diagnostics partial-cache-report)))
     (check-equal?
      (project-frame-execution-diagnostics-workers-started
       (project-execution-report-diagnostics partial-cache-report))
      1)
     (check-equal?
      (process-frame-execution-report-persistent-cache-hit-count
       partial-subprocess-report)
      7)
     (check-equal?
      (process-frame-execution-report-rasterized-frame-count
       partial-subprocess-report)
      1)

     ;; The generic consumer trusts only the explicit witness, rasterizes four
     ;; representative slots, and materializes the other four in order.
     (define reuse-root (build-path root "reuse"))
     (define reuse-report
       (render-project!
        (make-preparation-project reuse-root module-path 4 #t)
        #:directory reuse-root))
     (define reuse-subprocess-report
       (project-frame-execution-diagnostics-subprocess-report
        (project-execution-report-diagnostics reuse-report)))
     (check-equal? (process-frame-execution-report-representative-frame-count
                    reuse-subprocess-report)
                   4)
     (check-equal? (process-frame-execution-report-frame-reuse-alias-count
                    reuse-subprocess-report)
                   4)
     (check-equal? (process-frame-execution-report-rasterized-frame-count
                    reuse-subprocess-report)
                   4)
     (check-equal? (length (project-frame-execution-diagnostics-paths
                            (project-execution-report-diagnostics reuse-report)))
                   8)

     ;; Corruption after parent preparation is rejected before any worker can
     ;; silently regenerate a layout artifact.
     (define integrity-root (build-path root "integrity"))
     (define integrity-plan
       (plan-project
        (make-preparation-project integrity-root module-path 2 #f)
        #:directory integrity-root))
     (define integrity-prepared (prepare-project! integrity-plan))
     ;; The model snapshots only bounded data, and a tampered manifest no
     ;; longer validates as a handoff for a worker generation.
     (check-exn exn:fail?
                (lambda () (source-preparation #:payload (lambda () 'invalid))))
     (check-false
      (render-preparation-manifest?
       (hash-set
        (prepared-project-preparation-manifest integrity-prepared)
        'payload
        (lambda () 'invalid))))
     (call-with-output-file (build-path source-directory "prepared-layout.txt")
       (lambda (output) (display "corrupt" output))
       #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (execute-prepared-project! integrity-prepared)))
     ;; The cache directory may have been created for managed staging, but an
     ;; artifact-integrity failure leaves no canonical frame publication.
     (define integrity-frame-root
       (build-path integrity-root "cache" "shared-preparation-all" "frames"))
     (check-true (directory-exists? integrity-frame-root))
     (check-equal? (directory-list integrity-frame-root) '())

     ;; A missing artifact follows the same fail-closed worker-load path.
     (define missing-root (build-path root "missing-artifact"))
     (define missing-prepared
       (prepare-project!
        (plan-project
         (make-preparation-project missing-root module-path 2 #f)
         #:directory missing-root)))
     (delete-file (build-path source-directory "prepared-layout.txt"))
     (check-exn exn:fail?
                (lambda () (execute-prepared-project! missing-prepared)))

     ;; A tracked helper edit after preparation invalidates the session instead
     ;; of allowing a mixed parent/child source revision to publish frames.
     (define mutation-root (build-path root "input-mutation"))
     (define mutation-plan
       (plan-project
        (make-preparation-project mutation-root module-path 2 #f)
        #:directory mutation-root))
     (define mutation-prepared (prepare-project! mutation-plan))
     (call-with-output-file (build-path source-directory "helper.rkt")
       (lambda (output)
         (display "#lang racket/base\n(provide fixture-fill)\n(define fixture-fill \"gold\")\n"
                  output))
       #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (execute-prepared-project! mutation-prepared)))

     ;; Overlapping leases preserve a real artifact until the final owner
     ;; releases it; this manager is explicit rather than a hidden registry.
     (define manifest
       (prepared-project-preparation-manifest mutation-prepared))
     (define artifact-identity
       (hash-ref (car (hash-ref manifest 'artifacts)) 'sha1))
     (define manager (make-preparation-lease-manager))
     (define first-lease (acquire-preparation-lease! manager manifest))
     (define second-lease (acquire-preparation-lease! manager manifest))
     (check-true (preparation-artifact-pinned? manager artifact-identity))
     (release-preparation-lease! first-lease)
     (check-true (preparation-artifact-pinned? manager artifact-identity))
     (release-preparation-lease! second-lease)
     (check-false (preparation-artifact-pinned? manager artifact-identity)))
   (lambda ()
     (when (directory-exists? root)
       (delete-directory/files root)))))
