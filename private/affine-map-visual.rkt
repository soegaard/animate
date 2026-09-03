#lang racket/base

;;;
;;; General Affine-Map Visual Wrapper
;;;

;; Represents a top-level world Visual whose fully rendered local picture is
;; transformed by a general affine2 map.  Keeping this separate from the older
;; affine-visual protocol preserves the latter's translation/rotation/positive-
;; scale contract for existing Visual implementations.


;;;
;;; Imports and Exports

(require racket/generic
         "affine-transform.rkt"
         "geometry.rkt"
         "visual-model.rkt")

(provide affine-map
         affine-map-visual?
         affine-map-visual-content
         affine-map-visual-map
         affine-map-visual-with-map
         affine-map-visual-content+map)


;;;
;;; Data Representation

(struct affine-map-visual (content map)
  #:transparent
  #:guard
  (lambda (content map who)
    (unless (visual? content)
      (raise-argument-error who "visual?" content))
    (unless (affine2? map)
      (raise-argument-error who "affine2?" map))
    (values content map))
  #:methods gen:visual
  [(define/generic generic-visual-id visual-id)
   (define/generic generic-visual-position visual-position)
   (define (visual-id visual)
     (generic-visual-id (affine-map-visual-content visual)))
   (define (visual-position visual)
     (affine2-apply-point
      (affine-map-visual-map visual)
      (generic-visual-position (affine-map-visual-content visual))))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (define map (affine-map-visual-map visual))
     (define content-position
       (generic-visual-position (affine-map-visual-content visual)))
     ;; Retain the full linear map while solving translation so the wrapped
     ;; Visual's mapped reference point lands at the requested position.
     (struct-copy
      affine-map-visual
      visual
      [map
       (affine2-with-translation
        map
        (vec2- position
               (affine2-apply-vector map content-position)))]))])

;; affine-map : visual? affine2? -> affine-map-visual?
;; Applies map in world coordinates to a complete top-level Visual.  It keeps
;; the wrapped Visual's stable identity, so it can replace that Visual in a
;; scene state without changing drawing order.
(define (affine-map content map)
  (affine-map-visual content map))

;; affine-map-visual-with-map : affine-map-visual? affine2?
;;                             -> affine-map-visual?
(define (affine-map-visual-with-map visual map)
  (unless (affine-map-visual? visual)
    (raise-argument-error 'affine-map-visual-with-map
                          "affine-map-visual?"
                          visual))
  (unless (affine2? map)
    (raise-argument-error 'affine-map-visual-with-map "affine2?" map))
  (struct-copy affine-map-visual visual [map map]))

;; affine-map-visual-content+map : visual? -> (values visual? affine2?)
;; Unwraps one already-mapped Visual for compositional animation. Ordinary
;; Visuals act as though they have the identity outer map.
(define (affine-map-visual-content+map visual)
  (unless (visual? visual)
    (raise-argument-error 'affine-map-visual-content+map "visual?" visual))
  (if (affine-map-visual? visual)
      (values (affine-map-visual-content visual)
              (affine-map-visual-map visual))
      (values visual identity-affine2)))
