#lang info

;;;
;;; Package Metadata
;;;

; collection : string?
;;   Names the installed Racket collection.
(define collection
  "visual-animation")

; deps : (listof string?)
;;   Lists runtime package dependencies.
(define deps
  '("base" "draw-lib" "latex-pict" "pict-lib"))

; build-deps : (listof string?)
;;   Lists dependencies needed for tests, examples, and documentation.
(define build-deps
  '("doc-coverage"
    "draw-doc"
    "pict-doc"
    "racket-doc"
    "rackunit-lib"
    "rhombus-lib"
    "scribble-lib"))

; pkg-desc : string?
;;   Describes the package in the Racket package catalog.
(define pkg-desc
  "SCENE-AX: dependency-driven geometry with stable moving text")

; version : string?
;;   Gives the prototype package version.
(define version "0.50.1")

; license : symbol?
;;   Declares the package license.
(define license
  'MIT)

; scribblings : list?
;;   Registers the public reference manual for raco setup.
(define scribblings
  '(("scribblings/visual-animation.scrbl" (multi-page))))

; test-omit-paths : (listof string?)
;;   Excludes examples from package test discovery.
(define test-omit-paths
  '("examples"))
