#lang racket/base

;;;
;;; Derived Visuals
;;;

;; Defines pure top-level Visual definitions whose concrete Visual value is
;; derived from one immutable sampled scene state.
;;
;; Each definition carries a concrete template Visual. The template supplies the
;; ordinary gen:visual identity/position behavior required when the definition is
;; handled as model data, while scene-aware resolution computes the concrete
;; Visual from a read-only context. Through SCENE-AX that context exposes both
;; named semantic values and recursively resolved top-level Visual dependencies.


;;;
;;; Imports and Exports
;;;

(require "geometry.rkt"
         "interpolation.rkt"
         "parameter.rkt"
         "visual-model.rkt")

(provide derived-visual
         derived-visual?
         derived-context?
         derived-context-value-has?
         derived-context-value-ref
         derived-context-visual-has?
         derived-context-visual-ref
         make-derived-context
         resolve-derived-visual)


;;;
;;; Read-Only Derivation Context
;;;

(struct derived-context-value (value-has-proc
                               value-ref-proc
                               visual-has-proc
                               visual-ref-proc)
  #:transparent)

; derived-context? : any/c -> boolean?
;;   Reports whether value is a read-only derivation context.
(define (derived-context? value)
  (derived-context-value? value))

; make-derived-context : (-> symbol? boolean?)
;                        (-> symbol? interpolable?)
;                        (-> symbol? boolean?)
;                        (-> symbol? visual?)
;                        -> derived-context?
;;   Constructs the internal read-only context supplied to derived resolvers.
(define (make-derived-context value-has-proc
                              value-ref-proc
                              visual-has-proc
                              visual-ref-proc)
  (for ([entry (in-list
                (list (cons "value presence" value-has-proc)
                      (cons "value lookup" value-ref-proc)
                      (cons "Visual presence" visual-has-proc)
                      (cons "Visual lookup" visual-ref-proc)))])
    (define proc (cdr entry))
    (unless (and (procedure? proc)
                 (procedure-arity-includes? proc 1))
      (raise-arguments-error
       'make-derived-context
       "each context operation must be a procedure accepting one argument"
       "operation" (car entry)
       "value" proc)))
  (derived-context-value value-has-proc
                         value-ref-proc
                         visual-has-proc
                         visual-ref-proc))

; derived-context-value-has? : derived-context? (or/c symbol? scene-parameter?) -> boolean?
;;   Reports whether context contains one named semantic value.
(define (derived-context-value-has? context target)
  (unless (derived-context? context)
    (raise-argument-error
     'derived-context-value-has?
     "derived-context?"
     context))
  (define id
    (parameter-target-id target 'derived-context-value-has?))
  (define result
    ((derived-context-value-value-has-proc context) id))
  (unless (boolean? result)
    (raise-arguments-error
     'derived-context-value-has?
     "the derivation context must return a boolean presence result"
     "value-id" id
     "result" result))
  result)

; derived-context-value-ref : derived-context? (or/c symbol? scene-parameter?) -> interpolable?
;;   Returns one named semantic value from context.
(define (derived-context-value-ref context target)
  (unless (derived-context? context)
    (raise-argument-error
     'derived-context-value-ref
     "derived-context?"
     context))
  (define id
    (parameter-target-id target 'derived-context-value-ref))
  (define value
    ((derived-context-value-value-ref-proc context) id))
  (unless (interpolable? value)
    (raise-arguments-error
     'derived-context-value-ref
     "the derivation context must return an interpolable semantic value"
     "value-id" id
     "value" value))
  value)

; derived-context-visual-has? : derived-context? symbol? -> boolean?
;;   Reports whether context contains one top-level Visual identity.
(define (derived-context-visual-has? context id)
  (unless (derived-context? context)
    (raise-argument-error
     'derived-context-visual-has?
     "derived-context?"
     context))
  (unless (symbol? id)
    (raise-argument-error 'derived-context-visual-has? "symbol?" id))
  (define result
    ((derived-context-value-visual-has-proc context) id))
  (unless (boolean? result)
    (raise-arguments-error
     'derived-context-visual-has?
     "the derivation context must return a boolean Visual presence result"
     "visual-id" id
     "result" result))
  result)

; derived-context-visual-ref : derived-context? symbol? -> visual?
;;   Returns one recursively resolved concrete top-level Visual from context.
(define (derived-context-visual-ref context id)
  (unless (derived-context? context)
    (raise-argument-error
     'derived-context-visual-ref
     "derived-context?"
     context))
  (unless (symbol? id)
    (raise-argument-error 'derived-context-visual-ref "symbol?" id))
  (define visual
    ((derived-context-value-visual-ref-proc context) id))
  (unless (and (visual? visual)
               (not (derived-visual? visual)))
    (raise-arguments-error
     'derived-context-visual-ref
     "the derivation context must return a concrete Visual"
     "visual-id" id
     "result" visual))
  (unless (eq? (visual-id visual) id)
    (raise-arguments-error
     'derived-context-visual-ref
     "the derivation context Visual lookup must preserve the requested ID"
     "requested visual-id" id
     "result visual-id" (visual-id visual)))
  visual)


;;;
;;; Derived Visual Definition
;;;

;; Alias the generic operations before defining methods with the same names.
;; This keeps method bodies delegated to the template rather than recursively
;; calling the method currently being defined.
(define template-visual-id visual-id)
(define template-visual-position visual-position)
(define template-visual-with-position visual-with-position)

(struct derived-visual-value (template resolver)
  #:transparent
  #:methods gen:visual
  [(define (visual-id definition)
     (template-visual-id (derived-visual-value-template definition)))
   (define (visual-position definition)
     (define position
       (template-visual-position (derived-visual-value-template definition)))
     (unless (vec2? position)
       (raise-arguments-error
        'visual-position
        "the derived Visual template must return a vec2 position"
        "visual-id" (template-visual-id (derived-visual-value-template definition))
        "position" position))
     position)
   (define (visual-with-position definition position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (define template
       (derived-visual-value-template definition))
     (define replacement
       (template-visual-with-position template position))
     (unless (and (visual? replacement)
                  (not (derived-visual-value? replacement))
                  (eq? (template-visual-id replacement)
                       (template-visual-id template))
                  (equal? (template-visual-position replacement) position))
       (raise-arguments-error
        'visual-with-position
        "the derived Visual template must preserve identity and install the requested position"
        "visual-id" (template-visual-id template)
        "position" position
        "result" replacement))
     (struct-copy derived-visual-value definition
                  [template replacement]))])

; derived-visual? : any/c -> boolean?
;;   Reports whether value is a SCENE-AW derived Visual definition.
(define (derived-visual? value)
  (derived-visual-value? value))

; derived-visual : visual?
;                  (-> derived-context? visual? visual?)
;                  -> derived-visual?
;;   Creates one pure Visual definition driven by sampled scene dependencies.
;;   Resolver receives both the read-only context and the immutable template.
(define (derived-visual template resolver)
  (unless (visual? template)
    (raise-argument-error 'derived-visual "visual?" template))
  (when (derived-visual? template)
    (raise-arguments-error
     'derived-visual
     "the template must be a concrete Visual, not another derived Visual"
     "template" template))
  (define id
    (visual-id template))
  (unless (symbol? id)
    (raise-arguments-error
     'derived-visual
     "the template Visual must have a symbol identity"
     "visual-id" id))
  (define position
    (visual-position template))
  (unless (vec2? position)
    (raise-arguments-error
     'derived-visual
     "the template Visual must have a vec2 position"
     "visual-id" id
     "visual-position" position))
  (unless (and (procedure? resolver)
               (procedure-arity-includes? resolver 2))
    (raise-argument-error
     'derived-visual
     "procedure accepting derived-context? and template visual? arguments"
     resolver))
  (derived-visual-value template resolver))

; resolve-derived-visual : derived-visual? derived-context? -> visual?
;;   Evaluates one resolver and validates its concrete top-level Visual result.
(define (resolve-derived-visual definition context)
  (unless (derived-visual? definition)
    (raise-argument-error
     'resolve-derived-visual
     "derived-visual?"
     definition))
  (unless (derived-context? context)
    (raise-argument-error
     'resolve-derived-visual
     "derived-context?"
     context))
  (define template
    (derived-visual-value-template definition))
  (define result
    ((derived-visual-value-resolver definition) context template))
  (unless (visual? result)
    (raise-arguments-error
     'resolve-derived-visual
     "the derived resolver must return a Visual"
     "visual-id" (visual-id template)
     "result" result))
  (when (derived-visual? result)
    (raise-arguments-error
     'resolve-derived-visual
     "a derived resolver must return a concrete Visual, not another derived Visual"
     "visual-id" (visual-id template)
     "result" result))
  (unless (eq? (visual-id result)
               (visual-id template))
    (raise-arguments-error
     'resolve-derived-visual
     "the resolved Visual must preserve the derived Visual ID"
     "expected visual-id" (visual-id template)
     "resolved visual-id" (visual-id result)))
  (define position
    (visual-position result))
  (unless (vec2? position)
    (raise-arguments-error
     'resolve-derived-visual
     "the resolved Visual must return a vec2 position"
     "visual-id" (visual-id template)
     "visual-position" position))
  result)
