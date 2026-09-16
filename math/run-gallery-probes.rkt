#lang racket/base

;;;
;;; Actual Native Gallery Review Runner
;;;
;; Runs installed native graphics, formula preparation, and optional real process
;; rendering. Synthetic contracts are deliberately kept in the separate test runners.

;;;
;;; Imports and Exports
;;;
(require (only-in "tests/gallery-native-probes.rkt" run-gallery-native-probes!))
(module+ main (run-gallery-native-probes!))
