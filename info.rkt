#lang info

;;;
;;; Package Metadata
;;;

; collection : string?
;;   Names the installed Racket collection.
(define collection
  "animate")

; pkg-name : string?
;;   Names this package independently of its source directory.
(define pkg-name
  "animate")

; pkg-authors : (listof symbol?)
;;   Identifies the package maintainers for catalog metadata.
(define pkg-authors
  '(soegaard))

; deps : (listof string?)
;;   Lists runtime package dependencies.
(define deps
  '("base" "draw-lib" "gui-lib" "latex-pict" "pict-lib" ("svg" #:version "0.3")))

; raco-commands : (listof raco-command-spec?)
;; GUI code stays out of main.rkt; this command loads preview.rkt only when an
;; author explicitly invokes `raco animate preview`.
(define raco-commands
  '(("animate" animate/preview-cli "open an interactive animate source preview" #f)))

; build-deps : (listof string?)
;;   Lists dependencies needed for tests and examples.
(define build-deps
  '("rackunit-lib"))

; compile-omit-paths : (listof path-string?)
;;   Keeps optional Rhombus examples out of normal Racket compilation.
(define compile-omit-paths
  '("examples/rhombus"))

; source-omit-files : (listof path-string?)
;; Keeps generated renders, local experiments, and macOS Finder metadata out of
;; source archives produced by `raco pkg create --source`. Rhombus examples are
;; retained as requested; compile-omit-paths above keeps them out of the build.
(define source-omit-files
  '("tmp"
    "rendered-examples"
    ".DS_Store"
    "examples/.DS_Store"
    "examples/private/.DS_Store"))

; pkg-desc : string?
;;   Describes the package in the Racket package catalog.
(define pkg-desc
  "SCENE-EI: deterministic interactive animation authoring workbench")

; version : string?
;;   Gives the prototype package version.
(define version "1.7.0")

; license : symbol?
;;   Declares the package license.
(define license
  'MIT)

; test-omit-paths : (listof string?)
;;   Excludes examples from package test discovery.
(define test-omit-paths
  '("examples"))
