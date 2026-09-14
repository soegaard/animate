#lang racket/base

;;;
;;; House Style Regression Tests
;;;
;; Checks immutable snapshots, constructor validation, exact timing, callback contracts,
;; and rejection of invalid service evidence.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list last)
  "check.rkt"
  "../main.rkt"
  "../cas.rkt"
  "../cas/racket-cas.rkt"
  "../cas/calcura.rkt"
  (only-in "../private/model.rkt" prove-in-context)
  (only-in "../private/evidence.rkt" verification)
  (only-in "../private/typeset-model.rkt" prepared-token prepared-layout)
  (only-in "../private/format.rkt" math-source math-source-span)
  (prefix-in lc: "../examples/linear-concrete.rkt")
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qc: "../examples/quadratic-concrete.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;; Exports
(provide run-house-style-tests)

;;;
;;; Construction and Operations
;;;
; run-house-style-tests : -> void?
;;   Runs the named regression groups and records failures in the test harness.
(define (run-house-style-tests)
  (test-group
    "house style: immutable input snapshots and protocol boundaries"
    (lambda ()
      (check-raises (lambda () (cancel-factor #:factor 3 #:keep-one? 'yes)))
      (check-raises (lambda () (racket-cas-service #:loader 17)))
      (check-raises (lambda () (calcura-service #:loader (lambda (one) one))))
      (check-raises (lambda () (unknown 'test #t '() "pending" (lambda () 'effect))))
      (define circular (make-vector 1 #f))
      (vector-set! circular 0 circular)
      (check-raises (lambda () (unknown 'test #t '() "pending" circular)) #rx"acyclic")
      (check-raises
        (lambda ()
          (math-with-context (math 'x) (math-context) #:scope (string-copy "branch"))))
      (check-raises
        (lambda ()
          (make-case-derivation
            (math 'x)
            (list (list "not-a-symbol" #t (lambda (s) (derive s)))))))
      (check-raises
        (lambda ()
          (make-case-derivation
            (math 'x)
            (list (list 'branch #t (lambda () (derive (math 'x))))))))
      (define replacements (make-hash '((x . 2))))
      (define substitution (substitute replacements))
      (hash-set! replacements 'x 99)
      (define step
        (apply-math-operation
          (math '(+ x 1) #:context (math-context #:real '(x)))
          substitution))
      (check-equal (math-datum (rewrite-step-after step)) '(+ 2 1) 'snapshot-substitution)
      (define message (string-copy "pending"))
      (define details (hash 'description (vector message)))
      (define report (unknown 'test '(> x 0) '((> x 0)) message details))
      (string-set! message 0 #\X)
      (check-equal (verification-message report) "pending" 'immutable-message)
      (check-equal
        (vector-ref (hash-ref (verification-details report) 'description) 0)
        "pending")
      (check-true (immutable? (hash-ref (verification-details report) 'description)))
      (for ([bad (in-list '(-1 1/2 x #f))])
        (check-raises (lambda () (at-path (list bad))) #rx"path"))
      (check-raises (lambda () (math-context #:definitions (hash 0 'x))))
      (check-raises (lambda () (math-context #:assuming '((= x)))))
      (check-raises (lambda () (verification 'maybe 'test #t '() "" '())))
      (check-raises (lambda () (verification 'established 'test #t '(unknown) "" '())))
      (check-raises (lambda () (cas-service 'bad 'v '(proposition) (lambda (a) a))))
      (check-raises
        (lambda () (cas-service 'bad 'v '(proposition) (lambda (a b c #:required x) x))))
      (check-raises (lambda () (current-math-prover (lambda (a b #:required x) x))))
      (check-raises
        (lambda ()
          (parameterize ([current-math-prover (lambda (ctx p) (established 'invalid 'different))])
            (prove-in-context (math-context) #t)))
        #rx"requested proposition")
      (check-raises (lambda () (cas-result 'nonsense #f #f '())))
      (check-raises (lambda () (cas-result 'ok #f #f '(42))))
      (check-raises (lambda () (prepared-token '() 'leaf "x" "x.svg" +nan.0 0 1 1 'x)))
      (check-raises (lambda () (prepared-token '() 'leaf "x" "x.svg" 0 0 0 1 'x)))
      (check-raises (lambda () (math-source-span 3 2 '() 'leaf)))
      (define token (prepared-token '() 'leaf "x" "x.svg" 0 0 1 1 'x))
      (check-raises
        (lambda () (prepared-layout (math 'x) (list token token) (math-source "x" '()) '())))))
  (test-group
    "house style: exact default timing and validated choreography"
    (lambda ()
      (for ([plan (in-list (list lc:plan lg:plan qc:plan qg:plan))])
        (check-true (exact? (plan-duration plan)))
        (check-true
          (andmap
            (lambda (phase)
              (and
                (exact? (scheduled-phase-start phase))
                (exact? (scheduled-phase-duration phase))))
            (plan-schedule plan)))
        (check-equal (plan-schedule plan) (plan-schedule plan))
        (check-equal
          (math-datum (math-checkpoint-state (checkpoint-at plan (plan-duration plan))))
          (math-datum
            (after (plan-segment-derivation (last (presentation-plan-segments plan)))))))
      (check-equal (plan-duration lc:plan) 54/5 'exact-linear-duration)
      (check-raises (lambda () (present lc:solution #:allow-unverified? 'yes)))
      (check-raises (lambda () (present lc:solution #:case '(1))))
      (check-raises (lambda () (plan-with-choreography lc:plan '(()))))
      (check-raises
        (lambda ()
          (plan-with-choreography lc:plan
            (list (cons 'cancel-five (list (hold 1))) (cons 'cancel-five (list (hold 2))))))
        #rx"only once")
      (for ([bad (in-list (list +nan.0 +inf.0 -inf.0 -1 0))])
        (check-raises (lambda () (transition #:duration bad))))))
  (test-group
    "house style: failed CAS calls never supply mathematical evidence"
    (lambda ()
      (define opaque-result (box 'original-native-result))
      (define native-service
        (cas-service 'native-value-test 1 '(proposition)
          (lambda (capability payload context)
            (cas-result 'ok opaque-result (established 'native-test payload) '()))))
      (define frozen
        (verify-proposition! '(> x 0)
          (math-context #:real '(x))
          #:services (math-services #:local native-service)))
      (define saved (format "~s" frozen))
      (set-box! opaque-result 'changed-native-result)
      (check-equal (format "~s" frozen) saved 'opaque-result-not-in-evidence)
      (check-equal (verification-status frozen) 'established)
      (define ctx (math-context #:real '(x)))
      (define (answer-service answer)
        (cas-service 'test 'v '(proposition) (lambda (capability payload context) answer)))
      (check-equal
        (cas-result-status (cas-query! (answer-service #f) 'proposition '(> x 0) ctx))
        'error
        'false-is-not-timeout)
      (check-equal
        (cas-result-status
          (cas-query!
            (answer-service (cas-result 'ok #t (established 'bad '(> x 1)) '()))
            'proposition
            '(> x 0)
            ctx))
        'error
        'wrong-proposition)
      (for ([status (in-list '(unknown unsupported unavailable timeout error))])
        (define broken
          (answer-service (cas-result status #t (established 'bad '(> x 0)) '())))
        (check-equal
          (cas-result-status (cas-query! broken 'proposition '(> x 0) ctx))
          'error)
        (check-equal
          (verification-status
            (verify-proposition! '(> x 0) ctx #:services (math-services #:local broken)))
          'unknown)))))
