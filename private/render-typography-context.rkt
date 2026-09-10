#lang racket/base

;; Explicit immutable typography snapshots for one rendering operation.

(require "typography-theme.rkt"
         "typography-theme-data.rkt")

(provide (struct-out render-typography-context)
         render-typography-resolver-version
         make-render-typography-context
         current-render-typography-context
         current-or-default-render-typography-context)

(define render-typography-resolver-version 2)

(struct render-typography-context (theme appearance-fingerprint resolver-version)
  #:transparent)

(define (make-render-typography-context theme)
  (unless (typography-theme? theme)
    (raise-argument-error 'make-render-typography-context "typography-theme?" theme))
  (render-typography-context theme
                             (typography-theme-fingerprint theme)
                             render-typography-resolver-version))

;; This lexical render parameter is not an author-facing global selection.
(define current-render-typography-context (make-parameter #f))

(define (current-or-default-render-typography-context)
  (or (current-render-typography-context)
      (make-render-typography-context animate-typography-theme)))
