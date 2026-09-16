#lang info
;; The containing repository remains the animate package. This is its optional
;; slides subcollection; there is no independent runtime dependency installation.
(define version "0.1.4")
(define pkg-desc "Themeable immutable slide authoring with Pict and native Scene adapters (source preview)")
;; Optional effectful integrations are selected by slides/run-tests.rkt flags.
(define test-omit-paths
  '("examples"
    "tests/fixtures"
    "tests/math-test.rkt"
    "tests/geometry-test.rkt"
    "tests/media-test.rkt"
    "tests/project-test.rkt"))
(define source-omit-files '("compiled" ".DS_Store"))
