#lang racket/base

;;;
;;; Spatial Camera Fitting
;;;

;; Computes conservative camera endpoints for immutable 3D bounds.  The
;; calculation is pure and makes no assumptions about scene history or a
;; particular renderer.


;;;
;;; Imports and Exports
;;;

(require "../geometry.rkt"
         "bounds3.rkt"
         "camera3d.rkt"
         "projection3d.rkt"
         "vec3.rkt")

(provide camera3d-fit-bounds)


;;;
;;; Camera Fitting
;;;

; camera3d-fit-bounds : camera3d? aabb3? [#:aspect positive-real?]
;;                       [#:padding positive-real?] -> camera3d?
;;   Returns a camera that frames every corner of bounds conservatively.  A
;; perspective result looks at the bounds centre; an orthographic result keeps
;; its forward distance but moves to the corresponding centred target.
(define (camera3d-fit-bounds camera bounds
                             #:aspect [aspect 1]
                             #:padding [padding 11/10])
  (unless (camera3d? camera)
    (raise-argument-error 'camera3d-fit-bounds "camera3d?" camera))
  (unless (aabb3? bounds)
    (raise-argument-error 'camera3d-fit-bounds "aabb3?" bounds))
  (when (aabb3-empty? bounds)
    (raise-arguments-error 'camera3d-fit-bounds
                           "a nonempty spatial bounds value"
                           "bounds" bounds))
  (unless (and (finite-real? aspect) (positive? aspect))
    (raise-argument-error 'camera3d-fit-bounds "positive finite aspect" aspect))
  (unless (and (finite-real? padding) (positive? padding))
    (raise-argument-error 'camera3d-fit-bounds "positive finite padding" padding))
  (define center (aabb3-center bounds))
  (define forward (camera3d-forward camera))
  (define right (camera3d-right camera))
  (define up (camera3d-up camera))
  (define corners (aabb-corners bounds))
  (define projection (camera3d-projection camera))
  (cond
    [(perspective-projection3d? projection)
     (define tangent
       (tan (/ (perspective-projection3d-vertical-field-of-view projection) 2)))
     ;; For a candidate position C - dF, each point P needs
     ;; d + dot(P-C,F) >= |dot(P-C,R)|/tan-horizontal and the analogous
     ;; vertical inequality.  Taking the maximum produces a conservative
     ;; fit even when the original camera was not already aimed at centre.
     (define unpadded-distance
       (for/fold ([required (camera3d-near camera)])
                 ([corner (in-list corners)])
         (define displacement (vec3- corner center))
         (define forward-offset (vec3-dot displacement forward))
         (define horizontal-required
           (- (/ (abs (vec3-dot displacement right)) (* aspect tangent))
              forward-offset))
         (define vertical-required
           (- (/ (abs (vec3-dot displacement up)) tangent)
              forward-offset))
         (max required horizontal-required vertical-required)))
     (define distance (* padding unpadded-distance))
     (define position (vec3- center (vec3-scale distance forward)))
     (camera3d-look-at (camera3d-with-position camera position) center)]
    [else
     (define half-height
       (for/fold ([required 0])
                 ([corner (in-list corners)])
         (define displacement (vec3- corner center))
         (max required
              (abs (vec3-dot displacement up))
              (/ (abs (vec3-dot displacement right)) aspect))))
     (define visible-height (* 2 padding half-height))
     (define preserved-depth
       (vec3-dot (vec3- center (camera3d-position camera)) forward))
     (define position (vec3- center (vec3-scale preserved-depth forward)))
     (camera3d-look-at
      (camera3d-with-projection
       (camera3d-with-position camera position)
       (orthographic-projection3d (max visible-height 1e-9)))
      center)]))


;;;
;;; Local Helpers
;;;

(define (aabb-corners bounds)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (for*/list ([x (in-list (list (vec3-x minimum) (vec3-x maximum)))]
              [y (in-list (list (vec3-y minimum) (vec3-y maximum)))]
              [z (in-list (list (vec3-z minimum) (vec3-z maximum)))])
    (vec3 x y z)))
