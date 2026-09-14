#lang racket/base

;;;
;;; Mathematical States and Lineage
;;;
;; Defines held mathematical snapshots, deterministic occurrence identities, and
;; validated rewrite records independently of any renderer.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append* count remove-duplicates)
  racket/match
  "datum.rkt"
  "context.rkt"
  "evidence.rkt"
  "validation.rkt")

;; Exports
(provide
  current-math-prover prove-in-context math math? math-datum math-id math-context-of
  math-occurrences math-revision math-with-context math-occurrence-at math-inspect
  current-math-validation math-error enforce-verification (struct-out exn:fail:math)
  (struct-out occurrence) (struct-out path-link) (struct-out trace-event)
  (struct-out trace-relation) (struct-out rewrite-step) finish-step trace-descendants
  unchanged-links prefix-links prefix-events)

;;;
;;; Data Representation
;;;
(struct exn:fail:math exn:fail
  (code details)
  #:transparent)

;; exn:fail:math is an immutable record. Its fields have the following roles.
;;  - code  symbol?  stable mathematical diagnostic category
;;  - details  list?  ordered diagnostic context
; math-error : symbol? symbol? string? any/c ... -> none/c
;;   Raises a mathematical diagnostic with a stable error code.
(define (math-error who code message . details)
  (raise
    (exn:fail:math
      (format "~a: ~a~a" who message (if (null? details) "" (format "\n  ~s" details)))
      (current-continuation-marks)
      code
      details)))

; current-math-validation : (parameter/c (or/c 'strict 'draft))
;;   Controls construction-time obligation rejection; strict is the default.
(define current-math-validation
  (make-parameter 'strict
    (lambda (v)
      (unless (memq v '(strict draft))
        (raise-argument-error 'current-math-validation "'strict or 'draft" v))
      v)))

;; Construction-time proof hook. Never retained in a sampled animation scene.
; current-math-prover : (parameter/c procedure?)
;;   Selects a construction-time prover; callbacks are not retained in scenes.
(define current-math-prover
  (make-parameter context-prove (lambda (p) (check-procedure 'current-math-prover p 2))))

; prove-in-context : math-context? math-datum? -> verification?
;;   Checks the construction-time prover result against the evidence protocol.
(define (prove-in-context context proposition)
  (define result ((current-math-prover) context proposition))
  (unless (verification? result)
    (math-error 'prove-in-context 'prover-contract
      "A mathematical prover must return verification evidence."
      result))
  (unless (equal? (verification-proposition result) proposition)
    (math-error 'prove-in-context 'prover-contract
      "Prover evidence must refer to the requested proposition."
      proposition
      result))
  result)

; enforce-verification : symbol? any/c -> void?
;;   Rejects refutations and rejects unresolved obligations outside draft mode.
(define (enforce-verification who v)
  (case (verification-status v)
    [(refuted)
     (math-error who 'refuted (verification-message v) (verification-proposition v))]
    [(unknown)
     (when (eq? (current-math-validation) 'strict)
       (math-error who 'pending-obligation
         (verification-message v)
         (verification-obligations v)))]))

(struct occurrence (id path datum)
  #:transparent)

;; occurrence is an immutable record. Its fields have the following roles.
;;  - id  symbol?  stable occurrence identity, independent of rendered views
;;  - path  operand-path?  zero-based path in this state only
;;  - datum  math-datum?  exact held subexpression
(struct mathematical-state (id revision datum context occurrences)
  #:transparent)

;; mathematical-state is an immutable record. Its fields have the following roles.
;;  - id  symbol?  state identity namespace
;;  - revision  any/c  deterministic initial, step, or case revision
;;  - datum  math-datum?  held expression, never implicitly normalized
;;  - context  math-context?  assumptions, definitions, and retained exclusions
;;  - occurrences  immutable-hash?  operand path to occurrence map; traversal order
;;    comes from the datum
; math? : any/c -> boolean?
;;   Reports whether the value is a mathematical state.
(define math?
  mathematical-state?)

; math-datum : math? -> math-datum?
;;   Returns the exact held expression without normalizing it.
(define math-datum
  mathematical-state-datum)

; math-id : math? -> symbol?
;;   Returns the stable mathematical-state namespace.
(define math-id
  mathematical-state-id)

; math-revision : math? -> any/c
;;   Returns the deterministic derivation revision, not a process-global counter.
(define math-revision
  mathematical-state-revision)

; math-context-of : math? -> math-context?
;;   Returns the assumptions and retained domain of this state.
(define math-context-of
  mathematical-state-context)

; math-occurrences : math? -> immutable-hash?
;;   Returns the operand-path map for this immutable state.
(define math-occurrences
  mathematical-state-occurrences)

; identifier : symbol? any/c operand-path? -> symbol?
;;   Derives an occurrence identity from state, revision, and operand path.
(define (identifier id revision path)
  (string->symbol (format "~a/~s/~s" id revision path)))

;;;
;;; State Construction
;;;
; math : math-datum? [#:id symbol?] [#:context math-context?] -> math?
;;   Constructs a held mathematical state with deterministic occurrence identities.
(define (math datum #:id [id 'math] #:context [ctx (math-context)])
  (check-datum 'math datum)
  (unless (symbol? id) (raise-argument-error 'math "symbol? as #:id" id))
  (unless (math-context? ctx) (raise-argument-error 'math "math-context?" ctx))
  (when (context-inconsistent? ctx)
    (math-error 'math 'inconsistent-context "Inconsistent mathematical context."))
  (define needs
    (for/list ([r
                (in-list
                  (domain-requirements
                    (definition-expand datum (math-context-definitions ctx))))]
                #:do [(define report (prove-in-context ctx r))]
                #:unless (eq? (verification-status report) 'established))
      (when (eq? (verification-status report) 'refuted)
        (math-error 'math 'undefined-expression
          "The expression is undefined in this context."
          r))
      r))
  (define full-context (context-add-restrictions ctx needs))
  (when (context-inconsistent? full-context)
    (math-error 'math 'empty-domain "The displayed expression has an empty domain." datum))
  (mathematical-state id 'initial datum full-context
    (for/hash ([p (in-list (datum-paths datum))])
      (values p (occurrence (identifier id 'initial p) p (datum-ref datum p))))))

; math-with-context : math? math-context? [#:scope (or/c symbol? #f)] -> math?
;;   Creates a scoped state while retaining the original domain restrictions.
(define (math-with-context state requested-context #:scope [scope #f])
  (unless (or (not scope) (symbol? scope))
    (raise-argument-error 'math-with-context "symbol? or #f as #:scope" scope))
  (unless (math? state) (raise-argument-error 'math-with-context "math?" state))
  (unless (math-context? requested-context)
    (raise-argument-error 'math-with-context "math-context?" requested-context))
  (define ctx
    (context-add-restrictions requested-context
      (math-context-restrictions (math-context-of state))))
  (when (context-inconsistent? ctx)
    (math-error 'math-with-context 'inconsistent-context "Inconsistent branch context."))
  (struct-copy mathematical-state state
    [revision (if scope (list 'case scope (math-revision state)) (math-revision state))]
    [context ctx]))

; math-occurrence-at : math? operand-path? -> occurrence?
;;   Selects the occurrence at an exact zero-based operand path.
(define (math-occurrence-at state path)
  (hash-ref
    (math-occurrences state)
    path
    (lambda () (math-error 'math-occurrence-at 'invalid-path "Missing occurrence." path))))

;;;
;;; State Inspection
;;;
; math-inspect : math? operand-path? -> immutable-hash?
;;   Reports occurrence identity, held syntax, context, and revision.
(define (math-inspect state path)
  (define o (math-occurrence-at state path))
  (hash 'id
    (occurrence-id o)
    'path
    path
    'datum
    (occurrence-datum o)
    'state
    (math-id state)
    'revision
    (math-revision state)
    'assumptions
    (math-context-assumptions (math-context-of state))
    'domain
    (math-context-restrictions (math-context-of state))))

;; A subtree link carries an exact structural witness. A container link keeps
;; only the operator/container identity; its changed children are NOT inferred.
;;;
;;; Rewrite Witnesses
;;;
(struct path-link (source target kind subtree?)
  #:transparent)

;; path-link is an immutable record. Its fields have the following roles.
;;  - source  operand-path?  source location in the input snapshot
;;  - target  operand-path?  destination location in the output snapshot
;;  - kind  symbol?  preserve, container, reorder, or copy relationship
;;  - subtree?  boolean?  whether an exact equal subtree is witnessed
(struct trace-event (kind sources targets details)
  #:transparent)

;; trace-event is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  semantic rewrite event
;;  - sources  (listof operand-path?)  source witnesses in declared order
;;  - targets  (listof operand-path?)  target witnesses in declared order
;;  - details  any/c  event-specific explanation
(struct trace-relation (kind sources targets details)
  #:transparent)

;; trace-relation is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  preserve, copy, merge, cancel, evaluate, or related event
;;  - sources  (listof symbol?)  source occurrence identities in witness order
;;  - targets  (listof symbol?)  target occurrence identities in witness order
;;  - details  any/c  semantic explanation, not animation timing
(struct rewrite-step (name before after rule focus bindings links trace relation verification details version)
  #:transparent)

;; rewrite-step is an immutable record. Its fields have the following roles.
;;  - name  symbol?  unique step name within its derivation path
;;  - before  math?  exact input checkpoint
;;  - after  math?  exact output checkpoint
;;  - rule  symbol?  applied mathematical operation
;;  - focus  operand-path?  selected input location
;;  - bindings  immutable-hash?  held metavariable bindings
;;  - links  (listof path-link?)  ordered structural provenance
;;  - trace  (listof trace-relation?)  typed occurrence relationships in deterministic
;;    order
;;  - relation  symbol?  equivalence, implication, or specialization classification
;;  - verification  verification?  evidence and outstanding conditions
;;  - details  any/c  snapshotted rule-specific metadata
;;  - version  exact-positive-integer?  rule-version identity for reproducibility
; prefix-links : (listof path-link?) any/c any/c -> (listof path-link?)
;;   Rebases ordered structural witnesses into containing operand paths.
(define (prefix-links links before-prefix after-prefix)
  (for/list ([l (in-list links)])
    (struct-copy path-link l
      [source (append before-prefix (path-link-source l))]
      [target (append after-prefix (path-link-target l))])))

; prefix-events : (listof trace-event?) any/c any/c -> (listof trace-event?)
;;   Rebases event paths without changing their semantic order.
(define (prefix-events events before-prefix after-prefix)
  (for/list ([e (in-list events)])
    (struct-copy trace-event e
      [sources (map (lambda (p) (append before-prefix p)) (trace-event-sources e))]
      [targets (map (lambda (p) (append after-prefix p)) (trace-event-targets e))])))

; unchanged-links : math-datum? math-datum? [any/c] -> (listof path-link?)
;;   Retains exact mechanical subtrees without inferring algebraic correspondence.
(define (unchanged-links before after [p '()])
  ;; For mechanically rebuilt trees (evaluation/substitution), not arbitrary
  ;; equivalence matching. A changed arity has no inferred descendants.
  (cond
    [(equal? before after) (list (path-link p p 'preserve #t))]
    [(and
       (app? before)
       (app? after)
       (eq? (head before) (head after))
       (= (length before) (length after)))
     (cons
       (path-link p p 'container #f)
       (append*
         (for/list ([a (in-list (cdr before))] [b (in-list (cdr after))] [i (in-naturals)])
           (unchanged-links a b (append p (list i))))))]
    [else '()]))

; expanded-links : math-datum? math-datum? (listof path-link?) -> (listof path-link?)
;;   Expands exact subtree witnesses into validated occurrence links.
(define (expanded-links before after links)
  (remove-duplicates
    (append*
      (for/list ([l (in-list links)])
        (define a (datum-ref before (path-link-source l)))
        (define b (datum-ref after (path-link-target l)))
        (cond
          [(path-link-subtree? l)
           (unless (equal? a b)
             (math-error 'finish-step 'invalid-provenance
               "A preserved subtree changed value."
               l
               a
               b))
           (for/list ([p (in-list (datum-paths a))])
             (path-link
               (append (path-link-source l) p)
               (append (path-link-target l) p)
               (path-link-kind l)
               #f))]
          [else (list l)])))
    equal?))

;;;
;;; Rewrite Commit and Identity
;;;
; finish-step : symbol? math-datum? math-datum? math-rule? selector? hash? (listof
;   path-link?) (listof trace-event?) any/c any/c [#:details any/c] [#:version any/c] ->
;   rewrite-step?
;;   Validates a rewrite, retains domains, and assigns deterministic descendant
;;   identities.
(define (finish-step name before datum rule focus bindings links events relation verification
          #:details [details '()]
          #:version [version 1])
  (check-datum 'finish-step datum)
  (define ctx (math-context-of before))
  (define output-domain
    (domain-requirements (definition-expand datum (math-context-definitions ctx))))
  (define domain-checks (map (lambda (r) (prove-in-context ctx r)) output-domain))
  (define v (merge-verifications (cons verification domain-checks) (list 'step name)))
  (enforce-verification name v)
  ;; Pending conditions remain pending; never insert an unproved output
  ;; denominator into assumptions and then use it to discharge itself.
  (define proved-domain
    (for/list ([r (in-list output-domain)]
                [check (in-list domain-checks)]
                #:when (eq? (verification-status check) 'established))
      r))
  (define new-ctx (context-add-restrictions ctx proved-domain))
  (define ls (expanded-links (math-datum before) datum links))
  (define revision (list 'step name (math-revision before)))
  (define occurrences
    (for/hash ([p (in-list (datum-paths datum))])
      (define incoming (filter (lambda (l) (equal? (path-link-target l) p)) ls))
      (when (> (length incoming) 1)
        (math-error name 'ambiguous-provenance
          "Several preservation links target one occurrence; use a merge event."
          p))
      (define l (and (pair? incoming) (car incoming)))
      (define unique?
        (and l
          (= 1
            (count
              (lambda (other) (equal? (path-link-source l) (path-link-source other)))
              ls))))
      (define old-id
        (and l (occurrence-id (math-occurrence-at before (path-link-source l)))))
      (define id
        (if (and unique? (memq (path-link-kind l) '(preserve container reorder)))
          old-id
          (identifier (math-id before) revision p)))
      (values p (occurrence id p (datum-ref datum p)))))
  (define after (mathematical-state (math-id before) revision datum new-ctx occurrences))
  (define from-id (lambda (p) (occurrence-id (math-occurrence-at before p))))
  (define to-id (lambda (p) (occurrence-id (math-occurrence-at after p))))
  (define mapped-sources (remove-duplicates (map path-link-source ls) equal?))
  (define mapped-targets (map path-link-target ls))
  (define trace
    (append
      (for/list ([p (in-list mapped-sources)])
        (define entries (filter (lambda (l) (equal? (path-link-source l) p)) ls))
        (trace-relation
          (if (> (length entries) 1) 'copy (path-link-kind (car entries)))
          (list (from-id p))
          (map (lambda (l) (to-id (path-link-target l))) entries)
          '()))
      (for/list ([e (in-list events)])
        (trace-relation
          (trace-event-kind e)
          (map from-id (trace-event-sources e))
          (map to-id (trace-event-targets e))
          (trace-event-details e)))
      (for/list ([p (in-list (datum-paths (math-datum before)))]
                  #:unless (member p mapped-sources))
        (trace-relation 'remove (list (from-id p)) '() '()))
      (for/list ([p (in-list (datum-paths datum))] #:unless (member p mapped-targets))
        (trace-relation 'create '() (list (to-id p)) '()))))
  (rewrite-step name before after rule focus bindings ls trace relation v details version))

;;;
;;; Lineage Inspection
;;;
; trace-descendants : rewrite-step? (or/c symbol? occurrence?) -> (listof occurrence?)
;;   Returns traced descendants in numerical operand traversal order.
(define (trace-descendants step item)
  (define id (if (occurrence? item) (occurrence-id item) item))
  (define targets
    (remove-duplicates
      (append*
        (for/list ([r (in-list (rewrite-step-trace step))]
                    #:when
                    (and
                      (member id (trace-relation-sources r))
                      (not (memq (trace-relation-kind r) '(remove create)))))
          (trace-relation-targets r)))))
  (for/list ([path (in-list (datum-paths (math-datum (rewrite-step-after step))))]
              #:do [(define occurrence (math-occurrence-at (rewrite-step-after step) path))]
              #:when (member (occurrence-id occurrence) targets))
    occurrence))
