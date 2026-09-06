#lang racket/base

(require rackunit
         ffi/vector
         "../3d.rkt"
         "../private/3d/opengl/matrix-pack.rkt")

(module+ test
  ;; Column-major packing must still implement the ordinary Animate affine map.
  (define map
    (affine3 (linear3 2 0 0
                      0 3 0
                      0 0 4)
             (vec3 5 6 7)))
  (define transformed (gl-matrix4-apply-point (affine3->gl-matrix map)
                                              (vec3 1 2 3)))
  (check-= (vector-ref transformed 0) 7.0 1e-5)
  (check-= (vector-ref transformed 1) 12.0 1e-5)
  (check-= (vector-ref transformed 2) 19.0 1e-5)
  (check-= (vector-ref transformed 3) 1.0 1e-5)

  ;; The default camera is at +z looking at the origin.  Its projection puts
  ;; the origin at the centre with a positive homogeneous w.
  (define camera (perspective-camera3d))
  (define clip
    (gl-matrix4-apply-point
     (camera3d-view-projection-matrix camera 16/9)
     origin3))
  (check-= (vector-ref clip 0) 0.0 1e-5)
  (check-= (vector-ref clip 1) 0.0 1e-5)
  (check-true (positive? (vector-ref clip 3)))

  ;; The packed projection is explicitly float32 and does not accept values
  ;; that would silently overflow at the GPU boundary.
  (check-true (f32vector? (camera3d-projection-matrix camera 1)))
  (check-exn exn:fail:contract?
             (lambda () (finite-real->float32 1e100))))
