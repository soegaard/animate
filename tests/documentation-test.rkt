#lang racket/base

;;;
;;; Documentation Coverage Tests
;;;

;; Checks that every binding exported by the public module has a Scribble
;; documentation entry. Run this test after installing the package as a link
;; and building its documentation with raco setup.


;;;
;;; Imports
;;;

(require (only-in doc-coverage
                  check-all-documented)
         (only-in rackunit
                  test-case))


;;;
;;; Coverage
;;;

(module+ test
  (test-case
   "every public export is documented"
   (check-all-documented 'visual-animation)))
