#lang info
;; The containing repository remains the animate package. This is its optional
;; slides subcollection; there is no independent runtime dependency installation.
(define version "0.4.0")
(define pkg-desc "Themeable immutable slide authoring with Pict and native Scene adapters")
;; Optional effectful integrations are selected by slides/run-tests.rkt flags.
(define test-omit-paths
  '("examples"
    "tests/fixtures"
    "tests/math-test.rkt"
    "tests/geometry-test.rkt"
    "tests/media-test.rkt"
    "tests/project-test.rkt"
    "tests/semantic-domain-test.rkt"
    "tests/gallery-integration-test.rkt"
    "tests/geometry-codec-test.rkt"
    "tests/geometry-worker-test.rkt"))
(define source-omit-files
  '("compiled" ".DS_Store"
    "private/.animate-slide-preparation-v1"
    "private/.animate-math-preparation-artifacts-v1"))
