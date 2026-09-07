#lang racket/base

;; Deterministic eigendata for a finite real 3x3 matrix.  The closed cubic
;; route is bounded (unlike an unreported iterative routine) and lets us retain
;; convergence/near-defect diagnostics explicitly.

(require racket/list racket/math
         "../geometry.rkt" "linear3.rkt" "vec3.rkt")

(provide (struct-out eigensystem3d)
         eigensystem3d-of)

(struct eigensystem3d (eigenvalues real-directions diagnostics) #:transparent)

(define epsilon 1e-10)
(define (eigensystem3d-of matrix #:tolerance [tolerance epsilon])
  (unless (linear3? matrix) (raise-argument-error 'eigensystem3d-of "linear3?" matrix))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'eigensystem3d-of "positive finite real as #:tolerance" tolerance))
  (define tr (+ (linear3-m00 matrix) (linear3-m11 matrix) (linear3-m22 matrix)))
  (define c1 (+ (* (linear3-m00 matrix) (linear3-m11 matrix))
                (* (linear3-m00 matrix) (linear3-m22 matrix))
                (* (linear3-m11 matrix) (linear3-m22 matrix))
                (- (* (linear3-m01 matrix) (linear3-m10 matrix)))
                (- (* (linear3-m02 matrix) (linear3-m20 matrix)))
                (- (* (linear3-m12 matrix) (linear3-m21 matrix)))))
  (define det (linear3-determinant matrix))
  (define a (- tr)) (define b c1) (define c (- det))
  (define p (- b (/ (* a a) 3.0)))
  (define q (+ (/ (* 2.0 a a a) 27.0) (- (/ (* a b) 3.0)) c))
  (define discriminant (+ (* 0.25 q q) (* (/ p 3.0) (/ p 3.0) (/ p 3.0))))
  (define raw
    (cond [(> discriminant tolerance)
           (define root (sqrt discriminant))
           (define u (cuberoot (- (- (/ q 2.0)) root)))
           (define v (cuberoot (+ (- (/ q 2.0)) root)))
           (define real (- (+ u v) (/ a 3.0)))
           (define pair-real (- (- (/ (+ u v) 2.0)) (/ a 3.0)))
           (define imag (* (/ (sqrt 3.0) 2.0) (- u v)))
           (list (make-rectangular pair-real (abs imag))
                 (make-rectangular pair-real (- (abs imag))) real)]
          [(< discriminant (- tolerance))
           (define radius (* 2.0 (sqrt (- (/ p 3.0)))))
           (define cosine (max -1.0 (min 1.0 (/ (- (/ q 2.0)) (sqrt (- (* (/ p 3.0) (/ p 3.0) (/ p 3.0))))))))
           (define phi (acos cosine))
           (for/list ([k '(0 1 2)])
             (- (* radius (cos (/ (+ phi (* 2.0 pi k)) 3.0))) (/ a 3.0)))]
          [else
           (define u (cuberoot (- (/ q 2.0))) )
           (list (- (* 2.0 u) (/ a 3.0)) (- (- u) (/ a 3.0)) (- (- u) (/ a 3.0)))]))
  ;; Positive-imaginary member precedes its conjugate; otherwise real and
  ;; imaginary parts order ascending.  The original index remains a final
  ;; tie-breaker for defective matrices.
  (define ordered
    (map cdr
         (sort (for/list ([v (in-list raw)] [i (in-naturals)]) (cons i v))
               (lambda (left right)
                 (define l (cdr left)) (define r (cdr right))
                 (cond [(< (real-part l) (real-part r)) #t]
                       [(> (real-part l) (real-part r)) #f]
                       [(and (> (imag-part l) 0) (< (imag-part r) 0)) #t]
                       [(and (< (imag-part l) 0) (> (imag-part r) 0)) #f]
                       [(< (imag-part l) (imag-part r)) #t]
                       [(> (imag-part l) (imag-part r)) #f]
                       [else (< (car left) (car right))])))))
  (define values (vector->immutable-vector (list->vector ordered)))
  (define directions
    (vector->immutable-vector
     (list->vector
      (for/list ([value (in-list ordered)])
        (and (<= (abs (imag-part value)) tolerance)
             (real-eigenvector matrix (real-part value) tolerance))))))
  (define distinct (remove-duplicates (map (lambda (x) (list (real-part x) (imag-part x))) ordered) equal?))
  (eigensystem3d values directions
                (hasheq 'method 'closed-cubic
                        'characteristic-discriminant discriminant
                        'tolerance tolerance
                        'defective-or-near-defective? (< (abs discriminant) tolerance)
                        'distinct-eigenvalue-count (length distinct))))

(define (cuberoot x) (if (negative? x) (- (expt (- x) (/ 1.0 3.0))) (expt x (/ 1.0 3.0))))
(define (real-eigenvector m lambda tolerance)
  (define r0 (vec3 (- (linear3-m00 m) lambda) (linear3-m01 m) (linear3-m02 m)))
  (define r1 (vec3 (linear3-m10 m) (- (linear3-m11 m) lambda) (linear3-m12 m)))
  (define r2 (vec3 (linear3-m20 m) (linear3-m21 m) (- (linear3-m22 m) lambda)))
  (define candidates (list (vec3-cross r0 r1) (vec3-cross r0 r2) (vec3-cross r1 r2)))
  (define best (argmax vec3-length candidates))
  (and (> (vec3-length best) tolerance) (canonical-sign (vec3-normalize best))))
(define (canonical-sign v)
  (define parts (list (vec3-x v) (vec3-y v) (vec3-z v)))
  (define largest (argmax abs parts))
  (if (negative? largest) (vec3-scale -1 v) v))
