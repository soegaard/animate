#lang racket/base

;;;
;;; Relation Context
;;;

;; A relation context is a checked façade over the immutable derived context
;; supplied by scene-state. Every semantic read is recorded and must have an
;; equal explicit dependency description. The underlying state remains
;; read-only; this module carries only ephemeral per-resolution diagnostics.

(require "derived-visual.rkt"
         "geometry.rkt"
         "layout-box.rkt"
         "parameter.rkt"
         "relation-dependency.rkt"
         "resolvable-visual.rkt"
         "visual-selection.rkt"
         "visual-model.rkt")

(provide relation-context?
         make-relation-context
         relation-context-relation-id
         relation-context-declared-dependencies
         relation-context-used-dependencies
         relation-context-unused-dependencies
         relation-context-value-has?
         relation-context-value-ref
         relation-context-visual-has?
         relation-context-visual-ref
         relation-context-world-ref
         relation-context-position
         relation-context-anchor-ref
         relation-context-layout-box
         relation-context-selection-box
         relation-context-selection-anchor)

(struct relation-context-value
  (base relation-id declared used anchor-ref layout-box-ref selection-box-ref)
  #:transparent)

(define (relation-context? value)
  (relation-context-value? value))

(define (make-relation-context base relation-id declared
                               #:anchor-ref [anchor-ref #f]
                               #:layout-box-ref [layout-box-ref #f]
                               #:selection-box-ref [selection-box-ref #f])
  (unless (derived-context? base)
    (raise-argument-error 'make-relation-context "derived-context?" base))
  (unless (symbol? relation-id)
    (raise-argument-error 'make-relation-context "symbol?" relation-id))
  (unless (and (list? declared) (andmap relation-dependency? declared))
    (raise-argument-error
     'make-relation-context
     "(listof relation-dependency?)"
     declared))
  (unless (or (not anchor-ref)
              (and (procedure? anchor-ref)
                   (procedure-arity-includes? anchor-ref 2)))
    (raise-argument-error
     'make-relation-context
     "(or/c false/c procedure accepting target and anchor) as #:anchor-ref"
     anchor-ref))
  (unless (or (not selection-box-ref)
              (and (procedure? selection-box-ref)
                   (procedure-arity-includes? selection-box-ref 1)))
    (raise-argument-error
     'make-relation-context
     "(or/c false/c procedure accepting visual-selection?) as #:selection-box-ref"
     selection-box-ref))
  (unless (or (not layout-box-ref)
              (and (procedure? layout-box-ref)
                   (procedure-arity-includes? layout-box-ref 1)))
    (raise-argument-error
     'make-relation-context
     "(or/c false/c procedure accepting a concrete Visual) as #:layout-box-ref"
     layout-box-ref))
  ;; `used` keeps declaration values in first-use order, so diagnostics are
  ;; stable and never depend on hash iteration.
  (relation-context-value base relation-id declared (box '()) anchor-ref
                          layout-box-ref selection-box-ref))

(define (relation-context-relation-id context)
  (checked-context 'relation-context-relation-id context)
  (relation-context-value-relation-id context))

(define (relation-context-declared-dependencies context)
  (checked-context 'relation-context-declared-dependencies context)
  (relation-context-value-declared context))

(define (relation-context-used-dependencies context)
  (checked-context 'relation-context-used-dependencies context)
  (unbox (relation-context-value-used context)))

(define (relation-context-unused-dependencies context)
  (checked-context 'relation-context-unused-dependencies context)
  (define used (relation-context-used-dependencies context))
  (filter (lambda (dependency) (not (member dependency used)))
          (relation-context-value-declared context)))

(define (relation-context-value-has? context target)
  (define base (checked-context 'relation-context-value-has? context))
  (define id (parameter-target-id target 'relation-context-value-has?))
  (record-value-access! context id)
  (derived-context-value-has? base id))

(define (relation-context-value-ref context target)
  (define base (checked-context 'relation-context-value-ref context))
  (define id (parameter-target-id target 'relation-context-value-ref))
  (record-value-access! context id)
  (derived-context-value-ref base id))

(define (relation-context-visual-has? context target)
  (define base (checked-context 'relation-context-visual-has? context))
  (define path (visual-target-path target 'relation-context-visual-has?))
  (record-visual-access! context path)
  (derived-context-visual-has? base path))

(define (relation-context-visual-ref context target)
  (define base (checked-context 'relation-context-visual-ref context))
  (define path (visual-target-path target 'relation-context-visual-ref))
  (record-visual-access! context path)
  (derived-context-visual-ref base path))

;; Existing derived contexts already resolve a requested Visual through every
;; enclosing affine/opacity transform. Keep world access distinct in the
;; authoring API, even though its EL-2 implementation shares that lookup.
(define (relation-context-world-ref context target)
  (relation-context-visual-ref context target))

(define (relation-context-position context target)
  (visual-position (relation-context-visual-ref context target)))

;; relation-context-anchor-ref : relation-context? visual target anchor -> vec2?
;; Layout-phase relations use this renderer-supplied operation after declaring
;; the exact `(anchor-dependency target anchor)`. Semantic relations have no
;; such callback and therefore fail explicitly rather than measuring pixels.
(define (relation-context-anchor-ref context target anchor)
  (checked-context 'relation-context-anchor-ref context)
  (define path (visual-target-path target 'relation-context-anchor-ref))
  (unless (symbol? anchor)
    (raise-argument-error 'relation-context-anchor-ref "symbol?" anchor))
  (record-anchor-access! context path anchor)
  (define anchor-ref (relation-context-value-anchor-ref context))
  (unless anchor-ref
    (raise-arguments-error
     'relation-context-anchor-ref
     "a renderer-aware layout relation context"
     "relation" (relation-context-value-relation-id context)
     "target" path
     "anchor" anchor))
  (define point (anchor-ref path anchor))
  (unless (vec2? point)
    (raise-arguments-error
     'relation-context-anchor-ref
     "a renderer layout callback returning vec2?"
     "relation" (relation-context-value-relation-id context)
     "target" path
     "anchor" anchor
     "result" point))
  point)

;; relation-context-layout-box : relation-context? concrete-visual? -> layout-box?
;; Measures a resolver-local concrete Visual in the active camera/renderer
;; configuration. It is intentionally a layout-only capability: asking the
;; semantic relation phase to measure a Pict would make its value depend on a
;; renderer that has not yet been selected.
(define (relation-context-layout-box context visual)
  (checked-context 'relation-context-layout-box context)
  (unless (visual? visual)
    (raise-argument-error 'relation-context-layout-box "visual?" visual))
  (when (resolvable-visual? visual)
    (raise-argument-error
     'relation-context-layout-box
     "a concrete Visual, not a resolvable Visual"
     visual))
  (define layout-box-ref (relation-context-value-layout-box-ref context))
  (unless layout-box-ref
    (raise-arguments-error
     'relation-context-layout-box
     "a renderer-aware layout relation context"
     "relation" (relation-context-value-relation-id context)
     "visual" visual))
  (define result (layout-box-ref visual))
  (unless (layout-box? result)
    (raise-arguments-error
     'relation-context-layout-box
     "a renderer layout callback returning layout-box?"
     "relation" (relation-context-value-relation-id context)
     "visual" visual
     "result" result))
  result)

;; relation-context-selection-box : relation-context? visual-selection?
;;                                  -> layout-box?
;; Returns aggregate rendered bounds for a declared semantic selection.
(define (relation-context-selection-box context selection)
  (checked-context 'relation-context-selection-box context)
  (unless (visual-selection? selection)
    (raise-argument-error
     'relation-context-selection-box "visual-selection?" selection))
  (record-selection-access! context selection)
  (define box-ref (relation-context-value-selection-box-ref context))
  (unless box-ref
    (raise-arguments-error
     'relation-context-selection-box
     "a renderer-aware layout relation context"
     "relation" (relation-context-value-relation-id context)
     "selection" selection))
  (define result (box-ref selection))
  (unless (layout-box? result)
    (raise-arguments-error
     'relation-context-selection-box
     "a renderer layout callback returning layout-box?"
     "relation" (relation-context-value-relation-id context)
     "selection" selection
     "result" result))
  result)

(define (relation-context-selection-anchor context selection anchor)
  (layout-box-anchor
   (relation-context-selection-box context selection)
   anchor))

(define (checked-context who context)
  (unless (relation-context? context)
    (raise-argument-error who "relation-context?" context))
  (relation-context-value-base context))

(define (record-value-access! context id)
  (define matching
    (for/first ([dependency
                 (in-list (relation-context-value-declared context))]
                #:when
                (and (value-dependency? dependency)
                     (eq? (parameter-target-id
                           (value-dependency-target dependency)
                           'relation-context-value-ref)
                          id)))
      dependency))
  (unless matching
    (raise-arguments-error
     'relation-context-value-ref
     "a value dependency declared by this relation"
     "relation" (relation-context-value-relation-id context)
     "read value" id
     "declared dependencies" (relation-context-value-declared context)))
  (record-dependency-use! context matching))

(define (record-visual-access! context path)
  (define matching
    (for/first ([dependency
                 (in-list (relation-context-value-declared context))]
                #:when
                (and (visual-dependency? dependency)
                     (equal? (visual-target-path
                              (visual-dependency-target dependency)
                              'relation-context-visual-ref)
                             path)))
      dependency))
  (unless matching
    (raise-arguments-error
     'relation-context-visual-ref
     "a Visual dependency declared by this relation"
     "relation" (relation-context-value-relation-id context)
     "read Visual" path
     "declared dependencies" (relation-context-value-declared context)))
  (record-dependency-use! context matching))

(define (record-anchor-access! context path anchor)
  (define matching
    (for/first ([dependency
                 (in-list (relation-context-value-declared context))]
                #:when
                (and (anchor-dependency? dependency)
                     (equal? (visual-target-path
                              (anchor-dependency-target dependency)
                              'relation-context-anchor-ref)
                             path)
                     (eq? (anchor-dependency-anchor dependency) anchor)))
      dependency))
  (unless matching
    (raise-arguments-error
     'relation-context-anchor-ref
     "an anchor dependency declared by this relation"
     "relation" (relation-context-value-relation-id context)
     "read Visual" path
     "read anchor" anchor
     "declared dependencies" (relation-context-value-declared context)))
  (record-dependency-use! context matching))

(define (record-selection-access! context selection)
  (define matching
    (for/first ([dependency
                 (in-list (relation-context-value-declared context))]
                #:when
                (and (selection-dependency? dependency)
                     (equal? (selection-dependency-selection dependency)
                             selection)))
      dependency))
  (unless matching
    (raise-arguments-error
     'relation-context-selection-box
     "a selection dependency declared by this relation"
     "relation" (relation-context-value-relation-id context)
     "selection" selection
     "declared dependencies" (relation-context-value-declared context)))
  (record-dependency-use! context matching))

(define (record-dependency-use! context dependency)
  (define used (relation-context-value-used context))
  (unless (member dependency (unbox used))
    (set-box! used (append (unbox used) (list dependency)))))
