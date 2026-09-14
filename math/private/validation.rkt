#lang racket/base

;;;
;;; Shared Mathematical Validation
;;;
;; Provides pure boundary checks and immutable snapshots of metadata containers. It
;; imports no renderer or external-effect facilities.
;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/math infinite? nan?))

;; Exports
(provide
  finite-real? check-finite-real check-positive-real check-symbol check-boolean check-path
  check-procedure check-symbol-list snapshot-metadata check-list-of)

;;;
;;; Construction and Operations
;;;
; finite-real? : any/c -> boolean?
;;   Recognizes finite real numbers, excluding NaN and infinities.
(define (finite-real? number)
  (and (real? number) (not (infinite? number)) (not (nan? number))))

; check-finite-real : symbol? any/c -> finite-real?
;;   Validates and preserves an exact or inexact finite real.
(define (check-finite-real who number)
  (unless (finite-real? number) (raise-argument-error who "finite-real?" number))
  number)

; check-positive-real : symbol? any/c -> positive-real?
;;   Validates a strictly positive finite real without coercion.
(define (check-positive-real who number)
  (unless (and (finite-real? number) (positive? number))
    (raise-argument-error who "positive finite real" number))
  number)

; check-symbol : symbol? symbol? -> symbol?
;;   Validates a semantic identity symbol.
(define (check-symbol who name)
  (unless (symbol? name) (raise-argument-error who "symbol?" name))
  name)

; check-boolean : symbol? any/c -> boolean?
;;   Validates a flag without treating arbitrary truthy values as booleans.
(define (check-boolean who enabled?)
  (unless (boolean? enabled?) (raise-argument-error who "boolean?" enabled?))
  enabled?)

; check-path : symbol? operand-path? -> operand-path?
;;   Validates a list of zero-based operand indices.
(define (check-path who path)
  (check-list-of who path exact-nonnegative-integer? "zero-based operand path"))

; check-symbol-list : symbol? any/c -> (listof symbol?)
;;   Validates an ordered list of semantic names.
(define (check-symbol-list who names)
  (check-list-of who names symbol? "list of symbols"))

; check-list-of : symbol? any/c any/c any/c -> list?
;;   Validates an ordered collection at a public construction boundary.
(define (check-list-of who entries predicate description)
  (unless (and (list? entries) (andmap predicate entries))
    (raise-argument-error who description entries))
  entries)

; check-procedure : symbol? any/c any/c -> procedure?
;;   Checks callback arity and rejects required keyword arguments.
(define (check-procedure who procedure count)
  (unless (and (procedure? procedure) (procedure-arity-includes? procedure count))
    (raise-argument-error who (format "procedure accepting ~a arguments" count) procedure))
  (define-values (required allowed) (procedure-keywords procedure))
  (unless (null? required)
    (raise-arguments-error who
      "callback must not require keyword arguments"
      "required-keywords"
      required))
  procedure)

; snapshot-metadata : any/c [#:atomic? procedure?] -> any/c
;;   Snapshots acyclic metadata containers and rejects opaque or effectful values.
(define (snapshot-metadata datum #:atomic? [atomic? (lambda (value) #f)])
  (define active (make-hasheq))
  (define (container value build)
    (when (hash-ref active value #f)
      (raise-argument-error 'snapshot-metadata "acyclic metadata" value))
    (hash-set! active value #t)
    (define result (build))
    (hash-remove! active value)
    result)
  (define (copy value)
    (cond
      [(or
         (null? value)
         (boolean? value)
         (number? value)
         (symbol? value)
         (char? value)
         (keyword? value)
         (atomic? value))
       value]
      [(string? value) (string->immutable-string value)]
      [(bytes? value) (bytes->immutable-bytes value)]
      [(path? value) value]
      [(pair? value)
       (container value (lambda () (cons (copy (car value)) (copy (cdr value)))))]
      [(box? value) (container value (lambda () (box-immutable (copy (unbox value)))))]
      [(vector? value)
       (container value
         (lambda ()
           (vector->immutable-vector (for/vector ([item (in-vector value)]) (copy item)))))]
      [(hash? value)
       (container value
         (lambda ()
           (for/hash ([(key item) (in-hash value)]) (values (copy key) (copy item)))))]
      [else
       (raise-argument-error 'snapshot-metadata
         "acyclic data metadata, without opaque objects or procedures"
         value)]))
  (copy datum))
