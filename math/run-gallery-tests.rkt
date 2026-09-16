#lang racket/base

;;;
;;; Mathematical Gallery Tests
;;;
;; Runs the gallery's mathematical, assembly-contract, and portable-artifact tests.
;; Actual native rendering is deliberately tested by run-gallery-probes.rkt instead.

;;;
;;; Imports and Exports
;;;
(require "tests/check.rkt" "tests/gallery-test.rkt"
         "tests/gallery-cli-test.rkt")
(run-gallery-tests)
(run-gallery-cli-tests)

(report!)
