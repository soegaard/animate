#lang racket/base

;;;
;;; Scene State Model
;;;

;; Defines immutable snapshots of the top-level Visuals and named semantic values
;; in a scene.
;;
;; Scene state preserves an explicit back-to-front drawing order independently
;; of its Visual identity lookup table. Named values share the global scene ID
;; namespace with Visuals. They are not drawn directly, but derived Visuals may
;; resolve their concrete geometry/style from values and other top-level Visuals
;; in the same sampled immutable state.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "derived-visual.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "interpolation.rkt"
         "parameter.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out scene-state)
         empty-scene-state
         scene-state-count
         scene-state-has?
         scene-state-ref
         scene-state-add
         scene-state-remove
         scene-state-update
         scene-state-visuals-in-drawing-order
         scene-state-resolved-ref
         scene-state-resolved-world-ref
         scene-state-resolved-visuals-in-drawing-order
         scene-state-value-has?
         scene-state-value-ref
         scene-state-value-set
         scene-state-value-remove)


;;;
;;; Data Representation
;;;

(struct scene-state (visuals-by-id drawing-order values-by-id)
  #:transparent)

;; scene-state represents one immutable scene snapshot.
;;  - visuals-by-id  immutable hash?    maps ids to top-level Visual values.
;;  - drawing-order  (listof symbol?)   ids in back-to-front painting order.
;;                                     Ordering is significant.
;;  - values-by-id   immutable hash?    maps ids to interpolable semantic values.


;;;
;;; Constants
;;;

; empty-scene-state : scene-state?
;;   Gives an empty immutable scene state.
(define empty-scene-state
  (scene-state (hash) '() (hash)))


;;;
;;; Lookup
;;;

; scene-state-count : scene-state? -> exact-nonnegative-integer?
;;   Returns the number of top-level Visuals in state.
(define (scene-state-count state)
  (hash-count (scene-state-visuals-by-id state)))

; scene-state-has? : scene-state? (or/c visual? symbol? visual-path?) -> boolean?
;;   Reports whether state contains target at its top-level or nested path.
(define (scene-state-has? state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-has? "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-has?))
  (with-handlers ([exn:fail? (lambda (ignored) #f)])
    (scene-state-ref state path)
    #t))

; scene-state-ref : scene-state? (or/c visual? symbol? visual-path?) -> visual?
;;   Returns the stored Visual identified by target. Nested paths return their
;; locally stored child Visual, without inheriting ancestor transforms.
(define (scene-state-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-ref "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-ref))
  (define root
    (hash-ref
     (scene-state-visuals-by-id state)
     (car path)
     (lambda ()
       (raise-arguments-error
        'scene-state-ref
        "the Visual path is not present in the scene"
        "visual-path" path))))
  (visual-descendant-ref root (cdr path) path 'scene-state-ref))

; visual-descendant-ref : visual? (listof symbol?) visual-path? symbol? -> visual?
;; Resolves descendant IDs through built-in semantic groups and formula assemblies.
(define (visual-descendant-ref visual descendant-ids full-path who)
  (cond
    [(null? descendant-ids)
     visual]
    [(not (composite-visual? visual))
     (raise-arguments-error
      who
      "an intermediate Visual path entry must name a built-in group or formula assembly"
      "visual-path" full-path
      "visual" visual)]
    [else
     (define child-id (car descendant-ids))
     (define child
       (for/first ([candidate (in-list (composite-visual-children visual))]
                   #:when (eq? (visual-id candidate) child-id))
         candidate))
     (unless child
       (raise-arguments-error
        who
        "the Visual path is not present in the scene"
        "visual-path" full-path
        "missing-visual-id" child-id))
     (visual-descendant-ref child (cdr descendant-ids) full-path who)]))

; composite-visual? : any/c -> boolean?
;; Reports whether visual exposes built-in stable child identities.
(define (composite-visual? visual)
  (or (group-visual? visual)
      (formula-assembly-visual? visual)))

; composite-visual-children : composite-visual? -> (listof visual?)
;; Returns one composite's significant local children in drawing order.
(define (composite-visual-children visual)
  (cond
    [(group-visual? visual)
     (group-visual-children visual)]
    [(formula-assembly-visual? visual)
     (group-visual-children
      (formula-assembly-visual-group visual))]
    [else
     (raise-argument-error
      'composite-visual-children
      "(or/c group-visual? formula-assembly-visual?)"
      visual)]))

; composite-visual-with-children : composite-visual? (listof visual?) symbol?
;;                                   -> composite-visual?
;; Rebuilds a group or formula assembly while retaining its outer identity and
;; transform. Formula assemblies retain the exact formula-part local names.
(define (composite-visual-with-children visual children who)
  (cond
    [(group-visual? visual)
     (group-visual-with-children visual children)]
    [(formula-assembly-visual? visual)
     (define parts
       (for/list ([child (in-list children)])
         (unless (formula-visual? child)
           (raise-arguments-error
            who
            "formula assembly children must remain formula Visuals"
            "assembly-id" (visual-id visual)
            "child" child))
         (formula-part (visual-id child) child)))
     (formula-assembly-visual-with-parts visual parts)]
    [else
     (raise-argument-error
      who
      "(or/c group-visual? formula-assembly-visual?)"
      visual)]))

; scene-state-visuals-in-drawing-order : scene-state? -> (listof visual?)
;;   Returns top-level Visuals in significant back-to-front order.
(define (scene-state-visuals-in-drawing-order state)
  (for/list ([id (in-list (scene-state-drawing-order state))])
    (hash-ref (scene-state-visuals-by-id state) id)))



; make-scene-state-resolver : scene-state? -> (-> symbol? visual?)
;;   Creates one local dependency resolver for a sampled immutable state.
;;   Resolution is memoized only for this traversal. The stored scene state and
;;   derived definitions are never mutated or replaced by concrete results.
(define (make-scene-state-resolver state)
  (define cache (make-hasheq))
  (define active '())

  (define (cycle-for id)
    (define tail (memq id active))
    (if tail
        (append tail (list id))
        (append active (list id))))

  (define context
    (make-derived-context
     (lambda (id)
       (scene-state-value-has? state id))
     (lambda (id)
       (scene-state-value-ref state id))
     (lambda (target)
       (scene-state-has? state target))
     (lambda (target)
       (resolve-target-world target))))

  (define (resolve-id id)
    (unless (symbol? id)
      (raise-argument-error 'scene-state-resolved-ref "symbol?" id))
    (cond
      [(hash-has-key? cache id)
       (hash-ref cache id)]
      [(memq id active)
       (raise-arguments-error
        'scene-state-resolved-ref
        "derived Visual dependency cycle"
        "cycle" (cycle-for id))]
      [else
       (define visual
         (scene-state-ref state id))
       (define resolved
         (if (derived-visual? visual)
             (let ([saved-active active])
               (set! active (append active (list id)))
               (dynamic-wind
                 void
                 (lambda ()
                   (resolve-derived-visual visual context))
                 (lambda ()
                   (set! active saved-active))))
             visual))
       (hash-set! cache id resolved)
       resolved]))

  (define (resolve-target target)
    (define path
      (visual-target-path target 'scene-state-resolved-ref))
    (visual-descendant-ref
     (resolve-id (car path))
     (cdr path)
     path
     'scene-state-resolved-ref))

  (define (resolve-target-world target)
    (define path
      (visual-target-path target 'scene-state-resolved-ref))
    (resolved-world-descendant-ref
     (resolve-id (car path))
     (cdr path)
     path))

  resolve-target)

; scene-state-resolved-ref : scene-state? (or/c visual? symbol? visual-path?) -> visual?
;;   Resolves target against the state. Ordinary Visuals are returned unchanged;
;;   derived Visual definitions may recursively resolve top-level dependencies.
(define (scene-state-resolved-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-resolved-ref "scene-state?" state))
  ((make-scene-state-resolver state) target))

; scene-state-resolved-world-ref : scene-state?
;                                  (or/c visual? symbol? visual-path?) -> visual?
;;   Resolves a target and composes every enclosing group/formula transform and
;;   opacity into its returned Visual.  Unlike scene-state-resolved-ref, a
;;   nested result is ready to be rendered as an independent top-level layer.
(define (scene-state-resolved-world-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-resolved-world-ref "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-resolved-world-ref))
  (define resolve-id
    (make-scene-state-resolver state))
  (resolved-world-descendant-ref
   (resolve-id (car path))
   (cdr path)
   path))

; resolved-world-descendant-ref : visual? (listof symbol?) visual-path? -> visual?
;;   Descends through a Visual tree after each parent has resolved the next
;;   child's inherited transform and opacity.
(define (resolved-world-descendant-ref visual descendant-ids full-path)
  (cond
    [(null? descendant-ids) visual]
    [(not (composite-visual? visual))
     (raise-arguments-error
      'scene-state-resolved-world-ref
      "an intermediate Visual path entry must name a built-in group or formula assembly"
      "visual-path" full-path
      "visual" visual)]
    [else
     (define child-id (car descendant-ids))
     (define child
       (for/first ([candidate
                    (in-list
                     (composite-visual-world-children visual))]
                   #:when (eq? (visual-id candidate) child-id))
         candidate))
     (unless child
       (raise-arguments-error
        'scene-state-resolved-world-ref
        "the Visual path is not present in the scene"
        "visual-path" full-path
        "missing-visual-id" child-id))
     (resolved-world-descendant-ref child (cdr descendant-ids) full-path)]))

; composite-visual-world-children : composite-visual? -> (listof visual?)
;;   Returns children with the complete enclosing affine transform and opacity
;;   composed into their local values.  Group rendering intentionally leaves a
;;   parent translation to Pict composition; an independently rendered copy
;;   cannot do that, so this helper uses affine-transform-apply-point directly.
(define (composite-visual-world-children visual)
  (define parent-transform
    (visual-transform visual))
  (for/list ([child (in-list (composite-visual-children visual))])
    (unless (affine-visual? child)
      (raise-arguments-error
       'scene-state-resolved-world-ref
       "a composite child that supports affine placement"
       "parent" visual
       "child" child))
    (define child-transform
      (visual-transform child))
    (define transformed-child
      (visual-with-transform
       child
       (make-affine-transform
        #:translation
        (affine-transform-apply-point
         parent-transform
         (affine-transform-translation child-transform))
        #:rotation
        (+ (affine-transform-rotation parent-transform)
           (affine-transform-rotation child-transform))
        #:scale
        (vec2* (affine-transform-scale parent-transform)
               (affine-transform-scale child-transform)))))
    (if (and (opacity-visual? visual)
             (opacity-visual? transformed-child))
        (visual-with-opacity
         transformed-child
         (* (visual-opacity visual) (visual-opacity transformed-child)))
        transformed-child)))

; scene-state-resolved-visuals-in-drawing-order : scene-state? -> (listof visual?)
;;   Returns concrete top-level Visuals in significant back-to-front order.
;;   All entries share one local dependency-resolution session so a dependency
;;   used by several derived Visuals is resolved consistently once per traversal.
(define (scene-state-resolved-visuals-in-drawing-order state)
  (unless (scene-state? state)
    (raise-argument-error
     'scene-state-resolved-visuals-in-drawing-order
     "scene-state?"
     state))
  (define resolve-id
    (make-scene-state-resolver state))
  (for/list ([id (in-list (scene-state-drawing-order state))])
    (resolve-id id)))

;;;
;;; Immutable Updates
;;;

; scene-state-add : scene-state? visual? -> scene-state?
;;   Adds visual as the frontmost top-level Visual.
(define (scene-state-add state visual)
  (unless (visual? visual)
    (raise-argument-error 'scene-state-add "visual?" visual))
  (define id
    (visual-target-id visual 'scene-state-add))
  (when (hash-has-key? (scene-state-visuals-by-id state) id)
    (raise-arguments-error
     'scene-state-add
     "a visual with this ID is already present"
     "visual-id" id))
  (when (hash-has-key? (scene-state-values-by-id state) id)
    (raise-arguments-error
     'scene-state-add
     "a named scene value with this ID is already present"
     "id" id))
  (scene-state
   (hash-set (scene-state-visuals-by-id state) id visual)
   (append (scene-state-drawing-order state) (list id))
   (scene-state-values-by-id state)))

; scene-state-remove : scene-state? (or/c visual? symbol? visual-path?) -> scene-state?
;;   Removes target while preserving the order of remaining visuals.
(define (scene-state-remove state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-remove "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-remove))
  (define root-id (car path))
  (define root
    (hash-ref
     (scene-state-visuals-by-id state)
     root-id
     (lambda ()
       (raise-arguments-error
        'scene-state-remove
        "the Visual path is not present in the scene"
        "visual-path" path))))
  (if (null? (cdr path))
      (scene-state
       (hash-remove (scene-state-visuals-by-id state) root-id)
       (filter (lambda (existing-id)
                 (not (eq? existing-id root-id)))
               (scene-state-drawing-order state))
       (scene-state-values-by-id state))
      (scene-state
       (hash-set
        (scene-state-visuals-by-id state)
        root-id
        (remove-visual-descendant root (cdr path) path 'scene-state-remove))
       (scene-state-drawing-order state)
       (scene-state-values-by-id state))))

; scene-state-update : scene-state? (or/c visual? symbol? visual-path?) visual?
;                       -> scene-state?
;;   Replaces target without changing its identity or drawing order.
(define (scene-state-update state target replacement)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-update "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-update))
  (define root-id (car path))
  (define target-id (car (reverse path)))
  (unless (visual? replacement)
    (raise-argument-error 'scene-state-update "visual?" replacement))
  (unless (eq? target-id (visual-id replacement))
    (raise-arguments-error
     'scene-state-update
     "the replacement must preserve the visual ID"
     "expected visual-id" target-id
     "replacement visual-id" (visual-id replacement)))
  (define root
    (hash-ref
     (scene-state-visuals-by-id state)
     root-id
     (lambda ()
       (raise-arguments-error
        'scene-state-update
        "the Visual path is not present in the scene"
        "visual-path" path))))
  (scene-state
   (hash-set
    (scene-state-visuals-by-id state)
    root-id
    (if (null? (cdr path))
        replacement
        (replace-visual-descendant
         root (cdr path) replacement path 'scene-state-update)))
   (scene-state-drawing-order state)
   (scene-state-values-by-id state)))

; replace-visual-descendant : composite-visual? (listof symbol?) visual? visual-path?
;                             symbol? -> composite-visual?
;; Rebuilds the ancestor composite chain with one descendant replaced.
(define (replace-visual-descendant composite descendant-ids replacement full-path who)
  (unless (composite-visual? composite)
    (raise-arguments-error
     who
     "an intermediate Visual path entry must name a built-in group or formula assembly"
     "visual-path" full-path
     "visual" composite))
  (define child-id (car descendant-ids))
  (define found? #f)
  (define children
    (for/list ([child (in-list (composite-visual-children composite))])
      (if (eq? (visual-id child) child-id)
          (begin
            (set! found? #t)
            (if (null? (cdr descendant-ids))
                replacement
                (replace-visual-descendant
                 child (cdr descendant-ids) replacement full-path who)))
          child)))
  (unless found?
    (raise-arguments-error
     who
     "the Visual path is not present in the scene"
     "visual-path" full-path
     "missing-visual-id" child-id))
  (composite-visual-with-children composite children who))

; remove-visual-descendant : composite-visual? (listof symbol?) visual-path? symbol?
;                            -> composite-visual?
;; Rebuilds the ancestor composite chain with one descendant removed.
(define (remove-visual-descendant composite descendant-ids full-path who)
  (unless (composite-visual? composite)
    (raise-arguments-error
     who
     "an intermediate Visual path entry must name a built-in group or formula assembly"
     "visual-path" full-path
     "visual" composite))
  (define child-id (car descendant-ids))
  (define found? #f)
  (define children
    (for/list ([child (in-list (composite-visual-children composite))]
               #:unless (and (eq? (visual-id child) child-id)
                             (null? (cdr descendant-ids))))
      (cond
        [(eq? (visual-id child) child-id)
         (set! found? #t)
         (remove-visual-descendant child (cdr descendant-ids) full-path who)]
        [else
         child])))
  (when (and (null? (cdr descendant-ids))
             (for/or ([child (in-list (composite-visual-children composite))])
               (eq? (visual-id child) child-id)))
    (set! found? #t))
  (unless found?
    (raise-arguments-error
     who
     "the Visual path is not present in the scene"
     "visual-path" full-path
     "missing-visual-id" child-id))
  (composite-visual-with-children composite children who))


;;;
;;; Named Scene Values
;;;

; scene-state-value-has? : scene-state? (or/c symbol? scene-parameter?) -> boolean?
;;   Reports whether state contains one named semantic value.
(define (scene-state-value-has? state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-has? "scene-state?" state))
  (hash-has-key?
   (scene-state-values-by-id state)
   (parameter-target-id target 'scene-state-value-has?)))

; scene-state-value-ref : scene-state? (or/c symbol? scene-parameter?) -> interpolable?
;;   Returns one named semantic value.
(define (scene-state-value-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-ref "scene-state?" state))
  (define id
    (parameter-target-id target 'scene-state-value-ref))
  (define value
    (hash-ref
     (scene-state-values-by-id state)
     id
     (lambda ()
       (raise-arguments-error
        'scene-state-value-ref
        "the named scene value is not present in the scene"
        "value-id" id))))
  (unless (interpolable? value)
    (raise-arguments-error
     'scene-state-value-ref
     "the scene state must contain an interpolable semantic value"
     "value-id" id
     "value" value))
  value)

; scene-state-value-set : scene-state? (or/c symbol? scene-parameter?) interpolable? -> scene-state?
;;   Adds or replaces one named semantic value while preserving Visual state.
(define (scene-state-value-set state target value)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-set "scene-state?" state))
  (define id
    (parameter-target-id target 'scene-state-value-set))
  (unless (interpolable? value)
    (raise-argument-error 'scene-state-value-set "interpolable?" value))
  (when (hash-has-key? (scene-state-visuals-by-id state) id)
    (raise-arguments-error
     'scene-state-value-set
     "a Visual with this ID is already present"
     "id" id))
  (scene-state
   (scene-state-visuals-by-id state)
   (scene-state-drawing-order state)
   (hash-set (scene-state-values-by-id state) id value)))

; scene-state-value-remove : scene-state? (or/c symbol? scene-parameter?) -> scene-state?
;;   Removes one named semantic value.
(define (scene-state-value-remove state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-remove "scene-state?" state))
  (define id
    (parameter-target-id target 'scene-state-value-remove))
  (unless (hash-has-key? (scene-state-values-by-id state) id)
    (raise-arguments-error
     'scene-state-value-remove
     "the named scene value is not present in the scene"
     "value-id" id))
  (scene-state
   (scene-state-visuals-by-id state)
   (scene-state-drawing-order state)
   (hash-remove (scene-state-values-by-id state) id)))
