#lang racket/base

;;;
;;; Geometry Generic Process-Render Migration Tests
;;;

;; These tests use the actual module builder, generic project executor, and
;; Racket children. They deliberately retain one local geometry render as the
;; legacy pixel oracle; normal full-frame CLI work never takes that path.


;;;
;;; Imports
;;;

(require rackunit
         racket/class
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string
         racket/system
         racket/draw
         "../../project.rkt"
         "../../private/project-execution.rkt"
         "../../private/process-frame-executor.rkt"
         "../private/frame-reuse.rkt"
         "../render.rkt"
         (prefix-in colors: "../../colors.rkt")
         (prefix-in example: "../examples/equilateral-triangle.rkt")
         (prefix-in copy-angle: "../examples/copy-angle.rkt"))

(define-runtime-path example-path "../examples/equilateral-triangle.rkt")
(define-runtime-path examples-directory "../examples")
(define-runtime-path runner-path "../examples/private/run-example.rkt")


;;;
;;; Test Helpers
;;;

; temporary-test : (path? -> any/c) -> any/c
;;   Runs one integration test under a private directory and always removes it.
(define (temporary-test thunk)
  (define root (make-temporary-file "geometry-process-render-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda () (thunk root))
   (lambda () (when (directory-exists? root) (delete-directory/files root)))))

; frame-paths : path-string? -> (listof path?)
;;   Returns a canonical full-frame sequence in lexical frame-index order.
(define (frame-paths directory)
  (sort
   (for/list ([entry (in-list (directory-list directory))]
              #:when (regexp-match? #rx"^frame-[0-9]+\\.png$"
                                    (path->string (file-name-from-path entry))))
     (build-path directory entry))
   string<?
   #:key path->string))

; check-same-png-sequence : (listof path?) (listof path?) -> void?
;;   Confirms byte-identical PNG transport and ordering, not only equal counts.
(define (check-same-png-sequence expected actual)
  (check-equal? (length actual) (length expected))
  (for ([expected-path (in-list expected)] [actual-path (in-list actual)])
    (check-equal? (file->bytes actual-path) (file->bytes expected-path))))

; generic-project : path-string? path-string? exact-positive-integer? symbol? boolean?
;                   exact-positive-integer? exact-positive-integer? symbol? -> animate-project?
;;   Declares a direct generic project around the real shared geometry wrappers.
(define (generic-project output-root cache-root workers worker-mode captions?
                         width height theme-mode)
  (animate-project
   #:id 'geometry-process-render-test
   #:source
   (module-builder-source
    example-path
    'geometry-render-builder
    #:prepare 'geometry-render-preparer
    #:options (hasheq 'width width
                       'height height
                       'fps 2
                       'theme-mode theme-mode
                       'captions? captions?))
   #:render
   (render-spec #:fps 2
                #:width width
                #:height height
                #:workers workers
                #:worker-mode worker-mode
                #:theme (if (eq? theme-mode 'dark)
                            colors:animate-dark-theme
                            colors:animate-light-theme))
   #:output
   (output-spec #:root output-root
                #:name "frames"
                #:format 'png-sequence
                #:overwrite-policy 'replace)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root cache-root #:policy 'read-write)))

; render-generic : path-string? path-string? exact-positive-integer? symbol? boolean?
;                  exact-positive-integer? exact-positive-integer? symbol?
;                  -> project-execution-report?
;;   Executes one real geometry builder declaration through the generic service.
(define (render-generic output-root cache-root workers worker-mode captions?
                        width height theme-mode)
  (render-project!
   (generic-project output-root cache-root workers worker-mode captions?
                    width height theme-mode)
   #:directory output-root))

; report-frame-paths : project-execution-report? -> (listof path?)
;;   Retrieves the generic executor's published PNG paths in local output order.
(define (report-frame-paths report)
  (hash-ref (project-execution-report-artifact-paths report) 'frames))

; report-worker-count : project-execution-report? -> exact-nonnegative-integer?
;;   Reads the parent-observed child count from generic execution diagnostics.
(define (report-worker-count report)
  (project-frame-execution-diagnostics-workers-started
   (project-execution-report-diagnostics report)))

; worker-resources-closed? : immutable-hash? -> boolean?
;;   Recognizes parent-observed closure of every resource owned by one worker.
(define (worker-resources-closed? status)
  (and (not (hash-ref status 'open?))
       (hash-ref status 'input-closed?)
       (hash-ref status 'output-closed?)
       (hash-ref status 'error-closed?)
       (hash-ref status 'reader-dead?)
       (hash-ref status 'error-reader-dead?)))

; check-png-dimensions : path? exact-positive-integer? exact-positive-integer? -> void?
;;   Loads one native PNG to verify the requested raster size survives migration.
(define (check-png-dimensions path width height)
  (define bitmap (make-object bitmap% path 'png/alpha))
  (check-equal? (send bitmap get-width) width)
  (check-equal? (send bitmap get-height) height))

; run-example-cli : path-string? (listof string?) -> exact-integer? string? string?
;;   Runs the real main-submodule command interface with captured diagnostics.
(define (run-example-cli directory arguments)
  (define executable
    (or (find-executable-path (find-system-path 'exec-file))
        (find-system-path 'exec-file)))
  (define output (open-output-string))
  (define errors (open-output-string))
  (define code
    (parameterize ([current-directory directory]
                   [current-output-port output]
                   [current-error-port errors])
      (apply system*/exit-code executable example-path arguments)))
  (values code (get-output-string output) (get-output-string errors)))


;;;
;;; Real Generic-Process Coverage
;;;

(module+ test
  (test-case "every standard geometry example exports the same inert generic builder/preparer pair"
    (for ([name (in-list '("circumcenter" "copy-angle" "copy-triangle-sas"
                           "divide-segment-five" "equilateral-triangle-chain"
                           "equilateral-triangle" "gallery" "incircle" "orthocenter"
                           "parallel-at-distance" "perpendicular-bisector"
                           "perpendicular-through-point" "reflect-point"
                           "regular-hexagon" "semantic-labels" "square-on-segment"
                           "tangent-at-point" "transformations" "triangle-midline"))])
      (define module-path
        (build-path examples-directory (string-append name ".rkt")))
      (define preparer (dynamic-require module-path 'geometry-render-preparer))
      (define builder (dynamic-require module-path 'geometry-render-builder))
      (check-true (procedure-arity-includes? preparer 2) name)
      (check-true (procedure-arity-includes? builder 3) name)))

  (test-case "geometry's generic project preserves local pixels across real one, two, four, and ten-worker sessions"
    (temporary-test
     (lambda (root)
       (define legacy-directory (build-path root "legacy"))
       (define legacy-timeline
         (example:make-demo-timeline #:aspect (/ 160 90) #:theme-mode 'dark))
       (render-geometry-frames/report!
        legacy-timeline legacy-directory
        #:width 160 #:height 90 #:fps 2 #:workers 1
        #:color-theme colors:animate-dark-theme)
       (define legacy-paths (frame-paths legacy-directory))
       (check-equal? (length legacy-paths) 43)
       (for ([workers '(1 2 4 10)])
         (define output-root (build-path root (format "generic-~a" workers)))
         (define report
           (render-generic output-root (build-path output-root "cache")
                           workers 'subprocess #t 160 90 'dark))
         (define diagnostics (project-execution-report-diagnostics report))
         (define child-report
           (project-frame-execution-diagnostics-subprocess-report diagnostics))
         (check-equal? (project-frame-execution-diagnostics-mode diagnostics) 'subprocess)
         (check-equal? (report-worker-count report) workers)
         (check-equal? (project-frame-execution-diagnostics-workers-completing diagnostics)
                       workers)
         (check-equal? (length (process-frame-execution-report-worker-pids child-report))
                       workers)
         (check-equal? (length (remove-duplicates
                                (process-frame-execution-report-worker-pids child-report)))
                       workers)
         (check-true
          (andmap worker-resources-closed?
                  (process-frame-execution-report-worker-resource-statuses child-report)))
         (check-true
          (> (hash-ref (project-frame-execution-diagnostics-work-accounting diagnostics)
                       'frame-reuse-aliases)
             0))
         (check-true
          (< (hash-ref (project-frame-execution-diagnostics-work-accounting diagnostics)
                       'representative-raster-jobs)
             (length legacy-paths)))
         (check-same-png-sequence legacy-paths (report-frame-paths report)))))))

  (test-case "generic geometry reuse and cache accounting materialize aliases once and then start no workers"
    (temporary-test
     (lambda (root)
       (define output-root (build-path root "output"))
       (define cache-root (build-path root "cache"))
       (define first
         (render-generic output-root cache-root 2 'subprocess #t 160 90 'dark))
       (define first-diagnostics (project-execution-report-diagnostics first))
       (define first-accounting
         (project-frame-execution-diagnostics-work-accounting first-diagnostics))
       (check-equal? (report-worker-count first) 2)
       (check-equal? (hash-ref first-accounting 'materialized-output-frames) 43)
       (check-true (> (hash-ref first-accounting 'frame-reuse-aliases) 0))
       ;; A representative cache loss schedules just that useful frame rather
       ;; than a whole legacy shard; this tests partial-hit ordering directly.
       (delete-file (car (report-frame-paths first)))
       (define partial
         (render-generic output-root cache-root 10 'subprocess #t 160 90 'dark))
       (define partial-diagnostics (project-execution-report-diagnostics partial))
       (check-equal? (report-worker-count partial) 1)
       (check-equal? (hash-ref (project-frame-execution-diagnostics-work-accounting partial-diagnostics)
                               'persistent-frame-cache-hits)
                     42)
       ;; Worker mode is not a visual cache input. A complete subsequent hit
       ;; remains useful after changing from subprocess capacity to local mode.
       (define second
         (render-generic output-root cache-root 10 'in-process #t 160 90 'dark))
       (define second-diagnostics (project-execution-report-diagnostics second))
       (check-equal? (report-worker-count second) 0)
       (check-equal? (hash-ref (project-frame-execution-diagnostics-work-accounting second-diagnostics)
                               'persistent-frame-cache-hits)
                     43)
       (check-same-png-sequence (report-frame-paths first) (report-frame-paths second)))))

  (test-case "geometry caption, theme, and aspect choices remain builder inputs and generic output dimensions"
    (temporary-test
     (lambda (root)
       (define captions-on
         (render-generic (build-path root "captions-on") (build-path root "cache-on")
                         1 'in-process #t 160 90 'dark))
       (define captions-off
         (render-generic (build-path root "captions-off") (build-path root "cache-off")
                         1 'in-process #f 160 90 'dark))
       (define light
         (render-generic (build-path root "light") (build-path root "cache-light")
                         1 'in-process #t 160 90 'light))
       (define wide
         (render-generic (build-path root "wide") (build-path root "cache-wide")
                         2 'subprocess #t 200 90 'dark))
       (check-not-equal? (file->bytes (car (report-frame-paths captions-on)))
                         (file->bytes (car (report-frame-paths light))))
       (check-true
        (for/or ([on (in-list (report-frame-paths captions-on))]
                 [off (in-list (report-frame-paths captions-off))])
          (not (equal? (file->bytes on) (file->bytes off)))))
       (check-png-dimensions (car (report-frame-paths wide)) 200 90)
       (define timeline
         (example:make-demo-timeline #:aspect (/ 160 90) #:theme-mode 'dark))
       (define on-reuse
         (geometry-frame-reuse-representatives
          timeline (build-list (geometry-frame-count timeline 2) values) 2 #t))
       (define off-reuse
         (geometry-frame-reuse-representatives
          timeline (build-list (geometry-frame-count timeline 2) values) 2 #f))
       (check-equal? (length on-reuse) (length off-reuse))
       (check-true
        (<= (length (remove-duplicates (map cadr off-reuse)))
            (length (remove-duplicates (map cadr on-reuse))))))))

  (test-case "geometry reuse uses the exact 10fps source-grid time at copy-angle boundaries"
    (define timeline
      (copy-angle:make-demo-timeline #:aspect (/ 16 9) #:theme-mode 'dark))
    (define representatives
      (geometry-frame-reuse-representatives
       timeline (build-list (geometry-frame-count timeline 10) values) 10 #t))
    ;; Frame 158 is the first rendered frame of the next construction
    ;; narration.  The scene clock rounds through the authored action boundary
    ;; there, so it must not reuse the earlier stable frame at 154.
    (check-equal? (list-ref representatives 158) '(158 158))
    (check-not-equal? (list-ref representatives 158) '(158 154)))

  (test-case "the user-facing geometry CLI uses generic workers, retains subtitles, cleans trailing frames, and rejects retired shard flags"
    (temporary-test
     (lambda (root)
       (define first-output "frames with space Æ")
       (define second-output "frames with space Æ")
       (define-values (first-code first-stdout first-stderr)
         (run-example-cli
          root
          (list "--dark" "--frames" "--workers" "2"
                "--width" "160" "--height" "90" "--fps" "2"
                "--srt" "subtitles/lesson.srt" "--vtt" "subtitles/lesson.vtt"
                first-output)))
       (check-equal? first-code 0 first-stderr)
       (check-true (string-contains? first-stdout "subprocess shared renderer"))
       (check-true (file-exists? (build-path root first-output "narration.srt")))
       (check-true (file-exists? (build-path root "subtitles/lesson.srt")))
       (check-true (file-exists? (build-path root "subtitles/lesson.vtt")))
       ;; Reuse the same public directory at a shorter FPS; managed old PNGs
       ;; must be removed even though the generic cache output is private.
       (define-values (second-code _second-stdout second-stderr)
         (run-example-cli
          root
          (list "--dark" "--frames" "--workers" "1"
                "--width" "160" "--height" "90" "--fps" "1"
                second-output)))
       (check-equal? second-code 0 second-stderr)
       (check-equal? (length (frame-paths (build-path root second-output))) 22)
       (define-values (retired-code _retired-stdout _retired-stderr)
         (run-example-cli root (list "--worker-shard")))
       (check-not-equal? retired-code 0)
       (check-false (regexp-match? #rx"run-process-sharded-render!|worker-shard"
                                   (file->string runner-path))))))
