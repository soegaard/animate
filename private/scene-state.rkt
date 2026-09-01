#lang racket/base

;;;
;;; Scene State Model
;;;

;; Defines immutable snapshots of the top-level Visuals and named scalar values
;; in a scene.
;;
;; Scene state preserves an explicit back-to-front drawing order independently
;; of its Visual identity lookup table. Scalar values share the global scene ID
;; namespace with Visuals. They are not drawn directly, but derived Visuals may
;; resolve their concrete geometry/style from scalars and other top-level Visuals
;; in the same sampled immutable state.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "derived-visual.rkt"
         "geometry.rkt"
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
;;  - values-by-id   immutable hash?    maps ids to finite real scalar values.


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

; scene-state-has? : scene-state? (or/c visual? symbol?) -> boolean?
;;   Reports whether state contains target as a top-level Visual.
(define (scene-state-has? state target)
  (hash-has-key? (scene-state-visuals-by-id state)
                 (visual-target-id target 'scene-state-has?)))

; scene-state-ref : scene-state? (or/c visual? symbol?) -> visual?
;;   Returns the top-level Visual identified by target.
(define (scene-state-ref state target)
  (define id
    (visual-target-id target 'scene-state-ref))
  (hash-ref
   (scene-state-visuals-by-id state)
   id
   (lambda ()
     (raise-arguments-error
      'scene-state-ref
      "the visual is not present in the scene"
      "visual-id" id))))

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
     (lambda (id)
       (scene-state-has? state id))
     (lambda (id)
       (resolve-id id))))

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

  resolve-id)

; scene-state-resolved-ref : scene-state? (or/c visual? symbol?) -> visual?
;;   Resolves target against the state. Ordinary Visuals are returned unchanged;
;;   derived Visual definitions may recursively resolve top-level dependencies.
(define (scene-state-resolved-ref state target)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-resolved-ref "scene-state?" state))
  (define id
    (visual-target-id target 'scene-state-resolved-ref))
  ((make-scene-state-resolver state) id))

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
     "a scalar value with this ID is already present"
     "id" id))
  (scene-state
   (hash-set (scene-state-visuals-by-id state) id visual)
   (append (scene-state-drawing-order state) (list id))
   (scene-state-values-by-id state)))

; scene-state-remove : scene-state? (or/c visual? symbol?) -> scene-state?
;;   Removes target while preserving the order of remaining visuals.
(define (scene-state-remove state target)
  (define id
    (visual-target-id target 'scene-state-remove))
  (unless (hash-has-key? (scene-state-visuals-by-id state) id)
    (raise-arguments-error
     'scene-state-remove
     "the visual is not present in the scene"
     "visual-id" id))
  (scene-state
   (hash-remove (scene-state-visuals-by-id state) id)
   (filter (lambda (existing-id)
             (not (eq? existing-id id)))
           (scene-state-drawing-order state))
   (scene-state-values-by-id state)))

; scene-state-update : scene-state? (or/c visual? symbol?) visual? -> scene-state?
;;   Replaces target without changing its identity or drawing order.
(define (scene-state-update state target replacement)
  (define id
    (visual-target-id target 'scene-state-update))
  (unless (visual? replacement)
    (raise-argument-error 'scene-state-update "visual?" replacement))
  (unless (eq? id (visual-id replacement))
    (raise-arguments-error
     'scene-state-update
     "the replacement must preserve the visual ID"
     "expected visual-id" id
     "replacement visual-id" (visual-id replacement)))
  (unless (hash-has-key? (scene-state-visuals-by-id state) id)
    (raise-arguments-error
     'scene-state-update
     "the visual is not present in the scene"
     "visual-id" id))
  (scene-state
   (hash-set (scene-state-visuals-by-id state) id replacement)
   (scene-state-drawing-order state)
   (scene-state-values-by-id state)))


;;;
;;; Named Scalar Values
;;;

; scene-state-value-has? : scene-state? symbol? -> boolean?
;;   Reports whether state contains one named scalar value.
(define (scene-state-value-has? state id)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-has? "scene-state?" state))
  (unless (symbol? id)
    (raise-argument-error 'scene-state-value-has? "symbol?" id))
  (hash-has-key? (scene-state-values-by-id state) id))

; scene-state-value-ref : scene-state? symbol? -> finite-real?
;;   Returns one named scalar value.
(define (scene-state-value-ref state id)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-ref "scene-state?" state))
  (unless (symbol? id)
    (raise-argument-error 'scene-state-value-ref "symbol?" id))
  (hash-ref
   (scene-state-values-by-id state)
   id
   (lambda ()
     (raise-arguments-error
      'scene-state-value-ref
      "the scalar value is not present in the scene"
      "value-id" id))))

; scene-state-value-set : scene-state? symbol? finite-real? -> scene-state?
;;   Adds or replaces one named scalar while preserving Visual state.
(define (scene-state-value-set state id value)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-set "scene-state?" state))
  (unless (symbol? id)
    (raise-argument-error 'scene-state-value-set "symbol?" id))
  (unless (finite-real? value)
    (raise-argument-error 'scene-state-value-set "finite-real?" value))
  (when (hash-has-key? (scene-state-visuals-by-id state) id)
    (raise-arguments-error
     'scene-state-value-set
     "a Visual with this ID is already present"
     "id" id))
  (scene-state
   (scene-state-visuals-by-id state)
   (scene-state-drawing-order state)
   (hash-set (scene-state-values-by-id state) id value)))

; scene-state-value-remove : scene-state? symbol? -> scene-state?
;;   Removes one named scalar value.
(define (scene-state-value-remove state id)
  (unless (scene-state? state)
    (raise-argument-error 'scene-state-value-remove "scene-state?" state))
  (unless (symbol? id)
    (raise-argument-error 'scene-state-value-remove "symbol?" id))
  (unless (hash-has-key? (scene-state-values-by-id state) id)
    (raise-arguments-error
     'scene-state-value-remove
     "the scalar value is not present in the scene"
     "value-id" id))
  (scene-state
   (scene-state-visuals-by-id state)
   (scene-state-drawing-order state)
   (hash-remove (scene-state-values-by-id state) id)))
