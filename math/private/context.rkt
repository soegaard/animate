#lang racket/base

;;;
;;; Mathematical Contexts
;;;
;; Defines immutable real-scalar contexts and conservative local reasoning about
;; domains, signs, and parameter-case coverage.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "validation.rkt"
  (only-in racket/list append* append-map count remove-duplicates rest)
  (only-in racket/match match)
  "datum.rkt"
  "polynomial.rkt"
  "evidence.rkt")

;; Exports
(provide
  math-context math-context? math-context-real math-context-assumptions
  math-context-definitions math-context-restrictions context-assume context-add-restrictions
  context-expand context-prove context-signs context-real? context-inconsistent?
  check-case-coverage context-facts)

;;;
;;; Data Representation
;;;
(struct context (real assumptions definitions restrictions)
  #:transparent)
;; context is an immutable record. Its fields have the following roles.
;;  - real  (listof symbol?)  real declarations in first declaration order
;;  - assumptions  (listof math-datum?)  guard propositions in declaration order
;;  - definitions  immutable-hash?  acyclic scoped name definitions
;;  - restrictions  (listof math-datum?)  retained exclusions independent of simplified
;;    syntax

; math-context? : any/c -> boolean?
;;   Recognizes an immutable real-scalar context.
(define math-context?
  context?)

; math-context-real : math-context? -> (listof symbol?)
;;   Returns real-variable declarations in declaration order.
(define math-context-real
  context-real)

; math-context-assumptions : math-context? -> (listof math-datum?)
;;   Returns the ordered assumption propositions.
(define math-context-assumptions
  context-assumptions)

; math-context-definitions : math-context? -> immutable-hash?
;;   Returns the immutable map of scoped definitions.
(define math-context-definitions
  context-definitions)

; math-context-restrictions : math-context? -> (listof math-datum?)
;;   Returns domain exclusions retained independently of current syntax.
(define math-context-restrictions
  context-restrictions)

; flatten-and : any/c -> (listof math-datum?)
;;   Flattens conjunctions while preserving the order of their propositions.
(define (flatten-and x)
  (if (eq? (head x) 'and) (append-map flatten-and (cdr x)) (list x)))

;;;
;;; Context Construction
;;;
; math-context : [#:real (listof symbol?)] [#:assuming (listof math-datum?)]
;   [#:definitions (or/c hash? list?)] -> math-context?
;;   Validates real variables, ordered assumptions, and acyclic scoped definitions.
(define (math-context
          #:real [real '()]
          #:assuming [assumptions '()]
          #:definitions [definitions '()])
  (unless (and (list? real) (andmap symbol? real))
    (raise-argument-error 'math-context "list of real variable symbols" real))
  (unless (and (list? assumptions) (andmap math-datum? assumptions))
    (raise-argument-error 'math-context "list of assumption propositions" assumptions))
  (for-each (lambda (p) (check-datum 'math-context p)) assumptions)
  (define defs
    (cond
      [(hash? definitions) (make-immutable-hash (hash->list definitions))]
      [else
       (unless (and
                 (list? definitions)
                 (andmap
                   (lambda (d) (and (list? d) (= (length d) 2) (symbol? (car d))))
                   definitions))
         (raise-argument-error 'math-context
           "list of (name expression) definitions"
           definitions))
       (unless (= (length definitions) (length (remove-duplicates (map car definitions))))
         (error 'math-context "duplicate definition"))
       (make-immutable-hash (map (lambda (d) (cons (car d) (cadr d))) definitions))]))
  (for ([(name value) (in-hash defs)])
    (check-symbol 'math-context name)
    (check-datum 'math-context value)
    (definition-expand name defs))
  (context
    (remove-duplicates real)
    (append-map flatten-and assumptions)
    defs
    (remove-duplicates
      (append-map (lambda (p) (domain-requirements (definition-expand p defs))) assumptions)
      equal?)))

; context-facts : math-context? -> (listof math-datum?)
;;   Returns assumptions followed by retained domain restrictions.
(define (context-facts c)
  (append (context-assumptions c) (context-restrictions c)))

; context-assume : math-context? math-datum? -> math-context?
;;   Adds a branch guard and the guard expression's definedness conditions.
(define (context-assume c guard)
  (unless (math-context? c) (raise-argument-error 'context-assume "math-context?" c))
  (check-datum 'context-assume guard)
  (context-add-restrictions
    (struct-copy context c
      [assumptions (append (context-assumptions c) (flatten-and guard))])
    (domain-requirements (definition-expand guard (context-definitions c)))))

; context-add-restrictions : math-context? (listof math-datum?) -> math-context?
;;   Adds validated domain obligations without deleting existing exclusions.
(define (context-add-restrictions c rs)
  (unless (math-context? c)
    (raise-argument-error 'context-add-restrictions "math-context?" c))
  (check-list-of 'context-add-restrictions rs math-datum? "list of domain propositions")
  (for-each (lambda (r) (check-datum 'context-add-restrictions r)) rs)
  (struct-copy context c
    [restrictions (remove-duplicates (append (context-restrictions c) rs) equal?)]))

;;;
;;; Scoped Expansion
;;;
; context-expand : math-context? math-datum? -> math-datum?
;;   Expands definitions and contextual equalities with a bounded substitution pass.
(define (context-expand c x)
  (define expanded (definition-expand x (context-definitions c)))
  (define bindings
    (for/fold ([h (hash)]) ([fact (in-list (context-facts c))])
      (match (definition-expand fact (context-definitions c))
        [(list '= (? symbol? a) b)
         (if (and
               (free-of? b a)
               (or (not (symbol? b)) (string<? (symbol->string a) (symbol->string b))))
           (hash-set h a b)
           h)]
        [(list '= a (? symbol? b)) (if (free-of? a b) (hash-set h b a) h)]
        [_ h])))
  (let loop ([x expanded] [n (+ 1 (hash-count bindings))])
    (define y (held-substitute x bindings))
    (if (or (zero? n) (equal? x y)) y (loop y (sub1 n)))))

; context-real? : math-context? math-datum? [exact-nonnegative-integer?] -> boolean?
;;   Conservatively establishes real-valuedness within a finite recursion budget.
(define (context-real? c x [fuel 40])
  (and
    (positive? fuel)
    (let ([v (definition-expand x (context-definitions c))])
      (cond
        [(real? v) #t]
        [(symbol? v) (and (or (memq v (context-real c)) (memq v '(@pi @e))) #t)]
        [(memq (head v) '(+ - * / abs parens))
         (andmap (lambda (a) (context-real? c a (sub1 fuel))) (cdr v))]
        [(eq? (head v) 'expt)
         (and (exact-integer? (caddr v)) (context-real? c (cadr v) (sub1 fuel)))]
        [(eq? (head v) 'sqrt)
         (and
           (context-real? c (cadr v) (sub1 fuel))
           (not (member -1 (context-signs c (cadr v) (sub1 fuel)))))]
        [else #f]))))

;;;
;;; Conservative Sign Analysis
;;;
; all-signs : (listof exact-integer?)
;;   Lists negative, zero, and positive sign alternatives in fixed order.
(define all-signs
  '(-1 0 1))

; sgn : any/c -> (or/c -1 0 1)
;;   Classifies the sign of a known real number.
(define (sgn x)
  (cond [(negative? x) -1] [(positive? x) 1] [else 0]))

; intersect : any/c any/c -> list?
;;   Preserves first-list order while intersecting sign possibilities.
(define (intersect a b)
  (filter (lambda (x) (member x b)) a))

; op-signs : math-operation? -> (listof exact-integer?)
;;   Returns the signs permitted by a scalar comparison operator.
(define (op-signs op)
  (case op [(=) '(0)] [(<) '(-1)] [(<=) '(-1 0)] [(>) '(1)] [(>=) '(0 1)] [(!=) '(-1 1)]))

; fact-comparison : any/c -> (or/c list? #f)
;;   Recognizes direct scalar comparisons and negated equality.
(define (fact-comparison f)
  (match f
    [(list 'not (list '= a b)) (list '!= a b)]
    [(list (and op (or '= '< '<= '> '>=)) a b) (list op a b)]
    [_ #f]))

; direct-signs : any/c any/c -> (listof exact-integer?)
;;   Intersects sign constraints that match contextual arithmetic identities.
(define (direct-signs c x)
  (for/fold ([result all-signs]) ([f (in-list (context-facts c))])
    (define v (fact-comparison (context-expand c f)))
    (cond
      [(not v) result]
      [else
       (define difference `(- ,(cadr v) ,(caddr v)))
       (cond
         [(rational-equivalent? x difference) (intersect result (op-signs (car v)))]
         [(rational-equivalent? x `(- ,difference))
          (intersect result (map - (op-signs (car v))))]
         [else result])])))

; combine-signs : math-operation? any/c any/c -> (listof exact-integer?)
;;   Combines sign possibilities conservatively for addition or multiplication.
(define (combine-signs op a b)
  (sort
    (remove-duplicates
      (append*
        (for*/list ([x (in-list a)] [y (in-list b)])
          (if (eq? op '*)
            (list (* x y))
            (cond
              [(zero? x) (list y)]
              [(zero? y) (list x)]
              [(= x y) (list x)]
              [else all-signs])))))
    <))

; context-signs : math-context? math-datum? [exact-nonnegative-integer?] -> (listof
;   exact-integer?)
;;   Returns conservative possible signs; uncertainty is never treated as positivity.
(define (context-signs c expr [fuel 24])
  (cond
    [(<= fuel 0) all-signs]
    [else
     (define x (context-expand c expr))
     (define numeric (polynomial-constant x))
     (define exact-number (or numeric (numeric-value x)))
     (cond
       [(number? exact-number) (list (sgn exact-number))]
       [else
        (define sign (lambda (a) (context-signs c a (sub1 fuel))))
        (define structural
          (match x
            [(list '* vs ...)
             (foldl (lambda (a b) (combine-signs '* a b)) '(1) (map sign vs))]
            [(list '+ vs ...)
             (foldl (lambda (a b) (combine-signs '+ a b)) '(0) (map sign vs))]
            [(list '- u) (map - (sign u))]
            [(list '- u v) (combine-signs '+ (sign u) (map - (sign v)))]
            [(list '/ u v)
             (define ds (sign v))
             (if (member 0 ds) all-signs (combine-signs '* (sign u) ds))]
            [(list 'expt u (? exact-integer? n))
             (cond
               [(zero? n) '(1)]
               [(even? n)
                (if (context-real? c u (sub1 fuel))
                  (if (member 0 (sign u)) '(0 1) '(1))
                  all-signs)]
               [else (sign u)])]
            [(list 'sqrt u)
             (define ss (sign u))
             (if (member -1 ss) all-signs (if (member 0 ss) '(0 1) '(1)))]
            [(list 'abs u) (if (member 0 (sign u)) '(0 1) '(1))]
            [(list 'parens u) (sign u)]
            [_ all-signs]))
        (intersect structural (direct-signs c x))])]))

; status-and : any/c -> symbol?
;;   Combines three-valued decisions without treating unknown as true.
(define (status-and ss)
  (cond
    [(memq 'refuted ss) 'refuted]
    [(andmap (lambda (s) (eq? s 'established)) ss) 'established]
    [else 'unknown]))

; status-or : any/c -> symbol?
;;   Combines three-valued decisions without treating unknown as true.
(define (status-or ss)
  (cond
    [(memq 'established ss) 'established]
    [(andmap (lambda (s) (eq? s 'refuted)) ss) 'refuted]
    [else 'unknown]))

;;;
;;; Three-Valued Propositions
;;;
; prove-status : any/c any/c -> symbol?
;;   Evaluates supported proposition structure under the current scalar context.
(define (prove-status c p)
  (define x (context-expand c p))
  (match x
    [#t 'established]
    [#f 'refuted]
    [(list 'real? v) (if (context-real? c v) 'established 'unknown)]
    [(list 'and vs ...) (status-and (map (lambda (v) (prove-status c v)) vs))]
    [(list 'or vs ...) (status-or (map (lambda (v) (prove-status c v)) vs))]
    [(list 'not v)
     (case (prove-status c v)
       [(established) 'refuted]
       [(refuted) 'established]
       [else 'unknown])]
    [(list (and op (or '= '< '<= '> '>=)) a b)
     (define signs (context-signs c `(- ,a ,b)))
     (cond
       [(null? signs) 'unknown]
       [(andmap (lambda (s) (member s (op-signs op))) signs) 'established]
       [(andmap (lambda (s) (not (member s (op-signs op)))) signs) 'refuted]
       [else 'unknown])]
    [_ (if (member p (context-facts c)) 'established 'unknown)]))

; context-prove : math-context? math-datum? -> verification?
;;   Checks definedness before reporting an established, refuted, or unknown
;;   proposition.
(define (context-prove c p)
  (with-handlers ([exn:fail? (lambda (e) (unknown 'scalar-context p (list p) (exn-message e)))])
    (define requirements
      (domain-requirements (definition-expand p (context-definitions c))))
    (define unproved
      (filter (lambda (r) (not (eq? (prove-status c r) 'established))) requirements))
    (cond
      [(pair? unproved)
       (unknown 'scalar-context p unproved
         "The proposition needs explicit definedness conditions.")]
      [else
       (case (prove-status c p)
         [(established) (established 'scalar-context p)]
         [(refuted) (refuted 'scalar-context p)]
         [else (unknown 'scalar-context p)])])))

;; Propositional coverage over real sign atoms. The assignments overapproximate
;; realizable arithmetic states, so a tautology here is a sound coverage result.
;; Failure to prove coverage is UNKNOWN, not a claimed numerical counterexample.

;;;
;;; Parameter-Case Coverage
;;;
; guard-shape : any/c any/c -> any/c
;;   Converts a guard to bounded propositional sign atoms for case coverage.
(define (guard-shape c guard)
  (define p (definition-expand guard (context-definitions c)))
  (match p
    [(? boolean?) p]
    [(list (and op (or 'and 'or 'not)) vs ...)
     (cons op (map (lambda (v) (guard-shape c v)) vs))]
    [(list (and op (or '= '< '<= '> '>=)) a b)
     (define d `(- ,a ,b))
     (define n (polynomial-constant d))
     (if (number? n)
       (and (member (sgn n) (op-signs op)) #t)
       (let* ([key (polynomial-key d)]
               [negative-key (polynomial-key `(- ,d))]
               [flip? (string<? (format "~s" negative-key) (format "~s" key))])
         (list 'atom
           (if flip? negative-key key)
           (if flip? (map - (op-signs op)) (op-signs op)))))]
    [_ (list 'boolean-atom p)]))

; shape-atoms : any/c -> list?
;;   Lists distinct coverage atoms in their first structural occurrence order.
(define (shape-atoms x)
  (cond
    [(boolean? x) '()]
    [(memq (car x) '(atom boolean-atom)) (list (cadr x))]
    [else (remove-duplicates (append-map shape-atoms (cdr x)) equal?)]))

; shape-true? : any/c any/c -> boolean?
;;   Evaluates one coverage shape in a complete sign assignment.
(define (shape-true? x env)
  (cond
    [(boolean? x) x]
    [else
     (case (car x)
       [(atom) (and (member (hash-ref env (cadr x)) (caddr x)) #t)]
       [(boolean-atom) (= (hash-ref env (cadr x)) 1)]
       [(not) (not (shape-true? (cadr x) env))]
       [(and) (andmap (lambda (v) (shape-true? v env)) (cdr x))]
       [(or) (ormap (lambda (v) (shape-true? v env)) (cdr x))])]))

; assignments : any/c -> (listof immutable-hash?)
;;   Enumerates sign assignments in fixed key and sign order.
(define (assignments keys)
  (if (null? keys)
    (list (hash))
    (for*/list ([rest (in-list (assignments (cdr keys)))] [s (in-list all-signs)])
      (hash-set rest (car keys) s))))

; check-case-coverage : math-context? (listof math-datum?) -> verification?
;;   Checks exhaustiveness and disjointness over at most seven sign atoms.
(define (check-case-coverage c guards)
  (with-handlers ([exn:fail? (lambda (e) (unknown 'case-coverage guards guards (exn-message e)))])
    (define shapes (map (lambda (g) (guard-shape c g)) guards))
    (define facts (guard-shape c (cons 'and (context-facts c))))
    (define keys
      (remove-duplicates
        (append (shape-atoms facts) (append-map shape-atoms shapes))
        equal?))
    (cond
      [(> (length keys) 7)
       (unknown 'case-coverage guards guards "Sign-atom coverage budget exceeded.")]
      [else
       (define environments (filter (lambda (e) (shape-true? facts e)) (assignments keys)))
       (define counts
         (map (lambda (env) (count (lambda (s) (shape-true? s env)) shapes)) environments))
       (cond
         [(null? environments)
          (refuted 'case-coverage guards "Inconsistent parent context.")]
         [(andmap (lambda (n) (= n 1)) counts) (established 'real-sign-partition guards)]
         [else
          (unknown 'case-coverage guards guards
            "Cases are not established as exhaustive and mutually exclusive.")])])))

; context-inconsistent? : math-context? -> boolean?
;;   Reports an established inconsistency without guessing from unknown evidence.
(define (context-inconsistent? c)
  (or
    (for/or ([f (in-list (context-facts c))]) (eq? (prove-status c f) 'refuted))
    (eq? (verification-status (check-case-coverage c '(#t))) 'refuted)))
