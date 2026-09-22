#lang racket/base
(require animate/calculus)
(provide differentiate-x-squared-model mathematical-state sample-function)

(define-calculus-model differentiate-x-squared-model
  (model
    [f (function (x) (* x x))]
    [df (derivative-function f #:method 'supplied
          #:using (function (x) (* 2 x))
          #:justification "For h != 0, (f(x0+h)-f(x0))/h = h+2*x0, whose limit is 2*x0.")]
    [x0 (parameter 1 #:domain (closed -3 3))]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [probe-x (parameter 0 #:domain real-line)]
    [sample (value-at f probe-x)]
    [G (graph f)]
    [P (point-on G #:x x0)]
    [Q (point-on G #:x (+ x0 h))]
    [S (secant G P Q)]
    [change (increment P Q)]
    [dx (part change 'dx)]
    [dy (part change 'dy)]
    [m (difference-quotient f x0 h)]
    [T (tangent G #:at P #:derivative df)]
    [tangent-slope (slope T)]
    [L (limit-statement (slope S) #:parameter h #:to 0
         #:side 'right #:value (value-at df x0)
         #:justification "The finite demonstration stays at h>0. Algebra proves the two-sided limit h+2*x0 -> 2*x0.")]))

(define (required snapshot name)
  (define r (calculus-snapshot-ref snapshot name))
  (unless (eq? (calculus-result-status r) 'defined)
    (raise-arguments-error 'differentiation-example "mathematical result is not defined"
                           "name" name "result" (calculus-result->datum r)))
  (calculus-result-value r))

(define (mathematical-state x0 h)
  (define snapshot
    (calculus-model-at differentiate-x-squared-model #:values (hash 'x0 x0 'h h)))
  (for/hash ([name (in-list '(P Q dx dy m tangent-slope))])
    (values name (required snapshot name))))

(define (sample-function x)
  (required (calculus-model-at differentiate-x-squared-model
                              #:values (hash 'probe-x x)) 'sample))
