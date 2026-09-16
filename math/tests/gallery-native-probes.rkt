#lang racket/base

;;;
;;; Actual Mathematical Gallery Probes
;;;
;; Uses installed Animate, TeX, and native graphics. Optional process checking renders
;; the same gallery through the real direct and shared subprocess executors, not a mock.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline
         (only-in racket/file make-temporary-file delete-directory/files file->lines)
         (only-in racket/list remove-duplicates)
         (only-in racket/path file-name-from-path)
         (only-in openssl/sha1 bytes->hex-string)
         (only-in racket/lazy-require lazy-require)
         json
         "../main.rkt" "../private/native.rkt" "../private/prepared-plan-model.rkt"
         "../examples/gallery/model.rkt" "../examples/gallery/catalogue.rkt")
(lazy-require ["../examples/gallery/review.rkt" (write-gallery-review!)]
              ["../examples/gallery/project.rkt" (render-gallery-frames!)])
(provide run-gallery-native-probes!)

; positive-integer : string? -> exact-positive-integer?
;;   Parses a native probe quantity without silently truncating the frame grid.
(define (positive-integer text)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-user-error 'gallery-probes "expected a positive integer, got ~s" text))
  value)

; frame-manifest! : path-string? -> list?
;;   Hashes every canonical PNG in output order without decoding production images.
(define (frame-manifest! root)
  (for/list ([name (in-list (sort (directory-list root) path<?))]
               #:when (regexp-match? #px"^frame-[0-9]{6}\\.png$" (path->string name)))
    (list (path->string name)
          (call-with-input-file (build-path root name)
            (lambda (in) (bytes->hex-string (sha256-bytes in)))))))

; log-line-count! : path-string? -> exact-nonnegative-integer?
;;   Counts inherited effect-boundary events emitted by both parent and child runtimes.
(define (log-line-count! path)
  (if (file-exists? path) (length (file->lines path)) 0))

; with-event-logs! : path-string? path-string? procedure? -> any/c
;;   Scopes observer environment variables and restores the caller's original settings.
(define (with-event-logs! preparation-log typeset-log thunk)
  (define variables '("ANIMATE_MATH_PREPARATION_EVENT_LOG" "ANIMATE_MATH_TYPESET_EVENT_LOG"))
  (define environment (current-environment-variables))
  (define names (map string->bytes/utf-8 variables))
  (define previous (map (lambda (name) (environment-variables-ref environment name)) names))
  (dynamic-wind
    (lambda ()
      (for ([name (in-list names)] [path (in-list (list preparation-log typeset-log))])
        (environment-variables-set! environment name (path->bytes (path->complete-path path)))))
    thunk
    (lambda ()
      (for ([name (in-list names)] [value (in-list previous)])
        (environment-variables-set! environment name value)))))

; check-process-gallery! : list? path-string? symbol? integer? integer? integer? integer? boolean? -> hash?
;;   Verifies real native 1/N-worker pixel identity, shared preparation, and zero-worker cache reuse.
(define (check-process-gallery! plates output theme fps workers width height show-api?)
  (unless (> workers 1) (raise-user-error 'gallery-probes "--process-check requires --workers > 1"))
  (define scratch (make-temporary-file "gallery-native-workers-~a" 'directory output))
  (define entries (gallery-entries plates))
  (define expected-typesets
    (for/sum ([entry (in-list entries)])
      (length (remove-duplicates
                (map math-datum (math-preparation-states (gallery-view-plan (gallery-entry-view entry))))))))
  (define (run name count cache)
    (define frames (build-path scratch name))
    (define prepare-log (build-path scratch (string-append name "-prepare.txt")))
    (define typeset-log (build-path scratch (string-append name "-typeset.txt")))
    (define report
      (with-event-logs! prepare-log typeset-log
        (lambda ()
          (render-gallery-frames! plates frames theme fps count width height 1 show-api? #:cache-root cache))))
    (define diagnostics ((native 'project-execution 'project-execution-report-diagnostics) report))
    (define (field suffix)
      ((native 'project-execution
               (string->symbol (string-append "project-frame-execution-diagnostics-" suffix))) diagnostics))
    (unless (and (= (log-line-count! prepare-log) (length entries))
                 (= (log-line-count! typeset-log) expected-typesets))
      (raise-user-error 'gallery-probes "unexpected preparation/typesetter calls in ~a" name))
    (values
      (hasheq 'run name 'mode (symbol->string (field "mode"))
              'requested count 'started (field "workers-started")
              'completing (field "workers-completing")
              'frames (field "requested-frame-count") 'rendered (field "rendered-frame-count")
              'reused (field "reused-frame-count") 'parent-math-preparations (log-line-count! prepare-log)
              'total-typeset-entries (log-line-count! typeset-log)
              'elapsed-ms (exact->inexact (field "elapsed-milliseconds")))
      (frame-manifest! frames)))
  (dynamic-wind void
    (lambda ()
      (define-values (direct oracle) (run "direct" 1 (build-path scratch "cache-direct")))
      (define-values (parallel actual) (run "parallel" workers (build-path scratch "cache-shared")))
      (unless (and (pair? oracle) (equal? oracle actual))
        (raise-user-error 'gallery-probes "direct/subprocess PNG bytes differ"))
      (unless (and (equal? (hash-ref parallel 'mode) "subprocess")
                   (> (hash-ref parallel 'started) 1)
                   (> (or (hash-ref parallel 'completing) 0) 1))
        (raise-user-error 'gallery-probes "multiple subprocess workers did not complete real frame work"))
      (define-values (cached cache-actual) (run "cached" workers (build-path scratch "cache-shared")))
      (unless (and (equal? oracle cache-actual) (zero? (hash-ref cached 'started))
                   (zero? (hash-ref cached 'rendered))
                   (= (hash-ref cached 'reused) (length oracle)))
        (raise-user-error 'gallery-probes "identical gallery repeat did not reuse every cached frame"))
      (define result
        (hasheq 'schema "animate-math-gallery-process-check-v1" 'native? #t
                'fps fps 'width width 'height height 'frame-count (length oracle)
                'hash "SHA-256" 'byte-mismatches 0 'oracle oracle
                'runs (list direct parallel cached)))
      (call-with-output-file (build-path output "process-check.json") #:exists 'error
        (lambda (out) (write-json result out)))
      result)
    (lambda () (delete-directory/files scratch))))

; run-gallery-native-probes! : -> void?
;;   Writes native review material and optionally checks the actual process renderer.
(define (run-gallery-native-probes!)
  (define ids '())
  (define chapter #f)
  (define theme 'light)
  (define width 1280)
  (define height 720)
  (define show-api? #f)
  (define dense? #t)
  (define process? #f)
  (define workers 2)
  (define fps 2)
  (define output #f)
  (command-line
    #:program "math gallery probes"
    #:once-each
    ["--chapter" value "Select one chapter." (set! chapter (string->symbol value))]
    ["--dark" "Use dark formulas and background." (set! theme 'dark)]
    ["--light" "Use light formulas and background." (set! theme 'light)]
    ["--width" value "Native review/process width (default 1280)." (set! width (positive-integer value))]
    ["--height" value "Native review/process height (default 720)." (set! height (positive-integer value))]
    ["--show-api" "Show the API labels." (set! show-api? #t)]
    ["--checkpoints-only" "Omit intermediate stills." (set! dense? #f)]
    ["--process-check" "Also compare real 1/N worker PNGs and a full cache hit." (set! process? #t)]
    ["--workers" value "Subprocess capacity for --process-check (default 2)." (set! workers (positive-integer value))]
    ["--fps" value "Frame grid for --process-check (default 2, not a performance benchmark)." (set! fps (positive-integer value))]
    #:multi
    ["--plate" value "Select a plate, repeatable." (set! ids (append ids (list (string->symbol value))))]
    #:args (directory) (set! output directory))
  (when (and process? (= workers 1)) (raise-user-error 'gallery-probes "choose at least two workers"))
  (define plates (select-gallery-plates #:plates (and (pair? ids) ids) #:chapter chapter))
  (define review
    (write-gallery-review! plates output #:theme theme #:width width #:height height
                           #:show-api? show-api? #:dense? dense?))
  (printf "Native gallery: ~a deterministic stills; ~a contact sheets.\n"
          (length (hash-ref review 'stills)) (length (hash-ref review 'sheets)))
  (when process?
    (define evidence (check-process-gallery! plates (path->complete-path output) theme fps workers width height show-api?))
    (printf "Actual process renderer: ~a frames matched; multiple workers completed work; cached rerun started zero workers.\n"
            (hash-ref evidence 'frame-count))))
