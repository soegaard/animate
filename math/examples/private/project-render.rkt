#lang racket/base

;;;
;;; Mathematical Example Project Rendering
;;;
;; Separates lesson declarations from explicit inspection, cache preparation, frame
;; rendering, and video encoding.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (for-syntax racket/base)
  racket/file
  racket/format
  racket/list
  racket/path
  (only-in racket/runtime-path define-runtime-path)
  (only-in racket/string string-replace)
  (prefix-in native-colors: "../../../colors.rkt")
  "../../../project.rkt"
  "../../../private/project-execution.rkt"
  "../../main.rkt"
  "../../render.rkt"
  "../../private/native.rkt")

;; Exports
(provide render-math-example!)

;;;
;;; Construction and Operations
;;;
; render-module : path?
;;   Locates the parent animate rendering module without loading it during lesson
;;   construction.
(define-runtime-path render-module "../../../render.rkt")

;;;
;;; Generic Project Frame Execution
;;;

; math-project-output-parts : path-string? -> path? string? path?
;;   Allocates an invocation-owned generic publication directory next to the
;;   long-standing public math frame directory.
(define (math-project-output-parts destination)
  (define complete-destination
    (simplify-path (path->complete-path destination)))
  (define root (or (path-only complete-destination) (current-directory)))
  (define leaf (file-name-from-path complete-destination))
  (unless leaf
    (raise-arguments-error
     'math-project-output-parts
     "a named output directory rather than a filesystem root"
     "destination" destination))
  (define temporary-name
    (format ".~a.animate-project-frames-~a"
            (path->string leaf)
            (gensym 'math-render)))
  (values root temporary-name (build-path root temporary-name)))

; directory-frame-paths : path-string? -> (listof path?)
;;   Lists Animate-owned six-digit PNGs in deterministic local frame order.
(define (directory-frame-paths directory)
  (sort
   (for/list ([entry (in-list (directory-list directory))]
              #:when (regexp-match? #rx"^frame-[0-9]+\\.png$"
                                    (path->string (file-name-from-path entry))))
     (build-path directory entry))
   string<?
   #:key path->string))

; clean-math-frame-directory! : path-string? -> void?
;;   Replaces only the frame paths the historic math runner itself owned.
(define (clean-math-frame-directory! directory)
  (make-directory* directory)
  (for ([path (in-list (directory-frame-paths directory))])
    (delete-file path)))

; math-frame-path : path-string? exact-nonnegative-integer? -> path?
;;   Keeps the runner's established numbered PNG convention.
(define (math-frame-path directory frame-index)
  (build-path directory
              (format "frame-~a.png"
                      (~r frame-index #:min-width 6 #:pad-string "0"))))

; current-example-module-path : symbol? -> path?
;;   Resolves the explicitly launched lesson module for every restarted builder.
(define (current-example-module-path name)
  (define run-file (find-system-path 'run-file))
  (unless run-file
    (error name "cannot determine the current example module"))
  (simplify-path (path->complete-path run-file)))

; make-math-render-project : symbol? path-string? path-string? ... -> animate-project? path?
;;   Declares the shared-preparation, restartable math project and private output.
(define (make-math-render-project name source-module-path destination
                                  case-path theme fps workers width height supersample)
  (define-values (output-root output-name private-output-directory)
    (math-project-output-parts destination))
  (when (or (file-exists? private-output-directory)
            (directory-exists? private-output-directory)
            (link-exists? private-output-directory))
    (raise-arguments-error
     'make-math-render-project
     "a fresh generated private output directory"
     "private-output-directory" private-output-directory))
  (define native-theme
    (case theme
      [(light) native-colors:animate-light-theme]
      [(dark) native-colors:animate-dark-theme]
      [else (raise-argument-error 'make-math-render-project "'light or 'dark" theme)]))
  (values
   (animate-project
    #:id (string->symbol (format "math-~a" name))
    #:source
    (module-builder-source
     source-module-path
     'math-render-builder
     #:prepare 'math-render-preparer
     #:options
     (hasheq 'lesson name
             'case-path case-path
             'title (string-replace (symbol->string name) "-" " ")
             'theme-mode theme
             'width width
             'height height
             'fps fps
             'supersample supersample))
    #:render
    (render-spec #:fps fps
                 #:width width
                 #:height height
                 #:supersample supersample
                 #:workers workers
                 #:worker-mode 'auto
                 #:theme native-theme)
    #:output
    (output-spec #:root output-root
                 #:name output-name
                 #:format 'png-sequence
                 #:overwrite-policy 'replace)
    #:encoder (encoder-spec #:codec 'none)
    #:cache
    (cache-spec #:root (build-path output-root ".animate-math-render-cache")
                 #:policy 'read-write))
   private-output-directory))

; publish-generic-math-frames! : path-string? path-string? exact-nonnegative-integer?
;;                                -> (listof path?)
;;   Transfers a complete generic frame sequence to the public math location once.
(define (publish-generic-math-frames! private-directory destination expected-count)
  (unless (directory-exists? private-directory)
    (raise-arguments-error
     'publish-generic-math-frames!
     "the private generic PNG sequence produced by this invocation"
     "private-directory" private-directory))
  (define paths (directory-frame-paths private-directory))
  (unless (= (length paths) expected-count)
    (raise-arguments-error
     'publish-generic-math-frames!
     "the complete expected math PNG sequence"
     "actual-frame-count" (length paths)
     "expected-frame-count" expected-count))
  (clean-math-frame-directory! destination)
  (for ([path (in-list paths)] [frame-index (in-naturals 0)])
    (rename-file-or-directory path (math-frame-path destination frame-index) #f))
  (directory-frame-paths destination))

; render-math-project-frames! : symbol? path-string? path-string? ...
;;                             -> project-execution-report? (listof path?)
;;   Runs parent preparation plus shared worker rendering, then optionally encodes once.
(define (render-math-project-frames! name source-module-path destination
                                     case-path theme fps workers width height supersample video)
  (define-values (project private-output-directory)
    (make-math-render-project name source-module-path destination case-path theme
                              fps workers width height supersample))
  (define report #f)
  (define paths #f)
  (dynamic-wind
   void
   (lambda ()
     (set! report (render-project! project #:directory (current-directory)))
     (define artifact-directory
       (hash-ref (project-execution-report-artifact-paths report) 'frame-sequence #f))
     (unless (and artifact-directory
                  (equal? (simplify-path (path->complete-path artifact-directory))
                          (simplify-path private-output-directory)))
       (raise-arguments-error
        'render-math-project-frames!
        "the declared private generic frame-sequence artifact"
        "artifact-directory" artifact-directory
        "private-output-directory" private-output-directory))
     (define diagnostics (project-execution-report-diagnostics report))
     (set! paths
           (publish-generic-math-frames!
            private-output-directory destination
            (project-frame-execution-diagnostics-requested-frame-count diagnostics)))
     (when video
       (define-values (parent base directory?) (split-path (path->complete-path video)))
       (when (path? parent) (make-directory* parent))
       ((dynamic-require render-module 'encode-mp4!) destination video
                                                   #:fps fps
                                                   #:width width
                                                   #:height height)
       (printf "Wrote ~a\n" video))
     (values report paths))
   (lambda ()
     ;; This generated directory was fresh at call entry.  The persistent cache
     ;; remains intact for a later invocation with the same preparation identity.
     (when (directory-exists? private-output-directory)
       (delete-directory/files private-output-directory))))
  (values report paths))

; render-math-example! : symbol? path-string? any/c symbol? exact-positive-integer?
;   exact-positive-integer? exact-positive-integer? exact-positive-integer?
;   exact-positive-integer? (or/c path-string? #f) -> void?
;;   Executes the shared project renderer and reports its actual worker usage.
(define (render-math-example! name output case-path theme fps workers width height supersample video)
  (define-values (report frames)
    (render-math-project-frames!
     name (current-example-module-path name) output
     case-path theme fps workers width height supersample video))
  (define diagnostics (project-execution-report-diagnostics report))
  (printf "Rendered ~a frames to ~a\n" (length frames) output)
  (printf "Workers: requested ~a, started ~a, completing ~a (~a shared renderer)\n"
          workers
          (project-frame-execution-diagnostics-workers-started diagnostics)
          (or (project-frame-execution-diagnostics-workers-completing diagnostics) "n/a")
          (project-frame-execution-diagnostics-mode diagnostics)))
