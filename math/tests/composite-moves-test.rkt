#lang racket/base

;;;
;;; Composite Mathematical Move Tests
;;;
;; Checks hierarchical authoring without weakening elementary mathematics, and compares
;; all four migrated lessons with frozen pre-migration declarations and native contracts.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/list append-map last remove-duplicates)
         "check.rkt"
         "../main.rkt"
         "../private/native.rkt"
         "../private/typeset.rkt"
         "../private/prepare.rkt"
         "../private/prepared-plan-codec.rkt"
         (only-in "../private/presentation.rkt" select-case-plan)
         (prefix-in adapter: "../private/animate-adapter.rkt")
         (submod "native-contract.rkt" support)
         (prefix-in lc: "../examples/linear-concrete.rkt")
         (prefix-in lg: "../examples/linear-general.rkt")
         (prefix-in qc: "../examples/quadratic-concrete.rkt")
         (prefix-in qg: "../examples/quadratic-general.rkt")
         (prefix-in flat-lc: "fixtures/flat-linear-concrete.rkt")
         (prefix-in flat-lg: "fixtures/flat-linear-general.rkt")
         (prefix-in flat-qc: "fixtures/flat-quadratic-concrete.rkt")
         (prefix-in flat-qg: "fixtures/flat-quadratic-general.rkt"))

;; Exports
(provide run-composite-moves-tests)

;;;
;;; Comparison Helpers
;;;
; all-elementary-steps : (or/c derivation? case-derivation?) -> list?
;;   Enumerates unchanged primitive rewrite records through a guarded derivation tree.
(define (all-elementary-steps source)
  (if (derivation? source)
      (derivation-steps source)
      (append (derivation-steps (case-derivation-prefix source))
              (append-map (lambda (branch) (all-elementary-steps (case-branch-derivation branch)))
                          (case-derivation-branches source)))))

; local-name : (or/c symbol? list? #f) -> (or/c symbol? #f)
;;   Removes only the new address prefix when comparing otherwise identical schedules.
(define (local-name address)
  (if (pair? address) (last address) address))

; semantic-schedule : presentation-plan? -> list?
;;   Captures every phase decision apart from the new hierarchical spelling of its address.
(define (semantic-schedule plan)
  (for/list ([phase (in-list (plan-schedule plan))])
    (list (scheduled-phase-segment phase) (local-name (scheduled-phase-step phase))
          (scheduled-phase-kind phase) (scheduled-phase-start phase)
          (scheduled-phase-duration phase) (scheduled-phase-group phase)
          (scheduled-phase-phase phase))))

; sample-problem : math?
;;   Gives an exact real equation for small independent recipe and validation tests.
(define sample-problem
  (math '(= (+ x 2) 10) #:id 'composite-test #:context (math-context #:real '(a x))))

; subtract-and-cancel : math-datum? -> step-sequence?
;;   Demonstrates an ordinary reusable Racket recipe whose child steps remain inspectable.
(define (subtract-and-cancel amount)
  (steps [subtract (both-sides 'subtract amount)]
         [cancel (cancel-addends #:at (lhs))]))

; phase-durations : presentation-plan? list? list? -> list?
;;   Selects the phases for one exact case-relative leaf address.
(define (phase-durations plan case-path step-path)
  (for/list ([phase (in-list (plan-schedule plan))]
             #:when (and (equal? (scheduled-phase-step phase) step-path)
                         (equal? (plan-segment-path
                                  (list-ref (presentation-plan-segments plan)
                                            (scheduled-phase-segment phase))) case-path)
                         (not (eq? (scheduled-phase-kind phase) 'checkpoint))))
    (scheduled-phase-duration phase)))

;;;
;;; Recipe and Hierarchy Contracts
;;;
; run-composite-moves-tests : -> void?
;;   Runs pure semantics, address, grouping, case, adapter, and portable-layout parity checks.
(define (run-composite-moves-tests)
  (test-group "composite moves: reusable recipes and exact elementary lineage"
    (lambda ()
      (define recipe (subtract-and-cancel 2))
      (check-true (step-sequence? recipe))
      (check-equal (procedure-arity lc:math-render-preparer) 2 'fixed-preparer-contract)
      (check-equal (procedure-arity lc:math-render-builder) 3 'fixed-builder-contract)
      (check-false (math-operation? recipe) 'sequence-is-not-opaque-operation)
      (define d (derive sample-problem
                  [isolate (steps [remove (subtract-and-cancel 2)]
                                  [calculate (evaluate #:at (rhs))])]))
      (define flat (derive sample-problem
                     [subtract (both-sides 'subtract 2)]
                     [cancel (cancel-addends #:at (lhs))]
                     [calculate (evaluate #:at (rhs))]))
      (check-equal (derivation-steps d) (derivation-steps flat) 'exact-leaf-records)
      (check-equal (derivation-states d) (derivation-states flat) 'exact-held-states-and-lineage)
      (check-equal (derivation-step-paths d)
                   '((isolate remove subtract) (isolate remove cancel) (isolate calculate)))
      (check-equal (length (derivation-tree d)) 1)
      (define outer (derivation-node-at d 'isolate))
      (check-false (derivation-node-step outer))
      (check-equal (length (derivation-node-children outer)) 2)
      (check-equal (derivation-node-before outer) sample-problem)
      (check-equal (derivation-node-after outer) (derivation-final flat))
      (check-equal (derivation-node-relation outer) 'equation-equivalence)
      (check-equal (verification-status (derivation-node-verification outer)) 'established)
      (check-equal (after d 'isolate) (after d '(isolate calculate)))
      (check-equal (after d '(isolate remove)) (after flat 'cancel))
      (check-equal (derivation-step d 'subtract) (derivation-step d '(isolate remove subtract)))
      (check-raises (lambda () (derivation-step d 'isolate)) #rx"composite move")
      (check-raises (lambda () (derivation-node-at d '(remove cancel))) #rx"Unknown")
      (check-raises (lambda () (derivation-node-at d '())) #rx"nonempty")
      (check-equal (derive sample-problem [a recipe]) (derive sample-problem [a recipe]))
      (check-equal (derivation-tree (derive sample-problem)) '())
      (check-equal (plan-duration (present (derive sample-problem))) 9/5)))

  (test-group "composite moves: duplicate names, transactional construction, and scope"
    (lambda ()
      (define op (both-sides 'add 1))
      (check-raises (lambda () (steps/proc '())) #rx"nonempty")
      (check-raises (lambda () (steps/proc (list (cons 'a 1)))) #rx"math-operation")
      (check-raises (lambda () (steps/proc (list (cons 'a op) (cons 'a op)))) #rx"siblings")
      (check-raises (lambda () (derive/proc sample-problem (list (cons "bad" op)))) #rx"symbol")
      (define recipes (steps/proc (list (cons 'same op))))
      (define d (derive sample-problem [one recipes] [two recipes]))
      (check-equal (derivation-step-paths d) '((one same) (two same)))
      (check-raises (lambda () (derivation-step d 'same)) #rx"Ambiguous")
      (check-false (equal? (math-revision (after d '(one same)))
                          (math-revision (after d '(two same)))))
      (check-equal (length (derivation-steps d)) 2)
      (check-raises (lambda () (derive d [one op])) #rx"top-level siblings")
      (define extended (derive d [three (steps [same op])]))
      (check-equal (length (derivation-tree extended)) 3)
      (check-equal (take-first-two (derivation-tree extended)) (derivation-tree d))
      (define checked 0)
      (parameterize ([current-math-prover
                      (lambda (context proposition)
                        (set! checked (add1 checked)) (context-prove context proposition))])
        (define lazy-recipe (steps [later op]))
        (check-equal checked 0 'recipe-does-not-apply)
        (check-raises
         (lambda () (derive/proc sample-problem (list (cons 'valid lazy-recipe)
                                                      (cons 'invalid 17)))))
        (check-equal checked 0 'validate-siblings-before-application))
      (check-equal (length (derivation-tree d)) 2 'input-not-mutated)
      (define root-shadow (derive sample-problem [same op] [nested (steps [same op])]))
      (check-raises (lambda () (derivation-step root-shadow 'same)) #rx"Ambiguous")
      (check-equal (rewrite-step-name (derivation-step root-shadow '(same))) 'same)
      (check-raises (lambda () (choreograph (present root-shadow) [same (transition)]))
                    #rx"Ambiguous")))

  (test-group "composite moves: conditions and relationship summaries stay conservative"
    (lambda ()
      (define guarded (steps [divide (both-sides 'divide 'a)]))
      (define failure
        (with-handlers ([exn:fail:math? values])
          (derive sample-problem [unguarded guarded]) #f))
      (check-true (exn:fail:math? failure))
      (check-equal (exn:fail:math-code failure) 'pending-obligation)
      (check-true (regexp-match? #rx"unguarded divide" (exn-message failure)))
      (define draft
        (parameterize ([current-math-validation 'draft])
          (derive sample-problem [unguarded guarded])))
      (check-equal (verification-status
                    (derivation-node-verification (derivation-node-at draft 'unguarded))) 'unknown)
      (check-raises (lambda () (present draft)) #rx"unverified")
      (check-true (presentation-plan? (present draft #:allow-unverified? #t)))
      (define zero-a (math-with-context sample-problem
                       (context-assume (math-context-of sample-problem) '(= a 0))))
      (check-raises (lambda () (parameterize ([current-math-validation 'draft])
                                (derive zero-a [bad guarded]))) #rx"refuted|Refuted|nonzero|zero")
      (define squared (derive sample-problem
                        [forward (steps [square (both-sides 'power 2 #:relationship 'implication)]
                                         [add (both-sides 'add 0)])]))
      (check-equal (derivation-node-relation (derivation-node-at squared 'forward)) 'implication)
      (define specialized (derive sample-problem
                            [specialize (steps [set-x (substitute '((x . 8)))]
                                                [calculate (evaluate)])]))
      (check-equal (derivation-node-relation (derivation-node-at specialized 'specialize)) 'specialization)
      (define mixed (derive sample-problem
                      [mixed (steps [square (both-sides 'power 2 #:relationship 'implication)]
                                     [set-x (substitute '((x . 8)))])]))
      (check-equal (derivation-node-relation (derivation-node-at mixed 'mixed)) 'mixed)
      (check-equal (verification-status (derivation-node-verification (derivation-node-at mixed 'mixed)))
                   'established 'individual-checks-do-not-imply-equivalence)))

  (test-group "composite moves: presentation partitions and exact hierarchical overrides"
    (lambda ()
      (define d (derive sample-problem
                  [remove (subtract-and-cancel 2)]
                  [finish (steps [calculate (evaluate #:at (rhs))])]))
      (define p (present d))
      (check-equal (plan-segment-groups (car (presentation-plan-segments p)))
                   '(((remove subtract) (remove cancel)) ((finish calculate))))
      (check-equal (plan-schedule p) (plan-schedule (present d #:groups 'top-level)))
      (check-equal (length (plan-segment-groups (car (presentation-plan-segments
                                                     (present d #:groups 'steps))))) 3)
      (check-equal (plan-schedule p) (plan-schedule (present d #:groups '((remove) (finish)))))
      (check-equal (length (plan-segment-groups (car (presentation-plan-segments
                       (present d #:groups '(((remove subtract)) ((remove cancel) finish))))))) 2)
      (for ([bad (in-list '(invalid ((finish) (remove)) ((remove)) ((remove remove finish)) (()) ))])
        (check-raises (lambda () (present d #:groups bad))))
      (define tuned (choreograph p [(remove cancel) (transition #:duration 2)]))
      (check-equal (phase-durations tuned '() '(remove cancel)) '(2))
      (check-equal (presentation-plan-source tuned) d 'presentation-never-rewrites)
      (check-equal (vector-length (plan-checkpoints tuned)) 4 'no-extra-move-checkpoint)
      (check-equal (map math-checkpoint-state (vector->list (plan-checkpoints tuned)))
                   (derivation-states d))
      (check-raises (lambda () (choreograph p [remove (hold 1)])) #rx"composite")
      (define repeated (derive sample-problem
                          [one (steps [same (both-sides 'add 1)])]
                          [two (steps [same (both-sides 'add 2)])]))
      (check-raises (lambda () (choreograph (present repeated) [same (transition)])) #rx"Ambiguous")
      (define unique (choreograph (present repeated) [(two same) (transition #:duration 2)]))
      (check-equal (phase-durations unique '() '(two same)) '(2))
      (check-false (equal? (phase-durations unique '() '(one same)) '(2)))
      (parameterize ([current-native-loader loader] [current-math-typesetter synthetic-typesetter])
        (check-close (scene-duration (adapter:math-plan->scene! unique)) (plan-duration unique)))))

  (test-group "composite moves: case scopes, prefix grouping, and override specificity"
    (lambda ()
      (define prefix (derive sample-problem
                       [prefix (steps [begin (both-sides 'add 0)] [compute (evaluate #:at (rhs))])]))
      (define cases (derive-cases prefix
                      [positive '(> a 0) [work (steps [op (both-sides 'add 1)])]]
                      [zero '(= a 0) [work (steps [op (both-sides 'add 2)])]]
                      [negative '(< a 0) [work (steps [op (both-sides 'add 3)])]]))
      (define p (present cases #:groups 'top-level #:case-layout 'shared-prefix))
      (check-raises (lambda () (present cases #:groups (hash '(typo) 'top-level)))
                    #rx"unknown case path")
      (check-equal (length (presentation-plan-segments p)) 4)
      (check-true (plan-segment-shared? (car (presentation-plan-segments p))))
      (check-equal (after cases '(prefix begin)) (after prefix 'begin))
      (check-equal (rewrite-step-name (derivation-step cases '(positive work op))) 'op)
      (check-equal (derivation-node-path (derivation-node-at cases '(positive work))) '(work))
      (check-raises (lambda () (derivation-step cases 'op)) #rx"Unknown")
      (define tuned
        (choreograph p
          [op (transition #:duration 1)]
          [(work op) (transition #:duration 2)]
          [(positive work op) (transition #:duration 3)]
          [(prefix begin) (transition #:duration 5)]))
      (check-equal (phase-durations tuned '(positive) '(work op)) '(3))
      (check-equal (phase-durations tuned '(zero) '(work op)) '(2))
      (check-equal (phase-durations tuned '(negative) '(work op)) '(2))
      (define selected (select-case-plan tuned '(positive)))
      (check-equal (phase-durations selected '(positive) '(prefix begin)) '(5))
      (check-equal (phase-durations selected '(positive) '(work op)) '(3))
      (check-equal (length (derivation-tree (plan-segment-derivation
                                             (car (presentation-plan-segments selected))))) 2)
      (define conflicting
        (hash '(positive) '((prefix) (work))
              '(zero) '(((prefix begin)) ((prefix compute)) (work))
              '(negative) '((prefix) (work))))
      (check-raises (lambda () (present cases #:groups conflicting #:case-layout 'shared-prefix))
                    #rx"Shared prefix groups must agree")
      (define qualified
        (derive-cases sample-problem
          [nonzero '(not (= a 0)) [isolate (steps [divide (both-sides 'divide 'a)])]]
          [zero '(= a 0) [classify (steps [add (both-sides 'add 0)])]]))
      (check-equal (verification-status (derivation-verification qualified)) 'established)))

  (test-group "composite moves: all four lessons preserve every checkpoint and native contract"
    (lambda ()
      (for ([new (in-list (list lc:plan lg:plan qc:plan qg:plan))]
             [old (in-list (list flat-lc:plan flat-lg:plan flat-qc:plan flat-qg:plan))]
             [duration (in-list '(54/5 18 88/5 519/10))])
        (check-equal (derivation-states (presentation-plan-source new))
                     (derivation-states (presentation-plan-source old)) 'exact-states)
        (check-equal (all-elementary-steps (presentation-plan-source new))
                     (all-elementary-steps (presentation-plan-source old)) 'exact-witnesses)
        (check-equal (semantic-schedule new) (semantic-schedule old) 'exact-phase-behavior)
        (check-equal (plan-duration new) duration 'reviewed-duration)
        (for ([a (in-vector (plan-checkpoints new))] [b (in-vector (plan-checkpoints old))])
          (check-equal (math-checkpoint-state a) (math-checkpoint-state b))
          (check-equal (math-checkpoint-time a) (math-checkpoint-time b)))
        (parameterize ([current-native-loader loader] [current-math-typesetter synthetic-typesetter])
          (check-equal (adapter:math-plan->scene! new) (adapter:math-plan->scene! old)
                       'all-native-requests-identical))
        (for ([segment (in-list (presentation-plan-segments new))]
               #:unless (plan-segment-shared? segment))
          (define path (plan-segment-path segment))
          (define selected-new (select-case-plan new path))
          (define selected-old (select-case-plan old path))
          (check-equal (semantic-schedule selected-new) (semantic-schedule selected-old))
          (parameterize ([current-native-loader loader] [current-math-typesetter synthetic-typesetter])
            (check-equal (adapter:math-plan->scene! selected-new)
                         (adapter:math-plan->scene! selected-old) 'selected-case-native-parity))))))

  (test-group "composite moves: portable preparation retains paths and never typesets on rebind"
    (lambda ()
      (for ([plan (in-list (list lc:plan lg:plan qc:plan qg:plan))])
        (parameterize ([current-native-loader loader] [current-math-typesetter synthetic-typesetter])
          (define prepared (prepare-math-plan! plan #:theme 'dark))
          (define options (hasheq 'test 'composite-paths))
          (define payload (prepared-math-plan->portable-payload
                            prepared options (hash "synthetic-test-asset.svg" "synthetic-test-asset.svg")))
          (define same-plan (struct-copy-plan-with-same-source plan))
          (parameterize ([current-math-typesetter
                          (lambda ignored (error 'moves-test "rebind must not typeset"))]
                         [current-math-preparation-observer
                          (lambda ignored (error 'moves-test "rebind must not prepare"))])
            (define rebound (portable-payload->prepared-math-plan
                              payload same-plan (prepared-math-plan-camera prepared) options))
            (check-equal (prepared-math-plan-schedule rebound) (prepared-math-plan-schedule prepared))
            (check-equal (adapter:math-plan->scene! rebound) (adapter:math-plan->scene! prepared))))))))

; take-first-two : list? -> list?
;;   Extracts the expected immutable prefix without importing a broad list API.
(define (take-first-two sequence)
  (list (car sequence) (cadr sequence)))

; struct-copy-plan-with-same-source : presentation-plan? -> presentation-plan?
;;   Rebuilds a presentation from its source so portable checks do not require plan identity.
(define (struct-copy-plan-with-same-source plan)
  (define shared? (ormap plan-segment-shared? (presentation-plan-segments plan)))
  (plan-with-choreography
   (present (presentation-plan-source plan) #:style (presentation-plan-style plan)
            #:groups 'top-level #:case-layout (if shared? 'shared-prefix 'complete-paths))
   (for/list ([(key phases) (in-hash (presentation-plan-choreography plan))])
     (cons key phases))))
