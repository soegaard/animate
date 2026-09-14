#lang info

;;;
;;; Mathematics Subcollection Metadata
;;;

;; Registers documentation and optional integrations without modifying the
;; parent animate repository's metadata.

;;;
;;; Documentation and Version
;;;

; version : string?
;;   Identifies the math subcollection revision independently of the parent.
(define version "0.3.3")

; scribblings : list?
;;   Registers the subcollection reference with package documentation setup.
(define scribblings
  '(("scribblings/math.scrbl" (multi-page) ("Animation"))))

;;;
;;; Optional Environment-Dependent Sources
;;;

; compile-omit-paths : (listof path-string?)
;;   Excludes the optional Rhombus example from ordinary Racket compilation.
(define compile-omit-paths
  '("examples/rhombus"))

; test-omit-paths : (listof path-string?)
;;   Keeps source audits, native renderers, and TeX probes separate from model tests.
(define test-omit-paths
  '("run-probes.rkt"
    "run-style-checks.rkt"
    "examples"
    "tests/native-integration.rkt"
    "tests/tex-layout-probe.rkt"))
