#lang racket/base

;;;
;;; Spatial Relation Resolution Context
;;;

;; Provides checked, read-only access to one sampled view3d while resolving a
;; spatial relation.  Reads are matched against explicit dependency
;; declarations, making resolver inputs inspectable and cycle diagnostics
;; meaningful without retaining any mutable scene state.


;;;
;;; Imports and Exports
;;;

(require "affine3.rkt"
         "../visual-model.rkt"
         "camera3d.rkt"
         "spatial-dependency.rkt"
         "spatial-path.rkt"
         "spatial-visual.rkt"
         "view3d-visual.rkt")

(provide spatial-relation-context?
         make-spatial-relation-context
         spatial-relation-context-relation-path
         spatial-relation-context-view
         spatial-relation-context-declared-dependencies
         spatial-relation-context-used-dependencies
         spatial-relation-context-unused-dependencies
         spatial-relation-context-spatial-has?
         spatial-relation-context-spatial-ref
         spatial-relation-context-spatial-world-transform
         spatial-relation-context-spatial-position
         spatial-relation-context-value-has?
         spatial-relation-context-value-ref
         spatial-relation-context-camera)


;;;
;;; Context Value
;;;

(struct spatial-relation-context-value
  (view relation-path declared used resolve-spatial resolve-world-transform
        value-has? value-ref)
  #:transparent)

; spatial-relation-context? : any/c -> boolean?
;;   Public predicate for the opaque resolver context.
(define spatial-relation-context? spatial-relation-context-value?)

;; spatial-relation-context-value represents one ephemeral resolver façade.
;;  - view                    view3d?             sampled owner viewport.
;;  - relation-path           spatial-path?       complete currently resolving path.
;;  - declared                (listof spatial-dependency?) author-declared inputs.
;;  - used                    box?                dependencies in stable first-use order.
;;  - resolve-spatial         procedure?          resolver-owned spatial lookup.
;;  - resolve-world-transform procedure?          resolver-owned world-transform lookup.
;;  - value-has?              procedure?          immutable scene-value predicate.
;;  - value-ref               procedure?          immutable scene-value lookup.


;;;
;;; Construction and Observation
;;;

; make-spatial-relation-context : view3d? spatial-path?
;                                 (listof spatial-dependency?)
;                                 (spatial-path? -> spatial-visual?)
;                                 (spatial-path? -> affine3?)
;                                 (symbol? -> boolean?) (symbol? -> any/c)
;                                 -> spatial-relation-context?
;;   Creates a checked read-only context used for exactly one resolver call.
(define (make-spatial-relation-context view relation-path declared
                                       resolve-spatial resolve-world-transform
                                       value-has? value-ref)
  (unless (view3d? view)
    (raise-argument-error 'make-spatial-relation-context "view3d?" view))
  (unless (and (spatial-path? relation-path)
               (eq? (car relation-path) (visual-id view)))
    (raise-argument-error
     'make-spatial-relation-context
     "spatial path rooted at the supplied view3d"
     relation-path))
  (unless (and (list? declared) (andmap spatial-dependency? declared))
    (raise-argument-error
     'make-spatial-relation-context
     "(listof spatial-dependency?)"
     declared))
  (for ([procedure (in-list (list resolve-spatial resolve-world-transform
                                  value-has? value-ref))])
    (unless (procedure? procedure)
      (raise-argument-error 'make-spatial-relation-context "procedure?" procedure)))
  (spatial-relation-context-value view relation-path declared (box '())
                                  resolve-spatial resolve-world-transform
                                  value-has? value-ref))

; spatial-relation-context-relation-path : spatial-relation-context?
;                                           -> spatial-path?
;;   Returns the complete stable path of the relation currently being resolved.
(define (spatial-relation-context-relation-path context)
  (context-ref 'spatial-relation-context-relation-path context
               spatial-relation-context-value-relation-path))

; spatial-relation-context-view : spatial-relation-context? -> view3d?
;;   Returns the sampled immutable owning viewport.
(define (spatial-relation-context-view context)
  (context-ref 'spatial-relation-context-view context
               spatial-relation-context-value-view))

; spatial-relation-context-declared-dependencies : spatial-relation-context?
;                                                   -> (listof spatial-dependency?)
;;   Returns the exact author-declared dependency descriptions.
(define (spatial-relation-context-declared-dependencies context)
  (context-ref 'spatial-relation-context-declared-dependencies context
               spatial-relation-context-value-declared))

; spatial-relation-context-used-dependencies : spatial-relation-context?
;                                               -> (listof spatial-dependency?)
;;   Returns dependencies read so far, in deterministic first-use order.
(define (spatial-relation-context-used-dependencies context)
  (unbox (context-ref 'spatial-relation-context-used-dependencies context
                      spatial-relation-context-value-used)))

; spatial-relation-context-unused-dependencies : spatial-relation-context?
;                                                 -> (listof spatial-dependency?)
;;   Returns declared inputs that the resolver did not read.
(define (spatial-relation-context-unused-dependencies context)
  (define used (spatial-relation-context-used-dependencies context))
  (filter (lambda (dependency) (not (member dependency used)))
          (spatial-relation-context-declared-dependencies context)))


;;;
;;; Checked Resolver Reads
;;;

; spatial-relation-context-spatial-has? : spatial-relation-context?
;                                          spatial-path? -> boolean?
;;   Reports whether a declared spatial target resolves in the sampled view.
(define (spatial-relation-context-spatial-has? context target)
  (define checked
    (checked-context 'spatial-relation-context-spatial-has? context))
  (define path
    (normalize-target checked target 'spatial-relation-context-spatial-has?))
  ;; A missing declared target is ordinary negative information.  An
  ;; undeclared target is an authoring error, so record the access before
  ;; asking the resolver and intentionally let that error propagate.
  (record-spatial-access! context path 'spatial-relation-context-spatial-has?)
  (with-handlers ([exn:fail? (lambda (_failure) #f)])
    (define result ((spatial-relation-context-value-resolve-spatial checked) path))
    (and (spatial-visual? result) #t)))

; spatial-relation-context-spatial-ref : spatial-relation-context?
;                                         spatial-path? -> spatial-visual?
;;   Resolves a declared relative or rooted spatial target.
(define (spatial-relation-context-spatial-ref context target)
  (define checked (checked-context 'spatial-relation-context-spatial-ref context))
  (define path (normalize-target checked target 'spatial-relation-context-spatial-ref))
  (record-spatial-access! context path 'spatial-relation-context-spatial-ref)
  (define result ((spatial-relation-context-value-resolve-spatial checked) path))
  (unless (spatial-visual? result)
    (raise-arguments-error
     'spatial-relation-context-spatial-ref
     "the spatial resolver to return a spatial Visual"
     "spatial-path" path
     "result" result))
  result)

; spatial-relation-context-spatial-world-transform : spatial-relation-context?
;                                                      spatial-path? -> affine3?
;;   Returns a declared target's complete current local-to-world map.
(define (spatial-relation-context-spatial-world-transform context target)
  (define checked
    (checked-context 'spatial-relation-context-spatial-world-transform context))
  (define path
    (normalize-target checked target 'spatial-relation-context-spatial-world-transform))
  (record-spatial-access! context path 'spatial-relation-context-spatial-world-transform)
  (define result ((spatial-relation-context-value-resolve-world-transform checked) path))
  (unless (affine3? result)
    (raise-arguments-error
     'spatial-relation-context-spatial-world-transform
     "the spatial resolver to return an affine3"
     "spatial-path" path
     "result" result))
  result)

; spatial-relation-context-spatial-position : spatial-relation-context?
;                                              spatial-path? -> vec3?
;;   Returns a declared target's current world-space origin.
(define (spatial-relation-context-spatial-position context target)
  (affine3-translation
   (spatial-relation-context-spatial-world-transform context target)))

; spatial-relation-context-value-has? : spatial-relation-context? symbol? -> boolean?
;;   Reports whether a declared immutable scene value exists.
(define (spatial-relation-context-value-has? context target)
  (define checked (checked-context 'spatial-relation-context-value-has? context))
  (check-value-target 'spatial-relation-context-value-has? target)
  (record-value-access! context target 'spatial-relation-context-value-has?)
  ((spatial-relation-context-value-value-has? checked) target))

; spatial-relation-context-value-ref : spatial-relation-context? symbol? -> any/c
;;   Reads one declared immutable scene value.
(define (spatial-relation-context-value-ref context target)
  (define checked (checked-context 'spatial-relation-context-value-ref context))
  (check-value-target 'spatial-relation-context-value-ref target)
  (record-value-access! context target 'spatial-relation-context-value-ref)
  ((spatial-relation-context-value-value-ref checked) target))

; spatial-relation-context-camera : spatial-relation-context? -> camera3d?
;;   Reads the owning view3d camera after declaring a matching camera dependency.
(define (spatial-relation-context-camera context)
  (define checked (checked-context 'spatial-relation-context-camera context))
  (define view-id (visual-id (spatial-relation-context-value-view checked)))
  (record-camera-access! context view-id)
  (view3d-camera (spatial-relation-context-value-view checked)))


;;;
;;; Dependency Matching
;;;

(define (checked-context who context)
  (unless (spatial-relation-context? context)
    (raise-argument-error who "spatial-relation-context?" context))
  context)

(define (context-ref who context accessor)
  (accessor (checked-context who context)))

(define (normalize-target context target who)
  (unless (and (list? target) (pair? target) (andmap symbol? target))
    (raise-argument-error who "nonempty list of symbols" target))
  (define view-id (visual-id (spatial-relation-context-value-view context)))
  (if (eq? (car target) view-id)
      target
      (cons view-id target)))

(define (check-value-target who target)
  (unless (symbol? target)
    (raise-argument-error who "symbol?" target)))

(define (record-spatial-access! context path who)
  (define declared
    (spatial-relation-context-value-declared (checked-context who context)))
  (define matching
    (for/first ([dependency (in-list declared)]
                #:when (and (spatial-visual-dependency? dependency)
                            (equal? (normalize-target context
                                                      (spatial-visual-dependency-target dependency)
                                                      who)
                                    path)))
      dependency))
  (unless matching
    (raise-arguments-error
     who
     "a spatial visual dependency declared by this relation"
     "relation-path" (spatial-relation-context-relation-path context)
     "read spatial-path" path
     "declared dependencies" declared))
  (record-use! context matching))

(define (record-value-access! context target who)
  (define declared
    (spatial-relation-context-value-declared (checked-context who context)))
  (define matching
    (for/first ([dependency (in-list declared)]
                #:when (and (spatial-value-dependency? dependency)
                            (eq? (spatial-value-dependency-target dependency) target)))
      dependency))
  (unless matching
    (raise-arguments-error
     who
     "a spatial value dependency declared by this relation"
     "relation-path" (spatial-relation-context-relation-path context)
     "read value" target
     "declared dependencies" declared))
  (record-use! context matching))

(define (record-camera-access! context view-id)
  (define declared
    (spatial-relation-context-value-declared
     (checked-context 'spatial-relation-context-camera context)))
  (define matching
    (for/first ([dependency (in-list declared)]
                #:when (and (spatial-camera-dependency? dependency)
                            (eq? (spatial-camera-dependency-view-id dependency)
                                 view-id)))
      dependency))
  (unless matching
    (raise-arguments-error
     'spatial-relation-context-camera
     "a spatial camera dependency declared by this relation"
     "relation-path" (spatial-relation-context-relation-path context)
     "camera view-id" view-id
     "declared dependencies" declared))
  (record-use! context matching))

(define (record-use! context dependency)
  (define used
    (spatial-relation-context-value-used
     (checked-context 'record-use! context)))
  (unless (member dependency (unbox used))
    (set-box! used (append (unbox used) (list dependency)))))
