#lang racket/base

;;;
;;; Public String-Copy Name Boundary Tests
;;;

;; Animate must coexist with racket/base without shadowing its ordinary mutable
;; string helper. Formula-specific source-copy declarations use a longer name.

(require rackunit
         "../main.rkt")

(module+ test
  (check-equal? (string-copy "base string") "base string")
  (check-true
   (formula-string-copy?
    (formula-string-copy "source" "destination"))))
