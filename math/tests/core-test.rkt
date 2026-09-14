#lang racket/base

;;;
;;; Mathematical Core Regression Tests
;;;
;; Checks held syntax, exact rewrites, conditions, provenance, service contracts, and
;; the four complete lessons.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list remove-duplicates)
  "check.rkt"
  "../main.rkt"
  "../cas.rkt"
  (only-in "../private/model.rkt" finish-step path-link trace-event)
  (only-in "../private/operations.rkt" math-operation make-edit)
  (only-in "../private/format.rkt" math-source math-source-span)
  "../private/polynomial.rkt"
  "../private/semantic-svg.rkt"
  "../cas/calcura.rkt"
  "../cas/racket-cas.rkt"
  (prefix-in lc: "../examples/linear-concrete.rkt")
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qc: "../examples/quadratic-concrete.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;; Exports
(provide run-core-tests)

;;;
;;; Construction and Operations
;;;
; reals : math-context?
;;   Declares the real symbols used in exact algebra tests.
(define reals
  (math-context #:real '(a b c d u v w x y z)))

; st : math-datum? [math-context?] -> math?
;;   Constructs one held state in the fixed test context.
(define (st d [ctx reals])
  (math d #:id 'test #:context ctx))

; apply-op : math-datum? math-operation? [math-context?] -> rewrite-step?
;;   Applies a test operation to one held state.
(define (apply-op d op [ctx reals])
  (apply-math-operation (st d ctx) op))

; out : math-datum? math-operation? [math-context?] -> math-datum?
;;   Returns the held destination of one test operation.
(define (out d op [ctx reals])
  (math-datum (rewrite-step-after (apply-op d op ctx))))

; status : any/c any/c -> symbol?
;;   Extracts the local prover status used by assertions.
(define (status c p)
  (verification-status (context-prove c p)))

; distribute-left : math-rule?
;;   Defines an explicit template rule for the following trace and ambiguity tests.
(define-math-rule distribute-left
  #:metavariables (u v w)
  #:from (* u (+ v w))
  #:to (+ (* u v) (* u w))
  #:check polynomial-identity)

; collect-twice : math-rule?
;;   Defines an explicit template rule for the following trace and ambiguity tests.
(define-math-rule collect-twice
  #:metavariables (u)
  #:from (+ u u)
  #:to (* 2 u)
  #:check polynomial-identity
  #:merge 'merge)

; ambiguous-twice : math-rule?
;;   Defines an explicit template rule for the following trace and ambiguity tests.
(define-math-rule ambiguous-twice
  #:metavariables (u)
  #:from (+ u u)
  #:to (* 2 u)
  #:check polynomial-identity)

; run-core-tests : -> void?
;;   Runs the named regression groups and records failures in the test harness.
(define (run-core-tests)
  (test-group "held syntax and selection"
    (lambda ()
      (for ([d (in-list '((+ x x) (* 1 x) (- 17 5) (/ 6 3) (= 17 17)))])
        (check-equal (math-datum (st d)) d))
      (check-equal (held-substitute '(+ x y) (hash 'x 'y 'y 'z)) '(+ y z) 'simultaneous)
      (check-equal
        (held-substitute '(+ (* x x) 0) (hash 'x 2))
        '(+ (* 2 2) 0)
        'not-normalized)
      (check-raises (lambda () (held-substitute '(sum x x 1 5) (hash 'x 'y))))
      (define s (st '(= (+ (* 3 x) 5) 17)))
      (check-equal (map occurrence-datum (math-select s (lhs))) '((+ (* 3 x) 5)))
      (check-equal (map occurrence-datum (math-select s (at-path '(0 0 1)))) '(x))
      (check-equal (length (math-select (st '(+ x x x)) (all-matching 'x))) 3)
      (check-equal
        (map occurrence-path (math-select (st '(+ x x x)) (matching 'x #:occurrence 2)))
        '((1)))
      (check-raises
        (lambda () (resolve-one (st '(+ x x)) (matching 'x)))
        #rx"[Aa]mbig|exactly")
      (check-raises (lambda () (math-select s (at-path '(9)))))
      (check-raises (lambda () (st '(= x))))
      (check-raises (lambda () (st '(+ 1 . x))))
      (check-raises (lambda () (st +nan.0)))
      (check-raises (lambda () (math-context #:definitions '((a b) (b a)))))
      (check-equal
        (length
          (remove-duplicates
            (map occurrence-id (hash-values (math-occurrences (st '(+ x x x)))))))
        4)))
  (test-group
    "exact algebra and domain guards"
    (lambda ()
      (check-true (rational-equivalent? '(* a (+ b c)) '(+ (* a b) (* a c))))
      (check-false (rational-equivalent? '(+ (expt x 2) 1) '(expt (+ x 1) 2)))
      (check-equal (status reals '(= (* 0 x) 0)) 'established)
      (check-equal (status reals '(not (= a 0))) 'unknown)
      (check-equal (status reals '(= (/ x x) 1)) 'unknown 'definedness-not-discarded)
      (check-raises
        (lambda () (apply-op '(= (/ x x) 1) (conclude 'all-real #:for 'x)))
        #rx"restrict")
      (define positive-x (context-assume reals '(> x 0)))
      (check-equal
        (verification-status
          (solution-check-verification
            (check-solution (st '(= (expt x 2) 4) positive-x) #:for 'x #:value -2)))
        'refuted)
      (check-equal (status reals '(>= (expt x 2) 0)) 'established)
      (check-equal (status (math-context) '(>= (expt z 2) 0)) 'unknown 'unknown-real-domain)
      (define nz (context-assume reals '(not (= a 0))))
      (check-equal (status nz '(not (= (* 2 a) 0))) 'established)
      (check-raises (lambda () (apply-op '(= (* a x) b) (both-sides 'divide 'a))))
      (check-raises (lambda () (apply-op '(= x 2) (both-sides 'divide 0))))
      (check-equal
        (out '(= (* a x) b) (both-sides 'divide 'a) nz)
        '(= (/ (* a x) a) (/ b a)))
      (define cancel (apply-op '(/ (* x y) x) (cancel-factor #:factor 'x)))
      (check-equal (math-datum (rewrite-step-after cancel)) 'y)
      (check-true
        (member '(not (= x 0))
          (math-context-restrictions (math-context-of (rewrite-step-after cancel)))))
      (check-equal (out '(< x 2) (both-sides 'multiply -3)) '(> (* -3 x) (* -3 2)))
      (check-raises (lambda () (apply-op '(< x 2) (both-sides 'multiply 'a))))
      (check-raises (lambda () (apply-op '(= x 2) (both-sides 'power 2))))
      (check-equal
        (rewrite-step-relation
          (apply-op '(= x 2) (both-sides 'power 2 #:relationship 'implication)))
        'implication)
      (check-equal
        (out '(= x 2) (both-sides 'multiply 0 #:relationship 'implication))
        '(= (* 0 x) (* 0 2)))
      (check-raises (lambda () (apply-op '(expt x 2) (rewrite-to '(+ x 2)))))
      (check-equal
        (out '(+ (expt x 2) (* 6 x) 9)
          (rewrite-to '(expt (+ x 3) 2) #:using 'perfect-square))
        '(expt (+ x 3) 2))
      (check-equal (out '(= 17 17) (evaluate)) '(= 17 17))
      (check-equal (out '(+ 1 (* 3 4)) (evaluate #:mode 'deepest)) '(+ 1 12))
      (check-equal (out '(+ 1 (* 3 4)) (evaluate)) 13)
      (check-equal (out '(+ x 5 (- 5)) (cancel-addends)) 'x)
      (check-raises (lambda () (apply-op '(+ x (- x) x (- x)) (cancel-addends))))
      (check-equal (out '(- a b) (reorder-addends #:order '(1 0))) '(+ (- b) a))
      (check-raises (lambda () (apply-op '(+ x y) (reorder-addends #:order '(0 0)))))
      (check-raises (lambda () (st '(/ x 0))))
      (check-raises
        (lambda ()
          (math '(= x 1) #:context (context-assume reals '(and (= a 0) (not (= a 0)))))))))
  (test-group
    "occurrence lineage and custom rules"
    (lambda ()
      (define s (st '(= (+ (* 3 x) 5) 17)))
      (define old-x (occurrence-id (car (math-select s (matching 'x)))))
      (define step (apply-math-operation s (both-sides 'subtract 5)))
      (check-equal
        (occurrence-id (car (math-select (rewrite-step-after step) (matching 'x))))
        old-x)
      (define ds (apply-rewrite distribute-left (st '(* a (+ b c)))))
      (check-equal (math-datum (rewrite-step-after ds)) '(+ (* a b) (* a c)))
      (check-true
        (ormap (lambda (r) (eq? (trace-relation-kind r) 'copy)) (rewrite-step-trace ds)))
      (define as (math-select (rewrite-step-after ds) (all-matching 'a)))
      (check-equal (length as) 2)
      (check-false (eq? (occurrence-id (car as)) (occurrence-id (cadr as))))
      (define ms (apply-rewrite collect-twice (st '(+ x x))))
      (check-equal (math-datum (rewrite-step-after ms)) '(* 2 x))
      (check-true
        (ormap (lambda (r) (eq? (trace-relation-kind r) 'merge)) (rewrite-step-trace ms)))
      (check-raises (lambda () (apply-rewrite ambiguous-twice (st '(+ x x)))) #rx"merge")
      (check-raises (lambda () (apply-rewrite collect-twice (st '(+ x y)))))
      (check-equal (rewrite-step-version ds) 1)
      (check-equal (hash-ref (rewrite-step-bindings ds) 'u) 'a)))
  (test-group
    "four examples and all parameter cases"
    (lambda ()
      (check-equal (math-datum (after lc:solution)) '(= x 4))
      (check-equal
        (map math-datum (derivation-states lc:solution))
        '((= (+ (* 3 x) 5) 17)
           (= (- (+ (* 3 x) 5) 5) (- 17 5))
           (= (* 3 x) (- 17 5))
           (= (* 3 x) 12)
           (= (/ (* 3 x) 3) (/ 12 3))
           (= (* 1 x) (/ 12 3))
           (= x (/ 12 3))
           (= x 4)))
      (check-equal
        (verification-status (solution-check-verification lc:answer-check))
        'established)
      (check-equal (math-datum (after qc:solution)) '(or (= x -1) (= x -5)))
      (for ([d (in-list (list lc:solution lg:solution qc:solution qg:solution))])
        (check-equal (verification-status (derivation-verification d)) 'established))
      (check-equal (length (case-derivation-branches lg:solution)) 3)
      (check-equal (length (presentation-plan-segments qg:plan)) 7)
      (for ([segment (in-list (presentation-plan-segments qg:plan))])
        (check-equal
          (verification-status (derivation-verification (plan-segment-derivation segment)))
          'established))
      (check-equal
        (out '(= (expt x 2) 4) (square-solutions))
        '(or (= x (sqrt 4)) (= x (- (sqrt 4)))))
      (check-equal (out '(= (expt x 2) 0) (square-solutions)) '(= x 0))
      (check-equal (out '(= (expt x 2) -1) (square-solutions)) #f)
      (check-raises (lambda () (apply-op '(= (expt x 2) a) (square-solutions))))
      (check-equal
        (verification-status (check-case-coverage reals '((> a 0) (= a 0) (< a 0))))
        'established)
      (check-equal
        (verification-status (check-case-coverage reals '((> a 0) (< a 0))))
        'unknown)
      (check-equal
        (verification-status (check-case-coverage reals '((>= a 0) (<= a 0))))
        'unknown)
      (define bad-check (check-solution (st '(= (/ x x) 1)) #:for 'x #:value 0))
      (check-equal (verification-status (solution-check-verification bad-check)) 'refuted)
      (check-false (solution-check-derivation bad-check))
      (check-equal
        (verification-status
          (solution-check-verification (check-solution lc:problem #:for 'x #:value 3)))
        'refuted)))
  (test-group
    "presentation schedule and strict/draft boundaries"
    (lambda ()
      (check-true (> (plan-duration lc:plan) 1))
      (define schedule (plan-schedule lc:plan))
      (for ([a (in-list schedule)] [b (in-list (cdr schedule))])
        (check-close
          (+ (scheduled-phase-start a) (scheduled-phase-duration a))
          (scheduled-phase-start b)))
      (check-equal (scheduled-phase-kind (plan-inspect lc:plan 0)) 'show-initial)
      (check-raises (lambda () (present lc:solution #:groups '((subtract-five)))))
      (check-raises (lambda () (plan-inspect lc:plan -1)))
      (check-raises (lambda () (math-presentation #:duration +inf.0)))
      (check-raises (lambda () (reveal-created #:effect 'magic)))
      (check-raises (lambda () (choreograph lc:plan [nonexistent (hold 1)])))
      (define draft
        (parameterize ([current-math-validation 'draft])
          (derive (st '(= (* a x) b)) [divide (both-sides 'divide 'a)])))
      (check-equal (verification-status (derivation-verification draft)) 'unknown)
      (check-raises (lambda () (present draft)))
      (check-true (presentation-plan? (present draft #:allow-unverified? #t)))))
  (test-group
    "CAS contracts, failure states and bounded execution"
    (lambda ()
      (define unavailable (calcura-service))
      (check-equal
        (cas-result-status (cas-query! unavailable 'proposition '(= (sin x) x) reals))
        'unavailable)
      (define good
        (cas-service 'good 1 '(proposition)
          (lambda (cap p c) (cas-result 'ok #t (established 'test p) '()))))
      (define bad
        (cas-service 'bad 1 '(proposition)
          (lambda (cap p c) (cas-result 'ok #f (refuted 'test p) '()))))
      (check-equal
        (verification-status
          (verify-proposition! '(= (sin x) x) reals #:services (math-services #:local good)))
        'established)
      (check-equal
        (verification-status
          (verify-proposition! '(= (sin x) x) reals
            #:services (math-services #:local good #:extended bad)))
        'unknown)
      (check-equal (cas-result-status (cas-query! good 'different 0 reals)) 'unsupported)
      (check-equal
        (cas-result-status
          (cas-query!
            (cas-service 'broken 1 '(proposition) (lambda _ (error 'broken)))
            'proposition
            #t
            reals))
        'error)
      (define late? (box #f))
      (define slow
        (cas-service 'slow 1 '(proposition)
          (lambda _ (sleep .2) (set-box! late? #t) (cas-result 'ok #t #f '()))))
      (check-equal
        (cas-result-status (cas-query! slow 'proposition #t reals #:timeout .01))
        'timeout)
      (sleep .25)
      (check-false (unbox late?) 'worker-cancelled)
      (check-raises (lambda () (cas-query! good 'proposition #t reals #:timeout +inf.0)))
      (check-equal (verification-status (verify-derivation! lc:solution)) 'established)))
  (test-group
    "optional CAS adapter transport and construction hooks"
    (lambda ()
      (define loaded 0)
      (define rc
        (racket-cas-service
          #:loader
          (lambda (module name)
            (set! loaded (add1 loaded))
            (lambda (x) (if (equal? x '(+ 1 2)) 3 x)))))
      (check-equal loaded 0 'no-eager-CAS-load)
      (check-equal (cas-result-value (cas-calculate! rc 'normalize '(+ 1 2))) 3)
      (check-true (> loaded 0))
      (check-equal
        (cas-result-status (cas-calculate! rc 'unimplemented '(+ 1 2)))
        'unsupported)
      (check-equal
        (cas-result-status (cas-query! rc 'proposition '(= (sin x) x) reals))
        'unknown)
      (define sent #f)
      (define fake-calcura
        (calcura-service
          #:module "/temporary/calcura.rkt"
          #:loader
          (lambda (module name)
            (check-true (path? module) 'native-module-path-object)
            (case name
              [(parse-input-form-string) (lambda (text) (set! sent text) text)]
              [(Eval) (lambda (text) 'True)]))))
      (check-equal
        (cas-result-status (cas-query! fake-calcura 'proposition '(= (sin x) x) reals))
        'ok)
      (check-true (regexp-match? #rx"Element\\[" sent) 'real-assumptions-transported)
      (check-true
        (regexp-match? #rx"animateMathVariable" (datum->calcura-input 'Sin))
        'variable-not-builtin)
      (check-raises (lambda () (datum->calcura-input '(unrecognized x))))
      (define calls 0)
      (define provider
        (cas-service 'test-provider 1 '(proposition)
          (lambda (cap p c)
            (set! calls (add1 calls))
            (cas-result 'ok #t (established 'test-provider p) '()))))
      (define guarded
        (call-with-math-services!
          (math-services #:extended provider)
          (lambda () (derive (st '(= (* a x) b)) [divide (both-sides 'divide 'a)]))))
      (check-true (> calls 0) 'construction-used-proof-service)
      (check-equal (verification-status (derivation-verification guarded)) 'established)
      (check-true (presentation-plan? (present guarded)))))
  (test-group
    "notation and semantic markers"
    (lambda ()
      (check-equal (datum->tex '(* (+ x 1) (+ x 5))) "(x+1)(x+5)" 'product-parentheses)
      (check-equal (datum->tex '(+ x -1/2)) "x-\\frac{1}{2}" 'negative-fraction)
      (check-equal (datum->tex '(* -4 a c)) "-4ac" 'negative-leading-coefficient)
      (check-equal (math->tex (st '(= (* 1 x) (/ 12 3)))) "1\\cdot x=\\frac{12}{3}")
      (check-true (regexp-match? #rx"-4" (math->tex (st '(- (expt b 2) (* 4 a c))))))
      (check-true (regexp-match? #rx"\\\\frac" (math->tex (st '(/ (+ x 1) a)))))
      (define src (format-math-source (st '(= (/ (+ (* 3 x) 5) a) (sqrt b)))))
      (define-values (marked markers) (annotate-math-source src))
      (check-true (regexp-match? #rx"dvisvgm:raw" marked))
      (check-true (regexp-match? #rx"animate-math-" marked)))))
