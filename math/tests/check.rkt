#lang racket/base

;;;
;;; Dependency-Light Test Harness
;;;
;; Records explicit checks with failure exit status. Its mutable counters are confined
;; to this effectful test harness.

;;;
;;; Imports and Exports
;;;
;; Exports
(provide
  check-equal check-true check-false check-close check-raises test-group report!
  checks-passed checks-failed)

;;;
;;; Construction and Operations
;;;
; checks-passed : exact-nonnegative-integer?
;;   Counts successful checks inside this test process only.
(define checks-passed
  0)

; checks-failed : exact-nonnegative-integer?
;;   Counts failed checks inside this test process only.
(define checks-failed
  0)

; current-group : (parameter/c string?)
;;   Labels the currently running test group.
(define current-group
  (make-parameter "tests"))

; fail : symbol? any/c any/c -> void?
;;   Records and prints a labeled regression failure.
(define (fail name actual expected)
  (set! checks-failed (add1 checks-failed))
  (eprintf "FAIL [~a] ~a\n  got: ~s\n  expected: ~s\n" (current-group) name actual expected))

; check-equal : any/c any/c [symbol?] -> void?
;;   Records a test result without aborting the remaining checks.
(define (check-equal actual expected [name 'equal])
  (if (equal? actual expected)
    (set! checks-passed (add1 checks-passed))
    (fail name actual expected)))

; check-true : any/c [symbol?] -> void?
;;   Records a test result without aborting the remaining checks.
(define (check-true actual [name 'true])
  (check-equal (and actual #t) #t name))

; check-false : any/c [symbol?] -> void?
;;   Records a test result without aborting the remaining checks.
(define (check-false actual [name 'false])
  (check-equal actual #f name))

; check-close : any/c any/c [any/c] [symbol?] -> void?
;;   Records a test result without aborting the remaining checks.
(define (check-close actual expected [tolerance 1e-8] [name 'close])
  (check-true
    (and (real? actual) (<= (abs (- actual expected)) tolerance))
    (list name actual expected)))

; check-raises : procedure? [any/c] [symbol?] -> void?
;;   Records a test result without aborting the remaining checks.
(define (check-raises thunk [pattern #rx"."] [name 'raises])
  (define result (with-handlers ([exn:fail? values]) (thunk) #f))
  (check-true
    (and (exn:fail? result) (regexp-match? pattern (exn-message result)))
    (list name (and (exn:fail? result) (exn-message result)))))

; test-group : symbol? procedure? -> void?
;;   Runs a labeled group and reports an uncaught exception as one test failure.
(define (test-group name thunk)
  (printf "TEST ~a\n" name)
  (parameterize ([current-group name])
    (with-handlers ([exn:fail? (lambda (e) (fail 'uncaught (exn-message e) 'no-exception))])
      (thunk))))

; report! : -> void?
;;   Prints check totals and exits unsuccessfully when any check failed.
(define (report!)
  (printf "~a checks passed; ~a failed.\n" checks-passed checks-failed)
  (when (positive? checks-failed) (exit 1)))
