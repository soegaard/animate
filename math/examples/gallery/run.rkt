#lang racket/base

;;;
;;; Mathematical Gallery Command Line
;;;
;; Separates pure catalogue inspection, sparse review, and normal process-rendered
;; movies. All child-process orchestration is delegated to Animate's project executor.

;;;
;;; Imports and Exports
;;;
(require racket/cmdline
         json
         (only-in racket/file make-directory* make-temporary-file)
         (only-in racket/path path-only find-relative-path)
         (only-in racket/string string-join)
         (only-in racket/lazy-require lazy-require)
         "../../main.rkt" "../../private/native.rkt"
         (only-in "../../private/derivation.rkt" derivation-step-keys)
         "model.rkt" "catalogue.rkt")
(lazy-require ["review.rkt" (write-gallery-review! write-gallery-index!)]
              ["project.rkt" (render-gallery-frames!)])
(provide run-gallery!)

; positive-integer : string? -> exact-positive-integer?
;;   Parses the explicit positive integer frame-grid and raster quantities.
(define (positive-integer text)
  (define n (string->number text))
  (unless (exact-positive-integer? n)
    (raise-user-error 'gallery "expected a positive integer, got ~s" text))
  n)

; path-inside? : path-string? path-string? -> boolean?
;;   Detects output-path overlap before rendering or encoding mutates any files.
(define (path-inside? path root)
  (define relative (find-relative-path (simplify-path (path->complete-path root))
                                       (simplify-path (path->complete-path path))))
  (and (relative-path? relative) (not (member 'up (explode-path relative)))))

; describe-gallery : list? boolean? -> void?
;;   Prints the catalogue or held step trees without requiring the native renderer.
(define (describe-gallery plates steps?)
  (printf "Math gallery: ~a plates, ~a seconds\n" (length plates) (gallery-duration plates))
  (for ([entry (in-list (gallery-entries plates))])
    (define plate (gallery-entry-plate entry))
    (define view (gallery-entry-view entry))
    (printf "\n~a / ~a [~a .. ~a s]\n  ~a\n  ~a\n  API: ~a\n"
            (gallery-plate-id plate) (gallery-view-id view) (gallery-entry-start entry)
            (gallery-entry-end entry) (gallery-plate-title plate) (gallery-view-caption view)
            (string-join (map symbol->string (gallery-view-api view)) ", "))
    (when steps?
      (for ([segment (in-list (presentation-plan-segments (gallery-view-plan view)))])
        (define d (plan-segment-derivation segment))
        (printf "  Case ~s~a\n    initial: ~s\n" (plan-segment-path segment)
                (if (plan-segment-shared? segment) " (shared prefix)" "")
                (math-datum (derivation-initial d)))
        (for ([key (in-list (derivation-step-keys d))] [step (in-list (derivation-steps d))])
          (printf "    ~s: ~s [~a]\n" key (math-datum (rewrite-step-after step)) (rewrite-step-relation step)))))))

; check-replace-gallery! : path-string? -> void?
;;   Refuses replacement of an unmarked directory or one containing unrelated user files.
(define (check-replace-gallery! root)
  (define marker (build-path root "gallery-index.json"))
  (define record
    (with-handlers ([exn:fail? (lambda (_) #f)])
      (and (file-exists? marker) (not (link-exists? marker))
           (call-with-input-file marker read-json))))
  (unless (and (hash? record)
               (equal? (hash-ref record 'schema #f) "animate-math-gallery-index-v1"))
    (raise-user-error 'gallery "--replace requires a previous gallery frame directory"))
  (for ([name (in-list (directory-list root))])
    (unless (and (file-exists? (build-path root name))
                 (not (link-exists? (build-path root name)))
                 (or (equal? (path->string name) "gallery-index.json")
                     (regexp-match? #px"^frame-[0-9]{6}\\.png$" (path->string name))))
      (raise-user-error 'gallery "refusing to replace a directory containing unowned data: ~a" name))))

; encode-gallery! : path-string? path-string? integer? integer? integer? boolean? -> void?
;;   Encodes once in the parent and publishes an MP4 only after FFmpeg succeeds.
(define (encode-gallery! frames video fps width height replace?)
  (define target (path->complete-path video))
  (make-directory* (path-only target))
  (define temporary (make-temporary-file "gallery-encode-~a.mp4" #f (path-only target)))
  (dynamic-wind void
    (lambda ()
      ((native 'render 'encode-mp4!) frames temporary #:fps fps #:width width #:height height)
      (unless (positive? (file-size temporary)) (raise-user-error 'gallery "encoder produced an empty file"))
      (rename-file-or-directory temporary target replace?))
    (lambda () (when (file-exists? temporary) (delete-file temporary)))))

; run-gallery! : -> void?
;;   Executes exactly one inspection, local review, or shared-process rendering mode.
(define (run-gallery!)
  (define ids '())
  (define chapter #f)
  (define listing #f)
  (define review? #f)
  (define review-zip #f)
  (define dense? #t)
  (define theme 'light)
  (define fps 30)
  (define workers 1)
  (define worker-mode 'auto)
  (define width 1280)
  (define height 720)
  (define supersample 1)
  (define show-api? #f)
  (define video #f)
  (define output #f)
  (define replace? #f)
  (define (inspection! mode)
    (when listing (raise-user-error 'gallery "choose one inspection mode"))
    (set! listing mode))
  (command-line
    #:program "math gallery"
    #:once-each
    ["--chapter" value "Select one chapter: held, selection, conditions, moves, presentation."
                    (set! chapter (string->symbol value))]
    ["--list-plates" "List stable plate ids and chapter membership, without rendering." (inspection! 'plates)]
    ["--list-chapters" "List the five chapters, without rendering." (inspection! 'chapters)]
    ["--describe" "Describe selected plates, variants, API calls, and timings." (inspection! 'describe)]
    ["--steps" "Print the selected held mathematical steps and relationships." (inspection! 'steps)]
    ["--review-stills" "Write sparse native review stills, contact sheets, and an HTML index." (set! review? #t)]
    ["--review-zip" path "Also package the sparse review bundle; implies --review-stills."
                          (set! review? #t) (set! review-zip path)]
    ["--checkpoints-only" "In review mode, omit intermediate phase probes." (set! dense? #f)]
    ["--show-api" "Show a small API label on each plate." (set! show-api? #t)]
    ["--dark" "Use the dark mathematical palette." (set! theme 'dark)]
    ["--light" "Use the light mathematical palette." (set! theme 'light)]
    ["--fps" value "Movie frame rate (positive integer; default 30)." (set! fps (positive-integer value))]
    ["--workers" value "Shared renderer concurrency limit (default 1)." (set! workers (positive-integer value))]
    ["--worker-mode" value "auto, in-process, or subprocess; forwarded to the shared renderer."
                           (set! worker-mode (string->symbol value))]
    ["--width" value "Native camera width in pixels (default 1280)." (set! width (positive-integer value))]
    ["--height" value "Native camera height in pixels (default 720)." (set! height (positive-integer value))]
    ["--supersample" value "Movie PNG supersampling factor (default 1)." (set! supersample (positive-integer value))]
    ["--mp4" path "Encode one MP4 after the selected PNG sequence is complete." (set! video path)]
    ["--replace" "Explicitly replace an existing gallery frame output and/or MP4." (set! replace? #t)]
    #:multi
    ["--plate" value "Select a plate (repeatable; catalogue order is preserved)."
                      (set! ids (append ids (list (string->symbol value))))]
    #:args ([directory #f]) (set! output directory))
  (unless (memq worker-mode '(auto in-process subprocess))
    (raise-user-error 'gallery "unknown worker mode: ~a" worker-mode))
  (define plates (select-gallery-plates #:plates (and (pair? ids) ids) #:chapter chapter))
  (when (and listing (or review? video replace?))
    (raise-user-error 'gallery "inspection cannot be combined with output flags"))
  (when (and review? (or video replace? (not (= supersample 1))))
    (raise-user-error 'gallery "review uses a new directory and native-size stills; omit --mp4, --replace, and --supersample"))
  (when (and (not dense?) (not review?))
    (raise-user-error 'gallery "--checkpoints-only requires a review mode"))
  (cond
    [listing
     (case listing
       [(chapters) (for ([entry (in-list gallery-chapters)]) (printf "~a\t~a\n" (car entry) (cdr entry)))]
       [(plates) (for ([plate (in-list plates)])
                   (printf "~a\t~a\t~a\n" (gallery-plate-id plate) (gallery-plate-chapter plate) (gallery-plate-title plate)))]
       [else (describe-gallery plates (eq? listing 'steps))])]
    [else
     (define destination (or output (if review? "math-output/gallery/review" "math-output/gallery/frames/all")))
     (when (or (file-exists? destination) (link-exists? destination))
       (raise-user-error 'gallery "destination must not be a file or symbolic link: ~a" destination))
     (when (directory-exists? destination)
       (unless (and (not review?) replace? (file-exists? (build-path destination "gallery-index.json")))
         (raise-user-error 'gallery "destination exists; choose a new directory or use --replace on a previous gallery: ~a" destination)))
     (when (and replace? (directory-exists? destination)) (check-replace-gallery! destination))
     (when review-zip
       (when (or (path-inside? review-zip destination) (file-exists? review-zip)
                 (directory-exists? review-zip) (link-exists? review-zip))
         (raise-user-error 'gallery "review ZIP must be a new file outside the review directory")))
     (when video
       (when (or (path-inside? video destination) (directory-exists? video) (link-exists? video)
                 (and (file-exists? video) (not replace?)))
         (raise-user-error 'gallery "MP4 must be outside the frame directory; use --replace to replace a file"))
       (unless (and (even? (* width supersample)) (even? (* height supersample)))
         (raise-user-error 'gallery "H.264 MP4 output requires even actual PNG dimensions"))
       (unless (find-executable-path "ffmpeg") (raise-user-error 'gallery "ffmpeg must be on PATH for --mp4")))
     (cond
       [review?
        (define manifest (write-gallery-review! plates destination #:theme theme #:width width #:height height
                                                #:show-api? show-api? #:dense? dense? #:zip review-zip))
        (printf "Wrote ~a native stills and ~a sheets to ~a (local review; no worker pool).\n"
                (length (hash-ref manifest 'stills)) (length (hash-ref manifest 'sheets)) destination)]
       [else
        (define report
          (render-gallery-frames! plates destination theme fps workers width height supersample show-api?
                                  #:worker-mode worker-mode #:replace? replace?))
        (write-gallery-index! destination plates #:fps fps)
        (define diagnostics ((native 'project-execution 'project-execution-report-diagnostics) report))
        (printf "Gallery: ~a plates; ~a seconds; ~a requested frames.\n" (length plates)
                (gallery-duration plates)
                ((native 'project-execution 'project-frame-execution-diagnostics-requested-frame-count) diagnostics))
        (printf "Workers: requested ~a, started ~a, completing ~a (~a).\n" workers
                ((native 'project-execution 'project-frame-execution-diagnostics-workers-started) diagnostics)
                (or ((native 'project-execution 'project-frame-execution-diagnostics-workers-completing) diagnostics) "n/a")
                ((native 'project-execution 'project-frame-execution-diagnostics-mode) diagnostics))
        (when video
          (encode-gallery! destination video fps (* width supersample) (* height supersample) replace?)
          (printf "Wrote ~a\n" video))])]))
