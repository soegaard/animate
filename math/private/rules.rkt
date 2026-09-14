#lang racket/base

;;;
;;; Traceable Pattern Rules
;;;
;; Defines held rewrite templates and derives structural occurrence witnesses from their
;; declared metavariables.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "validation.rkt"
  (only-in racket/list remove-duplicates)
  racket/match
  (for-syntax racket/base syntax/parse)
  "datum.rkt"
  "model.rkt"
  "select.rkt"
  "operations.rkt"
  "context.rkt"
  "polynomial.rkt"
  "evidence.rkt")

;; Exports
(provide
  define-math-rule make-math-rule math-rule? math-rule-name use-rule apply-rule
  apply-rewrite template-bindings)

;;;
;;; Data Representation
;;;
(struct math-rule (name variables before after requires merge version check)
  #:transparent)
;; math-rule is an immutable record. Its fields have the following roles.
;;  - name  symbol?  rule identity
;;  - variables  (listof symbol?)  unique metavariables in declaration order
;;  - before  math-datum?  held input template
;;  - after  math-datum?  held output template
;;  - requires  (listof math-datum?)  ordered side-condition templates
;;  - merge  (or/c #f 'merge)  explicit repeated-source merge policy
;;  - version  exact-positive-integer?  rule version
;;  - check  symbol?  polynomial identity or author assertion policy

;;;
;;; Rule Construction
;;;
; make-math-rule : symbol? (listof symbol?) math-datum? math-datum? [#:requires (listof
;   math-datum?)] [#:merge (or/c symbol? #f)] [#:version exact-positive-integer?]
;   [#:check symbol?] -> math-rule?
;;   Validates held templates, metavariables, merge policy, and rule version.
(define (make-math-rule name variables before after
          #:requires [requires '()]
          #:merge [merge #f]
          #:version [version 1]
          #:check [check 'polynomial-identity])
  (unless (and
            (symbol? name)
            (list? variables)
            (andmap symbol? variables)
            (= (length variables) (length (remove-duplicates variables))))
    (raise-argument-error 'make-math-rule "unique named metavariables" variables))
  (check-datum 'make-math-rule before)
  (check-datum 'make-math-rule after)
  (check-list-of 'make-math-rule requires math-datum? "list of requirements")
  (for-each (lambda (p) (check-datum 'make-math-rule p)) requires)
  (unless (exact-positive-integer? version)
    (raise-argument-error 'make-math-rule "positive rule version" version))
  (unless (memq check '(polynomial-identity author-assertion))
    (raise-argument-error 'make-math-rule "'polynomial-identity or 'author-assertion" check))
  (unless (memq merge '(#f merge))
    (raise-argument-error 'make-math-rule "#f or 'merge" merge))
  (for ([v (in-list variables)])
    (when (and (free-of? before v) (not (free-of? after v)))
      (math-error 'make-math-rule 'unbound-metavariable
        "Output metavariable has no source binding."
        v)))
  (math-rule name variables before after requires merge version check))

; define-math-rule : syntax -> syntax
;;   Captures held rule templates without invoking arithmetic constructors.
(define-syntax (define-math-rule stx)
  (syntax-parse stx
    [(_ name:id
       #:metavariables (v:id ...)
       #:from from
       #:to to
       (~optional (~seq #:in domain:id) #:defaults ([domain #'real-scalars]))
       (~optional (~seq #:check check:id) #:defaults ([check #'polynomial-identity]))
       (~optional (~seq #:requires (requirement ...)) #:defaults ([(requirement 1) '()]))
       (~optional (~seq #:merge merge-mode) #:defaults ([merge-mode #'#f]))
       (~optional (~seq #:version version) #:defaults ([version #'1])))
     #:fail-unless (eq? (syntax-e #'domain) 'real-scalars)
     "only real-scalars are currently supported"
     #'(define name
         (make-math-rule 'name '(v ...) 'from 'to
           #:requires '(requirement ...)
           #:merge merge-mode
           #:version version
           #:check 'check))]))

;;;
;;; Structural Matching
;;;
; template-bindings : math-datum? math-datum? (listof symbol?) -> (values
;   immutable-hash? immutable-hash?)
;;   Returns structural bindings and all source occurrence witnesses.
(define (template-bindings template value variables)
  (define (walk t v p bindings witnesses)
    (cond
      [(and (symbol? t) (memq t variables))
       (when (and (hash-has-key? bindings t) (not (equal? (hash-ref bindings t) v)))
         (math-error 'template-match 'conflicting-bindings
           "Repeated metavariable does not match structurally."
           t))
       (values
         (hash-set bindings t v)
         (hash-set witnesses t (append (hash-ref witnesses t '()) (list p))))]
      [(and (app? t) (app? v) (eq? (car t) (car v)) (= (length t) (length v)))
       (for/fold ([bindings bindings] [witnesses witnesses]) ([a (in-list (cdr t))] [b (in-list (cdr v))] [i (in-naturals)])
         (walk a b (append p (list i)) bindings witnesses))]
      [(equal? t v) (values bindings witnesses)]
      [else
       (math-error 'template-match 'no-match
         "Template shape does not match the held expression."
         t
         v
         p)]))
  (walk template value '() (hash) (hash)))

; template-occurrences : any/c symbol? -> (listof operand-path?)
;;   Finds occurrences of one declared metavariable in template order.
(define (template-occurrences template variable)
  (for/list ([p (in-list (datum-paths template))]
              #:when (eq? (datum-ref template p) variable))
    p))

;;;
;;; Rule Application
;;;
; use-rule : math-rule? [#:at selector?] -> math-operation?
;;   Creates an operation from a trace-aware held rule template.
(define (use-rule rule #:at [focus (whole)])
  (unless (math-rule? rule) (raise-argument-error 'use-rule "math-rule?" rule))
  (math-operation
    (math-rule-name rule)
    focus
    (lambda (d ctx)
      (define-values (bindings witnesses)
        (template-bindings (math-rule-before rule) d (math-rule-variables rule)))
      (define out (held-substitute (math-rule-after rule) bindings))
      (define links '())
      (define events '())
      (for ([v (in-list (math-rule-variables rule))])
        (define sources (hash-ref witnesses v '()))
        (define targets (template-occurrences (math-rule-after rule) v))
        (cond
          [(and (pair? targets) (= (length sources) 1))
           (set! links
             (append links
               (for/list ([p (in-list targets)])
                 (path-link (car sources) p (if (> (length targets) 1) 'copy 'preserve) #t))))]
          [(and (> (length sources) 1) (pair? targets))
           (unless (eq? (math-rule-merge rule) 'merge)
             (math-error
               (math-rule-name rule)
               'ambiguous-merge
               "Repeated source metavariables require an explicit #:merge 'merge policy."
               v))
           (set! events
             (cons (trace-event 'merge sources targets (list 'metavariable v)) events))]
          [else (void)]))
      (define proof
        (if (and
              (eq? (math-rule-check rule) 'polynomial-identity)
              (rational-equivalent? (context-expand ctx d) (context-expand ctx out)))
          (established 'exact-polynomial-template `(= ,d ,out))
          (unknown (math-rule-check rule) `(= ,d ,out))))
      (make-edit out
        #:links links
        #:events
        (cons (trace-event 'rewrite '(()) '(()) (list (math-rule-name rule))) events)
        #:requires
        (append
          (map (lambda (r) (held-substitute r bindings)) (math-rule-requires rule))
          (for/list ([v (in-list (math-rule-variables rule))]
                      #:when (hash-has-key? bindings v)
                      #:unless (context-real? ctx (hash-ref bindings v)))
            `(real? ,(hash-ref bindings v))))
        #:proof proof
        #:bindings bindings
        #:version (math-rule-version rule)
        #:details (list (cons 'source-witnesses witnesses))))))

; apply-rule : math-rule? [#:at selector?] -> math-operation?
;;   Creates an operation from a trace-aware held rule template.
(define apply-rule
  use-rule)

; apply-rewrite : math-rule? math? [#:name symbol?] [#:at selector?] -> rewrite-step?
;;   Applies a traceable template rule directly to a mathematical state.
(define (apply-rewrite rule state #:name [name (math-rule-name rule)] #:at [focus (whole)])
  (apply-math-operation state (use-rule rule #:at focus) #:name name))
