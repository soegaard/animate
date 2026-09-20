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
                  calculus-model-nodes
                  calculus-snapshot-presentation-state
                  calculus-snapshot-function-branch
                  calculus-snapshot-function-branch-value
                  calculus-snapshot-formula-text))

;; Exports
(provide run-calculus-guide-lesson-tests
         guide-reading-square
         guide-secant-to-tangent
         guide-build-derivative
         guide-limit-not-value
         guide-sums-and-accumulation
         guide-component-example)


;;;
;;; Guide Fixtures
;;;

;; guide-reading-square : calculus-lesson?
;;   Retains the complete opening Guide lesson, including its named readout and
;;   linear parameter path rather than a simplified graph-only substitute.
(define-calculus-lesson guide-reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a #:input-label 'both #:output-label 'both)]
    [name (graph-label G "f" #:at 3/2)]
    [output (value-readout (part R 'output)
                           #:label "f(a)" #:format 'decimal #:digits 2)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R name))]
    [facts (formula-view #:objects (output))])
  (roles [G 'primary] [R 'input] [output 'output])
  (initially (show G name))
  (step read-two
    #:say "The input is 2. Read the corresponding output."
    (read R)
    (show output))
  (step scan-inputs
    #:say "Now vary the input from 2 to −2."
    (vary a #:to -2 #:easing 'linear #:duration 4))
  (step compare-ends
    #:say "Both 2 and −2 have output 4."
    (highlight output)))

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
    [L (limit-statement m #:parameter h #:to 0 #:value 2 #:side 'right
                        #:justification "The finite secant quotient approaches the supplied tangent slope.")]
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
  (step introduce-tangent (limit-transition S T #:claim L)))

;; guide-build-derivative : calculus-lesson?
;;   Retains the complete Guide derivative correspondence: the tangent slope
;;   and derivative-graph ordinate share one moving input rather than a screen
;;   coordinate tween.
(define-calculus-lesson guide-build-derivative
  (model
    [a (parameter -2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [df (derivative-function f #:method 'symbolic)]
    [G (graph f)]
    [D (graph df)]
    [P (point-on G #:x a)]
    [T (tangent G #:at P #:derivative df)]
    [Q (point-on D #:x a)]
    [reading (coordinate-reading Q #:labels 'both)]
    [slope-value (slope T)]
    [link (quantity-correspondence
           slope-value (part reading 'output)
           #:justification "Both quantities are the derivative of f at input a.")]
    [meter (value-readout slope-value #:label "f′(a)" #:format 'decimal #:digits 2)]
    [derivative-trace (trace-of Q #:parameter a #:over (closed -2 2))]
    [definition (formula-of df)])
  (views
    [function-plot (graph-view #:x (closed -5/2 5/2)
                               #:y (closed -1 5)
                               #:objects (G P T))]
    [derivative-plot (graph-view #:x (closed -5/2 5/2)
                                 #:y (closed -5 5)
                                 #:objects (D Q reading derivative-trace))]
    [facts (formula-view #:objects (meter definition))])
  (roles [G 'primary] [T 'auxiliary] [D 'result]
         [derivative-trace 'result] [Q 'output])
  (initially (show G P T Q))
  (step transfer-slope
    (show reading meter)
    (highlight-quantity slope-value))
  (step trace-slopes
    (trace derivative-trace #:duration 1))
  (step name-derivative
    (together (hide derivative-trace) (show D))
    (show definition)))

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
    [boxes (riemann-rectangles sum)]
    [q (sum-value sum)]
    [I (definite-integral f #:from 0 #:to 2 #:antiderivative F)]
    [sum-value-label (value-readout q #:label "Sₙ" #:format 'decimal #:digits 4)]
    [integral-value-label (value-readout I #:label "I" #:format 'exact)]
    [x (parameter 0 #:domain (closed 0 2))]
    [A (accumulation-function f #:from 0 #:antiderivative F)]
    [GA (graph A)]
    [region (integral-region G #:from 0 #:to x)]
    [B (point-on GA #:x x)]
    [A-trace (trace-of B #:parameter x #:over (closed 0 2))]
    [amount (value-at A x)]
    [amount-label (value-readout amount #:label "A(x)" #:format 'decimal #:digits 3)]
    [dA (derivative-function A #:method 'supplied #:using f #:justification "A′=f.")]
    [TA (tangent GA #:at B #:derivative dA)]
    [rate (slope TA)]
    [rate-label (value-readout rate #:label "A′(x)" #:format 'decimal #:digits 3)]
    [rate-link (quantity-correspondence rate (value-at f x)
                                        #:justification "A′(x)=f(x).")])
  (views
    [integrand (graph-view #:x (closed 0 2) #:y (closed 0 4) #:objects (G boxes region))]
    [accumulation (graph-view #:x (closed 0 2) #:y (closed 0 3) #:objects (GA B A-trace TA))]
    [facts (formula-view #:objects (sum-value-label integral-value-label amount-label rate-label))])
  (initially (show G))
  (step midpoint-samples (show boxes sum-value-label))
  (step refine-partition
    (refine partition #:counts (list 8 16 32) #:duration 3)
    (checkpoint rectangles-32))
  (step compare-integral
    (show integral-value-label)
    (compare sum-value-label integral-value-label))
  (step accumulate
    (hide boxes sum-value-label integral-value-label)
    (show region B amount-label)
    (trace A-trace #:duration 1))
  (step identify-accumulation
    (together (hide A-trace) (show GA)))
  (step accumulation-rate (show TA rate-label)))

;; guide-secant-study : calculus-component?
;;   The complete Guide §7 reusable construction. Its chord stays private to
;;   callers but is available during the declaration's own expanded exposition.
(define-calculus-component guide-secant-study
  (inputs [G : Graph]
          [a : Scalar]
          [h : Scalar])
  (model
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)]
    [S (secant G P Q)]
    [change (increment P Q)]
    [triangle (slope-triangle change)]
    [m (slope S)]
    [meter (value-readout m #:label "m" #:format 'decimal #:digits 3)])
  (exports P Q S change triangle m meter)
  (constraints (not (= h 0)))
  (exposition
    (step points
      #:say "Choose two points on the graph."
      (show P Q))
    (step chord
      #:say "Join the points with a chord."
      (show C))
    (step slope
      #:say "Extend the chord and compare the two coordinate changes."
      (hide C)
      (show S triangle meter))))

;; guide-component-example : calculus-lesson?
;;   Retains Guide §7 verbatim at the mathematical and exposition level.
(define-calculus-lesson guide-component-example
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component guide-secant-study G 1 h)])
  (views
    [plot
     (graph-view #:x (closed -1/2 5/2)
                 #:y (closed -1/2 5)
                 #:objects (G
                            (part study 'P)
                            (part study 'Q)
                            (part study 'S)
                            (part study 'triangle)))]
    [facts (formula-view #:objects ((part study 'meter)))])
  (roles
    [(part study 'S) 'auxiliary]
    [(part study 'triangle) 'increment])
  (initially (show G))
  (step introduce-study
    #:say "Compare the graph at a fixed input and a nearby input."
    (explain study #:mode 'expanded #:auxiliaries 'hide))
  (step decrease-increment
    #:say "Bring the second input closer to the first."
    (approach h #:to 0 #:side 'right #:until 1/10 #:duration 4)))


;;;
;;; Tests
;;;

;; run-calculus-guide-lesson-tests : -> void?
;;   Checks exact derived quantities and source-ordered piecewise branches.
(define (run-calculus-guide-lesson-tests)
  (define reading-plan (compile-calculus-lesson guide-reading-square))
  (check-equal? (length (calculus-plan-diagnostics reading-plan)) 0)
  (define reading-final (calculus-plan-sample reading-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref reading-final 'a)) -2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref reading-final '(R point)))
                (cons -2 4))
  (check-equal? (calculus-result-value (calculus-snapshot-ref reading-final '(R output))) 4)
  (check-true (calculus-snapshot-visible? reading-final 'output))
  (define secant-plan (compile-calculus-lesson guide-secant-to-tangent))
  (check-equal? (length (calculus-plan-diagnostics secant-plan)) 0)
  (define secant-final
    (calculus-plan-sample secant-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final '(change dx))) 1/20)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final '(change dy))) 41/400)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final 'm)) 41/20)
  (check-equal? (calculus-result-value (calculus-snapshot-ref secant-final 'tangent-slope)) 2)
  (check-false (calculus-snapshot-visible? secant-final 'S))
  (check-true (calculus-snapshot-visible? secant-final 'T))
  (define derivative-plan (compile-calculus-lesson guide-build-derivative))
  (check-equal? (length (calculus-plan-diagnostics derivative-plan)) 0)
  (define derivative-final (calculus-plan-sample derivative-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref derivative-final 'a)) 2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref derivative-final 'P)) (cons 2 4))
  (check-equal? (calculus-result-value (calculus-snapshot-ref derivative-final 'Q)) (cons 2 4))
  (check-equal? (calculus-result-value (calculus-snapshot-ref derivative-final 'slope-value)) 4)
  (check-false (calculus-snapshot-visible? derivative-final 'derivative-trace))
  (check-true (calculus-snapshot-visible? derivative-final 'D))
  ;; `highlight-quantity` follows the retained slope construction, its
  ;; author-declared output correspondence, and its visible readout. It does
  ;; not select the unrelated function graph merely because it has a matching
  ;; numeric value at this input.
  (define derivative-highlight
    (calculus-plan-sample derivative-plan #:at 3))
  (define derivative-nodes
    (calculus-model-nodes (calculus-lesson-model guide-build-derivative)))
  (define (derivative-node name) (hash-ref derivative-nodes name))
  (check-eq? (calculus-snapshot-presentation-state derivative-highlight
                                                    (derivative-node 'T))
             'highlighted)
  (check-eq? (calculus-snapshot-presentation-state derivative-highlight
                                                    (derivative-node 'reading))
             'highlighted)
  (check-eq? (calculus-snapshot-presentation-state derivative-highlight
                                                    (derivative-node 'meter))
             'highlighted)
  (check-eq? (calculus-snapshot-presentation-state derivative-highlight
                                                    (derivative-node 'G))
             'normal)
  (define limit-initial
    (calculus-plan-sample (compile-calculus-lesson guide-limit-not-value) #:at 'initial))
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial '(at-one output))) 4)
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial 'delta)) 1/2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial '(bands input-band)))
                (list 'input-band 1/2 3/2))
  (check-equal? (calculus-result-value (calculus-snapshot-ref limit-initial '(bands output-band)))
                (list 'output-band 3/2 5/2))
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
  (define accumulation-plan (compile-calculus-lesson guide-sums-and-accumulation))
  (check-equal? (length (calculus-plan-diagnostics accumulation-plan)) 0)
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-ref
     (calculus-plan-sample accumulation-plan #:at (calculus-checkpoint 'rectangles-32))
     'n))
   32)
  (define accumulation-final
    (calculus-plan-sample accumulation-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'n)) 32)
  (define component-plan (compile-calculus-lesson guide-component-example))
  (check-equal? (length (calculus-plan-diagnostics component-plan)) 0)
  (define component-final (calculus-plan-sample component-plan #:at 'final))
  (check-equal? (calculus-result-value (calculus-snapshot-ref component-final 'h)) 1/10)
  (check-equal? (calculus-result-value (calculus-snapshot-ref component-final '(study m))) 21/10)
  ;; A component's exported value-readout is displayed through its instantiated
  ;; private declaration, not by evaluating the public part as an opaque value.
  (check-equal?
   (calculus-result-value
    (calculus-snapshot-formula-text component-final '(study meter)))
   "m 2.100")
  (check-equal? (calculus-result-status (calculus-snapshot-ref component-final '(study C))) 'undefined)
  (check-true (calculus-snapshot-visible? component-final '(study S)))
  (check-true (calculus-snapshot-visible? component-final '(study triangle)))
  (check-true (calculus-snapshot-visible? component-final '(study meter)))
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'q)) 1365/512)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'I)) 8/3)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'x)) 2)
  (check-equal? (calculus-result-value (calculus-snapshot-ref accumulation-final 'rate)) 4)
  (check-true (calculus-snapshot-visible? accumulation-final 'GA))
  (check-true (calculus-snapshot-visible? accumulation-final 'TA)))

(module+ test
  (run-calculus-guide-lesson-tests))
