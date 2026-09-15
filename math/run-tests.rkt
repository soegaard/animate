#lang racket/base

;;;
;;; Mandatory Mathematics Tests
;;;
;; Runs the dependency-light mathematical and adapter-contract suites. Native graphics
;; and external CAS installations are not substituted or assumed.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "tests/check.rkt"
  "tests/core-test.rkt"
  "tests/native-contract.rkt"
  "tests/property-test.rkt"
  "tests/house-style-test.rkt"
  "tests/prepared-plan-codec-test.rkt"
  "tests/choreography-test.rkt")

(run-core-tests)

(run-native-contract-tests)

(run-property-tests)

(run-house-style-tests)

(run-prepared-plan-codec-tests)

(run-choreography-tests)

(report!)
