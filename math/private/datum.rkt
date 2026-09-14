#lang racket/base

;;;
;;; Held Scalar Expressions
;;;
;; Defines ordinary scalar-expression data, structural traversal, held substitution, and
;; exact arithmetic without rendering or filesystem dependencies.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append* append-map remove-duplicates take)
  (only-in racket/match match)
  (only-in racket/math infinite? nan?))

;; Exports
(provide
  math-datum? check-datum app? operands head datum-paths datum-ref datum-replace
  path-prefix? held-substitute free-of? definition-expand datum-symbols exact-evaluate
  numeric-value domain-requirements relation? comparison? signed-addends build-sum
  build-product (struct-out addend))

;;;
;;; Construction and Operations
;;;
; app? : any/c -> boolean?
;;   Recognizes a symbol-headed mathematical application.
(define (app? x)
  (and (list? x) (pair? x) (symbol? (car x))))

; head : any/c -> (or/c symbol? #f)
;;   Returns an application operator, or false for an atom.
(define (head x)
  (and (app? x) (car x)))

; operands : any/c -> (listof math-datum?)
;;   Returns operands in their held order, excluding the operator.
(define (operands x)
  (if (app? x) (cdr x) '()))

; math-datum? : any/c -> boolean?
;;   Recognizes supported scalar-expression data without evaluating it.
(define (math-datum? x)
  (or
    (and (real? x) (not (nan? x)) (not (infinite? x)))
    (symbol? x)
    (boolean? x)
    (and (app? x) (andmap math-datum? (cdr x)))))

; check-datum : symbol? any/c -> math-datum?
;;   Validates scalar syntax and the arities of known operators.
(define (check-datum who x)
  (unless (math-datum? x) (raise-argument-error who "held scalar S-expression" x))
  (when (app? x)
    (define n (length (cdr x)))
    (define valid?
      (case (car x)
        [(= < <= > >= / expt) (= n 2)]
        [(-) (or (= n 1) (= n 2))]
        [(sqrt abs not parens) (= n 1)]
        [(+ * and or) (>= n 1)]
        [else #t]))
    (unless valid? (raise-arguments-error who "wrong mathematical arity" "datum" x))
    (for-each (lambda (a) (check-datum who a)) (cdr x)))
  x)

; relation? : any/c -> boolean?
;;   Recognizes a binary scalar comparison.
(define (relation? x)
  (and (app? x) (memq (car x) '(= < <= > >=)) (= (length x) 3) #t))

; comparison? : any/c -> boolean?
;;   Recognizes a binary scalar comparison.
(define comparison?
  relation?)

; path-prefix? : any/c any/c -> boolean?
;;   Tests whether one operand path contains the other.
(define (path-prefix? p q)
  (and (<= (length p) (length q)) (equal? p (take q (length p)))))

;;;
;;; Held Traversal and Replacement
;;;
; datum-paths : math-datum? [operand-path?] -> (listof operand-path?)
;;   Enumerates the root and descendants in preorder without sorting operands.
(define (datum-paths x [p '()])
  (cons p
    (append*
      (for/list ([a (in-list (operands x))] [i (in-naturals)])
        (datum-paths a (append p (list i)))))))

; datum-ref : math-datum? operand-path? -> math-datum?
;;   Looks up a held subexpression by zero-based operand indices.
(define (datum-ref x p)
  (unless (and (list? p) (andmap exact-nonnegative-integer? p))
    (raise-argument-error 'datum-ref "list of zero-based operand indices" p))
  (for/fold ([v x]) ([i (in-list p)])
    (unless (and (app? v) (< i (length (cdr v))))
      (raise-arguments-error 'datum-ref "invalid operand path" "path" p "datum" x))
    (list-ref (cdr v) i)))

; datum-replace : any/c any/c any/c -> math-datum?
;;   Replaces one held subtree without simplifying its ancestors.
(define (datum-replace x p y)
  (if (null? p)
    y
    (begin
      (datum-ref x p)
      (cons
        (car x)
        (for/list ([a (in-list (cdr x))] [i (in-naturals)])
          (if (= i (car p)) (datum-replace a (cdr p) y) a))))))

;;;
;;; Held Substitution
;;;
; binders : (listof symbol?)
;;   Names operators requiring binding-aware substitution rather than structural
;;   traversal.
(define binders
  '(lambda integral integrate sum product forall exists limit))

; held-substitute : math-datum? hash? -> math-datum?
;;   Performs simultaneous structural substitution and rejects traversal under binders.
(define (held-substitute x replacements)
  ;; Simultaneous, structural substitution; values are never resubstituted.
  ;; Refuse traversal under binders until binding-aware substitution exists.
  (define table (if (hash? replacements) replacements (make-immutable-hash replacements)))
  (define (walk x)
    (cond
      [(hash-has-key? table x) (hash-ref table x)]
      [(app? x)
       (when (memq (car x) binders)
         (raise-arguments-error 'held-substitute
           "binding-aware substitution is required"
           "datum"
           x))
       (cons (car x) (map walk (cdr x)))]
      [else x]))
  (check-datum 'held-substitute (walk x)))

; free-of? : math-datum? math-datum? -> boolean?
;;   Tests absence of a structurally equal complete subexpression.
(define (free-of? x target)
  (and (not (equal? x target)) (andmap (lambda (a) (free-of? a target)) (operands x))))

; datum-symbols : any/c -> (listof symbol?)
;;   Lists distinct operand symbols in first-occurrence order.
(define (datum-symbols x)
  (remove-duplicates
    (cond [(symbol? x) (list x)] [(app? x) (append-map datum-symbols (cdr x))] [else '()])))

; definition-expand : any/c (or/c hash? list?) -> math-datum?
;;   Expands scoped definitions and diagnoses cycles explicitly.
(define (definition-expand x definitions)
  (define table (if (hash? definitions) definitions (make-immutable-hash definitions)))
  (define (walk x seen)
    (cond
      [(and (symbol? x) (hash-has-key? table x))
       (when (memq x seen)
         (raise-arguments-error 'definition-expand "cyclic definition" "cycle"
           (reverse (cons x seen))))
       (walk (hash-ref table x) (cons x seen))]
      [(app? x) (cons (car x) (map (lambda (v) (walk v seen)) (cdr x)))]
      [else x]))
  (walk x '()))

;;;
;;; Exact Numeric Arithmetic
;;;
; numeric-value : any/c -> (or/c exact-rational? #f)
;;   Computes supported exact numeric arithmetic or returns false without approximating.
(define (numeric-value x)
  ;; #f denotes not exactly evaluable, never a numerical approximation.
  (cond
    [(and (real? x) (exact? x)) x]
    [(app? x)
     (define vs (map numeric-value (cdr x)))
     (and
       (andmap number? vs)
       (case (car x)
         [(+) (apply + vs)]
         [(*) (apply * vs)]
         [(-) (apply - vs)]
         [(/) (and (not (zero? (cadr vs))) (/ (car vs) (cadr vs)))]
         [(expt)
          (and
            (exact-integer? (cadr vs))
            (<= (abs (cadr vs)) 256)
            (not (and (zero? (car vs)) (<= (cadr vs) 0)))
            (expt (car vs) (cadr vs)))]
         [(sqrt) (and (>= (car vs) 0) (let ([r (sqrt (car vs))]) (and (exact? r) r)))]
         [(abs) (abs (car vs))]
         [(parens) (car vs)]
         [else #f]))]
    [else #f]))

; exact-evaluate : any/c [#:deepest? any/c] -> math-datum?
;;   Evaluates selected arithmetic while keeping relations as visible relations.
(define (exact-evaluate x #:deepest? [deepest? #f])
  ;; Equations stay equations, including (= 17 17).
  (cond
    [(not (app? x)) x]
    [else
     (define children (cdr x))
     (define updated (map (lambda (v) (exact-evaluate v #:deepest? deepest?)) children))
     (define raw (cons (car x) updated))
     (define value (and (or (not deepest?) (equal? children updated)) (numeric-value raw)))
     (if (number? value) value raw)]))

;;;
;;; Real-Domain Requirements
;;;
; domain-requirements : any/c -> (listof math-datum?)
;;   Collects explicit real-domain obligations before simplification can erase them.
(define (domain-requirements x)
  (remove-duplicates
    (append
      (match x
        [(list '/ u v) (list `(not (= ,v 0)))]
        [(list 'expt u (? exact-integer? n)) (if (<= n 0) (list `(not (= ,u 0))) '())]
        [(list 'sqrt u) (list `(>= ,u 0))]
        [(list 'ln u) (list `(> ,u 0))]
        [(list 'log b u) (list `(> ,b 0) `(not (= ,b 1)) `(> ,u 0))]
        [_ '()])
      (append-map domain-requirements (operands x)))
    equal?))

(struct addend (sign value path)
  #:transparent)
;; addend is an immutable record. Its fields have the following roles.
;;  - sign  (or/c -1 1)  syntactic additive sign
;;  - value  math-datum?  held unsigned term
;;  - path  operand-path?  original source occurrence location

;;;
;;; Signed Term Views
;;;
; signed-addends : any/c [any/c] [any/c] -> (listof addend?)
;;   Flattens additive syntax into signed terms with original operand paths.
(define (signed-addends x [p '()] [sign 1])
  (match x
    [(list '+ vs ...)
     (append*
       (for/list ([v (in-list vs)] [i (in-naturals)])
         (signed-addends v (append p (list i)) sign)))]
    [(list '- u v)
     (append
       (signed-addends u (append p '(0)) sign)
       (signed-addends v (append p '(1)) (- sign)))]
    [(list '- u) (signed-addends u (append p '(0)) (- sign))]
    [_ (list (addend sign x p))]))

; build-sum : any/c -> math-datum?
;;   Builds held arithmetic with explicit empty and singleton conventions.
(define (build-sum values)
  (cond [(null? values) 0] [(null? (cdr values)) (car values)] [else (cons '+ values)]))

; build-product : any/c -> math-datum?
;;   Builds held arithmetic with explicit empty and singleton conventions.
(define (build-product values)
  (cond [(null? values) 1] [(null? (cdr values)) (car values)] [else (cons '* values)]))
