#lang racket/base
(require rackunit "../3d.rkt")
(module+ test
  (define diagonal (eigensystem3d-of (linear3 1 0 0 0 -2 0 0 0 3)))
  (check-equal? (vector-length (eigensystem3d-eigenvalues diagonal)) 3)
  (check-= (vector-ref (eigensystem3d-eigenvalues diagonal) 0) -2 1e-8)
  (check-= (vector-ref (eigensystem3d-eigenvalues diagonal) 1) 1 1e-8)
  (check-= (vector-ref (eigensystem3d-eigenvalues diagonal) 2) 3 1e-8)
  ;; The closed-form eigensystem normalizes directions with flonum arithmetic.
  ;; Its mathematical direction is exact here, but its printed component can
  ;; differ from 1 by one floating-point unit.
  (define first-direction (vector-ref (eigensystem3d-real-directions diagonal) 0))
  (check-= (vec3-x first-direction) 0 1e-8)
  (check-= (vec3-y first-direction) 1 1e-8)
  (check-= (vec3-z first-direction) 0 1e-8)
  (check-equal? (hash-ref (eigensystem3d-diagnostics diagonal) 'method) 'closed-cubic)
  (define spiral (eigensystem3d-of (linear3 0 -1 0 1 0 0 0 0 -2)))
  (define values (eigensystem3d-eigenvalues spiral))
  (check-true (> (imag-part (vector-ref values 1)) 0))
  (check-true (< (imag-part (vector-ref values 2)) 0))
  (check-false (vector-ref (eigensystem3d-real-directions spiral) 1)))
