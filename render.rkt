#lang racket/base

;;;
;;; Frame and Media Rendering
;;;

;; Provides the effectful rendering boundary. Requiring this module enables
;; PNG output and external FFmpeg invocation; immutable scene construction and
;; sampling remain available from animate itself.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         racket/path
         racket/port
         file/sha1
         "colors.rkt"
         "private/png-renderer.rkt"
         (only-in "private/paint-pict.rkt" paint->draw-color)
         "private/project-execution.rkt"
         "private/section-renderer.rkt"
         "private/video-assembly.rkt"
         "private/video-encoder.rkt")

;; Exports
(provide (all-from-out "private/png-renderer.rkt"
                       "private/section-renderer.rkt"
                       "private/video-assembly.rkt"
                       "private/video-encoder.rkt")
         ;; This parameter is a private test/headless integration seam, not an
         ;; author-facing render API. Complete artifacts are configured through
         ;; output-spec's #:open-after? declaration.
         (except-out (all-from-out "private/project-execution.rkt")
                     current-project-artifact-opener)
         render-color->draw-color
         load-color-theme!)

;; render-color->draw-color : color-spec? -> color%
;; Converts a custom renderer's semantic color with the immutable context
;; installed by the public 2D rendering entry point. Custom renderers do not
;; receive the private context object and cannot mutate a global theme.
(define (render-color->draw-color color)
  (paint->draw-color color))

(define maximum-color-theme-file-bytes (* 1024 1024))

;; load-color-theme! : path-string? -> color-theme?
;; Reads one bounded, versioned data-only theme file at the effectful render
;; boundary. The digest and decoder share the exact same byte snapshot;
;; workers receive the resulting immutable snapshot and never reread the file.
(define (load-color-theme! path)
  (unless (path-string? path)
    (raise-argument-error 'load-color-theme! "path-string?" path))
  (define complete-path (path->complete-path path))
  (define snapshot (read-color-theme-snapshot complete-path))
  (define source-datum (read-one-color-theme-datum snapshot complete-path))
  (define digest (bytes->hex-string (sha1-bytes snapshot)))
  (define decoded (datum->theme source-datum))
  (define canonical (theme->datum decoded))
  (datum->theme
   (append (take canonical 7)
           (list (format "~a (sha1 ~a)" complete-path digest)))))

(define (read-color-theme-snapshot path)
  ;; Asking for one byte beyond the bound distinguishes a full permitted file
  ;; from an oversized one without trusting a separate, racy `file-size` read.
  (define bytes
    (call-with-input-file
     path
     (lambda (input)
       (read-bytes (add1 maximum-color-theme-file-bytes) input))))
  (define snapshot (if (eof-object? bytes) #"" bytes))
  (when (> (bytes-length snapshot) maximum-color-theme-file-bytes)
    (raise-arguments-error
     'load-color-theme!
     "a theme file no larger than the configured input budget"
     "path" path
     "maximum bytes" maximum-color-theme-file-bytes))
  (bytes->immutable-bytes snapshot))

(define (read-one-color-theme-datum snapshot path)
  (define input (open-input-bytes snapshot))
  (define (read-data)
    ;; Do not inherit a caller's reader extensions, graph notation, compiled
    ;; forms, custom readtable, or #reader/#lang behaviour at this data-only
    ;; boundary. `read` still accepts ordinary comments and whitespace.
    (call-with-default-reading-parameterization
     (lambda ()
       ;; Install the restrictive parameters *after* the default reader
       ;; parameterization, which otherwise deliberately enables graph and
       ;; language forms for ordinary Racket source readers.
       (parameterize ([read-accept-reader #f]
                      [read-accept-lang #f]
                      [read-accept-compiled #f]
                      [read-accept-graph #f]
                      [current-readtable #f])
         (read input)))))
  (define datum (read-data))
  (when (eof-object? datum)
    (raise-arguments-error 'load-color-theme! "a nonempty theme datum" "path" path))
  (define trailing (read-data))
  (unless (eof-object? trailing)
    (raise-arguments-error
     'load-color-theme!
     "a file containing exactly one theme datum"
     "path" path))
  datum)
