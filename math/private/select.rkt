#lang racket/base

;;;
;;; Mathematical Selection
;;;
;; Defines immutable selectors and resolves them against one held snapshot. Paths
;; identify locations; occurrence identities express lineage.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "validation.rkt"
  (only-in racket/list append* remove-duplicates)
  "datum.rkt"
  "model.rkt")

;; Exports
(provide
  whole lhs rhs numerator denominator at-path matching all-matching operator-of selector?
  resolve-selector resolve-one math-select)

;;;
;;; Data Representation
;;;
(struct selector (kind argument within)
  #:transparent
  #:guard
  (lambda (kind argument within who)
    (unless (memq kind '(path lhs rhs numerator denominator matching all-matching operator))
      (raise-argument-error who "selector kind" kind))
    (if (eq? kind 'path)
      (begin
        (check-path who argument)
        (unless (not within) (raise-argument-error who "#f for a path selector" within)))
      (unless (selector? within) (raise-argument-error who "selector?" within)))
    (case kind
      [(matching) (check-datum who (car argument))]
      [(all-matching) (check-datum who argument)])
    (values kind argument within)))
;; selector is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  validated selection operation
;;  - argument  any/c  operand path, ordinal, or structural pattern
;;  - within  (or/c selector? #f)  containing selector; false only for an absolute path

; whole : -> selector?
;;   Selects the complete root expression.
(define (whole)
  (selector 'path '() #f))

; at-path : operand-path? -> selector?
;;   Selects an exact zero-based operand path and validates the path immediately.
(define (at-path p)
  (selector 'path p #f))

; lhs : [selector?] -> selector?
;;   Selects the left operand of a relation within the containing selection.
(define (lhs [within (whole)])
  (selector 'lhs 0 within))

; rhs : [selector?] -> selector?
;;   Selects the right operand of a relation within the containing selection.
(define (rhs [within (whole)])
  (selector 'rhs 1 within))

; numerator : [selector?] -> selector?
;;   Selects the numerator of an explicitly held quotient.
(define (numerator [within (whole)])
  (selector 'numerator 0 within))

; denominator : [selector?] -> selector?
;;   Selects the denominator of an explicitly held quotient.
(define (denominator [within (whole)])
  (selector 'denominator 1 within))

; matching : math-datum? [#:occurrence (or/c exact-positive-integer? #f)] [#:within
;   selector?] -> selector?
;;   Selects structural matches, optionally choosing a one-based occurrence ordinal.
(define (matching datum #:occurrence [ordinal #f] #:within [within (whole)])
  (when (and ordinal (not (exact-positive-integer? ordinal)))
    (raise-argument-error 'matching "one-based positive occurrence ordinal" ordinal))
  (selector 'matching (cons datum ordinal) within))

; all-matching : math-datum? [#:within selector?] -> selector?
;;   Selects every structural match in held preorder within the containing selection.
(define (all-matching datum #:within [within (whole)])
  (selector 'all-matching datum within))

; operator-of : [selector?] -> selector?
;;   Selects the owning expression for inspection of an operator role.
(define (operator-of [within (whole)])
  (selector 'operator #f within))

; resolve-selector : (or/c math? math-datum?) selector? -> (listof operand-path?)
;;   Resolves an immutable selector to ordered operand paths in one snapshot.
(define (resolve-selector state s)
  (unless (selector? s) (raise-argument-error 'resolve-selector "selector?" s))
  (define datum (if (math? state) (math-datum state) state))
  (define (resolve s)
    (case (selector-kind s)
      [(path) (datum-ref datum (selector-argument s)) (list (selector-argument s))]
      [(lhs rhs numerator denominator)
       (append*
         (for/list ([p (in-list (resolve (selector-within s)))])
           (define value (datum-ref datum p))
           (unless (if (memq (selector-kind s) '(lhs rhs)) (relation? value) (eq? (head value) '/))
             (math-error 'select 'wrong-focus
               "Selector applied to the wrong expression kind."
               s
               value))
           (list (append p (list (selector-argument s))))))]
      [(matching all-matching)
       (define data
         (if (eq? (selector-kind s) 'matching)
           (car (selector-argument s))
           (selector-argument s)))
       (define paths
         (remove-duplicates
           (append*
             (for/list ([base (in-list (resolve (selector-within s)))])
               (for/list ([tail (in-list (datum-paths (datum-ref datum base)))]
                           #:when (equal? (datum-ref datum (append base tail)) data))
                 (append base tail))))
           equal?))
       (define ordinal (and (eq? (selector-kind s) 'matching) (cdr (selector-argument s))))
       (if ordinal
         (if (<= ordinal (length paths)) (list (list-ref paths (sub1 ordinal))) '())
         paths)]
      [(operator) (resolve (selector-within s))]
      [else (math-error 'select 'invalid-selector "Unknown selector." s)]))
  (resolve s))

; resolve-one : (or/c math? math-datum?) selector? -> operand-path?
;;   Requires exactly one result and diagnoses missing or ambiguous selection.
(define (resolve-one state s)
  (define ps (resolve-selector state s))
  (unless (= (length ps) 1)
    (math-error 'select 'ambiguous-selection
      "Expected exactly one occurrence; choose an ordinal or a unique path."
      s
      (length ps)))
  (car ps))

; math-select : math? selector? -> (listof occurrence?)
;;   Returns selected mathematical occurrences, not anonymous rendered glyphs.
(define (math-select state s)
  (map (lambda (p) (math-occurrence-at state p)) (resolve-selector state s)))
