#lang racket/base

;;;
;;; Explicit Mathematical Operations
;;;
;; Builds local held rewrites with domain obligations and ordered provenance.
;; Constructors do not evaluate through an external CAS.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "validation.rkt"
  racket/list
  (only-in racket/match match)
  "datum.rkt"
  "polynomial.rkt"
  "context.rkt"
  "evidence.rkt"
  "model.rkt"
  "select.rkt")

;; Exports
(provide
  (struct-out math-operation) (struct-out edit) make-edit run-operation apply-math-operation
  both-sides cancel-addends cancel-factor remove-unit reduce-identities evaluate rewrite-to
  reorder-addends zero-product square-solutions abbreviate each-branch substitute conclude
  assert-step)

;;;
;;; Data Representation
;;;
(struct edit (datum links events requires proof relation details bindings version)
  #:transparent)
;; edit is an immutable record. Its fields have the following roles.
;;  - datum  math-datum?  held local output
;;  - links  (listof path-link?)  ordered structural witnesses
;;  - events  (listof trace-event?)  ordered semantic events
;;  - requires  (listof math-datum?)  conditions checked before commit
;;  - proof  (or/c verification? #f)  local rule evidence; a smart constructor supplies
;;    default evidence
;;  - relation  symbol?  equivalence, implication, or specialization
;;  - details  any/c  snapshotted rule metadata
;;  - bindings  immutable-hash?  held template bindings
;;  - version  exact-positive-integer?  version of the applied rule
(struct math-operation (name selector run)
  #:transparent
  #:guard
  (lambda (name selection run who)
    (check-symbol who name)
    (unless (selector? selection) (raise-argument-error who "selector?" selection))
    (check-procedure who run 2)
    (values name selection run)))
;; math-operation is an immutable record. Its fields have the following roles.
;;  - name  symbol?  semantic operation name
;;  - selector  selector?  input focus resolved at application time
;;  - run  procedure?  pure two-argument datum/context callback returning an edit

; make-edit : math-datum? [#:links (listof path-link?)] [#:events (listof trace-event?)]
;   [#:requires (listof math-datum?)] [#:proof any/c] [#:relation any/c] [#:details
;   any/c] [#:bindings hash?] [#:version any/c] -> edit?
;;   Constructs a validated local rewrite result with immutable metadata.
(define (make-edit datum
          #:links [links '()]
          #:events [events '()]
          #:requires [requires '()]
          #:proof [proof #f]
          #:relation [relation 'equivalence]
          #:details [details '()]
          #:bindings [bindings (hash)]
          #:version [version 1])
  (check-datum 'make-edit datum)
  (check-list-of 'make-edit links path-link? "list of path links")
  (check-list-of 'make-edit events trace-event? "list of trace events")
  (check-list-of 'make-edit requires math-datum? "list of requirements")
  (unless (exact-positive-integer? version)
    (raise-argument-error 'make-edit "positive rule version" version))
  (unless (or (not proof) (verification? proof))
    (raise-argument-error 'make-edit "verification? or #f" proof))
  (unless (memq relation '(equivalence implication specialization))
    (raise-argument-error 'make-edit "rewrite relationship" relation))
  (edit datum links events requires
    (or proof (established 'built-in-law 'local-rewrite))
    relation
    (snapshot-metadata details)
    (snapshot-metadata bindings)
    version))

; keep : any/c -> edit?
;;   Produces an identity edit with an exact preservation witness.
(define (keep x)
  (make-edit x #:links (list (path-link '() '() 'preserve #t))))

; outside-links : math-datum? operand-path? -> (listof path-link?)
;;   Preserves untouched surrounding syntax while excluding the active focus.
(define (outside-links before focus)
  (define (walk x path)
    (cond
      [(equal? path focus) '()]
      [(not (path-prefix? path focus)) (list (path-link path path 'preserve #t))]
      [else
       (cons
         (path-link path path 'container #f)
         (append*
           (for/list ([a (in-list (operands x))] [i (in-naturals)])
             (walk a (append path (list i))))))]))
  (walk before '()))

; run-operation : math-datum? math-context? math-operation? -> edit?
;;   Applies one operation locally and rebases its witnesses into the complete
;;   expression.
(define (run-operation datum ctx op)
  (unless (math-operation? op) (raise-argument-error 'run-operation "math-operation?" op))
  (define p (resolve-one datum (math-operation-selector op)))
  (define e ((math-operation-run op) (datum-ref datum p) ctx))
  (unless (edit? e)
    (math-error (math-operation-name op) 'invalid-rule "An operation must return an edit."))
  (define result (datum-replace datum p (edit-datum e)))
  (struct-copy edit e
    [datum result]
    [links (append (outside-links datum p) (prefix-links (edit-links e) p p))]
    [events (prefix-events (edit-events e) p p)]))

;;;
;;; Operation Application
;;;
; apply-math-operation : math? math-operation? [#:name symbol?] -> rewrite-step?
;;   Applies and verifies one named operation before committing a new state.
(define (apply-math-operation state op #:name [name (math-operation-name op)])
  (unless (math? state) (raise-argument-error 'apply-math-operation "math?" state))
  (unless (symbol? name)
    (raise-argument-error 'apply-math-operation "symbol? as step name" name))
  (define e (run-operation (math-datum state) (math-context-of state) op))
  (define v
    (merge-verifications
      (cons
        (edit-proof e)
        (map (lambda (r) (prove-in-context (math-context-of state) r)) (edit-requires e)))
      (list 'rewrite name)))
  (define relationship
    (if (eq? (edit-relation e) 'equivalence)
      (if (or (relation? (math-datum state)) (memq (head (math-datum state)) '(or and)))
        'equation-equivalence
        'expression-equivalence)
      (edit-relation e)))
  (finish-step name state
    (edit-datum e)
    (math-operation-name op)
    (resolve-one state (math-operation-selector op))
    (edit-bindings e)
    (edit-links e)
    (edit-events e)
    relationship
    v
    #:details (edit-details e)
    #:version (edit-version e)))

; need-relation : symbol? math-datum? -> void?
;;   Rejects operations whose selected input is not a scalar relation.
(define (need-relation who datum)
  (unless (relation? datum)
    (math-error who 'wrong-focus "Expected a scalar relation." datum)))

; real-requirements : math-context? any/c -> (listof math-datum?)
;;   Records real-valuedness obligations not already established in the context.
(define (real-requirements ctx values)
  (for/list ([v (in-list values)] #:unless (context-real? ctx v)) `(real? ,v)))

;;;
;;; Relation Operations
;;;
; both-sides : symbol? math-datum? [#:at selector?] [#:relationship symbol?] ->
;   math-operation?
;;   Applies a held operation to both relation operands with explicit invertibility
;;   guards.
(define (both-sides op operand
          #:at [focus (whole)]
          #:relationship [relationship 'equivalence])
  (unless (memq op '(add subtract multiply divide power))
    (raise-argument-error 'both-sides "'add, 'subtract, 'multiply, 'divide, or 'power" op))
  (unless (memq relationship '(equivalence implication))
    (raise-argument-error 'both-sides "'equivalence or 'implication" relationship))
  (check-datum 'both-sides operand)
  (math-operation 'both-sides focus
    (lambda (d c)
      (need-relation 'both-sides d)
      (define rel (car d))
      (define new-rel rel)
      (define requires (domain-requirements operand))
      (when (memq op '(multiply divide))
        (cond
          [(eq? rel '=)
           (when (or (eq? relationship 'equivalence) (eq? op 'divide))
             (set! requires (cons `(not (= ,operand 0)) requires)))]
          [else
           (define ss (context-signs c operand))
           (cond
             [(equal? ss '(1)) (void)]
             [(equal? ss '(-1))
              (set! new-rel (case rel [(<) '>] [(>) '<] [(<=) '>=] [(>=) '<=]))]
             [else
              (math-error 'both-sides 'unknown-sign
                "Inequality multiplication/division requires a known nonzero sign; split cases first."
                operand
                ss)])]))
      (when (eq? op 'power)
        (unless (and (eq? rel '=) (eq? relationship 'implication) (exact-positive-integer? operand))
          (math-error 'both-sides 'noninvertible
            "Power is supported as an explicitly one-way equation implication with a positive integer exponent.")))
      (define operator
        (case op [(add) '+] [(subtract) '-] [(multiply) '*] [(divide) '/] [(power) 'expt]))
      (define old-slot (if (eq? op 'multiply) 1 0))
      (define new-slot (if (eq? op 'multiply) 0 1))
      (define (side x)
        (if (eq? op 'multiply) (list operator operand x) (list operator x operand)))
      (define out (list new-rel (side (cadr d)) (side (caddr d))))
      (make-edit out
        #:links
        (append
          (if (eq? rel new-rel) (list (path-link '() '() 'container #f)) '())
          (list
            (path-link '(0) (list 0 old-slot) 'preserve #t)
            (path-link '(1) (list 1 old-slot) 'preserve #t)))
        #:events
        (list
          (trace-event 'create '()
            (list (list 0 new-slot) (list 1 new-slot))
            (list op operand)))
        #:requires requires
        #:relation relationship
        #:details (list (cons 'operation op) (cons 'operand operand))
        #:proof (established 'relation-law (list op 'both-sides))))))

; signed-value : any/c -> math-datum?
;;   Reconstructs one signed addend without evaluating its value.
(define (signed-value a)
  (if (= (addend-sign a) 1) (addend-value a) `(- ,(addend-value a))))

; sum-links : any/c [#:kind any/c] -> (listof path-link?)
;;   Maps surviving signed terms into their new held sum positions.
(define (sum-links terms #:kind [kind 'preserve])
  (for/list ([a (in-list terms)] [i (in-naturals)])
    (define p (if (= (length terms) 1) '() (list i)))
    (path-link (addend-path a) (if (= (addend-sign a) -1) (append p '(0)) p) kind #t)))

;;;
;;; Explicit Cancellation
;;;
; cancel-addends : [#:at selector?] [#:pair (or/c list? #f)] -> math-operation?
;;   Cancels one specified or uniquely identified pair of additive inverses.
(define (cancel-addends #:at [focus (whole)] #:pair [pair #f])
  (math-operation 'cancel-addends focus
    (lambda (d c)
      (unless (memq (head d) '(+ -))
        (math-error 'cancel-addends 'wrong-focus "Expected an addition or subtraction." d))
      (define terms (signed-addends d))
      (define pairs
        (for*/list ([i (in-range (length terms))]
                     [j (in-range (add1 i) (length terms))]
                     #:when
                     (rational-equivalent?
                       `(+
                          ,(signed-value (list-ref terms i))
                          ,(signed-value (list-ref terms j)))
                       0))
          (list i j)))
      (define selected
        (cond
          [pair
           (unless (member pair pairs)
             (math-error 'cancel-addends 'invalid-pair
               "The selected zero-based term pair is not additive inverses."
               pair))
           pair]
          [(= (length pairs) 1) (car pairs)]
          [else
           (math-error 'cancel-addends 'ambiguous-cancellation
             "Expected exactly one inverse pair; use #:pair with two zero-based term indices."
             pairs)]))
      (define remaining
        (for/list ([a (in-list terms)] [i (in-naturals)] #:unless (member i selected)) a))
      (define out (build-sum (map signed-value remaining)))
      (make-edit out
        #:links (sum-links remaining)
        #:events
        (list
          (trace-event 'cancel
            (map (lambda (i) (addend-path (list-ref terms i))) selected)
            '()
            (list 'additive-inverses selected)))
        #:proof (established 'additive-inverse `(= ,d ,out))))))

; factor-entries : math-datum? [any/c] -> list?
;;   Flattens product factors while retaining their original operand paths.
(define (factor-entries d [p '()])
  (if (eq? (head d) '*)
    (append*
      (for/list ([v (in-list (cdr d))] [i (in-naturals)])
        (factor-entries v (append p (list i)))))
    (list (cons d p))))

; remove-factors : symbol? any/c any/c -> (values list? list?)
;;   Removes requested factor occurrences in order and reports their witnesses.
(define (remove-factors who entries requested)
  (for/fold ([remaining entries] [removed '()]) ([f (in-list requested)])
    (define pos (index-where remaining (lambda (e) (equal? (car e) f))))
    (unless pos
      (math-error who 'missing-factor
        "The requested factor is not structurally present."
        f
        (map car entries)))
    (values
      (append (take remaining pos) (drop remaining (add1 pos)))
      (append removed (list (list-ref remaining pos))))))

; product-links : any/c any/c any/c any/c -> (listof path-link?)
;;   Maps retained factor occurrences to ordered product destinations.
(define (product-links entries target-prefix offset total)
  (for/list ([entry (in-list entries)] [i (in-naturals offset)])
    (path-link
      (cdr entry)
      (append target-prefix (if (= total 1) '() (list i)))
      'preserve
      #t)))

; cancel-factor : [#:at selector?] #:factor math-datum? [#:keep-one? boolean?] ->
;   math-operation?
;;   Cancels a selected common factor only under an established nonzero condition.
(define (cancel-factor #:at [focus (whole)] #:factor factor #:keep-one? [keep-one? #f])
  (check-datum 'cancel-factor factor)
  (check-boolean 'cancel-factor keep-one?)
  (math-operation 'cancel-factor focus
    (lambda (d c)
      (unless (eq? (head d) '/)
        (math-error 'cancel-factor 'wrong-focus "Expected a displayed fraction." d))
      (define requested (map car (factor-entries factor)))
      (define-values (ns cancelled-n)
        (remove-factors 'cancel-factor (factor-entries (cadr d) '(0)) requested))
      (define-values (ds cancelled-d)
        (remove-factors 'cancel-factor (factor-entries (caddr d) '(1)) requested))
      (define nvalues (append (if (and keep-one? (pair? ns)) '(1) '()) (map car ns)))
      (define n (build-product nvalues))
      (define denominator (build-product (map car ds)))
      (define fraction? (pair? ds))
      (define out (if fraction? `(/ ,n ,denominator) n))
      (define np (if fraction? '(0) '()))
      (make-edit out
        #:links
        (append
          (product-links ns np (if (and keep-one? (pair? ns)) 1 0) (length nvalues))
          (product-links ds '(1) 0 (length ds)))
        #:events
        (list
          (trace-event 'cancel
            (map cdr (append cancelled-n cancelled-d))
            (if (and keep-one? (pair? ns)) (list (append np '(0))) '())
            (list 'common-factor factor)))
        #:requires (list `(not (= ,factor 0)))
        #:details (list (cons 'factor factor) (cons 'keep-one? keep-one?))
        #:proof (established 'nonzero-factor-cancellation `(= ,d ,out))))))

; remove-unit : [#:at selector?] -> math-operation?
;;   Removes an explicitly displayed unit factor as its own teaching step.
(define (remove-unit #:at [focus (whole)])
  (math-operation 'remove-unit focus
    (lambda (d c)
      (unless (and (eq? (head d) '*) (member 1 (cdr d)))
        (math-error 'remove-unit 'wrong-focus
          "Expected an explicit multiplicative identity."
          d))
      (define entries
        (for/list ([v (in-list (cdr d))] [i (in-naturals)] #:unless (equal? v 1))
          (cons v (list i))))
      (define removed
        (for/list ([v (in-list (cdr d))] [i (in-naturals)] #:when (equal? v 1)) (list i)))
      (make-edit
        (build-product (map car entries))
        #:links (product-links entries '() 0 (length entries))
        #:events (list (trace-event 'remove removed '() '(multiplicative-identity)))))))

;;;
;;; Numeric and Identity Evaluation
;;;
; evaluation-edit : math-datum? any/c -> edit?
;;   Records arithmetic evaluation events without matching digits by appearance.
(define (evaluation-edit d deepest?)
  (define out (exact-evaluate d #:deepest? deepest?))
  (define (events before after p)
    (cond
      [(equal? before after) '()]
      [(and (app? before) (number? after))
       (list (trace-event 'evaluate (list p) (list p) '(exact-arithmetic)))]
      [(and (app? before) (app? after))
       (append*
         (for/list ([a (in-list (cdr before))] [b (in-list (cdr after))] [i (in-naturals)])
           (events a b (append p (list i)))))]
      [else (list (trace-event 'evaluate (list p) (list p) '(exact-arithmetic)))]))
  (make-edit out
    #:links (unchanged-links d out)
    #:events (events d out '())
    #:proof (established 'exact-arithmetic `(= ,d ,out))))

; evaluate : [#:at selector?] [#:mode symbol?] -> math-operation?
;;   Evaluates exact arithmetic at the selected focus, optionally one deepest layer.
(define (evaluate #:at [focus (whole)] #:mode [mode 'all])
  (unless (memq mode '(all deepest))
    (raise-argument-error 'evaluate "'all or 'deepest" mode))
  (math-operation 'evaluate focus (lambda (d c) (evaluation-edit d (eq? mode 'deepest)))))

; identity-edit : math-datum? -> edit?
;;   Applies supported zero, unit, and sign identities with mechanical provenance.
(define (identity-edit d)
  (cond
    [(not (app? d)) (keep d)]
    [else
     (define children (map identity-edit (cdr d)))
     (define vs (map edit-datum children))
     (define raw (cons (car d) vs))
     (define kept (range (length vs)))
     (define replacement #f)
     (define selected #f)
     (case (car d)
       [(+ *)
        (define neutral (if (eq? (car d) '+) 0 1))
        (set! kept (filter (lambda (i) (not (equal? (list-ref vs i) neutral))) kept))
        (when (and (eq? (car d) '*) (member 0 vs)) (set! selected (index-of vs 0)))
        (when (null? kept) (set! replacement neutral))]
       [(-)
        (cond
          [(= (length vs) 1) (when (number? (car vs)) (set! replacement (- (car vs))))]
          [(equal? (cadr vs) 0) (set! selected 0)]
          [(equal? (car vs) 0) (set! replacement `(- ,(cadr vs)))])]
       [(/) (when (equal? (cadr vs) 1) (set! selected 0))]
       [(expt)
        (cond
          [(equal? (cadr vs) 1) (set! selected 0)]
          [(equal? (cadr vs) 0) (set! replacement 1)])])
     (define out
       (cond
         [selected (list-ref vs selected)]
         [replacement replacement]
         [(memq (car d) '(+ *))
          ((if (eq? (car d) '+) build-sum build-product)
            (map (lambda (i) (list-ref vs i)) kept))]
         [else raw]))
     (define links
       (cond
         [selected
          (prefix-links (edit-links (list-ref children selected)) (list selected) '())]
         [replacement (unchanged-links d out)]
         [(memq (car d) '(+ *))
          (append*
            (for/list ([old (in-list kept)] [new (in-naturals)])
              (prefix-links
                (edit-links (list-ref children old))
                (list old)
                (if (= (length kept) 1) '() (list new)))))]
         [else
          (cons
            (path-link '() '() 'container #f)
            (append*
              (for/list ([e (in-list children)] [i (in-naturals)])
                (prefix-links (edit-links e) (list i) (list i)))))]))
     (make-edit out
       #:links links
       #:events
       (if (equal? d out) '() (list (trace-event 'rewrite '(()) '(()) '(identity-rules))))
       #:details (if (equal? d out) '() (list (list 'identities d out)))
       #:proof (established 'zero-unit-sign-identities `(= ,d ,out)))]))

; reduce-identities : [#:at selector?] -> math-operation?
;;   Reduces supported identities only inside the explicit focus.
(define (reduce-identities #:at [focus (whole)])
  (math-operation 'reduce-identities focus (lambda (d c) (identity-edit d))))

; algebra-equivalent? : any/c any/c any/c -> boolean?
;;   Checks exact rational identities in context without claiming a general theorem
;;   prover.
(define (algebra-equivalent? a b c)
  (define x (context-expand c a))
  (define y (context-expand c b))
  (cond
    [(and (relation? x) (relation? y) (eq? (head x) (head y)))
     (and
       (rational-equivalent? (cadr x) (cadr y))
       (rational-equivalent? (caddr x) (caddr y)))]
    [(or (relation? x) (relation? y)) #f]
    [else (rational-equivalent? x y)]))

;;;
;;; Target-Based Rewriting
;;;
; rewrite-to : math-datum? [#:at selector?] [#:using symbol?] -> math-operation?
;;   Requests a checked focused target and records an honest coarse rewrite event.
(define (rewrite-to target #:at [focus (whole)] #:using [rule 'rational-identity])
  (check-datum 'rewrite-to target)
  (unless (memq rule
            '(perfect-square expand-products rational-identity factor split-linear-term factor-by-grouping))
    (raise-argument-error 'rewrite-to "a registered algebraic target rule" rule))
  (math-operation rule focus
    (lambda (d c)
      (when (eq? rule 'perfect-square)
        (unless (match target [(list 'expt (list (or '+ '-) _ _) 2) #t] [_ #f])
          (math-error 'rewrite-to 'wrong-target
            "perfect-square expects a squared binomial target."
            target)))
      (unless (algebra-equivalent? d target c)
        (math-error 'rewrite-to 'unverified-target
          "The requested target is not established by exact rational-polynomial checking."
          d
          target))
      (define details
        (append
          (list
            (list 'scope 'focused-replacement)
            (list 'diagnostic
              "No invented glyph-level provenance inside an opaque algebraic replacement."))
          (if (eq? rule 'expand-products)
            (list (list 'certificate 'exact-sparse-polynomial-expansion))
            '())))
      (make-edit target
        #:events (list (trace-event 'rewrite '(()) '(()) (list rule)))
        #:proof (established 'exact-rational-polynomial `(equivalent ,d ,target))
        #:details details))))

; reorder-addends : [#:at selector?] #:order (listof exact-nonnegative-integer?) ->
;   math-operation?
;;   Permutes signed addends by explicit zero-based indices.
(define (reorder-addends #:at [focus (whole)] #:order order)
  (math-operation 'reorder-addends focus
    (lambda (d c)
      (unless (memq (head d) '(+ -))
        (math-error 'reorder-addends 'wrong-focus "Expected signed addends." d))
      (define terms (signed-addends d))
      (unless (and
                (list? order)
                (andmap exact-nonnegative-integer? order)
                (equal? (sort order <) (range (length terms))))
        (math-error 'reorder-addends 'invalid-permutation
          "#:order must permute all zero-based signed terms."
          order))
      (define sorted (map (lambda (i) (list-ref terms i)) order))
      (make-edit
        (build-sum (map signed-value sorted))
        #:links (sum-links sorted #:kind 'reorder)
        #:details (list (cons 'order order))))))

;;;
;;; Solution Branches
;;;
; zero-product : [#:at selector?] -> math-operation?
;;   Splits a real product equation into the direct zero-factor alternatives.
(define (zero-product #:at [focus (whole)])
  (math-operation 'zero-product focus
    (lambda (d c)
      (unless (match d [(list '= (list '* _ ...) 0) #t] [_ #f])
        (math-error 'zero-product 'wrong-focus "Expected a product equal to zero." d))
      (define fs (cdr (cadr d)))
      (define out (cons 'or (map (lambda (f) `(= ,f 0)) fs)))
      (make-edit out
        #:links
        (for/list ([f (in-list fs)] [i (in-naturals)])
          (path-link (list 0 i) (list i 0) 'preserve #t))
        #:events
        (list
          (trace-event 'split '(())
            (for/list ([i (in-range (length fs))]) (list i))
            '(zero-product)))
        #:requires (real-requirements c fs)
        #:proof (established 'real-zero-product out)))))

; square-solutions : [#:at selector?] -> math-operation?
;;   Solves a real square equation using explicit positive, zero, or negative cases.
(define (square-solutions #:at [focus (whole)])
  (math-operation 'square-solutions focus
    (lambda (d c)
      (unless (match d [(list '= (list 'expt _ 2) _) #t] [_ #f])
        (math-error 'square-solutions 'wrong-focus "Expected u^2 = v." d))
      (define u (cadadr d))
      (define v (caddr d))
      (define signs (context-signs c v))
      (define needs (real-requirements c (list u v)))
      (cond
        [(equal? signs '(-1))
         (make-edit #f
           #:requires needs
           #:events (list (trace-event 'classify '(()) '(()) '(no-real-solutions)))
           #:proof (established 'real-square-nonnegative d))]
        [(equal? signs '(0))
         (make-edit `(= ,u 0)
           #:requires needs
           #:links
           (list (path-link '() '() 'container #f) (path-link '(0 0) '(0) 'preserve #t))
           #:events
           (list (trace-event 'rewrite '((0) (1)) '((0) (1)) '(unique-zero-square-root)))
           #:proof (established 'zero-square-equivalence d))]
        [(and (pair? signs) (andmap (lambda (s) (member s '(0 1))) signs))
         (make-edit
           `(or (= ,u (sqrt ,v)) (= ,u (- (sqrt ,v))))
           #:requires needs
           #:links
           (list
             (path-link '(0 0) '(0 0) 'copy #t)
             (path-link '(0 0) '(1 0) 'copy #t)
             (path-link '(1) '(0 1 0) 'copy #t)
             (path-link '(1) '(1 1 0 0) 'copy #t))
           #:events
           (list (trace-event 'split '(()) '((0) (1)) '(positive-and-negative-roots)))
           #:proof (established 'real-square-roots d))]
        [else
         (math-error 'square-solutions 'unknown-sign
           "The right side's sign is unknown. Use parameter cases before taking square roots."
           v
           signs)]))))

; abbreviate : symbol? [#:at selector?] -> math-operation?
;;   Replaces a selected expression by an equivalent scoped definition name.
(define (abbreviate name #:at [focus (whole)])
  (math-operation 'abbreviate focus
    (lambda (d c)
      (define defs (math-context-definitions c))
      (unless (hash-has-key? defs name)
        (math-error 'abbreviate 'undefined-name "No scoped definition exists." name))
      (define expanded (definition-expand name defs))
      (unless (algebra-equivalent? d expanded c)
        (math-error 'abbreviate 'wrong-definition
          "The abbreviation does not denote the selected expression."
          name
          d))
      (make-edit name
        #:events (list (trace-event 'abbreviate '(()) '(()) (list name expanded)))
        #:proof (established 'scoped-definition `(= ,name ,expanded))))))

; each-branch : math-operation? -> math-operation?
;;   Applies one operation to each direct solution alternative in branch order.
(define (each-branch op)
  (math-operation 'each-branch
    (whole)
    (lambda (d c)
      (unless (eq? (head d) 'or)
        (math-error 'each-branch 'wrong-focus
          "Expected direct solution alternatives (or ...)."
          d))
      (define edits (map (lambda (branch) (run-operation branch c op)) (cdr d)))
      (make-edit
        (cons 'or (map edit-datum edits))
        #:links
        (cons
          (path-link '() '() 'container #f)
          (append*
            (for/list ([e (in-list edits)] [i (in-naturals)])
              (prefix-links (edit-links e) (list i) (list i)))))
        #:events
        (append*
          (for/list ([e (in-list edits)] [i (in-naturals)])
            (prefix-events (edit-events e) (list i) (list i))))
        #:requires (append-map edit-requires edits)
        #:proof (merge-verifications (map edit-proof edits) 'solution-alternatives)
        #:relation
        (if (ormap (lambda (e) (eq? (edit-relation e) 'implication)) edits)
          'implication
          'equivalence)
        #:details (list (cons 'operation (math-operation-name op)))))))

;;;
;;; Substitution and Conclusions
;;;
; substitute : (or/c hash? list?) [#:at selector?] -> math-operation?
;;   Snapshots a replacement map and constructs a held specialization operation.
(define (substitute replacements #:at [focus (whole)])
  (define captured-replacements
    (snapshot-metadata
      (if (hash? replacements) replacements (make-immutable-hash replacements))))
  (for ([(from to) (in-hash captured-replacements)])
    (check-datum 'substitute from)
    (check-datum 'substitute to))
  (math-operation 'substitute focus
    (lambda (d c)
      (define out (held-substitute d captured-replacements))
      (make-edit out
        #:links (unchanged-links d out)
        #:events (list (trace-event 'specialize '(()) '(()) (list captured-replacements)))
        #:relation 'specialization
        #:proof (established 'held-substitution captured-replacements)))))

; conclude : symbol? #:for symbol? -> math-operation?
;;   Requests a checked classification as all real values or no real solutions.
(define (conclude classification #:for variable)
  (unless (memq classification '(all-real no-solutions))
    (raise-argument-error 'conclude "'all-real or 'no-solutions" classification))
  (math-operation 'conclude
    (whole)
    (lambda (d c)
      (when (and
              (eq? classification 'all-real)
              (ormap (lambda (f) (not (free-of? f variable))) (context-facts c)))
        (math-error 'conclude 'restricted-domain
          "Cannot conclude all real values while the context restricts the solution variable."
          variable
          (context-facts c)))
      (define check (prove-in-context c (if (eq? classification 'all-real) d `(not ,d))))
      (make-edit
        (eq? classification 'all-real)
        #:proof check
        #:events (list (trace-event 'classify '(()) '(()) (list classification variable)))
        #:details (list (cons 'classification classification) (cons 'variable variable))))))

; assert-step : math-datum? [#:at selector?] [#:reason string?] -> math-operation?
;;   Creates a deliberately unverified author target that strict mode cannot certify.
(define (assert-step target
          #:at [focus (whole)]
          #:reason [reason "Author-supplied target."])
  (check-datum 'assert-step target)
  (unless (string? reason) (raise-argument-error 'assert-step "string?" reason))
  (define captured-reason (string->immutable-string reason))
  ;; Deliberate draft-only escape hatch. It cannot forge established evidence.
  (math-operation 'author-assertion focus
    (lambda (d c)
      (make-edit target
        #:events (list (trace-event 'rewrite '(()) '(()) (list captured-reason)))
        #:proof
        (unknown 'author-assertion `(equivalent ,d ,target)
          (list `(equivalent ,d ,target))
          captured-reason)))))
