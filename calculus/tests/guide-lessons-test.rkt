#lang racket/base

;;;
;;; Calculus Guide Lesson Tests
;;;

;; These fixtures retain the mathematical cores of the Guide's complete
;; readings, secant, and limit lessons.  They catch regressions across parser,
;; held-function, domain, part-address, and timeline boundaries together.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt"
         (only-in "../private/core.rkt"
                  calculus-snapshot-function-branch
                  calculus-snapshot-function-branch-value))

;; Exports
(provide run-calculus-guide-lesson-tests)


;;;
;;; Guide Fixtures
;;;

;; guide-secant-to-tangent : calculus-lesson?
;;   Declares the Guide's supplied-derivative secant-to-tangent construction.
(define-calculus-lesson guide-secant-to-tangent
  (model
    [f (function (x) (* x x))]
    [df (derivative-function
         f #:method 'supplied
         #:using (function (x) (* 2 x))
         #:justification "The derivative of x² is 2x.")]
    [a 1]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [G (graph f)]
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)]
    [S (secant G P Q)]
    [change (increment P Q)]
    [m (difference-quotient f a h)]
    [T (tangent G #:at P #:derivative df)]
    [tangent-slope (slope T)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G P Q C S T))])
  (initially (show G))
  (step choose-points (show P Q))
  (step extend (hide C) (show S))
  (step approach-point
    (approach h #:to 0 #:side 'right #:until 1/20 #:duration 1))
  (step introduce-tangent (show T)))

;; guide-limit-not-value : calculus-lesson?
;;   Preserves the value-at-one versus nearby-limit distinction from the Guide.
(define-calculus-lesson guide-limit-not-value
  (model
    [u (parameter 0 #:domain (domain-except (closed 0 2) 1))]
    [epsilon (parameter 1/2 #:domain (open-closed 0 1))]
    [delta epsilon]
    [g (piecewise-function (x)
         [(= x 1) 4]
         [else (+ x 1)])]
    [G (graph g)]
    [at-one (input-reading G 1)]
    [nearby (input-reading G u)]
    [L (limit-statement (value-at g u)
                        #:parameter u #:to 1 #:value 2 #:side 'both
                        #:justification "Nearby inputs follow x+1.")]
    [bands (epsilon-delta-condition
            g #:at 1 #:limit 2 #:epsilon epsilon #:delta delta
            #:justification "Taking δ=ε works.")])
  (views
    [plot (graph-view #:x (closed -1/4 9/4)
                      #:y (closed 0 9/2)
                      #:objects (G at-one nearby
                                   (part bands 'input-band)
                                   (part bands 'output-band)))])
  (initially (show G))
  (step value-at-one (read at-one))
  (step approach-left
    (read nearby)
    (approach u #:to 1 #:side 'left #:until 9/10 #:duration 1))
  (step approach-right
    (set-parameter u 2)
    (approach u #:to 1 #:side 'right #:until 11/10 #:duration 1)))

;; guide-sums-and-accumulation : calculus-lesson?
;;   Exercises midpoint sums, supplied antiderivatives, and trace-driven sweep.
(define-calculus-lesson guide-sums-and-accumulation
  (model
    [f (function (t) (* t t))]
    [F (antiderivative-function
        f #:using (function (t) (/ (expt t 3) 3))
        #:justification "The derivative of t³/3 is t².")]
    [G (graph f)]
    [n (parameter 4 #:domain (integers 1 128) #:kind 'integer)]
    [partition (uniform-partition 0 2 #:count n)]
    [tags (tag-partition partition #:sample 'midpoint)]
    [sum (riemann-sum f tags)]
    [q (sum-value sum)]
    [I (definite-integral f #:from 0 #:to 2 #:antiderivative F)]
    [x (parameter 0 #:domain (closed 0 2))]
    [A (accumulation-function f #:from 0 #:antiderivative F)]
    [GA (graph A)]
    [B (point-on GA #:x x)]
    [A-trace (trace-of B #:parameter x #:over (closed 0 2))]
    [dA (derivative-function A #:method 'supplied #:using f #:justification "A′=f.")]
    [TA (tangent GA #:at B #:derivative dA)]
    [rate (slope TA)])
  (views
    [integrand (graph-view #:x (closed 0 2) #:y (closed 0 4) #:objects (G))]
    [accumulation (graph-view #:x (closed 0 2) #:y (closed 0 3) #:objects (GA B A-trace TA))])
  (initially (show G))
  (step show-sum (show q I))
  (step trace-accumulation (show GA) (trace A-trace #:duration 1)))


;;;
;;; Tests
;;;

;; run-calculus-guide-lesson-tests : -> void?
;;   Checks exact derived quantities and source-ordered piecewise branches.
(define (run-calculus-guide-lesson-tests)
  (define secant-final
    (calculus-plan-sample (compile-calculus-lesson guide-secant-to-tangent) #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final '(change dx))) 1/20)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final '(change dy))) 41/400)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final 'm)) 41/20)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final 'tangent-slope)) 2)
  (define limit-initial
    (calculus-plan-sample (compile-calculus-lesson guide-limit-not-value) #:at 'initial))
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial '(at-one output))) 4)
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial 'delta)) 1/2)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-function-branch
                  limit-initial
                  (calculus-result-value (calculus-snapshot-ref limit-initial 'g))
                  1))
                0)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-function-branch
                  limit-initial
                  (calculus-result-value (calculus-snapshot-ref limit-initial 'g))
                  9/10))
                'else)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-function-branch-value
                  limit-initial
                  (calculus-result-value (calculus-snapshot-ref limit-initial 'g))
                  'else
                  1))
                2)
  (define limit-final
    (calculus-plan-sample (compile-calculus-lesson guide-limit-not-value) #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-final 'u)) 11/10)
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-final '(nearby output))) 21/10)
  (define accumulation-final
    (calculus-plan-sample (compile-calculus-lesson guide-sums-and-accumulation) #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'q)) 21/8)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'I)) 8/3)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'x)) 2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'rate)) 4))

(module+ test
  (run-calculus-guide-lesson-tests))
