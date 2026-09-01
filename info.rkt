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
;;   Lists dependencies needed for tests and examples.
(define build-deps
  '("rackunit-lib"
    "rhombus-lib"))

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

; test-omit-paths : (listof string?)
;;   Excludes examples and the unregistered documentation coverage test.
(define test-omit-paths
  '("examples"
    "tests/documentation-test.rkt"))
