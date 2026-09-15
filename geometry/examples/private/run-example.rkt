#lang racket/base

;;;
;;; Geometry Example Command Runner
;;;

;; The full-frame path declares a restartable project and delegates its owned
;; worker session to the shared project executor. Sparse review and still
;; commands intentionally remain local geometry presentation operations.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/cmdline
         racket/file
         racket/format
         racket/list
         racket/path
         racket/pretty
         (prefix-in native-colors: "../../../colors.rkt")
         "../../../project.rkt"
         "../../../private/project-execution.rkt"
         "../../main.rkt"
         "../../render.rkt"
         "../../review.rkt"
         "../../private/subtitle-output.rkt")

;; Exports
(provide run-geometry-example)


;;;
;;; Local Output Helpers
;;;

; positive-integer : string? string? -> exact-positive-integer?
;;   Parses one positive command-line integer with the option in its diagnostic.
(define (positive-integer text option)
  (define n (string->number text))
  (unless (exact-positive-integer? n)
    (error 'run-geometry-example "~a expects a positive integer, received ~e" option text))
  n)

; ensure-clean-frame-directory! : path-string? -> void?
;;   Removes only geometry-managed full-frame files while preserving other output.
(define (ensure-clean-frame-directory! directory)
  (make-directory* directory)
  (for ([entry (in-list (directory-list directory))])
    (define name (path->string (file-name-from-path entry)))
    (define path (build-path directory entry))
    (when (or (regexp-match? #rx"^frame-[0-9]+\\.png$" name)
              (member name '("narration.srt" "stills.tsv")))
      (when (file-exists? path) (delete-file path)))))

; directory-frame-paths : path-string? -> (listof path?)
;;   Returns managed PNG paths in their canonical local-sequence order.
(define (directory-frame-paths directory)
  (sort (for/list ([entry (in-list (directory-list directory))]
                   #:when (regexp-match? #rx"^frame-[0-9]+\\.png$"
                                         (path->string (file-name-from-path entry))))
          (build-path directory entry))
        string<?
        #:key path->string))

; frame-index->destination-path : path-string? exact-nonnegative-integer? -> path?
;;   Produces geometry's established six-digit PNG destination name.
(define (frame-index->destination-path directory frame-index)
  (build-path directory
              (format "frame-~a.png"
                      (~r frame-index #:min-width 6 #:pad-string "0"))))

; make-timeline : symbol? procedure? exact-positive-integer? exact-positive-integer?
;                 symbol? -> geometry-timeline?
;;   Adapts the historic main-submodule factory convention to a timeline value.
(define (make-timeline name factory width height theme-mode)
  (define aspect (/ width height))
  (cond [(procedure-arity-includes? factory 2) (factory aspect theme-mode)]
        [(procedure-arity-includes? factory 1) (factory aspect)]
        [else (error name "factory must accept 1 or 2 arguments")]))


;;;
;;; Generic Project Frame Execution
;;;

; geometry-project-output-parts : path-string? -> path? string? path?
;;   Allocates one private, per-invocation generic output directory beside the
;;   public geometry directory. Its generated name makes cleanup ownership
;;   explicit and avoids replacing a user-selected sibling.
(define (geometry-project-output-parts destination)
  (define complete-destination
    (simplify-path (path->complete-path destination)))
  (define root
    (or (path-only complete-destination) (current-directory)))
  (define leaf (file-name-from-path complete-destination))
  (unless leaf
    (raise-arguments-error
     'geometry-project-output-parts
     "a named output directory rather than a filesystem root"
     "destination" destination))
  (define temporary-name
    (format ".~a.animate-project-frames-~a"
            (path->string leaf)
            (gensym 'geometry-render)))
  (values root temporary-name (build-path root temporary-name)))

; make-geometry-render-project : string? path-string? path-string? ... -> animate-project? path?
;;   Declares the restartable full-frame project for one example and returns its
;;   private generic PNG publication directory. Geometry's source preparer owns
;;   semantic static-frame reuse; this wrapper owns only project configuration.
(define (make-geometry-render-project name source-module-path destination
                                      fps width height supersample workers
                                      theme-mode native-color-theme captions?)
  (define-values (output-root output-name private-output-directory)
    (geometry-project-output-parts destination))
  (when (or (file-exists? private-output-directory)
            (directory-exists? private-output-directory)
            (link-exists? private-output-directory))
    (raise-arguments-error
     'make-geometry-render-project
     "a fresh generated private output directory"
     "private-output-directory" private-output-directory))
  (values
   (animate-project
    #:id (string->symbol (format "geometry-~a" name))
    #:source
    (module-builder-source
     source-module-path
     'geometry-render-builder
     #:prepare 'geometry-render-preparer
     #:options (hasheq 'width width
                        'height height
                        'fps fps
                        'theme-mode theme-mode
                        'captions? captions?))
    #:render
    (render-spec #:fps fps
                 #:width width
                 #:height height
                 #:supersample supersample
                 #:workers workers
                 #:worker-mode 'auto
                 #:theme native-color-theme)
    #:output
    (output-spec #:root output-root
                 #:name output-name
                 #:format 'png-sequence
                 #:overwrite-policy 'replace)
    #:encoder (encoder-spec #:codec 'none)
    #:cache
    (cache-spec #:root (build-path output-root ".animate-geometry-render-cache")
                 #:policy 'read-write))
   private-output-directory))

; publish-generic-geometry-frames! : path-string? path-string? exact-positive-integer? -> (listof path?)
;;   Moves a complete generic frame sequence into geometry's long-standing
;;   public directory names. This is final output publication, not a second
;;   semantic reuse pass: all representative/alias materialization is complete.
(define (publish-generic-geometry-frames! private-directory destination expected-count)
  (unless (directory-exists? private-directory)
    (raise-arguments-error
     'publish-generic-geometry-frames!
     "the private generic PNG sequence produced by this invocation"
     "private-directory" private-directory))
  (define paths (directory-frame-paths private-directory))
  (unless (= (length paths) expected-count)
    (raise-arguments-error
     'publish-generic-geometry-frames!
     "the complete expected geometry PNG sequence"
     "actual-frame-count" (length paths)
     "expected-frame-count" expected-count))
  (ensure-clean-frame-directory! destination)
  (for ([path (in-list paths)]
        [frame-index (in-naturals 0)])
    (rename-file-or-directory
     path
     (frame-index->destination-path destination frame-index)
     #f))
  (directory-frame-paths destination))

; render-geometry-project-frames! : string? geometry-timeline? path-string? ...
;                                   -> project-execution-report? (listof path?)
;;   Runs the shared project executor, publishes the completed sequence, and
;;   emits geometry's subtitle/MP4 artifacts after PNG ownership transfers.
(define (render-geometry-project-frames! name timeline source-module-path destination
                                         fps width height supersample workers
                                         theme-mode native-color-theme captions?
                                         subtitle-plan mp4 mp4-srt subtitle-language)
  (define-values (project private-output-directory)
    (make-geometry-render-project name source-module-path destination
                                  fps width height supersample workers
                                  theme-mode native-color-theme captions?))
  (define expected-count (geometry-frame-count timeline fps))
  (define report #f)
  (define paths #f)
  (dynamic-wind
   void
   (lambda ()
     (set! report (render-project! project #:directory (current-directory)))
     (define artifact-directory
       (hash-ref (project-execution-report-artifact-paths report)
                 'frame-sequence
                 #f))
     (unless (and artifact-directory
                  (equal? (simplify-path (path->complete-path artifact-directory))
                          (simplify-path private-output-directory)))
       (raise-arguments-error
        'render-geometry-project-frames!
        "the declared private generic frame-sequence artifact"
        "artifact-directory" artifact-directory
        "private-output-directory" private-output-directory))
     (set! paths
           (publish-generic-geometry-frames!
            private-output-directory destination expected-count))
     (write-geometry-subtitle-outputs! timeline subtitle-plan)
     (when mp4
       (encode-geometry-mp4! timeline destination mp4
                             #:fps fps #:width width #:height height
                             #:srt mp4-srt
                             #:subtitle-language subtitle-language))
     (values report paths))
   (lambda ()
     ;; The generated directory was fresh at call entry and is the only private
     ;; final-output path this invocation owns. Persistent caches stay intact.
     (when (directory-exists? private-output-directory)
       (delete-directory/files private-output-directory))))
  (values report paths))

; current-example-module-path : string? -> path?
;;   Resolves the explicitly launched example module used by worker builders.
(define (current-example-module-path name)
  (define run-file (find-system-path 'run-file))
  (unless run-file
    (error name "cannot determine the current example file for project rendering"))
  (simplify-path (path->complete-path run-file)))

; print-project-frame-report : project-execution-report? exact-positive-integer?
;                              (listof path?) path-string? -> void?
;;   Prints parent-observed generic worker facts without inferring process state.
(define (print-project-frame-report report requested-workers paths destination)
  (define diagnostics (project-execution-report-diagnostics report))
  (printf "Wrote ~a frames to ~a\n" (length paths) destination)
  (printf "Workers: requested ~a, started ~a, completing ~a (~a shared renderer)\n"
          requested-workers
          (project-frame-execution-diagnostics-workers-started diagnostics)
          (or (project-frame-execution-diagnostics-workers-completing diagnostics) "n/a")
          (project-frame-execution-diagnostics-mode diagnostics))
  (printf "Render time: ~a ms\n"
          (inexact->exact
           (round (project-frame-execution-diagnostics-elapsed-milliseconds diagnostics)))))


;;;
;;; Command Line
;;;

; run-geometry-example : string? procedure? -> void?
;;   Runs one geometry example's explicit main-submodule command interface.
(define (run-geometry-example name factory)
  (define frames? #f)
  (define review-directory #f)
  (define review-zip #f)
  (define contact-sheet? #t)
  (define expanded-review? #t)
  (define include-cleanup-review? #f)
  (define review-modifier? #f)
  (define positional-directory #f)
  (define describe? #f)
  (define captions? #t)
  (define mp4 #f)
  (define srt #f)
  (define vtt #f)
  (define subtitles-only? #f)
  (define subtitle-language "eng")
  (define fps 30)
  (define width 1280)
  (define height 720)
  (define supersample 1)
  (define workers 10)
  (define destination #f)
  (define theme-mode 'light)
  (define native-color-theme native-colors:animate-light-theme)
  (command-line
   #:program name
   #:once-each
   [("--frames") "Render every frame (the default is one still per step)." (set! frames? #t)]
   [("--review-stills") dir "Render sparse review images (including compass phases) into DIR." (set! review-directory dir)]
   [("--review-zip") path "Write a review ZIP; also keep its image directory." (set! review-zip path)]
   [("--no-contact-sheet") "Omit paginated review contact sheets." (set! contact-sheet? #f) (set! review-modifier? #t)]
   [("--review-top-level-only") "Only outer authored steps in the review." (set! expanded-review? #f) (set! review-modifier? #t)]
   [("--review-include-cleanup") "Include silent cleanup/no-op rows in the review." (set! include-cleanup-review? #t) (set! review-modifier? #t)]
   [("--describe") "Print realization diagnostics without rendering." (set! describe? #t)]
   [("--captions") "Show on-screen captions (default); independent of subtitle export." (set! captions? #t)]
   [("--no-captions") "Omit on-screen captions; subtitle exports are unchanged." (set! captions? #f)]
   [("--srt") path "Write an SRT file; overrides the default MP4-sidecar filename." (set! srt path)]
   [("--vtt") path "Also write a WebVTT file." (set! vtt path)]
   [("--subtitles-only") "Export --srt/--vtt without rendering images or encoding video." (set! subtitles-only? #t)]
   [("--subtitle-language") code "ISO 639-2 subtitle language code for embedded MP4 tracks; default eng." (set! subtitle-language code)]
   [("--mp4") path "Render an MP4 with a selectable subtitle track plus a same-basename SRT file (captions remain on)." (set! mp4 path) (set! frames? #t)]
   [("--light") "Use the animate light theme and matching geometry palette (default)."
                 (set! theme-mode 'light)
                 (set! native-color-theme native-colors:animate-light-theme)]
   [("--dark") "Use the animate dark theme and matching geometry palette."
                (set! theme-mode 'dark)
                (set! native-color-theme native-colors:animate-dark-theme)]
   [("--fps") n "Frame rate, default 30." (set! fps (positive-integer n "--fps"))]
   [("--width") n "Output width in pixels, default 1280." (set! width (positive-integer n "--width"))]
   [("--height") n "Output height in pixels, default 720." (set! height (positive-integer n "--height"))]
   [("--supersample") n "Native render supersampling factor, default 1." (set! supersample (positive-integer n "--supersample"))]
   [("--workers") n "Shared renderer worker capacity for full-frame rendering, default 10."
                    (set! workers (positive-integer n "--workers"))]
   #:args ([directory #f])
   (set! positional-directory directory)
   (set! destination (or directory (build-path "geometry-output" name))))
  (unless (regexp-match? #px"^[A-Za-z]{3}$" subtitle-language)
    (error name "--subtitle-language expects a three-letter ISO 639-2 code, received ~e" subtitle-language))
  (set! subtitle-language (string-downcase subtitle-language))
  (define review? (or review-directory review-zip))
  (when (and subtitles-only? (or review? frames? mp4 describe? positional-directory))
    (error name "--subtitles-only cannot be combined with rendering, --describe, or a frame directory"))
  (when (and subtitles-only? (not (or srt vtt)))
    (error name "--subtitles-only needs --srt FILE and/or --vtt FILE"))
  (when (and review? (or frames? mp4 describe?))
    (error name "review mode cannot be combined with --frames, --mp4, or --describe"))
  (when (and review-modifier? (not review?))
    (error name "review modifiers need --review-stills or --review-zip"))
  (when (and review-directory positional-directory)
    (error name "choose the review directory with --review-stills, not both it and a positional directory"))
  (when review-zip
    (unless (regexp-match? #px"(?i:\\.zip)$" review-zip)
      (error name "--review-zip expects a filename ending in .zip")))
  (when review?
    (set! destination
          (or review-directory positional-directory
              (regexp-replace #px"(?i:\\.zip)$" review-zip ""))))

  ;; Preflight all export paths before rendering or cleaning frame output.
  ;; Review extras must remain outside the managed bundle directory, otherwise
  ;; they would invalidate its manifest and make a later safe rerun fail.
  (define subtitle-plan
    (geometry-subtitle-output-plan
     #:directory (and (not review?) (not describe?) (not subtitles-only?) destination)
     #:mp4 mp4 #:srt srt #:vtt vtt))
  (when review?
    (define review-parts (explode-path (simplify-path (path->complete-path destination))))
    (for ([entry (in-list subtitle-plan)])
      (define parts (explode-path (car entry)))
      (when (or (and (<= (length review-parts) (length parts))
                     (equal? review-parts (take parts (length review-parts))))
                (and review-zip (equal? (car entry) (simplify-path (path->complete-path review-zip)))))
        (error name "subtitle export must be outside the review bundle and use a different path from its ZIP: ~a" (car entry)))))
  (define timeline (make-timeline name factory width height theme-mode))
  (define (announce-subtitles!)
    (for ([entry (in-list subtitle-plan)])
      (printf "Subtitles (~a): ~a\n" (cdr entry) (car entry))))

  (cond [subtitles-only?
         (write-geometry-subtitle-outputs! timeline subtitle-plan)
         (announce-subtitles!)]
        [review?
         (printf "Rendering sparse review images (~a / ~a)...\n" name theme-mode)
         (flush-output)
         (define report
           (render-geometry-review! timeline destination #:name name
                                    #:width width #:height height #:fps fps #:supersample supersample
                                    #:captions? captions? #:color-theme native-color-theme
                                    #:theme-name (symbol->string theme-mode)
                                    #:expanded? expanded-review?
                                    #:include-cleanup? include-cleanup-review?
                                    #:contact-sheet? contact-sheet?
                                    #:zip review-zip))
         (printf "Wrote ~a review images for ~a steps to ~a\n"
                 (geometry-review-result-image-count report) (geometry-review-result-step-count report)
                 (geometry-review-result-directory report))
         (printf "Contact sheets: ~a; step captions: steps.txt; browser index: index.html\n"
                 (length (geometry-review-result-contact-sheets report)))
         (when (geometry-review-result-zip report)
           (printf "Review ZIP: ~a\n" (geometry-review-result-zip report)))
         (write-geometry-subtitle-outputs! timeline subtitle-plan)
         (announce-subtitles!)
         (void)]
        [describe?
         (printf "~a: ~a seconds\n" name (geometry-timeline-duration timeline))
         (pretty-write (geometry-realization-diagnostics (geometry-timeline-realization timeline)))
         (pretty-write (geometry-realization-choices (geometry-timeline-realization timeline)))
         (define plan (geometry-timeline->annotation-plan timeline #:width width
                                                          #:captions? captions?))
         (printf "Annotation metrics: ~a\n" (annotation-plan-metrics plan))
         (printf "Annotation warnings: ~a\n" (annotation-plan-warnings plan))
         (pretty-write (annotation-plan-labels plan))
         (write-geometry-subtitle-outputs! timeline subtitle-plan)
         (announce-subtitles!)]
        [frames?
         (printf "Rendering with ~a requested worker~a...\n"
                 workers (if (= workers 1) "" "s"))
         (define-values (report paths)
           (render-geometry-project-frames!
            name timeline (current-example-module-path name) destination
            fps width height supersample workers theme-mode native-color-theme captions?
            subtitle-plan mp4 srt subtitle-language))
         (print-project-frame-report report workers paths destination)
         (when mp4 (printf "Encoded ~a with selectable subtitles\n" mp4))
         (announce-subtitles!)]
        [else
         (define paths
           (render-geometry-stills! timeline destination #:width width #:height height
                                    #:fps fps #:supersample supersample #:captions? captions?
                                    #:color-theme native-color-theme #:srt srt #:vtt vtt))
         (printf "Wrote ~a step stills to ~a\n" (length paths) destination)
         (announce-subtitles!)]))
