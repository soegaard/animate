#lang racket/base

;;;
;;; Worked Derivations and Cases
;;;
;; Builds immutable named derivations, checked parameter cases, and candidate
;; substitutions while preserving the original problem.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append-map remove-duplicates)
  (only-in racket/match match-define)
  (for-syntax racket/base syntax/parse)
  "datum.rkt"
  "model.rkt"
  "context.rkt"
  "operations.rkt"
  "evidence.rkt"
  "validation.rkt")

;; Exports
(provide
  derive derive/proc derive-cases make-case-derivation (struct-out derivation)
  (struct-out case-branch) (struct-out case-derivation) (struct-out solution-check) after
  derivation-step derivation-states derivation-verification derivation-prefix check-solution)

;;;
;;; Data Representation
;;;
(struct derivation (initial steps final)
  #:transparent)

;; derivation is an immutable record. Its fields have the following roles.
;;  - initial  math?  initial checkpoint
;;  - steps  (listof rewrite-step?)  chronological applied steps
;;  - final  math?  last checkpoint, or initial state for an empty derivation
(struct case-branch (name guard derivation)
  #:transparent)

;; case-branch is an immutable record. Its fields have the following roles.
;;  - name  symbol?  unique sibling branch name
;;  - guard  math-datum?  scoped parameter condition
;;  - derivation  any/c  nested derivation or case tree
(struct case-derivation (prefix branches coverage)
  #:transparent)

;; case-derivation is an immutable record. Its fields have the following roles.
;;  - prefix  derivation?  shared mathematical prefix
;;  - branches  (listof case-branch?)  declared branch presentation order
;;  - coverage  verification?  exhaustiveness and disjointness evidence
(struct solution-check (problem variable value derivation verification)
  #:transparent)

;; solution-check is an immutable record. Its fields have the following roles.
;;  - problem  math?  original problem and domain
;;  - variable  symbol?  variable being specialized
;;  - value  math-datum?  candidate value
;;  - derivation  (or/c derivation? #f)  visible substitution steps, absent for an
;;    undefined candidate
;;  - verification  verification?  candidate membership report, not solution-set
;;    completeness
; derivation-prefix : any/c -> derivation?
;;   Turns a state into an empty derivation or retains the existing prefix.
(define (derivation-prefix value)
  (cond
    [(math? value) (derivation value '() value)]
    [(derivation? value) value]
    [else (raise-argument-error 'derivation-prefix "math? or derivation?" value)]))

;;;
;;; Named Derivations
;;;
; derive/proc : (or/c math? derivation?) list? -> derivation?
;;   Appends named operations in order while rejecting duplicate step names.
(define (derive/proc initial named-operations)
  (define start (derivation-prefix initial))
  (for/fold ([d start]) ([entry (in-list named-operations)])
    (define name (car entry))
    (define op (cdr entry))
    (when (findf (lambda (s) (eq? name (rewrite-step-name s))) (derivation-steps d))
      (math-error 'derive 'duplicate-step
        "Step names must be unique within a branch scope."
        name))
    (define step (apply-math-operation (derivation-final d) op #:name name))
    (derivation
      (derivation-initial d)
      (append (derivation-steps d) (list step))
      (rewrite-step-after step))))

; derive : syntax -> syntax
;;   Expands named step clauses into the procedural derivation builder.
(define-syntax-rule (derive initial [name operation] ...)
  (derive/proc initial (list (cons 'name operation) ...)))

;;;
;;; Parameter Cases
;;;
; make-case-derivation : (or/c math? derivation?) list? -> case-derivation?
;;   Builds scoped branches only after checking case coverage.
(define (make-case-derivation initial branch-specs)
  (unless (and
            (list? branch-specs)
            (pair? branch-specs)
            (andmap (lambda (entry) (and (list? entry) (= (length entry) 3))) branch-specs))
    (raise-argument-error 'make-case-derivation
      "nonempty list of three-element branch specifications"
      branch-specs))
  (for ([entry (in-list branch-specs)])
    (check-symbol 'make-case-derivation (car entry))
    (check-datum 'make-case-derivation (cadr entry))
    (check-procedure 'make-case-derivation (caddr entry) 1))
  ;; branch-spec: (list name guard (-> math? derivation-or-cases))
  (define prefix (derivation-prefix initial))
  (define state (derivation-final prefix))
  (define names (map car branch-specs))
  (unless (= (length names) (length (remove-duplicates names)))
    (math-error 'derive-cases 'duplicate-case "Case names must be unique." names))
  (define coverage (check-case-coverage (math-context-of state) (map cadr branch-specs)))
  (enforce-verification 'derive-cases coverage)
  (define branches
    (for/list ([spec (in-list branch-specs)])
      (match-define (list name guard factory) spec)
      (define branch-state
        (math-with-context state
          (context-assume (math-context-of state) guard)
          #:scope name))
      (define body (factory branch-state))
      (unless (or (derivation? body) (case-derivation? body))
        (raise-argument-error 'derive-cases
          "branch factory returning a derivation or case derivation"
          body))
      (case-branch name guard body)))
  (case-derivation prefix branches coverage))

; derive-cases : syntax -> syntax
;;   Expands named guards and branch bodies into an explicit case tree.
(define-syntax (derive-cases stx)
  (syntax-parse stx
    [(_ initial branch ...)
     (define specs
       (for/list ([b (in-list (syntax->list #'(branch ...)))])
         (syntax-parse b
           [[name:id guard #:then factory] #'(list 'name guard factory)]
           [[name:id guard [step:id op] ...]
            #'(list 'name guard (lambda (state) (derive state [step op] ...)))])))
     #`(make-case-derivation initial (list #,@specs))]))

;;;
;;; Checkpoint Inspection
;;;
; after : (or/c math? derivation? case-derivation? solution-check?) [(or/c symbol?
;   (listof symbol?) #f)] -> math?
;;   Returns a unique endpoint or named checkpoint, requiring an explicit branch for
;;   case trees.
(define (after d [label #f])
  (cond
    [label (rewrite-step-after (derivation-step d label))]
    [(math? d) d]
    [(derivation? d) (derivation-final d)]
    [(solution-check? d) (after (solution-check-derivation d))]
    [else
     (math-error 'after 'branch-required
       "A case tree has several endpoints; select a branch."
       label)]))

; derivation-step : (or/c derivation? case-derivation?) (or/c symbol? (listof symbol?))
;   -> rewrite-step?
;;   Looks up a named step or case path without silently selecting a branch.
(define (derivation-step d label)
  (cond
    [(derivation? d)
     (define result
       (findf (lambda (s) (eq? (rewrite-step-name s) label)) (derivation-steps d)))
     (or result (math-error 'derivation-step 'missing-step "Unknown step name." label))]
    [(case-derivation? d)
     (cond
       [(symbol? label) (derivation-step (case-derivation-prefix d) label)]
       [else
        (define b
          (findf
            (lambda (b) (eq? (case-branch-name b) (car label)))
            (case-derivation-branches d)))
        (unless b (math-error 'derivation-step 'missing-case "Unknown branch." label))
        (derivation-step
          (case-branch-derivation b)
          (if (= (length label) 2) (cadr label) (cdr label)))])]
    [else (raise-argument-error 'derivation-step "derivation or case derivation" d)]))

; derivation-states : (or/c derivation? case-derivation?) -> (listof math?)
;;   Returns checkpoint states in significant derivation and branch order.
(define (derivation-states d)
  (cond
    [(derivation? d)
     (cons (derivation-initial d) (map rewrite-step-after (derivation-steps d)))]
    [(case-derivation? d)
     (append
       (derivation-states (case-derivation-prefix d))
       (append-map
         (lambda (b) (derivation-states (case-branch-derivation b)))
         (case-derivation-branches d)))]
    [else (raise-argument-error 'derivation-states "derivation or case derivation" d)]))

; derivation-verification : (or/c derivation? case-derivation?) -> verification?
;;   Combines rewrite evidence and parameter-case coverage without external CAS calls.
(define (derivation-verification d)
  (cond
    [(derivation? d)
     (merge-verifications (map rewrite-step-verification (derivation-steps d)) 'derivation)]
    [(case-derivation? d)
     (merge-verifications
       (append
         (list
           (case-derivation-coverage d)
           (derivation-verification (case-derivation-prefix d)))
         (map
           (lambda (b) (derivation-verification (case-branch-derivation b)))
           (case-derivation-branches d)))
       'case-derivation)]
    [else (raise-argument-error 'derivation-verification "derivation or case derivation" d)]))

;;;
;;; Candidate Checking
;;;
; check-solution : math? #:for symbol? #:value math-datum? -> solution-check?
;;   Checks a candidate in the original domain before constructing visible substitution
;;   steps.
(define (check-solution problem #:for variable #:value value)
  (unless (and (math? problem) (relation? (math-datum problem)))
    (raise-argument-error 'check-solution "mathematical relation state" problem))
  (define bindings (hash variable value))
  (define ctx (math-context-of problem))
  (define domain-checks
    (map (lambda (r) (context-prove ctx (held-substitute r bindings))) (context-facts ctx)))
  (define domain-check (merge-verifications domain-checks 'candidate-domain))
  (cond
    [(not (eq? (verification-status domain-check) 'established))
     ;; The candidate may be outside the original domain. Do not construct
     ;; or numerically evaluate an undefined replacement such as 1/0.
     (solution-check problem variable value #f domain-check)]
    [else
     (define d0 (derive problem [substitute-candidate (substitute bindings)]))
     (define d
       (let loop ([d d0] [i 0])
         (define raw (math-datum (after d)))
         (define next (exact-evaluate raw #:deepest? #t))
         (if (or (equal? raw next) (>= i 128))
           d
           (loop
             (derive/proc d
               (list
                 (cons
                   (string->symbol (format "arithmetic-~a" i))
                   (evaluate #:mode 'deepest))))
             (add1 i)))))
     (solution-check problem variable value d (context-prove ctx (math-datum (after d))))]))
