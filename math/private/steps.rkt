#lang racket/base

;;;
;;; Named Mathematical Step Sequences
;;;
;; Describes reusable, ordered mathematical recipes without applying operations.
;; Names are sibling-local; recipes carry no timing, renderer, or mutable state.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/list remove-duplicates)
         (for-syntax racket/base syntax/parse)
         "operations.rkt"
         "model.rkt")

;; Exports
(provide steps steps/proc step-sequence? step-sequence-entries
         validate-named-operations)

;;;
;;; Recipe Descriptions
;;;
(struct step-sequence (entries)
  #:transparent)
;; step-sequence is an immutable recipe, not an applied rewrite or presentation.
;;  - entries  (listof (cons/c symbol? (or/c math-operation? step-sequence?)))
;;    nonempty immutable sibling sequence; order matters and sibling names are unique.

; validate-named-operations : symbol? any/c -> list?
;;   Validates and copies named recipe entries before applying any of their operations.
(define (validate-named-operations who entries)
  (unless (and (list? entries)
               (andmap (lambda (entry)
                         (and (pair? entry) (symbol? (car entry))
                              (or (math-operation? (cdr entry))
                                  (step-sequence? (cdr entry)))))
                       entries))
    (raise-argument-error who
      "list of (cons symbol (or/c math-operation? step-sequence?))" entries))
  (define names (map car entries))
  (unless (= (length names) (length (remove-duplicates names)))
    (math-error who 'duplicate-step "Step names must be unique among siblings." names))
  (for/list ([entry (in-list entries)]) (cons (car entry) (cdr entry))))

; steps/proc : list? -> step-sequence?
;;   Constructs a nonempty reusable recipe without changing a mathematical state.
(define (steps/proc entries)
  (define checked (validate-named-operations 'steps/proc entries))
  (when (null? checked)
    (raise-argument-error 'steps/proc "nonempty named operation list" entries))
  (step-sequence checked))

; steps : syntax -> syntax
;;   Captures nonempty named elementary operations or nested mathematical recipes.
(define-syntax (steps stx)
  (syntax-parse stx
    [(_ [name:id operation] ...+)
     #'(steps/proc (list (cons 'name operation) ...))]))
