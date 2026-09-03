#lang racket/base

;;;
;;; Semantic General Affine-Map Visual Wrapper
;;;

;; A general map is a first-class affine Visual wrapper, rather than a
;; renderer-only whole-Pict operation. The wrapped content is normalized to its
;; local origin, while `map` records the complete map from that local coordinate
;; system into its containing coordinate system. `transform` is a decomposed
;; placement view of the same map for the older group protocol. It lets a mapped
;; subtree remain a child of an ordinary group and keeps all descendant paths
;; addressable.

(require racket/generic
         "affine-transform.rkt"
         "geometry.rkt"
         "visual-model.rkt")

(provide affine-map
         affine-map-visual?
         affine-map-visual-content
         affine-map-visual-map
         affine-map-visual-with-map
         affine-map-visual-with-content
         affine-map-visual-content+map)


;;;
;;; Data Representation

(struct affine-map-visual (content transform map opacity)
  #:transparent
  #:guard
  (lambda (content transform map opacity who)
    (unless (and (visual? content) (affine-visual? content))
      (raise-argument-error who "(and/c visual? affine-visual?)" content))
    (unless (affine-transform? transform)
      (raise-argument-error who "affine-transform?" transform))
    (unless (affine2? map)
      (raise-argument-error who "affine2?" map))
    (unless (opacity? opacity)
      (raise-argument-error who "opacity?" opacity))
    (values content transform map opacity))
  #:methods gen:visual
  [(define/generic generic-visual-id visual-id)
   (define (visual-id visual)
     (generic-visual-id (affine-map-visual-content visual)))
   (define (visual-position visual)
     (affine-transform-translation (affine-map-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (visual-with-transform
      visual
      (affine-transform-with-translation
       (affine-map-visual-transform visual)
       position)))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (affine-map-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     ;; `transform` describes how an enclosing ordinary group has changed this
     ;; wrapper. Apply that relative map to the complete semantic affine map,
     ;; so descendants inherit the same shear/reflection exactly.
     (define old-transform (affine-map-visual-transform visual))
     (define old-normal-map (affine-transform->affine2 old-transform))
     (define inverse-old-normal-map (affine2-invert old-normal-map))
     (unless inverse-old-normal-map
       (raise-arguments-error
        'visual-with-transform
        "an invertible decomposed wrapper transform"
        "visual" visual
        "transform" old-transform))
     (define relative-map
       (affine2-compose (affine-transform->affine2 transform)
                        inverse-old-normal-map))
     (struct-copy affine-map-visual visual
                  [transform transform]
                  [map
                   (affine2-compose relative-map
                                    (affine-map-visual-map visual))]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (affine-map-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error 'visual-with-opacity "opacity?" opacity))
     (struct-copy affine-map-visual visual [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define/generic generic-visual-stroke-width visual-stroke-width)
   (define/generic generic-visual-with-stroke-width visual-with-stroke-width)
   (define (visual-stroke-width visual)
     (define content (affine-map-visual-content visual))
     (unless (stroke-width-visual? content)
       (raise-arguments-error
        'visual-stroke-width
        "mapped content supporting cosmetic stroke widths"
        "visual" visual))
     (generic-visual-stroke-width content))
   (define (visual-with-stroke-width visual stroke-width)
     (define content (affine-map-visual-content visual))
     (unless (stroke-width-visual? content)
       (raise-arguments-error
        'visual-with-stroke-width
        "mapped content supporting cosmetic stroke widths"
        "visual" visual))
     (struct-copy affine-map-visual visual
                  [content
                   (generic-visual-with-stroke-width content stroke-width)]))]
  #:methods gen:fill-color-visual
  [(define/generic generic-visual-fill-color visual-fill-color)
   (define/generic generic-visual-with-fill-color visual-with-fill-color)
   (define (visual-fill-color visual)
     (define content (affine-map-visual-content visual))
     (unless (fill-color-visual? content)
       (raise-arguments-error
        'visual-fill-color
        "mapped content supporting fill colors"
        "visual" visual))
     (generic-visual-fill-color content))
   (define (visual-with-fill-color visual color)
     (define content (affine-map-visual-content visual))
     (unless (fill-color-visual? content)
       (raise-arguments-error
        'visual-with-fill-color
        "mapped content supporting fill colors"
        "visual" visual))
     (struct-copy affine-map-visual visual
                  [content (generic-visual-with-fill-color content color)]))]
  #:methods gen:stroke-color-visual
  [(define/generic generic-visual-stroke-color visual-stroke-color)
   (define/generic generic-visual-with-stroke-color visual-with-stroke-color)
   (define (visual-stroke-color visual)
     (define content (affine-map-visual-content visual))
     (unless (stroke-color-visual? content)
       (raise-arguments-error
        'visual-stroke-color
        "mapped content supporting stroke colors"
        "visual" visual))
     (generic-visual-stroke-color content))
   (define (visual-with-stroke-color visual color)
     (define content (affine-map-visual-content visual))
     (unless (stroke-color-visual? content)
       (raise-arguments-error
        'visual-with-stroke-color
        "mapped content supporting stroke colors"
        "visual" visual))
     (struct-copy affine-map-visual visual
                  [content
                   (generic-visual-with-stroke-color content color)]))])


;;;
;;; Construction and Immutable Updates

;; affine-map : (and/c visual? affine-visual?) affine2? -> affine-map-visual?
;; Applies `map` after content's current affine transform. The endpoint keeps
;; the original content's stable identity but normalizes it at the wrapper
;; origin, so the same representation is valid at the scene top level and as a
;; nested group child.
(define (affine-map content map)
  (unless (and (visual? content) (affine-visual? content))
    (raise-argument-error 'affine-map "(and/c visual? affine-visual?)" content))
  (unless (affine2? map)
    (raise-argument-error 'affine-map "affine2?" map))
  (define-values (canonical-content current-map opacity)
    (affine-map-visual-content+map content))
  (make-affine-map-visual canonical-content
                          (affine2-compose map current-map)
                          opacity))

;; affine-map-visual-with-map : affine-map-visual? affine2?
;;                             -> affine-map-visual?
;; Replaces the wrapper's complete local-to-parent semantic map.
(define (affine-map-visual-with-map visual map)
  (unless (affine-map-visual? visual)
    (raise-argument-error 'affine-map-visual-with-map
                          "affine-map-visual?"
                          visual))
  (unless (affine2? map)
    (raise-argument-error 'affine-map-visual-with-map "affine2?" map))
  (make-affine-map-visual (affine-map-visual-content visual)
                          map
                          (affine-map-visual-opacity visual)))

;; affine-map-visual-with-content : affine-map-visual? visual?
;;                                  -> affine-map-visual?
;; Rebuilds the retained semantic subtree after one descendant replacement.
(define (affine-map-visual-with-content visual content)
  (unless (affine-map-visual? visual)
    (raise-argument-error 'affine-map-visual-with-content
                          "affine-map-visual?"
                          visual))
  (unless (and (visual? content) (affine-visual? content))
    (raise-argument-error 'affine-map-visual-with-content
                          "(and/c visual? affine-visual?)"
                          content))
  (unless (eq? (visual-id content) (visual-id visual))
    (raise-arguments-error
     'affine-map-visual-with-content
     "content preserving the wrapper's stable identity"
     "wrapper-id" (visual-id visual)
     "content-id" (visual-id content)))
  (struct-copy affine-map-visual visual [content content]))

;; affine-map-visual-content+map : (and/c visual? affine-visual?)
;;                                  -> (values (and/c visual? affine-visual?)
;;                                             affine2? opacity?)
;; Returns canonical content, its complete local-to-parent map, and any outer
;; wrapper opacity. An ordinary affine Visual contributes its own decomposed
;; transform as the initial map and is normalized at the local origin.
(define (affine-map-visual-content+map visual)
  (unless (and (visual? visual) (affine-visual? visual))
    (raise-argument-error
     'affine-map-visual-content+map
     "(and/c visual? affine-visual?)"
     visual))
  (if (affine-map-visual? visual)
      (values (affine-map-visual-content visual)
              (affine-map-visual-map visual)
              (affine-map-visual-opacity visual))
      (values (visual-with-transform visual identity-affine-transform)
              (affine-transform->affine2 (visual-transform visual))
              1)))

;; make-affine-map-visual : affine-visual? affine2? opacity?
;;                           -> affine-map-visual?
;; The legacy affine protocol needs a decomposed placement. Translation is the
;; exact affine-map origin; rotation and scale stay neutral because the complete
;; linear portion is represented by `map`.
(define (make-affine-map-visual content map opacity)
  (affine-map-visual
   content
   (make-affine-transform #:translation (affine2-translation map))
   map
   opacity))
