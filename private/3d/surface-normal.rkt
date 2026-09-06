#lang racket/base

;;;
;;; Deterministic Surface Normals
;;;

;; Computes finite, model-level normals for fixed surface grids.  Degenerate
;; samples are never normalized blindly: a documented neighbour and face-normal
;; fallback chain retains finite data and separately records unresolved sites.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "surface-grid.rkt"
         "vec3.rkt")

(provide surface-grid-vertex-normals
         surface-grid-face-normal
         surface-grid-finite-tangent-u
         surface-grid-finite-tangent-v)


;;;
;;; Grid Normals
;;;

; surface-grid-vertex-normals : surface-grid?
;                               [#:derivative-u (or/c #f procedure?)]
;                               [#:derivative-v (or/c #f procedure?)]
;                               -> (values immutable-vector? (listof exact-nonnegative-integer?))
;;   Computes one safe unit normal per grid vertex and reports unresolved sites.
(define (surface-grid-vertex-normals grid
                                     #:derivative-u [derivative-u #f]
                                     #:derivative-v [derivative-v #f])
  (unless (surface-grid? grid)
    (raise-argument-error 'surface-grid-vertex-normals "surface-grid?" grid))
  (unless (or (not derivative-u) (procedure? derivative-u))
    (raise-argument-error 'surface-grid-vertex-normals "(or/c #f procedure?)" derivative-u))
  (unless (or (not derivative-v) (procedure? derivative-v))
    (raise-argument-error 'surface-grid-vertex-normals "(or/c #f procedure?)" derivative-v))
  (define face-sums (adjacent-face-sums grid))
  (define unresolved '())
  (define normals
    (for*/vector ([u-index (in-range (surface-grid-u-count grid))]
                  [v-index (in-range (surface-grid-v-count grid))])
      (define index (surface-grid-index grid u-index v-index))
      (define analytic
        (and derivative-u derivative-v
             (safe-analytic-normal grid u-index v-index derivative-u derivative-v)))
      (define finite (or analytic (safe-finite-normal grid u-index v-index)))
      (define fallback (safe-normalize (vector-ref face-sums index)))
      (or finite fallback
          (begin
            (set! unresolved (cons index unresolved))
            ;; Mesh attributes require finite vectors; the unresolved index is
            ;; carried separately so callers never mistake this fallback for a
            ;; mathematically established normal.
            z-axis3))))
  (values (vector->immutable-vector normals) (reverse unresolved)))

; surface-grid-face-normal : surface-grid? exact-nonnegative-integer? ... -> vec3?
;;   Returns a normalized parameter-cell face normal, or origin3 if degenerate.
(define (surface-grid-face-normal grid index0 index1 index2)
  (for ([index (in-list (list index0 index1 index2))])
    (unless (and (exact-nonnegative-integer? index)
                 (< index (vector-length (surface-grid-points grid))))
      (raise-argument-error 'surface-grid-face-normal "in-range vertex index" index)))
  (or (safe-normalize
       (vec3-cross
        (vec3- (vector-ref (surface-grid-points grid) index1)
               (vector-ref (surface-grid-points grid) index0))
        (vec3- (vector-ref (surface-grid-points grid) index2)
               (vector-ref (surface-grid-points grid) index0))))
      origin3))

; surface-grid-finite-tangent-u : surface-grid? exact-nonnegative-integer?
;                                 exact-nonnegative-integer? -> vec3?
;;   Uses centred differences in the interior and one-sided differences at edges.
(define (surface-grid-finite-tangent-u grid u-index v-index)
  (check-grid-location 'surface-grid-finite-tangent-u grid u-index v-index)
  (difference-on-axis grid u-index v-index 'u))

; surface-grid-finite-tangent-v : surface-grid? exact-nonnegative-integer?
;                                 exact-nonnegative-integer? -> vec3?
;;   Uses centred differences in the interior and one-sided differences at edges.
(define (surface-grid-finite-tangent-v grid u-index v-index)
  (check-grid-location 'surface-grid-finite-tangent-v grid u-index v-index)
  (difference-on-axis grid u-index v-index 'v))


;;;
;;; Fallback Chain
;;;

(define (safe-analytic-normal grid u-index v-index derivative-u derivative-v)
  (define u (vector-ref (surface-grid-u-values grid) u-index))
  (define v (vector-ref (surface-grid-v-values grid) v-index))
  (define du (derivative-u u v))
  (define dv (derivative-v u v))
  (unless (and (vec3? du) (vec3-finite? du))
    (raise-arguments-error 'surface-grid-vertex-normals
                           "a finite vec3? analytic u derivative"
                           "u" u "v" v "result" du))
  (unless (and (vec3? dv) (vec3-finite? dv))
    (raise-arguments-error 'surface-grid-vertex-normals
                           "a finite vec3? analytic v derivative"
                           "u" u "v" v "result" dv))
  (safe-normalize (vec3-cross du dv)))

(define (safe-finite-normal grid u-index v-index)
  (safe-normalize
   (vec3-cross (surface-grid-finite-tangent-u grid u-index v-index)
               (surface-grid-finite-tangent-v grid u-index v-index))))

(define (adjacent-face-sums grid)
  (define sums (make-vector (vector-length (surface-grid-points grid)) origin3))
  (for ([triangle (in-vector (surface-grid-triangles grid))])
    (define index0 (vector-ref triangle 0))
    (define index1 (vector-ref triangle 1))
    (define index2 (vector-ref triangle 2))
    (define normal (surface-grid-face-normal grid index0 index1 index2))
    (unless (zero? (vec3-length normal))
      (for ([index (in-list (list index0 index1 index2))])
        (vector-set! sums index (vec3+ (vector-ref sums index) normal)))))
  sums)

(define (difference-on-axis grid u-index v-index axis)
  (define maximum
    (if (eq? axis 'u) (sub1 (surface-grid-u-count grid))
        (sub1 (surface-grid-v-count grid))))
  (define current (if (eq? axis 'u) u-index v-index))
  (define (point index)
    (if (eq? axis 'u)
        (surface-grid-ref grid index v-index)
        (surface-grid-ref grid u-index index)))
  (cond [(zero? current) (vec3- (point 1) (point 0))]
        [(= current maximum) (vec3- (point maximum) (point (sub1 maximum)))]
        [else (vec3- (point (add1 current)) (point (sub1 current)))]))

(define (safe-normalize vector)
  (and (not (zero? (vec3-length vector)))
       (vec3-normalize vector)))

(define (check-grid-location who grid u-index v-index)
  (unless (surface-grid? grid) (raise-argument-error who "surface-grid?" grid))
  (surface-grid-index grid u-index v-index)
  (void))
