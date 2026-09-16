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
  (only-in racket/list append-map last remove-duplicates)
  (only-in racket/match match-define)
  (for-syntax racket/base syntax/parse)
  "datum.rkt"
  "model.rkt"
  "context.rkt"
  "operations.rkt"
  "steps.rkt"
  "evidence.rkt"
  "validation.rkt")

;; Exports
(provide
  derive derive/proc derive-cases make-case-derivation (struct-out derivation)
  (struct-out case-branch) (struct-out case-derivation) (struct-out solution-check) after
  derivation-step derivation-states derivation-verification derivation-prefix check-solution
  (struct-out derivation-node) derivation-node-at derivation-node-relation
  derivation-node-verification derivation-step-paths derivation-step-keys
  derivation-step-key derivation-leaf-nodes node-leaf-nodes derivation-append)

;;;
;;; Data Representation
;;;
(struct derivation (initial steps final tree)
  #:transparent)

;; derivation is an immutable record. Its fields have the following roles.
;;  - initial  math?  initial checkpoint
;;  - steps  (listof rewrite-step?)  chronological applied steps
;;  - final  math?  last checkpoint, or initial state for an empty derivation
;;  - tree  (listof derivation-node?)  ordered roots; its leaf steps equal steps exactly

(struct derivation-node (path before after children step)
  #:transparent)
;; derivation-node describes one applied elementary step or composite move.
;;  - path  (nonempty-listof symbol?)  unique derivation-relative address; order matters
;;  - before  math?  the exact input state of the first descendant elementary step
;;  - after  math?  the exact output state of the final descendant elementary step
;;  - children  (listof derivation-node?)  ordered children; empty exactly for a leaf
;;  - step  (or/c rewrite-step? #f)  original leaf rewrite; false exactly for a move
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
    [(math? value) (derivation value '() value '())]
    [(derivation? value) value]
    [else (raise-argument-error 'derivation-prefix "math? or derivation?" value)]))

;;;
;;; Named Derivations
;;;
; apply-named-node : math? symbol? (or/c math-operation? step-sequence?) list?
;                    -> derivation-node?
;;   Applies one recipe recursively, preserving elementary operation names and lineage.
(define (apply-named-node state name operation parent-path)
  (define path (append parent-path (list name)))
  (cond
    [(step-sequence? operation)
     (define-values (end children)
       (for/fold ([current state] [nodes '()])
                 ([entry (in-list (step-sequence-entries operation))])
         (define node (apply-named-node current (car entry) (cdr entry) path))
         (values (derivation-node-after node) (cons node nodes))))
     (derivation-node path state end (reverse children) #f)]
    [else
     (define step
       (with-handlers
         ([exn:fail:math?
           (lambda (error)
             (raise (exn:fail:math
                     (format "~a\n  at mathematical step ~s" (exn-message error) path)
                     (exn-continuation-marks error)
                     (exn:fail:math-code error)
                     (cons (list 'step-path path) (exn:fail:math-details error)))))])
         (apply-math-operation state operation #:name name)))
     (derivation-node path state (rewrite-step-after step) '() step)]))

; node-leaf-nodes : derivation-node? -> (listof derivation-node?)
;;   Lists elementary descendants in the same order as mathematical execution.
(define (node-leaf-nodes node)
  (if (derivation-node-step node)
      (list node)
      (append-map node-leaf-nodes (derivation-node-children node))))

; derivation-leaf-nodes : derivation? -> (listof derivation-node?)
;;   Flattens only the inspection hierarchy, without constructing new mathematical steps.
(define (derivation-leaf-nodes d)
  (append-map node-leaf-nodes (derivation-tree d)))

; derive/proc : (or/c math? derivation?) list? -> derivation?
;;   Applies named operations or recipes and retains both their tree and elementary trace.
(define (derive/proc initial named-operations)
  (define start (derivation-prefix initial))
  (define entries (validate-named-operations 'derive named-operations))
  (define existing (map (lambda (node) (car (derivation-node-path node)))
                        (derivation-tree start)))
  (for ([entry (in-list entries)])
    (when (memq (car entry) existing)
      (math-error 'derive 'duplicate-step
                  "Step names must be unique among top-level siblings." (car entry))))
  (define-values (end nodes)
    (for/fold ([state (derivation-final start)] [nodes '()])
              ([entry (in-list entries)])
      (define node (apply-named-node state (car entry) (cdr entry) '()))
      (values (derivation-node-after node) (cons node nodes))))
  (define added (reverse nodes))
  (derivation (derivation-initial start)
              (append (derivation-steps start)
                      (map derivation-node-step (append-map node-leaf-nodes added)))
              end
              (append (derivation-tree start) added)))

; derive : syntax -> syntax
;;   Expands named elementary or composite clauses into the pure derivation builder.
(define-syntax (derive stx)
  (syntax-parse stx
    [(_ initial [name:id operation] ...)
     #'(derive/proc initial (list (cons 'name operation) ...))]))

; derivation-append : derivation? derivation? -> derivation?
;;   Concatenates a prefix and its context-specialized suffix without erasing their moves.
(define (derivation-append prefix suffix)
  (define tree (append (derivation-tree prefix) (derivation-tree suffix)))
  (define names (map (lambda (node) (car (derivation-node-path node))) tree))
  (unless (= (length names) (length (remove-duplicates names)))
    (math-error 'present 'duplicate-step-path
                "Use unique top-level names along each complete case path, including its shared prefix."
                names))
  (derivation (derivation-initial prefix)
              (append (derivation-steps prefix) (derivation-steps suffix))
              (derivation-final suffix) tree))

; derivation-node-relation : derivation-node? -> symbol?
;;   Summarizes descendant relationships conservatively; mixed claims never become equivalence.
(define (derivation-node-relation node)
  (define relations
    (remove-duplicates
     (map (lambda (leaf) (rewrite-step-relation (derivation-node-step leaf)))
          (node-leaf-nodes node))))
  (define (only? allowed) (andmap (lambda (r) (memq r allowed)) relations))
  (cond
    [(= (length relations) 1) (car relations)]
    [(only? '(expression-equivalence equation-equivalence)) 'equivalence]
    [(only? '(expression-equivalence equation-equivalence implication)) 'implication]
    [(only? '(expression-equivalence equation-equivalence specialization)) 'specialization]
    [else 'mixed]))

; derivation-node-verification : derivation-node? -> verification?
;;   Combines elementary evidence without claiming solution completeness or an endpoint proof.
(define (derivation-node-verification node)
  (merge-verifications
   (map (lambda (leaf) (rewrite-step-verification (derivation-node-step leaf)))
        (node-leaf-nodes node))
   (list 'move (derivation-node-path node) (derivation-node-relation node))))

;;;
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
    [label (derivation-node-after (derivation-node-at d label))]
    [(math? d) d]
    [(derivation? d) (derivation-final d)]
    [(solution-check? d) (after (solution-check-derivation d))]
    [else
     (math-error 'after 'branch-required
       "A case tree has several endpoints; select a branch."
       label)]))

; tree-nodes : list? -> (listof derivation-node?)
;;   Traverses a mathematical move forest in stable preorder for address resolution.
(define (tree-nodes roots)
  (append-map (lambda (node) (cons node (tree-nodes (derivation-node-children node)))) roots))

; node-matches : derivation? (or/c symbol? list?) -> (listof derivation-node?)
;;   Resolves exact paths, or an unambiguous local-name shorthand, within one derivation.
(define (node-matches d label)
  (define nodes (tree-nodes (derivation-tree d)))
  (if (list? label)
      (filter (lambda (node) (equal? label (derivation-node-path node))) nodes)
      (filter (lambda (node) (eq? label (last (derivation-node-path node)))) nodes)))

; derivation-node-at : (or/c derivation? case-derivation? solution-check?)
;                      (or/c symbol? (nonempty-listof symbol?)) -> derivation-node?
;;   Finds a move or leaf by exact path; ambiguous shorthand is never guessed.
(define (derivation-node-at source label)
  (unless (or (symbol? label)
              (and (list? label) (pair? label) (andmap symbol? label)))
    (raise-argument-error 'derivation-node-at "symbol or nonempty list of symbols" label))
  (define d (if (solution-check? source) (solution-check-derivation source) source))
  (define results
    (cond
      [(derivation? d) (node-matches d label)]
      [(case-derivation? d)
       (define prefix (node-matches (case-derivation-prefix d) label))
       (define branch
         (and (list? label) (pair? (cdr label))
              (findf (lambda (b) (eq? (case-branch-name b) (car label)))
                     (case-derivation-branches d))))
       (when (and branch (pair? prefix))
         (math-error 'derivation-node-at 'ambiguous-step
                     "Address names both a shared move and a case step." label))
       (if branch
           (list (derivation-node-at (case-branch-derivation branch)
                                     (if (null? (cddr label)) (cadr label) (cdr label))))
           prefix)]
      [else (raise-argument-error 'derivation-node-at "derivation or case derivation" d)]))
  (cond
    [(null? results) (math-error 'derivation-node-at 'missing-step "Unknown step name or path." label)]
    [(pair? (cdr results))
     (math-error 'derivation-node-at 'ambiguous-step
                 "Ambiguous step name; use a complete hierarchical path."
                 label (map derivation-node-path results))]
    [else (car results)]))

; derivation-step : (or/c derivation? case-derivation?) (or/c symbol? (listof symbol?))
;                   -> rewrite-step?
;;   Retrieves an elementary step; use derivation-node-at for a composite move.
(define (derivation-step d label)
  (define node (derivation-node-at d label))
  (or (derivation-node-step node)
      (math-error 'derivation-step 'composite-step
                  "This path names a composite move, not an elementary rewrite; use derivation-node-at."
                  label)))

; derivation-step-paths : derivation? -> (listof (nonempty-listof symbol?))
;;   Lists full derivation-relative leaf addresses in chronological order.
(define (derivation-step-paths d)
  (map derivation-node-path (derivation-leaf-nodes d)))

; path->step-key : (nonempty-listof symbol?) -> (or/c symbol? list?)
;;   Retains flat symbolic schedule keys and uses full paths for nested steps.
(define (path->step-key path)
  (if (null? (cdr path)) (car path) path))

; derivation-step-keys : derivation? -> list?
;;   Lists canonical presentation keys in the same order as elementary execution.
(define (derivation-step-keys d)
  (map path->step-key (derivation-step-paths d)))

; derivation-step-key : derivation? rewrite-step? -> (or/c symbol? list?)
;;   Locates the canonical schedule key for the exact leaf rewrite held by a derivation.
(define (derivation-step-key d step)
  (define node
    (findf (lambda (node) (eq? (derivation-node-step node) step)) (derivation-leaf-nodes d)))
  (unless node
    (raise-arguments-error 'derivation-step-key "an elementary step belonging to the derivation"
                           "step" step))
  (path->step-key (derivation-node-path node)))

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
