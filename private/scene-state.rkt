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
(require "affine-map-visual.rkt"
         "affine-transform.rkt"
         "derived-visual.rkt"
         "formula-parts-visual.rkt"
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "interpolation.rkt"
         "parameter.rkt"
         "relation-visual.rkt"
         "resolvable-visual.rkt"
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
         scene-state-resolved-world-refs
         scene-state-parent-affine-map
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

;; scene-state-parent-affine-map : scene-state? visual-path? -> affine2?
;; Returns the complete affine map from a target's containing coordinate system
;; to world coordinates. A root target has the identity parent map. Nested
;; world-coordinate requests use this to rebase a requested map into the local
;; coordinate system without losing enclosing semantic affine wrappers.
(define (scene-state-parent-affine-map state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-parent-affine-map "scene-state?" state))
  (define path
    (visual-target-path target 'scene-state-parent-affine-map))
  (define root
    (hash-ref
     (scene-state-visuals-by-id state)
     (car path)
     (lambda ()
       (raise-arguments-error
        'scene-state-parent-affine-map
        "the Visual path is present in the scene"
        "visual-path" path))))
  (let loop ([visual root]
             [descendant-ids (cdr path)]
             [parent-map identity-affine2])
    (cond
      [(null? descendant-ids)
       parent-map]
      [(not (composite-visual? visual))
       (raise-arguments-error
        'scene-state-parent-affine-map
        "an intermediate Visual path entry naming a built-in composite"
        "visual-path" path
        "visual" visual)]
      [else
       (define child-id (car descendant-ids))
       (define child
         (for/first ([candidate (in-list (composite-visual-children visual))]
                     #:when (eq? (visual-id candidate) child-id))
           candidate))
       (unless child
         (raise-arguments-error
          'scene-state-parent-affine-map
          "the Visual path is present in the scene"
          "visual-path" path
          "missing-visual-id" child-id))
       (loop child
             (cdr descendant-ids)
             (affine2-compose parent-map
                              (visual-local-affine-map visual)))])))

;; visual-local-affine-map : affine-visual? -> affine2?
;; Gives one node's semantic map from its own local coordinates to the
;; coordinates of its containing composite.
(define (visual-local-affine-map visual)
  (cond
    [(affine-map-visual? visual)
     (affine-map-visual-map visual)]
    [(affine-visual? visual)
     (affine-transform->affine2 (visual-transform visual))]
    [else
     (raise-arguments-error
      'scene-state-parent-affine-map
      "an affine Visual in every enclosing path position"
      "visual" visual)]))

; visual-descendant-ref : visual? (listof symbol?) visual-path? symbol? -> visual?
;; Resolves descendant IDs through Visuals that publish a stable child tree.
;; This includes a fixed relation's declared template tree; root-only relations
;; publish no descendants and are rejected explicitly before this traversal.
(define (visual-descendant-ref visual descendant-ids full-path who)
  (cond
    [(null? descendant-ids)
     visual]
    [(not (composite-visual? visual))
     (raise-arguments-error
      who
        "an intermediate Visual path entry must publish stable child identities"
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
;; Reports whether visual exposes stable child identities.  The generic is
;; deliberately broader than groups/formulas so a fixed relation's template
;; tree is targetable by the same path machinery.
(define (composite-visual? visual)
  (or (visual-container? visual)
      (and (affine-map-visual? visual)
           (composite-visual? (affine-map-visual-content visual)))))

; composite-visual-children : composite-visual? -> (listof visual?)
;; Returns one composite's significant local children in drawing order.
(define (composite-visual-children visual)
  (cond
    [(group-visual? visual)
     (group-visual-children visual)]
    [(formula-assembly-visual? visual)
     (group-visual-children
      (formula-assembly-visual-group visual))]
    [(affine-map-visual? visual)
     (composite-visual-children (affine-map-visual-content visual))]
    [(visual-container? visual)
     (for/list ([entry (in-list (visual-child-entries visual))])
       (visual-child-visual entry))]
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
    [(affine-map-visual? visual)
     (affine-map-visual-with-content
      visual
      (composite-visual-with-children
       (affine-map-visual-content visual)
       children
       who))]
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



; make-scene-state-resolver : scene-state? -> (values local-resolver world-resolver)
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
       ;; A nested resolver must see the stored graph/group tree while another
       ;; child is resolving. Resolving the entire root tree here would revisit
       ;; sibling derived edges and create an artificial cycle.
       (resolve-target-world/raw target))))

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
         (if (and (resolvable-visual? visual)
                  (eq? (resolvable-visual-phase visual) 'semantic))
             (let ([saved-active active])
               (set! active (append active (list id)))
               (dynamic-wind
                 void
                 (lambda ()
                   (resolve-resolvable-visual visual context))
                 (lambda ()
                   (set! active saved-active))))
             visual))
       (hash-set! cache id resolved)
       resolved]))

  ;; Resolve one derived child at a time, recursively rebuilding ordinary
  ;; groups only for the public sampled result. Stored scene state is never
  ;; changed. This supports derived children such as live graph edges while
  ;; retaining normal group rendering and nested lookup.
  (define (resolve-visual-tree visual)
    (cond
      [(and (resolvable-visual? visual)
            (eq? (resolvable-visual-phase visual) 'semantic))
       (resolve-visual-tree
        (resolve-resolvable-visual visual context))]
      [(group-visual? visual)
       (group-visual-with-children
        visual
        (for/list ([child (in-list (group-visual-children visual))])
          (resolve-visual-tree child)))]
      [(affine-map-visual? visual)
       (affine-map-visual-with-content
        visual
        (resolve-visual-tree (affine-map-visual-content visual)))]
      [else
       visual]))

  ;; These raw lookups are used only by the derived context above. In
  ;; particular, resolving a graph edge asks for a vertex without eagerly
  ;; resolving every sibling edge in the graph's `edges` group.
  (define (resolve-target/raw target)
    (define path
      (visual-target-path target 'scene-state-resolved-ref))
    (check-root-only-relation-target state path 'scene-state-resolved-ref)
    (visual-descendant-ref
     (resolve-id (car path))
     (cdr path)
     path
     'scene-state-resolved-ref))

  (define (resolve-target-world/raw target)
    (define path
      (visual-target-path target 'scene-state-resolved-ref))
    (check-root-only-relation-target state path 'scene-state-resolved-ref)
    (resolved-world-descendant-ref
     (resolve-id (car path))
     (cdr path)
     path))

  (define (resolve-target target)
    (define path
      (visual-target-path target 'scene-state-resolved-ref))
    (check-root-only-relation-target state path 'scene-state-resolved-ref)
    (visual-descendant-ref
     (resolve-visual-tree (resolve-id (car path)))
     (cdr path)
     path
     'scene-state-resolved-ref))

  (define (resolve-target-world target)
    (define path
      (visual-target-path target 'scene-state-resolved-world-ref))
    (check-root-only-relation-target state path
                                     'scene-state-resolved-world-ref)
    (resolved-world-descendant-ref
     (resolve-visual-tree (resolve-id (car path)))
     (cdr path)
     path))

  (values resolve-target resolve-target-world))

;; Reject paths that descend through a root-only relation before resolving its
;; concrete output.  Otherwise a transient group returned on one sampled frame
;; would accidentally make its temporary children public stable targets.
(define (check-root-only-relation-target state path who)
  (define root (scene-state-ref state (car path)))
  (let loop ([visual root] [remaining (cdr path)] [prefix (list (car path))])
    (cond
      [(and (relation-root-only? visual)
            (pair? remaining))
       (raise-arguments-error
        who
        "a root-only relation targeted only at its stable root"
        "relation path" prefix
        "requested visual-path" path)]
      [(null? remaining) (void)]
      [(affine-map-visual? visual)
       (loop (affine-map-visual-content visual) remaining prefix)]
      [(visual-container? visual)
       (define next-id (car remaining))
       (define child
         (for/first ([entry (in-list (visual-child-entries visual))]
                     #:when (eq? (visual-child-id entry) next-id))
           (visual-child-visual entry)))
       ;; Let ordinary path lookup issue its established missing-child error.
       (when child
         (loop child (cdr remaining) (append prefix (list next-id))))]
      [else (void)])))

(define (relation-root-only? visual)
  (define relation
    (if (relation-path-reveal-visual? visual)
        (relation-path-reveal-visual-relation visual)
        visual))
  (and (relation-visual? relation)
       (eq? (relation-visual-structure relation) 'root-only)))

; scene-state-resolved-ref : scene-state? (or/c visual? symbol? visual-path?) -> visual?
;;   Resolves target against the state. Ordinary Visuals are returned unchanged;
;;   derived Visual definitions may recursively resolve top-level dependencies.
(define (scene-state-resolved-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-resolved-ref "scene-state?" state))
  (let-values ([(resolve-target _resolve-target-world)
                (make-scene-state-resolver state)])
    (resolve-target target)))

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
  (let-values ([(_resolve-target resolve-target-world)
                (make-scene-state-resolver state)])
    (resolve-target-world path)))

;; Resolves several world paths through one memoized sampled-state resolver.
;; Inspection tools call this rather than repeatedly resolving derived Visuals
;; one target at a time.
(define (scene-state-resolved-world-refs state targets)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-resolved-world-refs "scene-state?" state))
  (unless (list? targets)
    (raise-argument-error 'scene-state-resolved-world-refs "list?" targets))
  (let-values ([(_resolve-target resolve-target-world)
                (make-scene-state-resolver state)])
    (for/list ([target (in-list targets)])
      (resolve-target-world target))))

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
  (cond
    [(affine-map-visual? visual)
     ;; The wrapper's map already includes every normal ancestor composed by
     ;; `visual-with-transform`. Rewrapping each direct child therefore gives
     ;; an independently drawable world-space target without discarding the
     ;; enclosing shear/reflection.
     (define content (affine-map-visual-content visual))
     (define inherited-opacity
       (* (visual-opacity visual)
          (if (opacity-visual? content)
              (visual-opacity content)
              1)))
     (for/list ([child (in-list (composite-visual-children content))])
       (define transformed-child
         (affine-map child (affine-map-visual-map visual)))
       (if (opacity-visual? transformed-child)
           (visual-with-opacity
            transformed-child
            (* inherited-opacity (visual-opacity transformed-child)))
           transformed-child))]
    [else
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
           transformed-child))]))

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
  (define-values (resolve-target _resolve-target-world)
    (make-scene-state-resolver state))
  (for/list ([id (in-list (scene-state-drawing-order state))])
    (resolve-target id)))

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
