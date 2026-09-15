#lang racket/base

;;;
;;; PR-D Project Subprocess Execution Tests
;;;

;; Exercises normal project planning, preparation, cache reuse, and final
;; output through real PR-C worker children. Worker protocol fault handling is
;; intentionally covered by the focused PR-C process tests; this file verifies
;; that ordinary project execution reaches that shared supervisor correctly.


;;;
;;; Imports and Runtime Paths
;;;

;; Imports
(require rackunit
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         "../main.rkt"
         "../authoring.rkt"
         "../project.rkt"
         "../render.rkt"
         "../private/3d/label-layout-preparation3d.rkt"
         "../private/process-frame-executor.rkt")

(define-runtime-path source-fixture "fixtures/project-subprocess-source.rkt")
(define-runtime-path source-program-fixture "../examples/source-block-hot-reload.rkt")


;;;
;;; Project Construction Helpers
;;;

; make-test-project : path? symbol? source-specification? render-spec? path?
;                      -> animate-project?
;;   Declares one owned PNG-sequence project with a caller-selected cache root.
(define (make-test-project root id source render cache-root)
  (animate-project
   #:id id
   #:source source
   #:render render
   #:output (output-spec #:root (build-path root "media")
                         #:name (symbol->string id)
                         #:format 'png-sequence
                         #:overwrite-policy 'replace
                         #:open-after? #f)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root cache-root #:policy 'read-write)))

; report-frame-diagnostics : project-execution-report?
;                            -> project-frame-execution-diagnostics?
;;   Extracts the normalized frame report without exposing a rendering choice.
(define (report-frame-diagnostics report)
  (project-execution-report-diagnostics report))

; project-render-for : exact-positive-integer? symbol? -> render-spec?
;;   Fixes the fixture raster while varying only worker capacity and mode.
(define (project-render-for workers worker-mode)
  (render-spec #:fps 2 #:width 80 #:height 50
               #:workers workers #:worker-mode worker-mode))

; status-closed? : immutable-hash? -> boolean?
;;   Checks all process resources the parent supervisor can directly observe.
(define (status-closed? status)
  (and (not (hash-ref status 'open? #t))
       (hash-ref status 'input-closed? #f)
       (hash-ref status 'output-closed? #f)
       (hash-ref status 'error-closed? #f)
       (hash-ref status 'reader-dead? #f)
       (hash-ref status 'error-reader-dead? #f)))

; write-builder-source! : path? -> path?
;;   Creates a restartable PR-A fixture below the test-owned temporary root.
(define (write-builder-source! root)
  (define source-path (build-path root "subprocess source æ.rkt"))
  (call-with-output-file
   source-path
   (lambda (out)
     (display
      "#lang racket/base\n\
(require animate animate/project racket/file racket/path)\n\
(provide prepare-source build-source)\n\
(define (record! context phase)\n\
  (call-with-output-file\n\
   (build-path (source-build-context-asset-base context) \"builder.log\")\n\
   #:exists 'append\n\
   (lambda (log) (writeln phase log))))\n\
(define (prepare-source context options)\n\
  (record! context 'prepare)\n\
  (source-preparation #:payload (hasheq 'options options)))\n\
(define (build-source context options payload)\n\
  (record! context 'build)\n\
  (when (file-exists? (build-path (source-build-context-asset-base context) \"fail-child\"))\n\
    (error 'build-source \"requested child failure\"))\n\
  (scene-wait\n\
   (scene-add (make-scene #:camera (make-camera #:width 80 #:height 50 #:world-width 8))\n\
              (circle #:id 'builder-dot #:radius 1 #:fill \"tomato\"))\n\
   2))\n"
      out))
   #:exists 'truncate/replace)
  source-path)


;;;
;;; Real Project Execution
;;;

(module+ test
  (define root
    (make-temporary-file "animate-project-subprocess-~a" 'directory))
  (dynamic-wind
   (lambda () #f)
   (lambda ()
     (define binding-source
       (module-binding-source source-fixture 'project-subprocess-scene))
     (define direct-scene
       (dynamic-require source-fixture 'project-subprocess-scene))

     ;; Auto keeps one restartable worker local, but moves a multi-worker
     ;; request into the PR-C subprocess executor. Both render the ordinary
     ;; project target and produce byte-identical PNGs.
     (define local-report
       (render-project!
        (make-test-project
         root 'auto-local binding-source (project-render-for 1 'auto)
         (build-path root "local-cache"))
        #:directory root))
     (define local-diagnostics (report-frame-diagnostics local-report))
     (check-eq? (project-frame-execution-diagnostics-mode local-diagnostics)
                'in-process)
     (check-false (project-frame-execution-diagnostics-subprocess-report
                   local-diagnostics))
     (define subprocess-report
       (render-project!
        (make-test-project
         root 'auto-subprocess binding-source (project-render-for 2 'auto)
         (build-path root "subprocess-cache"))
        #:directory root))
     (define subprocess-diagnostics
       (report-frame-diagnostics subprocess-report))
     (check-eq? (project-frame-execution-diagnostics-mode subprocess-diagnostics)
                'subprocess)
     (check-equal? (project-frame-execution-diagnostics-requested-worker-capacity
                    subprocess-diagnostics)
                   2)
     (check-equal? (project-frame-execution-diagnostics-workers-started
                    subprocess-diagnostics)
                   2)
     (check-equal? (project-frame-execution-diagnostics-source-frame-indices
                    subprocess-diagnostics)
                   '(0 1 2 3))
     (check-equal? (project-frame-execution-diagnostics-output-frame-indices
                    subprocess-diagnostics)
                   '(0 1 2 3))
     (check-equal?
      (map file->bytes
           (project-frame-execution-diagnostics-paths local-diagnostics))
      (map file->bytes
           (project-frame-execution-diagnostics-paths subprocess-diagnostics)))
     (define process-report
       (project-frame-execution-diagnostics-subprocess-report
        subprocess-diagnostics))
     (check-equal? (process-frame-execution-report-completed-frame-count
                    process-report)
                   4)
     (check-true
     (andmap status-closed?
              (process-frame-execution-report-worker-resource-statuses
               process-report)))

     ;; Explicit mode remains authoritative: a direct source may use local
     ;; workers, while an explicit single subprocess worker still starts a
     ;; real child. Direct auto/multi remains a planning rejection.
     (define explicit-local-report
       (render-project!
        (make-test-project
         root 'explicit-local (scene-source direct-scene)
         (project-render-for 3 'in-process)
         (build-path root "explicit-local-cache"))
        #:directory root))
     (check-eq?
      (project-frame-execution-diagnostics-mode
       (report-frame-diagnostics explicit-local-report))
      'in-process)
     (define explicit-subprocess-report
       (render-project!
        (make-test-project
         root 'explicit-subprocess binding-source
         (project-render-for 1 'subprocess)
         (build-path root "explicit-subprocess-cache"))
        #:directory root))
     (check-equal?
      (project-frame-execution-diagnostics-workers-started
       (report-frame-diagnostics explicit-subprocess-report))
      1)
     (check-exn
      exn:fail?
      (lambda ()
        (plan-project
         (make-test-project
          root 'direct-auto-multi (scene-source direct-scene)
          (project-render-for 2 'auto)
         (build-path root "direct-auto-multi-cache"))
         #:directory root)))

     ;; Target planning stays the source of truth. Render frame, range,
     ;; section, and source-program block targets through the same normal
     ;; execution entry points and compare each executor map to preparation.
     (define (check-target! id source target execute!)
       (define project
         (make-test-project
          root id source (project-render-for 2 'subprocess)
          (build-path root (format "~a-cache" id))))
       (define prepared
         (prepare-project! (plan-project project #:target target #:directory root)))
       (define report (execute! project))
       (define diagnostics (report-frame-diagnostics report))
       (check-equal?
        (project-frame-execution-diagnostics-source-frame-indices diagnostics)
        (prepared-project-target-frame-indices prepared))
       (check-equal?
        (project-frame-execution-diagnostics-output-frame-indices diagnostics)
       (build-list (length (prepared-project-target-frame-indices prepared)) values))
       diagnostics)
     (check-target!
      'frame-target binding-source (project-target-frame 2)
      (lambda (project)
        (render-project-frame! project 2 #:directory root)))
     (check-target!
      'range-target binding-source (project-target-range 1/2 3/2)
      (lambda (project)
        (render-project-range! project 1/2 3/2 #:directory root)))
     (check-target!
      'section-target
      (module-binding-source source-fixture 'project-subprocess-timeline)
      (project-target-section 'second)
      (lambda (project)
        (render-project-section! project 'second #:directory root)))
     (check-target!
      'block-target
      (module-binding-source source-program-fixture 'hot-reload-demo)
      (project-target-block 'move-dot)
      (lambda (project)
        (render-project-block! project 'move-dot #:directory root)))

     ;; Frame cache identity intentionally ignores worker policy/capacity. A
     ;; successful subprocess render is reusable by an in-process request, and
     ;; the hit report proves no executor child was started.
     (define shared-cache (build-path root "shared-cache"))
     (define first-cache-report
       (render-project!
        (make-test-project
         root 'shared-cache binding-source (project-render-for 2 'auto)
         shared-cache)
        #:directory root))
     (check-eq?
      (project-frame-execution-diagnostics-mode
       (report-frame-diagnostics first-cache-report))
      'subprocess)
     (define reused-cache-report
       (render-project!
        (make-test-project
         root 'shared-cache binding-source (project-render-for 1 'in-process)
         shared-cache)
        #:directory root))
     (define reused-diagnostics (report-frame-diagnostics reused-cache-report))
     (check-equal? (project-execution-report-reused-frames reused-cache-report) 4)
     (check-equal? (project-frame-execution-diagnostics-workers-started
                    reused-diagnostics)
                   0)
     (check-false (project-frame-execution-diagnostics-subprocess-report
                   reused-diagnostics))

     ;; The executor publishes the same local frame-root that normal MP4
     ;; assembly consumes. A subprocess target therefore retains frame export,
     ;; encoder invocation, and primary-artifact behavior.
     (define mp4-project
       (animate-project
        #:id 'subprocess-mp4
        #:source binding-source
        #:render (project-render-for 2 'subprocess)
        #:output (output-spec #:root (build-path root "mp4-media")
                              #:name "subprocess-mp4"
                              #:format 'mp4
                              #:write-frame-sequence? #t
                              #:overwrite-policy 'replace
                              #:open-after? #f)
        #:encoder (encoder-spec #:options #hasheq((crf . "28")))
        #:cache (cache-spec #:root (build-path root "mp4-cache")
                            #:policy 'read-write)))
     (define mp4-report (render-project! mp4-project #:directory root))
     (check-equal? (project-execution-report-encoded-segments mp4-report) 1)
     (check-true
      (file-exists?
       (hash-ref (project-execution-report-artifact-paths mp4-report)
                 'primary)))
     (check-eq?
      (project-frame-execution-diagnostics-mode
       (report-frame-diagnostics mp4-report))
      'subprocess)

     ;; A builder module stored at a path with both spaces and non-ASCII text
     ;; is loaded by the ordinary parent preparer and then by each real child.
     ;; The log lives only under this test's temporary asset base.
     (define builder-path (write-builder-source! root))
     (define builder-project
       (make-test-project
        root 'builder-subprocess
        (module-builder-source builder-path 'build-source
                               #:prepare 'prepare-source
                               #:options #hasheq((fixture . builder)))
        (project-render-for 2 'subprocess)
        (build-path root "builder-cache")))
     (define builder-report (render-project! builder-project #:directory root))
     (define builder-log
       (file->lines (build-path root "builder.log")))
     ;; PR-E preparation runs once in the parent; each child still constructs
     ;; its own local scene through the documented builder contract.
     (check-equal? (length (filter (lambda (line) (equal? line "prepare"))
                                  builder-log))
                   1)
     (check-equal? (length (filter (lambda (line) (equal? line "build"))
                                  builder-log))
                   3)
     (check-equal?
      (project-frame-execution-diagnostics-workers-started
      (report-frame-diagnostics builder-report))
      2)

     ;; The final worker protocol deliberately has no consumer for opaque
     ;; renderer options. Reject the project before an output/cache directory
     ;; is created rather than producing a partial or misleading PNG set.
     (define unsupported-root (build-path root "unsupported-cache"))
     (define unsupported-output-root (build-path root "unsupported-media"))
     (define unsupported-project
       (animate-project
        #:id 'unsupported
        #:source binding-source
        #:render (render-spec #:fps 2 #:width 80 #:height 50
                              #:workers 1 #:worker-mode 'subprocess
                              #:renderer-options #hasheq((opaque . option)))
        #:output (output-spec #:root unsupported-output-root
                              #:name "unsupported"
                              #:format 'png-sequence
                              #:open-after? #f)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root unsupported-root #:policy 'read-write)))
     (define unsupported-prepared
       (prepare-project! (plan-project unsupported-project #:directory root)))
     (define unsupported-frame-root
       (project-path-plan-frames-root
        (project-plan-path-plan (prepared-project-plan unsupported-prepared))))
     (check-exn
      exn:fail?
      (lambda ()
        (execute-prepared-project! unsupported-prepared #:open-after? #f)))
     (check-false (directory-exists? unsupported-root))
     (check-false (directory-exists? unsupported-output-root))
     (check-false (directory-exists? unsupported-frame-root))

     ;; The PR-C prepared-input carrier is not yet consumed by final workers;
     ;; even a valid prepared label layout is rejected before output mutation.
     (define layout-root (build-path root "layout-cache"))
     (define layout-output-root (build-path root "layout-media"))
     (define layout-project
       (animate-project
        #:id 'unsupported-layout
        #:source binding-source
        #:render (project-render-for 1 'subprocess)
        #:output (output-spec #:root layout-output-root
                              #:name "unsupported-layout"
                              #:format 'png-sequence
                              #:open-after? #f)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root layout-root #:policy 'read-write)))
     (define layout-prepared
       (prepare-project! (plan-project layout-project #:directory root)))
     (define layout-frame-root
       (project-path-plan-frames-root
        (project-plan-path-plan (prepared-project-plan layout-prepared))))
     (check-exn
      exn:fail?
      (lambda ()
        (execute-prepared-project!
         layout-prepared
         #:open-after? #f
         #:prepared-label-layout
         (prepared-label-layout3d #() #() 0 0))))
     (check-false (directory-exists? layout-root))
     (check-false (directory-exists? layout-output-root))
     (check-false (directory-exists? layout-frame-root))

     ;; A post-preparation child build failure propagates as the report-bearing
     ;; executor error. Its staging PNGs are removed and no output slot is
     ;; published, while the source module itself remains untouched.
     (define failure-project
       (make-test-project
        root 'builder-failure
        (module-builder-source builder-path 'build-source #:prepare 'prepare-source)
        (project-render-for 1 'subprocess)
        (build-path root "builder-failure-cache")))
     (define failure-prepared
       (prepare-project! (plan-project failure-project #:directory root)))
     (call-with-output-file
      (build-path root "fail-child")
      (lambda (out) (display "fail" out))
      #:exists 'truncate/replace)
     (check-exn
      exn:fail:process-frame-execution?
      (lambda () (execute-prepared-project! failure-prepared #:open-after? #f)))
     (define failed-frame-root
       (project-path-plan-frames-root
        (project-plan-path-plan (prepared-project-plan failure-prepared))))
     (check-false
      (ormap (lambda (path)
               (regexp-match? #px"^frame-[0-9]{6,}\\.png$"
                              (path->string (file-name-from-path path))))
             (if (directory-exists? failed-frame-root)
                 (directory-list failed-frame-root #:build? #t)
                 '())))
     (void))
   (lambda ()
     (when (directory-exists? root)
       (delete-directory/files root)))))
