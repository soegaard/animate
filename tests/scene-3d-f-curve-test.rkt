#lang racket/base

;;; SCENE-3D-F Curve Semantics Tests

(require rackunit
         "../3d.rkt")

(module+ test
  (define curve
    (parametric-curve3d
     (lambda (t) (vec3 t (* t t) 0))
     #:range (list -1 1) #:samples 5 #:id 'parabola #:radius 1/10))
  ;; Deterministic endpoint-inclusive samples are the curve's authored data.
  (check-equal? (vector-ref (curve3d-points curve) 0) (vec3 -1 1 0))
  (check-equal? (vector-ref (curve3d-points curve) 4) (vec3 1 1 0))
  (check-equal? (curve3d-point-at curve 0) (vec3 -1 1 0))
  (check-equal? (curve3d-point-at curve 1) (vec3 1 1 0))
  (check-true (positive? (vec3-length (curve3d-tangent-at curve 1/2))))

  ;; Repeated adjacent samples are removed before tangents or tube frames are
  ;; derived; the remaining geometric line is still usable.
  (define repeated
    (polyline3d (list origin3 origin3 (vec3 1 0 0) (vec3 1 0 0) (vec3 2 0 0))
                #:id 'repeated))
  (check-equal? (vector-length (curve3d-points repeated)) 3)
  (check-equal? (curve3d-point-at repeated 1/2) (vec3 1 0 0))

  ;; A partial curve derives its shape from the original complete sequence,
  ;; rather than a previous partial frame.
  (define first-half (curve3d-partial repeated 0 1/2))
  (define last-half (curve3d-partial repeated 1/2 1))
  (check-equal? (curve3d-point-at first-half 1) (vec3 1 0 0))
  (check-equal? (curve3d-point-at last-half 0) (vec3 1 0 0)))
