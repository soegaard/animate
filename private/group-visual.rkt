#lang racket/base

;;;
;;; Group Visual Model
;;;

;; Defines immutable semantic groups with ordered affine child Visuals.
;;
;; Child coordinates are local to the group. Group transforms are inherited by
;; children during adapter conversion, not stored as Pict composition in the
;; semantic model.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide group
         group-visual?
         group-visual-children
         group-visual-with-children
         group-visual-resolved-children)


;;;
;;; Data Representation
;;;

(struct group-visual (id transform opacity children)
  #:transparent
  #:methods gen:visual
  [(define (visual-id group)
     (group-visual-id group))
   (define (visual-position group)
     (affine-transform-translation
      (group-visual-transform group)))
   (define (visual-with-position group position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy group-visual group
                  [transform
                   (affine-transform-with-translation
                    (group-visual-transform group)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform group)
     (group-visual-transform group))
   (define (visual-with-transform group transform)
     (check-group-transform 'visual-with-transform transform)
     (struct-copy group-visual group [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity group)
     (group-visual-opacity group))
   (define (visual-with-opacity group opacity)
     (check-group-opacity 'visual-with-opacity opacity)
     (struct-copy group-visual group [opacity opacity]))])

;; group-visual represents one semantic composite Visual.
;;  - id         symbol?                  stable group identity.
;;  - transform  affine-transform?        group placement and deformation.
;;                                        Its scale must be uniform.
;;  - opacity    opacity?                 opacity of the complete composition.
;;  - children   (listof affine-visual?)  local children in back-to-front
;;                                        order. Ordering is significant.
;;
;; Direct sibling identities are unique and every descendant differs from its
;; enclosing group identity. The same local child identity may occur below two
;; different branches: their complete nested Visual paths remain distinct. This
;; is important for regular structures such as a matrix, where every row can
;; naturally contain a child named `col-1`.
;; Custom affine Visuals are treated as leaves. Child positions are coordinates
;; local to the group.


;;;
;;; Construction and Immutable Updates
;;;

; group : (listof (and/c visual? affine-visual?))
;         #:id symbol?
;         [#:center vec2?]
;         [#:rotation finite-real?]
;         [#:scale scale-factor?]
;         [#:opacity opacity?]
;         -> group-visual?
;;   Creates a semantic group whose children use local coordinates.
(define (group children
               #:id id
               #:center [center origin]
               #:rotation [rotation 0]
               #:scale [scale 1]
               #:opacity [opacity 1])
  (check-group-id 'group id)
  (unless (vec2? center)
    (raise-argument-error 'group "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'group "finite real?" rotation))
  (check-uniform-scale 'group scale)
  (check-group-opacity 'group opacity)
  (define checked-children
    (check-group-children 'group id children))
  (group-visual id
                (make-affine-transform #:translation center
                                       #:rotation rotation
                                       #:scale scale)
                opacity
                checked-children))

; group-visual-with-children : group-visual?
;                              (listof (and/c visual? affine-visual?))
;                              -> group-visual?
;;   Returns group with its ordered child list replaced.
(define (group-visual-with-children group children)
  (unless (group-visual? group)
    (raise-argument-error
     'group-visual-with-children
     "group-visual?"
     group))
  (struct-copy group-visual group
               [children
                (check-group-children
                 'group-visual-with-children
                 (visual-id group)
                 children)]))


;;;
;;; Transform Inheritance
;;;

; group-visual-resolved-children : group-visual? -> (listof affine-visual?)
;;   Returns children with the group's rotation and uniform scale inherited.
(define (group-visual-resolved-children group)
  (unless (group-visual? group)
    (raise-argument-error
     'group-visual-resolved-children
     "group-visual?"
     group))
  (define parent-transform
    (visual-transform group))
  (define parent-scale
    (uniform-transform-scale
     'group-visual-resolved-children
     parent-transform))
  (for/list ([child (in-list (group-visual-children group))])
    (resolve-child-transform child
                             parent-transform
                             parent-scale)))

; resolve-child-transform : affine-visual? affine-transform? positive-real?
;                           -> affine-visual?
;;   Applies one uniform parent transform to a child Visual.
(define (resolve-child-transform child parent-transform parent-scale)
  (define child-transform
    (checked-child-transform 'group-visual-resolved-children child))
  (define intended-transform
    (make-affine-transform
     #:translation
     (affine-transform-apply-vector
      parent-transform
      (affine-transform-translation child-transform))
     #:rotation
     (+ (affine-transform-rotation parent-transform)
        (affine-transform-rotation child-transform))
     #:scale
     (vec2-scale parent-scale
                 (affine-transform-scale child-transform))))
  (define result
    (visual-with-transform child intended-transform))
  (check-resolved-child 'group-visual-resolved-children
                        child
                        intended-transform
                        result)
  result)

; check-resolved-child : symbol? visual? affine-transform? any/c -> void?
;;   Checks that a child transform update preserves the required protocol data.
(define (check-resolved-child who original intended-transform result)
  (unless (and (visual? result)
               (affine-visual? result))
    (raise-arguments-error
     who
     "an affine child must remain an affine Visual after transform replacement"
     "child" original
     "result" result))
  (unless (eq? (visual-id result)
               (visual-id original))
    (raise-arguments-error
     who
     "an affine child transform replacement must preserve identity"
     "expected visual-id" (visual-id original)
     "result visual-id" (visual-id result)))
  (define result-transform
    (checked-child-transform who result))
  (unless (equal? result-transform intended-transform)
    (raise-arguments-error
     who
     "an affine child must install the requested complete transform"
     "child" original
     "requested transform" intended-transform
     "result transform" result-transform))
  (define result-position
    (checked-child-position who result))
  (unless (equal? result-position
                  (affine-transform-translation intended-transform))
    (raise-arguments-error
     who
     "an affine child's position must agree with its transform translation"
     "child" original
     "requested position"
     (affine-transform-translation intended-transform)
     "result position" result-position)))


;;;
;;; Child Validation
;;;

; check-group-children : symbol? symbol? any/c
;                        -> (listof (and/c visual? affine-visual?))
;;   Validates and copies a group's significant child list.
(define (check-group-children who group-id children)
  (unless (list? children)
    (raise-argument-error
     who
     "(listof (and/c visual? affine-visual?))"
     children))
  (define checked-children
    (for/list ([child (in-list children)])
      (check-group-child who child)
      child))
  (define child-ids
    (for/list ([child (in-list checked-children)])
      (visual-target-id child who)))
  (define child-tree-ids
    (for*/list ([child (in-list checked-children)]
                [id (in-list (visual-tree-ids child who))])
      id))
  (when (member group-id child-tree-ids)
    (raise-arguments-error
     who
     "a group identity must differ from every descendant identity"
     "group-id" group-id))
  (define duplicate-id
    (find-duplicate-id child-ids))
  (when duplicate-id
    (raise-arguments-error
     who
     "direct children of a built-in group must have distinct identities"
     "duplicate visual-id" duplicate-id))
  checked-children)

; check-group-child : symbol? any/c -> void?
;;   Raises an argument error unless child is a valid affine Visual.
(define (check-group-child who child)
  (unless (and (visual? child)
               (affine-visual? child))
    (raise-argument-error
     who
     "(and/c visual? affine-visual?)"
     child))
  (when (frame-space-visual? child)
    (raise-arguments-error
     who
     "frame-space Visuals must remain top-level; wrap the complete group instead"
     "child-id" (visual-id child)))
  (visual-target-id child who)
  (define transform
    (checked-child-transform who child))
  (define position
    (checked-child-position who child))
  (unless (equal? position
                  (affine-transform-translation transform))
    (raise-arguments-error
     who
     "an affine child's position must agree with its transform translation"
     "child" child
     "position" position
     "transform translation"
     (affine-transform-translation transform)))
  (void))

; checked-child-transform : symbol? affine-visual? -> affine-transform?
;;   Returns a child's validated complete affine transform.
(define (checked-child-transform who child)
  (define transform
    (visual-transform child))
  (unless (affine-transform? transform)
    (raise-arguments-error
     who
     "an affine child must return an affine transform"
     "child" child
     "transform" transform))
  transform)

; checked-child-position : symbol? visual? -> vec2?
;;   Returns a child's validated reference position.
(define (checked-child-position who child)
  (define position
    (visual-position child))
  (unless (vec2? position)
    (raise-arguments-error
     who
     "a child Visual must return a vec2 reference position"
     "child" child
     "position" position))
  position)

; visual-tree-ids : visual? symbol? -> (listof symbol?)
;;   Returns one Visual tree's identities in pre-order.
(define (visual-tree-ids visual who)
  (define id
    (visual-target-id visual who))
  (if (group-visual? visual)
      (cons id
            (for*/list ([child
                         (in-list (group-visual-children visual))]
                        [child-id
                         (in-list (visual-tree-ids child who))])
              child-id))
      (list id)))

; find-duplicate-id : (listof symbol?) -> (or/c symbol? false/c)
;;   Returns the first repeated identity or false when all are distinct.
(define (find-duplicate-id ids)
  (let loop ([remaining ids]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))


;;;
;;; Group Transform Validation
;;;

; check-group-id : symbol? any/c -> void?
;;   Raises an argument error unless id is a symbol.
(define (check-group-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id)))

; check-group-opacity : symbol? any/c -> void?
;;   Raises an argument error unless opacity is in the closed unit interval.
(define (check-group-opacity who opacity)
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity)))

; check-uniform-scale : symbol? any/c -> void?
;;   Raises an argument error unless scale has equal positive components.
(define (check-uniform-scale who scale)
  (unless (scale-factor? scale)
    (raise-argument-error who "scale-factor?" scale))
  (define normalized-scale
    (scale-factor->vec2 scale))
  (unless (= (vec2-x normalized-scale)
             (vec2-y normalized-scale))
    (raise-arguments-error
     who
     "group scale must be uniform"
     "scale" scale)))

; check-group-transform : symbol? any/c -> void?
;;   Raises an argument error unless transform has a uniform positive scale.
(define (check-group-transform who transform)
  (unless (affine-transform? transform)
    (raise-argument-error who "affine-transform?" transform))
  (uniform-transform-scale who transform)
  (void))

; uniform-transform-scale : symbol? affine-transform? -> positive-real?
;;   Returns transform's scalar scale or raises for non-uniform scale.
(define (uniform-transform-scale who transform)
  (define scale
    (affine-transform-scale transform))
  (unless (= (vec2-x scale)
             (vec2-y scale))
    (raise-arguments-error
     who
     "group transforms require uniform scale"
     "scale" scale))
  (vec2-x scale))
