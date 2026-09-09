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

;; load-color-theme! : path-string? -> color-theme?
;; Reads one versioned data-only theme file at the effectful render boundary.
;; The content digest becomes provenance on the returned immutable snapshot;
;; workers receive that snapshot and never reread the file during a job.
(define (load-color-theme! path)
  (unless (path-string? path)
    (raise-argument-error 'load-color-theme! "path-string?" path))
  (define complete-path (path->complete-path path))
  (define source-datum
    (call-with-input-file complete-path read))
  (define digest
    (call-with-input-file complete-path sha1))
  (define decoded (datum->theme source-datum))
  (define canonical (theme->datum decoded))
  (datum->theme
   (append (take canonical 7)
           (list (format "~a (sha1 ~a)" complete-path digest)))))
