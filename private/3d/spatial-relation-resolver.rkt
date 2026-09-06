#lang racket/base

;;;
;;; Deterministic Spatial Relation Resolver
;;;

;; Resolves the semantic graph inside one sampled view3d before that view
;; reaches either 3D renderer.  The resolver is intentionally local to a
;; sampled immutable view: caches and the active-cycle stack die at the end of
;; this call, so frame order cannot affect future frames.

(require "affine3.rkt"
         "../visual-model.rkt"
         "affine-map3d-visual.rkt"
         "spatial-group.rkt"
         "spatial-path.rkt"
         "spatial-relation-context.rkt"
         "spatial-relation.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "view3d-visual.rkt")

(provide resolve-view3d-spatial-relations)

; resolve-view3d-spatial-relations : view3d?
;                                    [#:value-has? (symbol? -> boolean?)]
;                                    [#:value-ref (symbol? -> any/c)]
;                                    -> view3d?
;; Resolves each spatial-relation in `view` from the same immutable sampled
;; spatial tree and camera.  A relation can ask for another relation by its
;; declared path; only that requested target is resolved lazily, avoiding
;; artificial sibling cycles.
(define (resolve-view3d-spatial-relations view
                                          #:value-has? [value-has? (lambda (_id) #f)]
                                          #:value-ref [value-ref missing-value])
  (unless (view3d? view)
    (raise-argument-error 'resolve-view3d-spatial-relations "view3d?" view))
  (unless (procedure? value-has?)
    (raise-argument-error 'resolve-view3d-spatial-relations "procedure?" value-has?))
  (unless (procedure? value-ref)
    (raise-argument-error 'resolve-view3d-spatial-relations "procedure?" value-ref))
  (define cache (make-hash))
  (define active '())
  (define view-id (visual-id view))

  (define (check-path who path)
    (unless (and (spatial-path? path)
                 (pair? (cdr path))
                 (eq? (car path) view-id))
      (raise-arguments-error
       who
       "a nonempty spatial path rooted at this view3d"
       "view3d-id" view-id
       "spatial-path" path)))

  (define (cycle-for path)
    (define tail (member path active equal?))
    (append (or tail active) (list path)))

  (define (resolve-object object path)
    (cond
      [(hash-has-key? cache path) (hash-ref cache path)]
      [(member path active equal?)
       (raise-arguments-error
        'resolve-view3d-spatial-relations
        "spatial relation dependency cycle"
        "cycle" (cycle-for path))]
      [(spatial-relation? object)
       (define saved-active active)
       (set! active (append active (list path)))
       (dynamic-wind
        void
        (lambda ()
          (define context
            (make-spatial-relation-context
             view path (spatial-relation-dependencies object)
             resolve-spatial-path
             world-transform-path
             value-has? value-ref))
          (define resolved (resolve-spatial-relation object context))
          (hash-set! cache path resolved)
          resolved)
        (lambda () (set! active saved-active)))]
      [(spatial-container? object)
       (define resolved
         (spatial-container-with-children
          object
          (for/list ([entry (in-list (spatial-child-entries object))])
            (resolve-object (spatial-child-visual entry)
                            (append path (list (spatial-child-id entry)))))))
       (hash-set! cache path resolved)
       resolved]
      [else
       (hash-set! cache path object)
       object]))

  ;; Resolve a path through the original tree one component at a time.  The
  ;; enclosing group is not fully rebuilt merely to reach one child: that is
  ;; what lets a relation read an ordinary sibling without re-entering itself.
  (define (resolve-spatial-path path)
    (check-path 'resolve-view3d-spatial-relations path)
    (let loop ([container view]
               [remaining (cdr path)]
               [prefix (list view-id)])
      (define entry (spatial-entry-by-id container (car remaining) path))
      (define object (spatial-child-visual entry))
      (define next-path (append prefix (list (spatial-child-id entry))))
      (cond
        [(null? (cdr remaining))
         (resolve-object object next-path)]
        [(spatial-relation? object)
         (unless (eq? (spatial-relation-structure object) 'fixed)
           (raise-arguments-error
            'resolve-view3d-spatial-relations
            "a root-only spatial relation targeted only at its stable root"
            "relation path" next-path
            "requested spatial-path" path))
         (define resolved (resolve-object object next-path))
         (unless (spatial-container? resolved)
           (raise-arguments-error
            'resolve-view3d-spatial-relations
            "a fixed spatial relation resolving to a spatial container"
            "relation-path" next-path
            "resolved spatial-visual" resolved))
         (loop resolved (cdr remaining) next-path)]
        [(spatial-container? object)
         (loop object (cdr remaining) next-path)]
        [else
         (raise-arguments-error
          'resolve-view3d-spatial-relations
          "an intermediate spatial path entry naming a spatial container"
          "spatial-path" path
          "spatial-visual" object)])))

  ;; Resolve the exact same lazy path while composing its local transforms.
  ;; The returned affine map runs from the target's local coordinates to the
  ;; owning view's 3D world coordinates.
  (define (world-transform-path path)
    (check-path 'resolve-view3d-spatial-relations path)
    (let loop ([container view]
               [remaining (cdr path)]
               [prefix (list view-id)]
               [parent identity-affine3])
      (define entry (spatial-entry-by-id container (car remaining) path))
      (define original (spatial-child-visual entry))
      (define next-path (append prefix (list (spatial-child-id entry))))
      (define object
        (if (or (spatial-relation? original)
                (null? (cdr remaining)))
            (resolve-object original next-path)
            original))
      (define world-transform
        (affine3-compose parent (spatial-visual->affine3 object)))
      (cond
        [(null? (cdr remaining)) world-transform]
        [(spatial-relation? original)
         (unless (eq? (spatial-relation-structure original) 'fixed)
           (raise-arguments-error
            'resolve-view3d-spatial-relations
            "a root-only spatial relation targeted only at its stable root"
            "relation path" next-path
            "requested spatial-path" path))
         (unless (spatial-container? object)
           (raise-arguments-error
            'resolve-view3d-spatial-relations
            "a fixed spatial relation resolving to a spatial container"
            "relation-path" next-path
            "resolved spatial-visual" object))
         (loop object (cdr remaining) next-path world-transform)]
        [(spatial-container? object)
         (loop object (cdr remaining) next-path world-transform)]
        [else
         (raise-arguments-error
          'resolve-view3d-spatial-relations
          "an intermediate spatial path entry naming a spatial container"
          "spatial-path" path
          "spatial-visual" object)])))

  (spatial-container-with-children
   view
   (for/list ([entry (in-list (spatial-child-entries view))])
     (resolve-object (spatial-child-visual entry)
                     (list view-id (spatial-child-id entry))))) )

(define (spatial-entry-by-id container id full-path)
  (define result
    (for/first ([entry (in-list (spatial-child-entries container))]
                #:when (eq? (spatial-child-id entry) id))
      entry))
  (unless result
    (raise-arguments-error
     'resolve-view3d-spatial-relations
     "a spatial path present in the owning view3d"
     "spatial-path" full-path
     "missing-spatial-id" id))
  result)

(define (missing-value id)
  (raise-arguments-error
   'spatial-relation-context-value-ref
   "a declared scene value that is present in this sampled scene"
   "value-id" id))
