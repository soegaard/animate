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
(require "private/png-renderer.rkt"
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
                     current-project-artifact-opener))
