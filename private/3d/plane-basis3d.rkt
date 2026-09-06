#lang racket/base

;;;
;;; Stable Two-Dimensional Coordinates for One Plane
;;;

(require "ray-plane.rkt" "vec3.rkt")

(provide (struct-out plane-basis3d)
         plane3d-basis
         plane-basis3d-project
         plane-basis3d-unproject
         plane-basis3d-signed-area
         plane-basis3d-centroid)

(struct plane-basis3d (plane u v) #:transparent)

; plane3d-basis : plane3? -> plane-basis3d?
;; Selects the least-aligned cardinal axis as a deterministic seed.  u cross v
;; is the authored plane normal.
(define (plane3d-basis plane)
  (unless (plane3? plane) (raise-argument-error 'plane3d-basis "plane3?" plane))
  (define normal (vec3-normalize (plane3-normal plane)))
  (define seed
    (argmin (lambda (axis) (abs (vec3-dot normal axis)))
            (list x-axis3 y-axis3 z-axis3)))
  (define u (vec3-normalize (vec3-cross seed normal)))
  (define v (vec3-cross normal u))
  (plane-basis3d plane u v))

(define (plane-basis3d-project basis point)
  (unless (plane-basis3d? basis) (raise-argument-error 'plane-basis3d-project "plane-basis3d?" basis))
  (unless (vec3? point) (raise-argument-error 'plane-basis3d-project "vec3?" point))
  (define offset (vec3- point (plane3-point (plane-basis3d-plane basis))))
  (vector (vec3-dot offset (plane-basis3d-u basis))
          (vec3-dot offset (plane-basis3d-v basis))))

(define (plane-basis3d-unproject basis coordinates)
  (unless (plane-basis3d? basis) (raise-argument-error 'plane-basis3d-unproject "plane-basis3d?" basis))
  (unless (and (vector? coordinates) (= (vector-length coordinates) 2))
    (raise-argument-error 'plane-basis3d-unproject "two-coordinate vector" coordinates))
  (vec3+ (plane3-point (plane-basis3d-plane basis))
         (vec3+ (vec3-scale (vector-ref coordinates 0) (plane-basis3d-u basis))
                (vec3-scale (vector-ref coordinates 1) (plane-basis3d-v basis)))))

(define (plane-basis3d-signed-area basis points)
  (unless (and (plane-basis3d? basis) (list? points) (andmap vec3? points))
    (raise-argument-error 'plane-basis3d-signed-area "plane basis and list of points" (list basis points)))
  (if (< (length points) 3)
      0
      (/ (for/sum ([point (in-list points)] [next (in-list (append (cdr points) (list (car points))))])
           (define first-2d (plane-basis3d-project basis point))
           (define second-2d (plane-basis3d-project basis next))
           (- (* (vector-ref first-2d 0) (vector-ref second-2d 1))
              (* (vector-ref first-2d 1) (vector-ref second-2d 0))))
         2)))

(define (plane-basis3d-centroid basis points)
  (unless (and (plane-basis3d? basis) (pair? points) (andmap vec3? points))
    (raise-argument-error 'plane-basis3d-centroid "plane basis and nonempty list of points" (list basis points)))
  (vec3-scale (/ 1 (length points))
              (for/fold ([sum origin3]) ([point (in-list points)]) (vec3+ sum point))))

(define (argmin score values)
  (for/fold ([best (car values)]) ([value (in-list (cdr values))])
    (if (< (score value) (score best)) value best)))
