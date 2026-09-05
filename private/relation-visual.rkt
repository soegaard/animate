#lang racket/base

;;;
;;; First-Class Relation Visuals
;;;

;; A relation is an immutable, explicitly dependent semantic Visual.  Its
;; resolver runs only while sampling a scene state; it is never a mutable frame
;; callback.  EL-1 supports semantic, root-only relations.  The stored template
;; supplies stable identity and the ordinary affine/opacity envelope. EL-3
;; additionally validates either root-only or fixed output structure.

(require "affine-transform.rkt"
         "derived-visual.rkt"
         "geometry.rkt"
         "interpolation.rkt"
         "path-geometry.rkt"
         "relation-context.rkt"
         "relation-dependency.rkt"
         "relation-spec.rkt"
         "resolvable-visual.rkt"
         "visual-model.rkt")

(provide relation-visual
         relation-visual?
         relation-visual-dependencies
         relation-visual-phase
         relation-visual-structure
         relation-visual-space
         relation-visual-cache-key
         relation-visual-cacheability
         resolve-relation-visual
         relation-path-reveal-visual?
         relation-path-reveal-visual-relation
         relation-path-reveal-visual-progress
         relation-path-reveal-visual-reverse?
         make-relation-path-reveal-visual
         resolve-relation-path-reveal-visual)

(define template-visual-id visual-id)
(define template-visual-position visual-position)
(define template-visual-with-position visual-with-position)
(define template-visual-transform visual-transform)
(define template-visual-with-transform visual-with-transform)
(define template-visual-opacity visual-opacity)
(define template-visual-with-opacity visual-with-opacity)
(define template-visual-fill-color visual-fill-color)
(define template-visual-with-fill-color visual-with-fill-color)
(define template-visual-stroke-color visual-stroke-color)
(define template-visual-with-stroke-color visual-with-stroke-color)
(define template-visual-stroke-width visual-stroke-width)
(define template-visual-with-stroke-width visual-with-stroke-width)
(define template-visual-child-entries visual-child-entries)
(define template-resolvable-visual-template resolvable-visual-template)
(define template-resolvable-visual-dependencies resolvable-visual-dependencies)
(define template-resolvable-visual-phase resolvable-visual-phase)

(define (phase? value)
  (memq value '(semantic layout)))

(define (structure? value)
  (memq value '(root-only fixed)))

(define (space? value)
  (memq value '(world local)))

;; The method declarations below refer to these bindings before the generated
;; relation struct accessors exist. Their implementations are installed just
;; after the struct definition.
(define relation-style-ref #f)
(define relation-style-set #f)

(struct relation-visual-value
  (template outer-transform outer-opacity style-overrides dependencies phase structure space
            cache-key resolver)
  #:transparent
  #:methods gen:visual
  [(define (visual-id relation)
     (template-visual-id (relation-visual-value-template relation)))
   (define (visual-position relation)
     (affine-transform-translation
      (relation-visual-value-outer-transform relation)))
   (define (visual-with-position relation position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy
      relation-visual-value
     relation
      [outer-transform
       (affine-transform-with-translation
        (relation-visual-value-outer-transform relation)
        position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform relation)
     (relation-visual-value-outer-transform relation))
   (define (visual-with-transform relation transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy
      relation-visual-value
     relation
      [outer-transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity relation)
     (relation-visual-value-outer-opacity relation))
   (define (visual-with-opacity relation opacity)
     (unless (opacity? opacity)
       (raise-argument-error 'visual-with-opacity "opacity?" opacity))
     (struct-copy
      relation-visual-value
     relation
     [outer-opacity opacity]))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color relation)
     (relation-style-ref relation 'fill fill-color-visual?
                         template-visual-fill-color))
   (define (visual-with-fill-color relation color)
     (relation-style-set relation 'fill color fill-color-visual?
                         template-visual-with-fill-color))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color relation)
     (relation-style-ref relation 'stroke stroke-color-visual?
                         template-visual-stroke-color))
   (define (visual-with-stroke-color relation color)
     (relation-style-set relation 'stroke color stroke-color-visual?
                         template-visual-with-stroke-color))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width relation)
     (relation-style-ref relation 'stroke-width stroke-width-visual?
                         template-visual-stroke-width))
   (define (visual-with-stroke-width relation width)
     (relation-style-set relation 'stroke-width width stroke-width-visual?
                         template-visual-with-stroke-width))]
  #:methods gen:visual-container
  [(define (visual-child-entries relation)
     ;; A fixed relation publishes its template tree for static path validation.
     ;; A root-only relation deliberately has no addressable descendants even
     ;; when the temporary concrete result happens to be a group.
     (define template (relation-visual-value-template relation))
     (if (and (eq? (relation-visual-value-structure relation) 'fixed)
              (visual-container? template))
         (template-visual-child-entries template)
         '()))]
  #:methods gen:resolvable-visual
  [(define (resolvable-visual-template relation)
     (relation-outer-template relation))
   (define (resolvable-visual-dependencies relation)
     (relation-visual-value-dependencies relation))
   (define (resolvable-visual-phase relation)
     (relation-visual-value-phase relation))
   (define (resolve-resolvable-visual relation context)
     (resolve-relation-visual relation context))])

(define (relation-visual? value)
  (relation-visual-value? value))

;; Relation style values live in the outer envelope just like affine placement
;; and opacity. The template advertises the capabilities an author may request;
;; resolution checks the concrete result again so a resolver cannot silently
;; discard a fill/stroke override by returning an incompatible Visual.
(set! relation-style-ref
      (lambda (relation key supported? getter)
        (define overrides (relation-visual-value-style-overrides relation))
        (cond
          [(hash-has-key? overrides key) (hash-ref overrides key)]
          [(supported? (relation-visual-value-template relation))
           (getter (relation-visual-value-template relation))]
          [else
           (raise-arguments-error
            'relation-visual
            "a relation template supporting the requested style capability"
            "relation-id" (visual-id relation)
            "style" key)])))

(set! relation-style-set
      (lambda (relation key value supported? setter)
        (define template (relation-visual-value-template relation))
        (unless (supported? template)
          (raise-arguments-error
           'relation-visual
           "a relation template supporting the requested style capability"
           "relation-id" (visual-id relation)
           "style" key))
        ;; Reuse the concrete protocol's own value validation without retaining
        ;; the temporary template result. The actual override is applied only
        ;; after a relation resolver has produced current concrete content.
        (void (setter template value))
        (struct-copy
         relation-visual-value relation
         [style-overrides
          (hash-set (relation-visual-value-style-overrides relation) key value)])))

;; A relation-path-reveal-visual is an internal deferred effect, rather than a
;; snapshot of path geometry taken when its clip is compiled.  Its wrapped
;; relation remains the persistent scene definition; each sampling pass first
;; resolves that relation against the current sampled dependencies and then
;; takes a prefix of the resulting path.  This is the essential distinction
;; between creating a moving relation and creating a static path that merely
;; happens to have started at the same coordinates.
(struct relation-path-reveal-visual-value (relation progress reverse?)
  #:transparent
  #:methods gen:visual
  [(define (visual-id effect)
     (template-visual-id
      (relation-path-reveal-visual-value-relation effect)))
   (define (visual-position effect)
     (template-visual-position
      (relation-path-reveal-visual-value-relation effect)))
   (define (visual-with-position effect position)
     (make-relation-path-reveal-visual
      (template-visual-with-position
       (relation-path-reveal-visual-value-relation effect)
       position)
      (relation-path-reveal-visual-value-progress effect)
      #:reverse? (relation-path-reveal-visual-value-reverse? effect)))]
  #:methods gen:affine-visual
  [(define (visual-transform effect)
     (template-visual-transform
      (relation-path-reveal-visual-value-relation effect)))
   (define (visual-with-transform effect transform)
     (make-relation-path-reveal-visual
      (template-visual-with-transform
       (relation-path-reveal-visual-value-relation effect)
       transform)
      (relation-path-reveal-visual-value-progress effect)
      #:reverse? (relation-path-reveal-visual-value-reverse? effect)))]
  #:methods gen:opacity-visual
  [(define (visual-opacity effect)
     (template-visual-opacity
      (relation-path-reveal-visual-value-relation effect)))
   (define (visual-with-opacity effect opacity)
     (make-relation-path-reveal-visual
      (template-visual-with-opacity
       (relation-path-reveal-visual-value-relation effect)
       opacity)
      (relation-path-reveal-visual-value-progress effect)
      #:reverse? (relation-path-reveal-visual-value-reverse? effect)))]
  #:methods gen:visual-container
  [(define (visual-child-entries effect)
     (template-visual-child-entries
      (relation-path-reveal-visual-value-relation effect)))]
  #:methods gen:resolvable-visual
  [(define (resolvable-visual-template effect)
     (template-resolvable-visual-template
      (relation-path-reveal-visual-value-relation effect)))
   (define (resolvable-visual-dependencies effect)
     (template-resolvable-visual-dependencies
      (relation-path-reveal-visual-value-relation effect)))
   (define (resolvable-visual-phase effect)
     (template-resolvable-visual-phase
      (relation-path-reveal-visual-value-relation effect)))
   (define (resolve-resolvable-visual effect context)
     (resolve-relation-path-reveal-visual effect context))])

(define (relation-path-reveal-visual? value)
  (relation-path-reveal-visual-value? value))

(define (relation-path-reveal-visual-relation effect)
  (unless (relation-path-reveal-visual? effect)
    (raise-argument-error
     'relation-path-reveal-visual-relation
     "relation-path-reveal-visual?"
     effect))
  (relation-path-reveal-visual-value-relation effect))

(define (relation-path-reveal-visual-progress effect)
  (unless (relation-path-reveal-visual? effect)
    (raise-argument-error
     'relation-path-reveal-visual-progress
     "relation-path-reveal-visual?"
     effect))
  (relation-path-reveal-visual-value-progress effect))

(define (relation-path-reveal-visual-reverse? effect)
  (unless (relation-path-reveal-visual? effect)
    (raise-argument-error
     'relation-path-reveal-visual-reverse?
     "relation-path-reveal-visual?"
     effect))
  (relation-path-reveal-visual-value-reverse? effect))

;; make-relation-path-reveal-visual : relation-visual? finite-real?
;;                                      [#:reverse? boolean?]
;;                                   -> relation-path-reveal-visual?
(define (make-relation-path-reveal-visual relation progress
                                           #:reverse? [reverse? #f])
  (unless (relation-visual? relation)
    (raise-argument-error
     'make-relation-path-reveal-visual "relation-visual?" relation))
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'make-relation-path-reveal-visual
     "finite real in [0, 1]"
     progress))
  (unless (boolean? reverse?)
    (raise-argument-error
     'make-relation-path-reveal-visual "boolean?" reverse?))
  (relation-path-reveal-visual-value relation progress reverse?))

;; relation-visual : visual? #:depends-on (listof relation-dependency?)
;;                   #:phase 'semantic #:structure 'root-only #:space 'world
;;                   #:cache-key any/c
;;                   (or/c relation-spec?
;;                         (-> relation-context? visual? visual?))
;;                   -> relation-visual?
(define (relation-visual template
                         #:depends-on [dependencies '()]
                         #:phase [phase 'semantic]
                         #:structure [structure 'root-only]
                         #:space [space 'world]
                         #:cache-key [cache-key #f]
                         resolver)
  (unless (visual? template)
    (raise-argument-error 'relation-visual "visual?" template))
  (when (resolvable-visual? template)
    (raise-arguments-error
     'relation-visual
     "the template must be a concrete Visual, not a resolvable Visual"
     "template" template))
  (unless (and (affine-visual? template) (opacity-visual? template))
    (raise-arguments-error
     'relation-visual
     "a concrete template supporting affine placement and opacity"
     "template" template))
  (unless (symbol? (visual-id template))
    (raise-arguments-error
     'relation-visual
     "a template Visual with a symbol identity"
     "visual-id" (visual-id template)))
  (unless (vec2? (visual-position template))
    (raise-arguments-error
     'relation-visual
     "a template Visual with a vec2 position"
     "visual-position" (visual-position template)))
  (unless (list? dependencies)
    (raise-argument-error 'relation-visual "list? as #:depends-on" dependencies))
  (for ([dependency (in-list dependencies)])
    (unless (relation-dependency? dependency)
      (raise-argument-error
       'relation-visual
       "relation-dependency? values in #:depends-on"
       dependency)))
  (unless (phase? phase)
    (raise-argument-error 'relation-visual "(or/c 'semantic 'layout)" phase))
  (unless (structure? structure)
    (raise-argument-error 'relation-visual "(or/c 'root-only 'fixed)" structure))
  (unless (space? space)
    (raise-argument-error 'relation-visual "(or/c 'world 'local)" space))
  (unless (or (relation-spec? resolver)
              (and (procedure? resolver)
                   (procedure-arity-includes? resolver 2)))
    (raise-argument-error
     'relation-visual
     "relation-spec? or procedure accepting relation-context? and template visual? arguments"
     resolver))
  ;; Split the authored Visual into a resolver-local template and an ordinary
  ;; outer envelope.  The resolver never has to remember a concurrent
  ;; move/rotate/scale/fade; its current local result is enveloped afterwards.
  (define outer-transform (template-visual-transform template))
  (define outer-opacity (template-visual-opacity template))
  (define local-template
    (template-visual-with-opacity
     (template-visual-with-transform template identity-affine-transform)
     1))
  (relation-visual-value
   local-template outer-transform outer-opacity (hash) dependencies phase structure
   space (or cache-key (and (relation-spec? resolver) resolver)) resolver))

(define (relation-visual-dependencies relation)
  (unless (relation-visual? relation)
    (raise-argument-error 'relation-visual-dependencies "relation-visual?" relation))
  (relation-visual-value-dependencies relation))

(define (relation-visual-phase relation)
  (unless (relation-visual? relation)
    (raise-argument-error 'relation-visual-phase "relation-visual?" relation))
  (relation-visual-value-phase relation))

(define (relation-visual-structure relation)
  (unless (relation-visual? relation)
    (raise-argument-error 'relation-visual-structure "relation-visual?" relation))
  (relation-visual-value-structure relation))

(define (relation-visual-space relation)
  (unless (relation-visual? relation)
    (raise-argument-error 'relation-visual-space "relation-visual?" relation))
  (relation-visual-value-space relation))

(define (relation-visual-cache-key relation)
  (unless (relation-visual? relation)
    (raise-argument-error 'relation-visual-cache-key "relation-visual?" relation))
  (relation-visual-value-cache-key relation))

;; relation-visual-cacheability : relation-visual?
;;                              -> (or/c 'serializable 'explicit-key 'disabled)
;; Built-in relation specifications are transparent immutable data. Generic
;; procedures remain valid but opaque unless the author takes responsibility
;; for a versioned cache key.
(define (relation-visual-cacheability relation)
  (unless (relation-visual? relation)
    (raise-argument-error
     'relation-visual-cacheability "relation-visual?" relation))
  (cond
    [(relation-spec? (relation-visual-value-resolver relation)) 'serializable]
    [(relation-visual-value-cache-key relation) 'explicit-key]
    [else 'disabled]))

;; resolve-relation-visual : relation-visual? derived-context?
;;                           [#:anchor-ref (or/c false/c procedure?)]
;;                           [#:on-context (or/c false/c procedure?)] -> visual?
;; Shared result validation for the semantic scene resolver and the later
;; renderer-aware layout phase. The semantic generic invokes it without an
;; anchor callback; the Pict adapter supplies one for `'layout` relations.
(define (resolve-relation-visual relation context
                                 #:anchor-ref [anchor-ref #f]
                                 #:layout-box-ref [layout-box-ref #f]
                                 #:selection-box-ref [selection-box-ref #f]
                                 #:on-context [on-context #f])
  (unless (relation-visual? relation)
    (raise-argument-error 'resolve-relation-visual "relation-visual?" relation))
  (unless (derived-context? context)
    (raise-argument-error 'resolve-relation-visual "derived-context?" context))
  (unless (or (not on-context)
              (procedure-arity-includes? on-context 1))
    (raise-argument-error
     'resolve-relation-visual
     "#f or procedure accepting a relation-context?"
     on-context))
  (define template (relation-visual-value-template relation))
  (define relation-context
    (make-relation-context
     context
     (visual-id template)
     (relation-visual-value-dependencies relation)
     #:anchor-ref anchor-ref
     #:layout-box-ref layout-box-ref
     #:selection-box-ref selection-box-ref))
  (define resolver (relation-visual-value-resolver relation))
  (define result
    (if (relation-spec? resolver)
        (resolve-relation-spec resolver relation-context template)
        (resolver relation-context template)))
  (unless (visual? result)
    (raise-arguments-error
     'resolve-relation-visual
     "a relation resolver must return a Visual"
     "visual-id" (visual-id template)
     "result" result))
  (when (resolvable-visual? result)
    (raise-arguments-error
     'resolve-relation-visual
     "a relation resolver must return a concrete Visual, not another resolvable Visual"
     "visual-id" (visual-id template)
     "result" result))
  (unless (eq? (visual-id result) (visual-id template))
    (raise-arguments-error
     'resolve-relation-visual
     "the resolved relation must preserve its template Visual ID"
     "expected visual-id" (visual-id template)
     "resolved visual-id" (visual-id result)))
  (unless (vec2? (visual-position result))
    (raise-arguments-error
     'resolve-relation-visual
     "the resolved relation must return a vec2 Visual position"
     "visual-id" (visual-id template)
     "visual-position" (visual-position result)))
  (when (and (eq? (relation-visual-value-structure relation) 'fixed)
             (not (equal? (visual-tree-signature template)
                          (visual-tree-signature result))))
    (raise-arguments-error
     'resolve-relation-visual
     "a fixed relation result with exactly the template child-ID tree"
     "visual-id" (visual-id template)
     "expected tree" (visual-tree-signature template)
     "result tree" (visual-tree-signature result)))
  ;; Inspection is an observation of the per-resolution context, not a second
  ;; resolver invocation. Calling this after validation ensures an observer
  ;; never reports dependency use for a malformed relation result.
  (when on-context (on-context relation-context))
  (apply-relation-envelope relation result))

;; resolve-relation-path-reveal-visual : relation-path-reveal-visual?
;;                                         derived-context?
;;                                         [#:anchor-ref procedure?]
;;                                         [#:selection-box-ref procedure?]
;;                                      -> path-visual?
;; Performs deferred path sampling after the wrapped relation has calculated
;; its *current* concrete geometry.  The effect intentionally supports only
;; path results in this first pass: a generic group reveal needs a separate
;; document-order policy rather than pretending every relation is one path.
(define (resolve-relation-path-reveal-visual effect context
                                              #:anchor-ref [anchor-ref #f]
                                              #:layout-box-ref [layout-box-ref #f]
                                              #:selection-box-ref
                                              [selection-box-ref #f])
  (unless (relation-path-reveal-visual? effect)
    (raise-argument-error
     'resolve-relation-path-reveal-visual
     "relation-path-reveal-visual?"
     effect))
  (define relation
    (relation-path-reveal-visual-value-relation effect))
  (define concrete
    (resolve-relation-visual
     relation context
     #:anchor-ref anchor-ref
     #:layout-box-ref layout-box-ref
     #:selection-box-ref selection-box-ref))
  (unless (path-visual? concrete)
    (raise-arguments-error
     'resolve-relation-path-reveal-visual
     "a relation that resolves to a path Visual for create/uncreate"
     "relation-id" (visual-id relation)
     "resolved-visual" concrete))
  (define progress
    (relation-path-reveal-visual-value-progress effect))
  (define visible-fraction
    (if (relation-path-reveal-visual-value-reverse? effect)
        (- 1 progress)
        progress))
  (path-visual-with-path
   concrete
   (path-geometry-partial
    (path-visual-path concrete)
    0
    visible-fraction)))

;; visual-tree-signature : visual? -> immutable semantic tree datum
;; Child IDs and order are the fixed-relation contract.  Geometry, style, and
;; transforms deliberately do not appear: those are legitimate resolver output.
(define (visual-tree-signature visual)
  (cons
   (visual-id visual)
   (if (visual-container? visual)
       (for/list ([child (in-list (visual-child-entries visual))])
         (visual-tree-signature (visual-child-visual child)))
       '())))

;; relation-outer-template : relation-visual? -> visual?
;; Reconstructs the relation's visible template as local content under its
;; current animation/group envelope.  This is useful only for internal generic
;; inspection; resolver evaluation always receives the local template.
(define (relation-outer-template relation)
  (apply-relation-envelope
   relation
   (relation-visual-value-template relation)))

;; apply-relation-envelope : relation-visual? concrete affine/opacity visual?
;;                            -> concrete visual?
;; Applies the current outer transform and opacity after each resolver result.
;; This gives ordinary envelope animation well-defined semantics even while the
;; resolver's dependencies independently change local geometry.
(define (apply-relation-envelope relation visual)
  (unless (and (affine-visual? visual) (opacity-visual? visual))
    (raise-arguments-error
     'resolve-relation-visual
     "a relation result supporting affine placement and opacity"
     "relation" (visual-id relation)
     "result" visual))
  (define outer (relation-visual-value-outer-transform relation))
  (define local (visual-transform visual))
  (define composed
    (make-affine-transform
     #:translation
     (affine-transform-apply-point
      outer (affine-transform-translation local))
     #:rotation
     (+ (affine-transform-rotation outer)
        (affine-transform-rotation local))
     #:scale
     (vec2* (affine-transform-scale outer)
            (affine-transform-scale local))))
  (define transformed (visual-with-transform visual composed))
  (define styled
    (apply-relation-style-overrides relation transformed))
  (define result
    (visual-with-opacity
     styled
     (* (relation-visual-value-outer-opacity relation)
        (visual-opacity styled))))
  (unless (and (visual? result)
               (eq? (visual-id result) (visual-id relation)))
    (raise-arguments-error
     'resolve-relation-visual
     "relation envelope application preserving concrete Visual identity"
     "relation" (visual-id relation)
     "result" result))
  result)

(define (apply-relation-style-overrides relation visual)
  (for/fold ([current visual])
            ([key (in-list '(fill stroke stroke-width))])
    (define overrides (relation-visual-value-style-overrides relation))
    (cond
      [(not (hash-has-key? overrides key)) current]
      [(eq? key 'fill)
       (unless (fill-color-visual? current)
         (raise-relation-style-capability-error relation key current))
       (visual-with-fill-color current (hash-ref overrides key))]
      [(eq? key 'stroke)
       (unless (stroke-color-visual? current)
         (raise-relation-style-capability-error relation key current))
       (visual-with-stroke-color current (hash-ref overrides key))]
      [(eq? key 'stroke-width)
       (unless (stroke-width-visual? current)
         (raise-relation-style-capability-error relation key current))
       (visual-with-stroke-width current (hash-ref overrides key))]
      [else
       (error 'apply-relation-style-overrides "internal unsupported relation style")])))

(define (raise-relation-style-capability-error relation key result)
  (raise-arguments-error
   'resolve-relation-visual
   "a relation result supporting a style requested through its template"
   "relation-id" (visual-id relation)
   "style" key
   "resolved-visual" result))
