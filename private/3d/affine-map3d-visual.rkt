#lang racket/base

;;;
;;; Semantic General Affine Spatial Wrapper
;;;

;; A spatial affine map can contain shear, reflection, and singular maps that
;; cannot be represented by transform3's scale/rotation/translation fields.
;; The wrapper keeps that complete map semantic and exposes the wrapped
;; container's child paths unchanged.

(require (only-in racket/generic define/generic)
         "affine3.rkt"
         "bounds3.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "transform3.rkt")

(provide affine-map3d
         affine-map3d?
         affine-map3d-content
         affine-map3d-map
         affine-map3d-with-map
         affine-map3d-with-content
         affine-map3d-content+map
         spatial-visual->affine3)


;;; Data Representation

(struct affine-map3d-value (content transform map opacity)
  #:transparent
  #:guard
  (lambda (content transform map opacity who)
    (unless (spatial-visual? content)
      (raise-argument-error who "spatial-visual?" content))
    (unless (transform3? transform)
      (raise-argument-error who "transform3?" transform))
    (unless (affine3? map)
      (raise-argument-error who "affine3?" map))
    (unless (spatial-opacity? opacity)
      (raise-argument-error who "finite real in the closed unit interval" opacity))
    (values content transform map opacity))
  #:methods gen:spatial-visual
  [(define/generic generic-spatial-id spatial-id)
   (define/generic generic-spatial-local-bounds spatial-local-bounds)
   (define (spatial-id visual)
     (generic-spatial-id (affine-map3d-value-content visual)))
   ;; `transform` is a decomposed public proxy for the full affine map.  The
   ;; renderer and spatial-world traversal use `map` directly; ordinary local
   ;; transform updates rebase that exact map through this proxy.
   (define (spatial-transform visual)
     (affine-map3d-value-transform visual))
   (define (spatial-with-transform visual transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (define previous-proxy
       (transform3->affine3 (affine-map3d-value-transform visual)))
     (define relative
       (affine3-compose (transform3->affine3 transform)
                        (affine3-invert previous-proxy)))
     (struct-copy affine-map3d-value visual
                  [transform transform]
                  [map (affine3-compose relative (affine-map3d-value-map visual))]))
   (define (spatial-opacity visual)
     (affine-map3d-value-opacity visual))
   (define (spatial-with-opacity visual opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error 'spatial-with-opacity
                             "finite real in the closed unit interval" opacity))
     (struct-copy affine-map3d-value visual [opacity opacity]))
   (define (spatial-local-bounds visual)
     ;; Generic containers apply `spatial-transform` to this value.  Express
     ;; the mapped content relative to the proxy so their existing bounds
     ;; protocol still encloses the complete general affine map exactly.
     (define proxy (transform3->affine3 (affine-map3d-value-transform visual)))
     (aabb3-transform
      (generic-spatial-local-bounds (affine-map3d-value-content visual))
      (affine3-compose (affine3-invert proxy) (affine-map3d-value-map visual))))]
  #:methods gen:spatial-container
  [(define/generic generic-spatial-child-entries spatial-child-entries)
   (define/generic generic-spatial-container-with-children
     spatial-container-with-children)
   (define (spatial-child-entries visual)
     ;; The wrapper is deliberately transparent to paths: a mapped group still
     ;; exposes precisely its original direct child identifiers.
     (define content (affine-map3d-value-content visual))
     (if (spatial-container? content)
         (generic-spatial-child-entries content)
         '()))
   (define (spatial-container-with-children visual children)
     (define content (affine-map3d-value-content visual))
     (unless (spatial-container? content)
       (raise-arguments-error
        'spatial-container-with-children
        "mapped spatial-container content"
        "visual" visual))
     (affine-map3d-with-content
      visual
      (generic-spatial-container-with-children content children)))])

(define affine-map3d? affine-map3d-value?)
(define affine-map3d-content affine-map3d-value-content)
(define affine-map3d-map affine-map3d-value-map)


;;; Construction and Immutable Updates

; affine-map3d : spatial-visual? affine3? -> affine-map3d?
;; Applies map after content's current local-to-parent map. The content is
;; normalized at the wrapper origin, leaving the full affine map as immutable
;; semantic data rather than resampling mesh topology.
(define (affine-map3d content map)
  (unless (spatial-visual? content)
    (raise-argument-error 'affine-map3d "spatial-visual?" content))
  (unless (affine3? map)
    (raise-argument-error 'affine-map3d "affine3?" map))
  (define-values (canonical-content current-map opacity)
    (affine-map3d-content+map content))
  (make-affine-map3d-value canonical-content
                           (affine3-compose map current-map)
                           opacity))

(define (affine-map3d-with-map visual map)
  (unless (affine-map3d? visual)
    (raise-argument-error 'affine-map3d-with-map "affine-map3d?" visual))
  (unless (affine3? map)
    (raise-argument-error 'affine-map3d-with-map "affine3?" map))
  (make-affine-map3d-value (affine-map3d-value-content visual)
                           map
                           (affine-map3d-value-opacity visual)))

(define (affine-map3d-with-content visual content)
  (unless (affine-map3d? visual)
    (raise-argument-error 'affine-map3d-with-content "affine-map3d?" visual))
  (unless (spatial-visual? content)
    (raise-argument-error 'affine-map3d-with-content "spatial-visual?" content))
  (unless (eq? (spatial-id content) (spatial-id visual))
    (raise-arguments-error
     'affine-map3d-with-content
     "content preserving the wrapper's stable identity"
     "wrapper-id" (spatial-id visual)
     "content-id" (spatial-id content)))
  (struct-copy affine-map3d-value visual [content content]))

; affine-map3d-content+map : spatial-visual?
;                            -> (values spatial-visual? affine3? spatial-opacity?)
;; Separates canonical transform-free content from its complete map and outer
;; opacity. Reapplying a map therefore composes exactly without rewrapping it.
(define (affine-map3d-content+map visual)
  (unless (spatial-visual? visual)
    (raise-argument-error 'affine-map3d-content+map "spatial-visual?" visual))
  (if (affine-map3d? visual)
      (values (affine-map3d-value-content visual)
              (affine-map3d-value-map visual)
              (affine-map3d-value-opacity visual))
      (values (spatial-with-opacity
               (spatial-with-transform visual identity-transform3)
               1)
              (transform3->affine3 (spatial-transform visual))
              (spatial-opacity visual))))

; spatial-visual->affine3 : spatial-visual? -> affine3?
;; Returns the full local-to-parent map, including an affine-map3d wrapper.
(define (spatial-visual->affine3 visual)
  (unless (spatial-visual? visual)
    (raise-argument-error 'spatial-visual->affine3 "spatial-visual?" visual))
  (if (affine-map3d? visual)
      (affine-map3d-value-map visual)
      (transform3->affine3 (spatial-transform visual))))

(define (make-affine-map3d-value content map opacity)
  ;; The proxy carries the map's translation for ordinary position tooling;
  ;; its scale and rotation remain neutral because `map` stores the exact
  ;; complete linear component.
  (affine-map3d-value
   content
   (make-transform3 #:translation (affine3-translation map))
   map
   opacity))
