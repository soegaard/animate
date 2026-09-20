#lang racket/base

;;;
;;; Calculus Component Declaration Tests
;;;

;; Ensures component declarations remain lexical data and can be referenced by
;; a lesson model without exposing their private implementation names.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         "../main.rkt"
         (only-in "../private/core.rkt" calculus-plan-caption))

;; Exports
(provide run-calculus-component-declaration-tests)


;;;
;;; Fixture
;;;

;; secant-study : calculus-component?
;;   A Guide-shaped reusable declaration with private chord construction.
(define-calculus-component secant-study
  (inputs [G : Graph] [a : Scalar] [h : Scalar])
  (model
    [P (point-on G #:x a)]
    [Q (point-on G #:x (+ a h))]
    [C (chord G P Q)]
    [S (secant G P Q)])
  (exports P Q S)
  (constraints (not (= h 0)))
  (exposition
    (step introduce-points #:say "Place P and Q." #:duration 1
      (show P Q)
      (checkpoint points-shown))
    (step isolate-secant #:say "Retain the secant." #:duration 1
      (hide P)
      (show S))))

;; component-client : calculus-lesson?
;;   Instantiates the component through its lexical Racket binding.
(define-calculus-lesson component-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'S)))])
  (initially (show G))
  (step explain-study (explain study #:mode 'collapsed)))

;; expanded-component-client : calculus-lesson?
;;   Lets the declaration's lexical exposition contribute its own sequential
;;   presentation actions while retaining only public component addresses.
(define-calculus-lesson expanded-component-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'Q) (part study 'S)))])
  (initially (show G))
  (step explain-study #:say "Study the secant construction."
    (explain study #:mode 'expanded)))

;; replayed-expanded-component-client : calculus-lesson?
;;   Replaying one component instance gives its local checkpoints separate
;;   occurrence paths rather than overwriting the first explanation's moment.
(define-calculus-lesson replayed-expanded-component-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views
    [plot (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'Q) (part study 'S)))])
  (initially (show G))
  (step first-explanation (explain study #:mode 'expanded))
  (step second-explanation (explain study #:mode 'expanded)))

;; ambiguous-private-placement-client : calculus-lesson?
;;   Two caller graph views containing the same related exports must not cause
;;   a private construction to be placed in whichever view happens to render
;;   first.
(define-calculus-lesson ambiguous-private-placement-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views
    [main (graph-view #:x (closed -1/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G (part study 'P) (part study 'Q) (part study 'S)))]
    [inset (graph-view #:x (closed -1/2 5/2)
                       #:y (closed -1/2 5)
                       #:objects (G (part study 'P) (part study 'Q) (part study 'S)))])
  (initially (show G))
  (step explain-study (explain study #:mode 'expanded)))

;; parameter-motion-study : calculus-component?
;;   A Parameter<Scalar> declaration grants an explicit, narrow write
;;   capability to the supplied direct caller parameter.
(define-calculus-component parameter-motion-study
  (inputs [p : (Parameter Scalar)])
  (model [current p])
  (exports current)
  (exposition
    (step move-parameter #:duration 1
      (vary p #:to 1))))

;; scalar-motion-study : calculus-component?
;;   The identical mathematical input as Scalar can be read but cannot acquire
;;   the caller parameter's animation capability.
(define-calculus-component scalar-motion-study
  (inputs [p : Scalar])
  (model [current p])
  (exports current)
  (exposition
    (step attempt-move #:duration 1
      (vary p #:to 1))))

(define-calculus-lesson parameter-motion-client
  (model
    [a (parameter 0 #:domain (closed 0 1))]
    [study (use-component parameter-motion-study a)])
  (views [line (number-line-view #:range (closed 0 1) #:objects (a))])
  (initially (show a))
  (step explain-study (explain study #:mode 'expanded)))

(define-calculus-lesson scalar-motion-client
  (model
    [a (parameter 0 #:domain (closed 0 1))]
    [study (use-component scalar-motion-study a)])
  (views [line (number-line-view #:range (closed 0 1) #:objects (a))])
  (initially (show a))
  (step explain-study (explain study #:mode 'expanded)))

;; invalid-expanded-step-client : calculus-lesson?
;;   An expanded component sequence owns the enclosing caption/timing slot and
;;   cannot be mixed with another command or started in `together`.
(define-calculus-lesson invalid-expanded-step-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views [plot (graph-view #:x (closed -1/2 5/2)
                           #:y (closed -1/2 5)
                           #:objects (G (part study 'P)))])
  (initially (show G))
  (step invalid-sequence
    (explain study #:mode 'expanded)
    (pause 1)))

(define-calculus-lesson invalid-expanded-group-client
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [h (parameter 1 #:domain (open-closed 0 1))]
    [study (use-component secant-study G 1 h)])
  (views [plot (graph-view #:x (closed -1/2 5/2)
                           #:y (closed -1/2 5)
                           #:objects (G (part study 'P)))])
  (initially (show G))
  (step invalid-group
    (together (explain study #:mode 'expanded) (pause 1))))


;;;
;;; Tests
;;;

;; run-calculus-component-declaration-tests : -> void?
;;   Checks lexical component storage and client plan construction.
(define (run-calculus-component-declaration-tests)
  (check-true (calculus-component? secant-study))
  (check-true (calculus-lesson? component-client))
  (check-true (calculus-lesson? expanded-component-client))
  (check-true (calculus-component? parameter-motion-study))
  (define plan (compile-calculus-lesson component-client))
  (check-true (calculus-plan? plan))
  (define snapshot (calculus-plan-sample plan #:at 'final))
  ;; Exported component parts retain their caller-supplied graph and parameter
  ;; dependencies. The private chord is deliberately unavailable by address.
  (define point-result (calculus-snapshot-ref snapshot '(study P)))
  (check-equal? (calculus-result-status point-result) 'defined)
  (check-equal? (calculus-result-value point-result) (cons 1 1))
  (check-equal? (calculus-result-status (calculus-snapshot-ref snapshot '(study S))) 'defined)
  (check-equal? (calculus-result-status (calculus-snapshot-ref snapshot '(study C))) 'undefined)
  ;; A collapsed explanation makes public component presentations visible
  ;; through their instance root without exposing the private construction.
  (check-true (calculus-snapshot-visible? snapshot '(study P)))
  ;; Expanded mode lowers the component's own declared steps into the caller
  ;; timeline.  The final hide for P must override root inheritance, while Q
  ;; and S retain the public visibility authored by the component.
  (define expanded-plan (compile-calculus-lesson expanded-component-client))
  (check-true (> (calculus-plan-duration expanded-plan) 0))
  (define expanded-snapshot (calculus-plan-sample expanded-plan #:at 'final))
  (check-false (calculus-snapshot-visible? expanded-snapshot '(study P)))
  (check-true (calculus-snapshot-visible? expanded-snapshot '(study Q)))
  (check-true (calculus-snapshot-visible? expanded-snapshot '(study S)))
  ;; Nested local steps are stable semantic moments and captions, not an
  ;; incidental property of whatever native frame was previously rendered.
  (check-false
   (calculus-snapshot-visible?
    (calculus-plan-sample
     expanded-plan
     #:at (calculus-step-start '(explain-study study introduce-points)))
    '(study P)))
  (check-true
   (calculus-snapshot-visible?
    (calculus-plan-sample
     expanded-plan
     #:at (calculus-step-end '(explain-study study introduce-points)))
    '(study P)))
  (check-equal? (calculus-plan-caption expanded-plan
                                      (calculus-step-start 'explain-study))
                "Study the secant construction.")
  (check-equal? (calculus-plan-caption expanded-plan
                                      (calculus-step-start
                                       '(explain-study study introduce-points)))
                "Place P and Q.")
  ;; Component-local checkpoints receive the enclosing outer step, instance,
  ;; and component step prefixes. A second replay keeps a distinct occurrence
  ;; identity even though its local checkpoint spelling is the same.
  (check-true
   (calculus-snapshot-visible?
    (calculus-plan-sample
     expanded-plan
     #:at (calculus-checkpoint '(explain-study study introduce-points points-shown)))
    '(study P)))
  (define replayed-plan (compile-calculus-lesson replayed-expanded-component-client))
  (for ([address (in-list
                  '((first-explanation study introduce-points points-shown)
                    (second-explanation study introduce-points points-shown)))])
    (check-true
     (calculus-snapshot-visible?
      (calculus-plan-sample replayed-plan #:at (calculus-checkpoint address))
      '(study P))))
  ;; A private chord may be placed only when exactly one related caller graph
  ;; view is available; identical main/inset candidates are intentionally
  ;; diagnosed rather than selected by renderer order.
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson ambiguous-private-placement-client)))
                1)
  ;; The Parameter signature preserves only the caller's direct capability.
  ;; The Scalar signature sees the same live value but its local exposition
  ;; cannot animate that caller-owned parameter.
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref
                  (calculus-plan-sample (compile-calculus-lesson parameter-motion-client) #:at 'final)
                  'a))
                1)
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson parameter-motion-client)))
                0)
  (check-equal? (calculus-result-value
                 (calculus-snapshot-ref
                  (calculus-plan-sample (compile-calculus-lesson scalar-motion-client) #:at 'final)
                  'a))
                0)
  (check-equal? (length (calculus-plan-diagnostics
                         (compile-calculus-lesson scalar-motion-client)))
                1)
  (define invalid-step-plan (compile-calculus-lesson invalid-expanded-step-client))
  (define invalid-group-plan (compile-calculus-lesson invalid-expanded-group-client))
  (check-equal? (length (calculus-plan-diagnostics invalid-step-plan)) 1)
  (check-equal? (length (calculus-plan-diagnostics invalid-group-plan)) 1)
  ;; Neither invalid form silently falls back to collapsed root visibility.
  (check-false (calculus-snapshot-visible?
                (calculus-plan-sample invalid-step-plan #:at 'final) '(study P)))
  (check-false (calculus-snapshot-visible?
                (calculus-plan-sample invalid-group-plan #:at 'final) '(study P))))

(module+ test
  (run-calculus-component-declaration-tests))
