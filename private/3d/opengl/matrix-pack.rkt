#lang racket/base

;;;
;;; Animate-to-OpenGL Matrix Packing
;;;

;; Animate stores `linear3` values in row-major constructor order and applies
;; them to column vectors.  GLSL consumes column-major arrays.  This module is
;; intentionally pure so the convention is testable without a GL context.

(require (only-in racket/math nan? infinite?)
         ffi/vector
         "../affine3.rkt"
         "../camera3d.rkt"
         "../linear3.rkt"
         "../projection3d.rkt"
         "../rotation3.rkt"
         "../vec3.rkt")

(provide affine3->gl-matrix
         normal-transform->gl-matrix
         camera3d-view-matrix
         camera3d-projection-matrix
         camera3d-view-projection-matrix
         gl-matrix4-multiply
         gl-matrix4-apply-point
         finite-real->float32)

(define largest-float32 3.4028234663852886e38)

; finite-real->float32 : finite-real? -> single-flonum?
;; Fails at the backend boundary rather than silently changing a semantic
;; coordinate to infinity during GPU upload.
(define (finite-real->float32 value)
  (unless (and (real? value) (not (nan? value)) (not (infinite? value))
               (<= (abs value) largest-float32))
    (raise-argument-error 'finite-real->float32
                          "finite real representable as IEEE float32" value))
  ;; Racket CS does not provide `real->single-flonum` on every target.  The
  ;; ffi/vector representation is the portable conversion authority instead.
  ;; Read the value back to detect a platform conversion that would overflow.
  (define converted
    (f32vector-ref (f32vector (exact->inexact value)) 0))
  (unless (and (not (nan? converted)) (not (infinite? converted)))
    (raise-arguments-error 'finite-real->float32
                           "a value representable as IEEE float32"
                           "value" value))
  converted)

(define (f32 . values)
  (apply f32vector (map finite-real->float32 values)))

(define (linear3->gl-columns map translation)
  ;; Row-major Animate matrix becomes a column-major GLSL matrix.
  (f32 (linear3-m00 map) (linear3-m10 map) (linear3-m20 map) 0
       (linear3-m01 map) (linear3-m11 map) (linear3-m21 map) 0
       (linear3-m02 map) (linear3-m12 map) (linear3-m22 map) 0
       (vec3-x translation) (vec3-y translation) (vec3-z translation) 1))

; affine3->gl-matrix : affine3? -> f32vector?
(define (affine3->gl-matrix map)
  (unless (affine3? map)
    (raise-argument-error 'affine3->gl-matrix "affine3?" map))
  (linear3->gl-columns (affine3-linear map) (affine3-translation map)))

; normal-transform->gl-matrix : linear3? -> f32vector?
;; A GLSL mat3 is also column-major; this is the exact inverse-transpose
;; supplied by compiled instances, not a recomputed approximation.
(define (normal-transform->gl-matrix map)
  (unless (linear3? map)
    (raise-argument-error 'normal-transform->gl-matrix "linear3?" map))
  (f32 (linear3-m00 map) (linear3-m10 map) (linear3-m20 map)
       (linear3-m01 map) (linear3-m11 map) (linear3-m21 map)
       (linear3-m02 map) (linear3-m12 map) (linear3-m22 map)))

; camera3d-view-matrix : camera3d? -> f32vector?
;; Animate camera rotations map camera-local coordinates into world space.
;; Therefore world-to-view uses the inverse rotation and -R^-1 * position.
(define (camera3d-view-matrix camera)
  (unless (camera3d? camera)
    (raise-argument-error 'camera3d-view-matrix "camera3d?" camera))
  (define world->view
    (rotation3->linear3 (rotation3-invert (camera3d-rotation camera))))
  (define camera-position (camera3d-position camera))
  (define translation
    (linear3-apply-vector world->view
                          (vec3 (- (vec3-x camera-position))
                                (- (vec3-y camera-position))
                                (- (vec3-z camera-position)))))
  (linear3->gl-columns world->view translation))

; camera3d-projection-matrix : camera3d? positive-real? -> f32vector?
;; Uses OpenGL's [-w,w] clip-space z convention.  Animate view space has
;; forward along negative z, so the conventional right-handed projection is
;; directly applicable.
(define (camera3d-projection-matrix camera aspect)
  (unless (camera3d? camera)
    (raise-argument-error 'camera3d-projection-matrix "camera3d?" camera))
  (unless (and (real? aspect) (positive? aspect) (not (nan? aspect))
               (not (infinite? aspect)))
    (raise-argument-error 'camera3d-projection-matrix "positive finite real?" aspect))
  (define near (camera3d-near camera))
  (define far (camera3d-far camera))
  (define projection (camera3d-projection camera))
  (cond
    [(perspective-projection3d? projection)
     (define focal (/ 1.0
                      (tan (/ (perspective-projection3d-vertical-field-of-view projection)
                              2))))
     (f32 (/ focal aspect) 0 0 0
          0 focal 0 0
          0 0 (/ (- (+ far near)) (- far near)) -1
          0 0 (/ (* -2 far near) (- far near)) 0)]
    [(orthographic-projection3d? projection)
     (define half-height (/ (orthographic-projection3d-vertical-size projection) 2))
     (define half-width (* aspect half-height))
     (f32 (/ 1 half-width) 0 0 0
          0 (/ 1 half-height) 0 0
          0 0 (/ -2 (- far near)) 0
          0 0 (/ (- (+ far near)) (- far near)) 1)]
    [else
     (raise-arguments-error 'camera3d-projection-matrix
                            "a supported projection" "projection" projection)]))

(define (m-ref matrix row column)
  (f32vector-ref matrix (+ row (* 4 column))))

; gl-matrix4-multiply : f32vector? f32vector? -> f32vector?
;; Returns outer × inner, matching Animate's transformation composition.
(define (gl-matrix4-multiply outer inner)
  (unless (and (f32vector? outer) (= (f32vector-length outer) 16))
    (raise-argument-error 'gl-matrix4-multiply "f32vector of length 16" outer))
  (unless (and (f32vector? inner) (= (f32vector-length inner) 16))
    (raise-argument-error 'gl-matrix4-multiply "f32vector of length 16" inner))
  (apply f32
         (for*/list ([column (in-range 4)] [row (in-range 4)])
           (for/sum ([index (in-range 4)])
             (* (m-ref outer row index) (m-ref inner index column))))))

(define (camera3d-view-projection-matrix camera aspect)
  (gl-matrix4-multiply (camera3d-projection-matrix camera aspect)
                       (camera3d-view-matrix camera)))

; gl-matrix4-apply-point : f32vector? vec3? -> (vectorof flonum?)
;; Test helper for CPU/GPU projection conformance.  It returns homogeneous clip
;; coordinates in column-vector order rather than applying the perspective
;; divide implicitly.
(define (gl-matrix4-apply-point matrix point)
  (unless (and (f32vector? matrix) (= (f32vector-length matrix) 16))
    (raise-argument-error 'gl-matrix4-apply-point "f32vector of length 16" matrix))
  (unless (vec3? point)
    (raise-argument-error 'gl-matrix4-apply-point "vec3?" point))
  (define input (vector (vec3-x point) (vec3-y point) (vec3-z point) 1))
  (for/vector ([row (in-range 4)])
    (for/sum ([column (in-range 4)])
      (* (m-ref matrix row column) (vector-ref input column)))))
