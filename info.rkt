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
  '("base" "draw-lib" "gui-lib" "latex-pict" "opengl" "pict-lib" ("svg" #:version "0.3")))

; raco-commands : (listof raco-command-spec?)
;; GUI code stays out of main.rkt; this command loads preview.rkt only when an
;; author explicitly invokes `raco animate preview`.
(define raco-commands
  '(("animate" animate/preview-cli "open an interactive animate source preview" #f)))

; build-deps : (listof string?)
;;   Lists dependencies needed for tests and examples.
(define build-deps
  '("rackunit-lib" "scribble-lib" "racket-doc"))

; scribblings : (listof scribbling-spec?)
;;   Registers the package manual so normal installation builds and links it.
(define scribblings
  '(("scribblings/animate.scrbl" (multi-page) ("Animation"))))

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
    ".git"
    ".DS_Store"
    "examples/.DS_Store"
    "examples/private/.DS_Store"
    "private/.DS_Store"
    "scribblings/.DS_Store"
    "tests/.DS_Store"))

; version : string?
;;   Gives the prototype package version.
(define version "1.22.0")

; pkg-desc : string?
;;   Describes the package in the Racket package catalog.
(define pkg-desc
  "SCENE-3D-P: immutable Racket animation toolkit with an optional retained OpenGL 3D backend")

; license : symbol?
;;   Declares the package license.
(define license
  'MIT)

; test-omit-paths : (listof string?)
;;   Excludes examples from package test discovery.
(define test-omit-paths
  '("examples"))
