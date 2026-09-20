#lang racket/base

;;;
;;; Calculus Audit Regressions
;;;

;; These focused public-API checks retain the mathematical counterexamples
;; from the 2026-09-20 audit. Native sampling and clipping checks live in the
;; renderer smoke suite because their oracle is a rendered frame.

(require rackunit
         "../main.rkt"
         (only-in "../private/core.rkt"
                  calculus-snapshot-function-value
                  calculus-snapshot-formula-text
                  calculus-snapshot-formula-tex
                  calculus-snapshot-formula-fragments
                  calculus-snapshot-motion-state
                  calculus-snapshot-presentation-state))

(provide run-calculus-audit-regression-tests)

(define (model-result model name [computation default-calculus-computation])
  (calculus-snapshot-ref (calculus-model-at model #:computation computation) name))

(define (check-value result expected)
  (check-equal? (calculus-result-status result) 'defined)
  (check-equal? (calculus-result-value result) expected))

(define (model-function-value model name input)
  (define snapshot (calculus-model-at model))
  (define function-result (calculus-snapshot-ref snapshot name))
  (if (eq? (calculus-result-status function-result) 'defined)
      (calculus-snapshot-function-value snapshot
                                        (calculus-result-value function-result)
                                        input)
      function-result))

(define audit-timing
  (calculus-timing #:opening-pause 0 #:read-delay 0
                   #:action-duration 1 #:step-pause 0))

(define audit-profile (calculus-profile #:timing audit-timing))

(define-calculus-model derivative-regressions
  (model
    [cube (function (x) (expt x 3))]
    [constant (function (x) 5)]
    [power-zero (function (x) (expt x 0))]
    [quotient (function (x) (/ 1 (+ x 1))
                        #:domain (domain-except real-line -1))]
    [second (derivative-function cube #:order 2)]
    [constant-prime (derivative-function constant)]
    [power-zero-prime (derivative-function power-zero)]
    [quotient-prime (derivative-function quotient)]))

(define-calculus-model integral-regressions
  (model
    [f (function (x) x)]
    [g (function (x) (* x x))]
    [F (antiderivative-function f #:using (function (x) (/ (* x x) 2)))]
    [G (antiderivative-function g #:using (function (x) (/ (* x x x) 3)))]
    [correct (definite-integral f #:from 0 #:to 1 #:antiderivative F)]
    [wrong-source (definite-integral f #:from 0 #:to 1 #:antiderivative G)]
    [quartic (function (x) (expt x 4))]
    [adaptive (definite-integral quartic #:from 0 #:to 1)]))

(define-calculus-lesson label-and-group-regressions
  (model [P (point 0 0)])
  (views [plot (graph-view #:x (closed -1 1) #:y (closed -1 1) #:objects (P))])
  (initially (show P) (deemphasize P))
  (step labels (hide-label P))
  (step grouped (together (normalize P) (pause 1))))

(define-calculus-lesson vary-regressions
  (model [a (parameter 0 #:domain (closed 0 2))])
  (views [axis (number-line-view #:range (closed 0 2) #:objects (a))])
  (initially (show a))
  (step route (vary a #:via (list 2) #:to 1 #:easing 'linear #:duration 3)))

;; Policies are sampled transient presentation tracks, not endpoint-only
;; records. This compact fixture gives headless coverage to graph/line reveal
;; and the guided-reading phase before native smoke tests inspect pixels.
(define-calculus-lesson motion-regressions
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [A (point 0 0)]
    [B (point 1 1)]
    [L (segment A B)]
    [R (input-reading G 1)])
  (views [plot (graph-view #:x (closed -1 2) #:y (closed -1 2)
                           #:objects (G L R))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step reveal (show G L))
  (step explain-reading (read R)))

(define-calculus-lesson refinement-regressions
  (model
    [n (parameter 2 #:kind 'integer #:domain (closed 2 8))]
    [f (function (x) x)]
    [partition (uniform-partition 0 2 #:count n)]
    [tags (tag-partition partition #:sample 'midpoint)]
    [sum (riemann-sum f tags)]
    [boxes (riemann-rectangles sum)])
  (views [plot (graph-view #:x (closed 0 2) #:y (closed 0 2)
                           #:objects (boxes))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (initially (show boxes))
  (step refine-boxes (refine partition #:counts (list 4 8) #:duration 2)))

(define-calculus-model part-regressions
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G 2)]
    [answer (x-coordinate (part R 'point))]))

(define-calculus-component audit-plus-one
  (inputs [a : (Parameter Scalar)])
  (model [y (+ a 1)])
  (exports y))

(define-calculus-model component-regressions
  (model
    [a (parameter 2 #:domain (closed 0 3))]
    [study (use-component audit-plus-one a)]))

(define-calculus-model live-field-regressions
  (model
    [a (parameter 9 #:domain (closed -20 20))]
    [equation (formula (= (value a) (+ (ref a) 1)))]))

;; run-calculus-audit-regression-tests : -> void?
;;   Exercises each repaired headless semantic contract at its public boundary.
(define (run-calculus-audit-regression-tests)
  (check-value (model-function-value derivative-regressions 'second 1) 6)
  (check-value (model-function-value derivative-regressions 'constant-prime 3) 0)
  (check-value (model-function-value derivative-regressions 'power-zero-prime 3) 0)
  (check-value (model-function-value derivative-regressions 'quotient-prime 1) -1/4)
  (check-value (model-result integral-regressions 'correct) 1/2)
  (check-equal? (calculus-result-status (model-result integral-regressions 'wrong-source))
                'undefined)
  (check-equal?
   (calculus-result-status
    (model-result
     integral-regressions 'adaptive
     (calculus-computation #:absolute-tolerance 1e-12 #:relative-tolerance 1e-12
                           #:integration-budget 3)))
   'unresolved)
  (check-= (calculus-result-value
            (model-result
             integral-regressions 'adaptive
             (calculus-computation #:absolute-tolerance 1e-10 #:relative-tolerance 1e-10
                                   #:integration-budget 4096)))
            1/5 1e-9)
  (define approximate-model
    (let ()
      (define-calculus-model model (model [a (sin 1)] [b (+ a 0)]))
      model))
  (check-true (calculus-result-approximate? (model-result approximate-model 'b)))
  (check-value (model-result part-regressions 'answer) 2)
  (check-value (calculus-snapshot-ref (calculus-model-at component-regressions) '(study y)) 3)
  (define labels-final
    (calculus-plan-sample
     (compile-calculus-lesson label-and-group-regressions #:profile audit-profile)
     #:at 'final))
  (check-true (calculus-snapshot-visible? labels-final 'P))
  (check-equal? (calculus-snapshot-presentation-state labels-final 'P) 'normal)
  (define route-plan (compile-calculus-lesson vary-regressions #:profile audit-profile))
  (check-value (calculus-snapshot-ref (calculus-plan-sample route-plan #:at 2) 'a) 2)
  (check-value (calculus-snapshot-ref (calculus-plan-sample route-plan #:at 3/4) 'a) 3/4)
  (define motion-plan (compile-calculus-lesson motion-regressions #:profile audit-profile))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 1/2) 'G)
                '(graph trace 1/2))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 1/2) 'L)
                '(line extend 1/2))
  (check-equal? (calculus-snapshot-motion-state
                 (calculus-plan-sample motion-plan #:at 3/2) 'R)
                '(reading guided 1/2))
  (define refinement-plan
    (compile-calculus-lesson refinement-regressions #:profile audit-profile))
  (define refinement-quarter
    (calculus-plan-sample refinement-plan #:at 1/2))
  (check-value (calculus-snapshot-ref refinement-quarter 'n) 2)
  (check-equal? (calculus-snapshot-motion-state refinement-quarter 'boxes)
                '(refinement subdivide 1/4 4))
  (check-equal? (calculus-snapshot-presentation-state refinement-quarter 'boxes)
                'refining)
  (define-calculus-model notation
    (model [equation (formula (* (+ 1 2) 3))]
           [power (formula (expt (+ 1 2) 10))]
           [root (formula (sqrt (+ 1 2)))]
           [nested-fraction (formula (/ (+ 1 2) (/ 3 4)))]))
  (define notation-snapshot (calculus-model-at notation))
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-text notation-snapshot 'equation))
                "(1 + 2) · 3")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'power))
                "{1 + 2}^{10}")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'root))
                "\\sqrt{1 + 2}")
  (check-equal? (calculus-result-value
                 (calculus-snapshot-formula-tex notation-snapshot 'nested-fraction))
                "\\frac{1 + 2}{\\frac{3}{4}}")
  (define live-initial (calculus-model-at live-field-regressions))
  (define live-final (calculus-model-at live-field-regressions #:values (hash 'a 10)))
  (define initial-fragments
    (calculus-result-value
     (calculus-snapshot-formula-fragments live-initial 'equation)))
  (define final-fragments
    (calculus-result-value
     (calculus-snapshot-formula-fragments live-final 'equation)))
  ;; The field payload can change width (9→10), while held prefix/suffix
  ;; fragments retain their source order for the prepared native field layout.
  (check-equal? (map car initial-fragments) (map car final-fragments))
  (check-equal? (map car initial-fragments) '(field text))
  (check-equal? (cadr (car initial-fragments)) "9")
  (check-equal? (cadr (car final-fragments)) "10"))

(module+ test
  (run-calculus-audit-regression-tests))
