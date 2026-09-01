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
  '("base" "draw-lib" "latex-pict" "pict-lib"))

; build-deps : (listof string?)
;;   Lists dependencies needed for tests and examples.
(define build-deps
  '("rackunit-lib"))

; compile-omit-paths : (listof path-string?)
;;   Keeps optional Rhombus examples out of normal Racket compilation.
(define compile-omit-paths
  '("examples/rhombus"))

; pkg-desc : string?
;;   Describes the package in the Racket package catalog.
(define pkg-desc
  "SCENE-BL: sampled implicit curves and contour paths")

; version : string?
;;   Gives the prototype package version.
(define version "0.61.0")

; license : symbol?
;;   Declares the package license.
(define license
  'MIT)

; test-omit-paths : (listof string?)
;;   Excludes examples from package test discovery.
(define test-omit-paths
  '("examples"))
