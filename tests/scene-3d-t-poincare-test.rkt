#lang racket/base

;;; SCENE-3D-T5: deterministic Poincare sections from dense trajectories.

(require rackunit
         (only-in racket/math pi)
         "../3d.rkt")

(module+ test
  ;; A circular orbit crosses x = 0 at pi/2 and 3pi/2.  Extraction is a pure
  ;; query over retained dense segments, so it cannot call the original field.
  (define calls (box 0))
  (define orbit
    (prepare-ode-trajectory3d
     (lambda (x y _z)
       (set-box! calls (add1 (unbox calls)))
       (vec3 (- y) x 0))
     (vec3 1 0 0) #:time-range (cons 0 (* 2 pi))
     #:step-size 1/100))
  (define calls-after-preparation (unbox calls))
  (define section-plane (plane3 origin3 x-axis3))
  (define hits
    (poincare-section3d orbit section-plane #:trajectory-id 'orbit
                        #:tolerance 1e-8 #:deduplicate-time 1e-8))
  (check-equal? (unbox calls) calls-after-preparation)
  (check-true (immutable? hits))
  (check-equal? (vector-length hits) 2)
  (check-equal? (for/list ([hit (in-vector hits)]) (poincare-hit3d-trajectory-id hit))
                '(orbit orbit))
  (check-equal? (for/list ([hit (in-vector hits)]) (poincare-hit3d-crossing-index hit))
                '(0 1))
  (check-= (poincare-hit3d-time (vector-ref hits 0)) (/ pi 2) 1e-5)
  (check-= (poincare-hit3d-time (vector-ref hits 1)) (* 3/2 pi) 1e-5)
  (check-equal? (poincare-hit3d-direction (vector-ref hits 0)) 'negative)
  (check-equal? (poincare-hit3d-direction (vector-ref hits 1)) 'positive)
  (for ([hit (in-vector hits)])
    (check-= (vec3-x (poincare-hit3d-point hit)) 0 1e-8)
    (check-true (ode-event-hit3d? (poincare-hit3d-source-event hit)))
    (check-equal? (vector-length (poincare-hit3d-plane-coordinates hit section-plane)) 2))
  (check-equal?
   (vector-length (poincare-section3d orbit section-plane #:direction 'positive)) 1)
  (check-equal?
   (vector-length (poincare-section3d orbit section-plane #:direction 'negative)) 1)
  (check-true
   (group3d? (poincare-hits3d hits #:id 'markers
                              #:style (point-style3d #:size 8 #:color "gold"))))

  ;; A trajectory contained in a plane has no transverse crossing. It is a
  ;; tangent contact only when that policy is explicitly requested.
  (define coplanar
    (prepare-ode-trajectory3d
     (lambda (_x _y _z) x-axis3) origin3
     #:time-range (cons 0 1) #:step-size 1/10))
  (define tangent-plane (plane3 origin3 y-axis3))
  (check-equal? (vector-length (poincare-section3d coplanar tangent-plane)) 0)
  (define tangent-hits
    (poincare-section3d coplanar tangent-plane
                         #:tangent-policy 'include #:initial-hit 'include))
  (check-equal? (vector-length tangent-hits) 1)
  (check-equal? (poincare-hit3d-direction (vector-ref tangent-hits 0)) 'tangent)

  ;; A prepared map keeps a missing first/second return in its seed slot rather
  ;; than presenting a misleading partial global return function.
  (define map
    (prepare-poincare-map3d
     (lambda (x y _z) (vec3 (- y) x 0)) section-plane
     (explicit-seeds3d (list (vec3 1 0 0) origin3))
     #:solver (fixed-rk4-solver3d #:step-size 1/100)
     #:termination (trajectory-termination3d #:time-limit (* 2 pi))))
  (check-true (prepared-poincare-map3d? map))
  (check-equal? (vector-length (prepared-poincare-map3d-trajectories map)) 2)
  (check-true (poincare-hit3d? (vector-ref (prepared-poincare-map3d-first-hits map) 0)))
  (check-true (poincare-hit3d? (vector-ref (prepared-poincare-map3d-second-hits map) 0)))
  (check-false (vector-ref (prepared-poincare-map3d-first-hits map) 1))
  (check-true (pair? (vector-ref (prepared-poincare-map3d-pairs map) 0)))
  (check-false (vector-ref (prepared-poincare-map3d-pairs map) 1))
  (check-equal? (hash-ref (prepared-poincare-map3d-diagnostics map) 'missing-first-hits) 1))
