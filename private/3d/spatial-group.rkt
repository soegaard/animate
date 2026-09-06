#lang racket/base

;;;
;;; Spatial Containers
;;;

;; Defines immutable ordered spatial groups.  The container protocol is kept
;; distinct from the ordinary 2D visual-container protocol so a spatial tree
;; never becomes an accidental target for a 2D animation operation.


;;;
;;; Imports and Exports
;;;

(require racket/generic
         "affine3.rkt"
         "bounds3.rkt"
         "spatial-visual.rkt"
         "transform3.rkt")

(provide gen:spatial-container
         spatial-container?
         spatial-child-entries
         spatial-container-with-children
         (struct-out spatial-child)
         group3d
         group3d?
         group3d-children
         group3d-with-children)


;;;
;;; Spatial Container Protocol
;;;

; spatial-child-entries : spatial-container? -> (listof spatial-child?)
;;   Returns immutable ordered child entries, back-to-front for future drawing.
;
; spatial-container-with-children : spatial-container?
;;                                    (listof spatial-visual?)
;;                                    -> spatial-container?
;;   Returns container rebuilt with its ordered direct children replaced.
;; This rebuilding method is public for path tooling but is not a 2D Visual
;; traversal protocol.
(define-generics spatial-container
  (spatial-child-entries spatial-container)
  (spatial-container-with-children spatial-container children))

(struct spatial-child (id visual)
  #:transparent
  #:guard
  (lambda (id visual who)
    (unless (symbol? id)
      (raise-argument-error who "symbol?" id))
    (unless (spatial-visual? visual)
      (raise-argument-error who "spatial-visual?" visual))
    (unless (eq? id (spatial-id visual))
      (raise-arguments-error
       who
       "a child ID matching spatial-id"
       "id" id
       "spatial-id" (spatial-id visual)))
    (values id visual)))

;; spatial-child represents one direct spatial child.
;;  - id      symbol?          stable direct child identity.
;;  - visual  spatial-visual?  immutable child value with matching identity.


;;;
;;; Group Value
;;;

(struct group3d-value (id transform opacity children)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id group)
     (group3d-value-id group))
   (define (spatial-transform group)
     (group3d-value-transform group))
   (define (spatial-with-transform group transform)
     (check-transform 'spatial-with-transform transform)
     (struct-copy group3d-value group [transform transform]))
   (define (spatial-opacity group)
     (group3d-value-opacity group))
   (define (spatial-with-opacity group opacity)
     (check-opacity 'spatial-with-opacity opacity)
     (struct-copy group3d-value group [opacity opacity]))
   (define (spatial-local-bounds group)
     (children-local-bounds (group3d-value-children group)))]
  #:methods gen:spatial-container
  [(define (spatial-child-entries group)
     (for/list ([child (in-list (group3d-value-children group))])
       (spatial-child (spatial-id child) child)))
   (define (spatial-container-with-children group children)
     (group3d-with-children group children))])

;; group3d-value represents an immutable spatial composite.
;;  - id         symbol?                    stable group identity.
;;  - transform  transform3?                local scale, rotation, translation.
;;  - opacity    spatial-opacity?           inherited semantic opacity.
;;  - children   (listof spatial-visual?)   direct local children in significant
;;                                           stable drawing/path order.

(define group3d? group3d-value?)
(define group3d-children group3d-value-children)


;;;
;;; Construction and Updates
;;;

; group3d : (listof spatial-visual?) #:id symbol?
;           [#:transform transform3?] [#:opacity spatial-opacity?]
;           -> group3d?
;;   Creates an ordered immutable spatial group with unique direct child IDs.
(define (group3d children
                 #:id id
                 #:transform [transform identity-transform3]
                 #:opacity [opacity 1])
  (unless (symbol? id)
    (raise-argument-error 'group3d "symbol?" id))
  (check-transform 'group3d transform)
  (check-opacity 'group3d opacity)
  (group3d-value id transform opacity (check-children 'group3d id children)))

; group3d-with-children : group3d? (listof spatial-visual?) -> group3d?
;;   Returns group with its direct child list replaced and revalidated.
(define (group3d-with-children group children)
  (unless (group3d? group)
    (raise-argument-error 'group3d-with-children "group3d?" group))
  (struct-copy group3d-value group
               [children
                (check-children 'group3d-with-children
                                (group3d-value-id group)
                                children)]))


;;;
;;; Bounds
;;;

; children-local-bounds : (listof spatial-visual?) -> aabb3?
;;   Returns the enclosing local bounds after each child transform is applied.
(define (children-local-bounds children)
  (for/fold ([bounds aabb3-empty])
            ([child (in-list children)])
    (aabb3-union
     bounds
     (aabb3-transform
      (spatial-local-bounds child)
      (transform3->affine3 (spatial-transform child))))))


;;;
;;; Validation
;;;

(define (check-transform who value)
  (unless (transform3? value)
    (raise-argument-error who "transform3?" value)))

(define (check-opacity who value)
  (unless (spatial-opacity? value)
    (raise-argument-error who "finite real in the closed unit interval" value)))

(define (check-children who group-id children)
  (unless (list? children)
    (raise-argument-error who "(listof spatial-visual?)" children))
  (define copied
    (for/list ([child (in-list children)])
      (unless (spatial-visual? child)
        (raise-argument-error who "(listof spatial-visual?)" children))
      child))
  (define ids (map spatial-id copied))
  (when (member group-id ids)
    (raise-arguments-error who
                           "a group ID distinct from every direct child ID"
                           "group-id" group-id
                           "child-ids" ids))
  (define duplicate (first-duplicate ids))
  (when duplicate
    (raise-arguments-error who
                           "unique direct spatial child IDs"
                           "duplicate-id" duplicate
                           "child-ids" ids))
  copied)

(define (first-duplicate values)
  (let loop ([remaining values] [seen '()])
    (cond [(null? remaining) #f]
          [(memq (car remaining) seen) (car remaining)]
          [else (loop (cdr remaining) (cons (car remaining) seen))])))
