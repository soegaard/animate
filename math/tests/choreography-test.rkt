#lang racket/base

;;;
;;; Semantic Choreography Regression Tests
;;;

;; Exercises the transition defects seen in the dark videos, including intermediate
;; visibility and conservative semantic units. Geometry here is an explicit deterministic
;; fixture, not evidence of real native rendering.

;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/match
         "check.rkt"
         "cancellation-source-test.rkt"
         (submod "native-contract.rkt" support)
         "../main.rkt"
         "../private/datum.rkt"
         "../private/native.rkt"
         "../private/typeset-model.rkt"
         "../private/typeset.rkt"
         "../private/transition-plan.rkt"
         (only-in "../private/presentation.rkt" select-case-plan)
         (prefix-in adapter: "../private/animate-adapter.rkt")
         (prefix-in lc: "../examples/linear-concrete.rkt")
         (prefix-in lg: "../examples/linear-general.rkt")
         (prefix-in qc: "../examples/quadratic-concrete.rkt")
         (prefix-in qg: "../examples/quadratic-general.rkt"))

(provide run-choreography-tests)

;;;
;;; Geometry and Sampling Fixtures
;;;

; fixture-typesetter : math? real? symbol? string? path-string? -> prepared-layout?
;;   Includes fraction bars, radicals, signs, and deliberate one-pixel-like metric drift.
(define (fixture-typesetter state size multiplication foreground directory)
  (define source (format-math-source state #:multiplication multiplication))
  (define datum (math-datum state))
  (define spans
    (filter (lambda (span)
              (or (not (eq? (math-source-span-role span) 'expression))
                  (memq (head (datum-ref datum (math-source-span-path span))) '(/ sqrt))))
            (math-source-spans source)))
  (define drift (if (eq? (math-revision state) 'initial) 0 1/25))
  (prepared-layout state
    (for/list ([span (in-list spans)] [i (in-naturals)])
      (define path (math-source-span-path span))
      (define role (prepared-token-role-for-source-span state span))
      (define text (substring (math-source-text source) (math-source-span-start span) (math-source-span-end span)))
      (prepared-token path role text (format "fixture|~s|~s|~s" datum path role)
                      (* 3/20 i) 0 (+ 1/10 drift) (+ 2/5 drift)
                      (string->symbol (format "fixture-~a" i))))
    source '("Synthetic geometry with deliberate metric drift; not a render.")))

; fixture-tokens : math? -> (listof prepared-token?)
;;   Returns prepared fixture tokens for direct transition-plan inspection.
(define (fixture-tokens state)
  (prepared-layout-tokens (fixture-typesetter state 11/20 'school "white" "unused")))

; fixture-plan : rewrite-step? -> (values token-transition? list? list?)
;;   Plans one step with realistic ownership roles and intentionally differing metrics.
(define (fixture-plan step)
  (define old (fixture-tokens (rewrite-step-before step)))
  (define new (fixture-tokens (rewrite-step-after step)))
  (values (plan-token-transition step old new) old new))

; check-partition : token-transition? list? list? -> void?
;;   Requires complete, disjoint source and destination visibility accounting.
(define (check-partition plan old new)
  (define sources (remove-duplicates (map token-match-source (token-transition-matches plan))))
  (define targets (map token-match-target (token-transition-matches plan)))
  (check-equal (sort (append sources (token-transition-outgoing plan)) <) (range (length old)) 'source-partition)
  (check-equal (sort (append targets (token-transition-incoming plan)) <) (range (length new)) 'target-partition))

; phase-by-name : presentation-plan? symbol? symbol? -> scheduled-phase?
;;   Finds the requested phase in the declared chronological lesson schedule.
(define (phase-by-name plan step kind)
  (findf (lambda (p) (and (eq? (let ([key (scheduled-phase-step p)]) (if (pair? key) (last key) key)) step)
                          (eq? (scheduled-phase-kind p) kind)))
         (plan-schedule plan)))

; sample-visual : scene? symbol? real? -> (or/c visual? #f)
;;   Samples a recorded contract clip with shared linear progress for visibility assertions.
(define (sample-visual scn id time)
  (define c (clip-for-time scn time))
  (and c
       (let ([start (hash-ref (clip-before c) id #f)]
             [end (hash-ref (clip-after c) id #f)])
         (and start end
              (let ([u (/ (- time (clip-start c)) (clip-duration c))])
                (struct-copy visual start
                  [opacity (+ (* (- 1 u) (visual-opacity start)) (* u (visual-opacity end)))]
                  [position (point (+ (* (- 1 u) (point-x (visual-position start))) (* u (point-x (visual-position end))))
                                   (+ (* (- 1 u) (point-y (visual-position start))) (* u (point-y (visual-position end)))))]))))))

; visibility-clips : scene? scheduled-phase? -> (listof clip?)
;;   Selects all native contract subclips implementing one semantic phase.
(define (visibility-clips scn phase)
  (filter (lambda (c) (and (>= (clip-start c) (scheduled-phase-start phase))
                           (< (clip-start c) (+ (scheduled-phase-start phase) (scheduled-phase-duration phase)))))
          (scene-clips scn)))

; check-replacement-barrier : scene? scheduled-phase? -> void?
;;   Samples every subclip and rejects a frame containing both old arithmetic and its result.
(define (check-replacement-barrier scn phase)
  (define cs (visibility-clips scn phase))
  (define outs
    (remove-duplicates
      (for*/list ([c (in-list cs)] [r (in-list (clip-requests c))]
                  #:when (and (eq? (request-kind r) 'fade) (= (request-value r) 0))) (request-id r))))
  (define ins
    (remove-duplicates
      (for*/list ([c (in-list cs)] [r (in-list (clip-requests c))]
                  #:when (and (eq? (request-kind r) 'fade) (= (request-value r) 1))) (request-id r))))
  (check-true (pair? outs) 'has-outgoing-focus)
  (check-true (pair? ins) 'has-incoming-focus)
  (for* ([c (in-list cs)] [u (in-list '(0 1/4 1/2 3/4))])
    (define time (+ (clip-start c) (* u (clip-duration c))))
    (define old-opacity (map (lambda (id) (visual-opacity (sample-visual scn id time))) outs))
    (define new-opacity (map (lambda (id) (visual-opacity (sample-visual scn id time))) ins))
    (check-true (or (andmap zero? old-opacity) (andmap zero? new-opacity)) 'no-old-new-hybrid)
    (check-true (andmap (lambda (x) (= x (car old-opacity))) old-opacity) 'whole-old-unit-opacity)
    (check-true (andmap (lambda (x) (= x (car new-opacity))) new-opacity) 'whole-new-unit-opacity)))

;;;
;;; Review Regressions
;;;

; run-choreography-tests : -> void?
;;   Checks semantic visibility, signed reordering, shared cases, and explanatory insets.
(define (run-choreography-tests)
  (run-cancellation-source-tests)
  (test-group "review: complete token partitions and metric-independent identity"
    (lambda ()
      (for* ([plan (in-list (list lc:plan lg:plan qc:plan qg:plan))]
              [segment (in-list (presentation-plan-segments plan))]
              [step (in-list (derivation-steps (plan-segment-derivation segment)))])
        (define-values (transition old new) (fixture-plan step))
        (check-partition transition old new))
      (for ([name '(cancel-five reduce-left remove-one)])
        (define-values (plan old new) (fixture-plan (derivation-step lc:solution name)))
        (for ([i (in-list (tokens-at-path old '(1)))])
          (check-false (member i (token-transition-outgoing plan)) (list name 'rhs-never-retires))))))
  (test-group "review: both-sides introduction preserves unchanged SVG appearance"
    (lambda ()
      (define solution
        (derive lc:problem [subtract-five (both-sides 'subtract 5)]))
      (define plan
        (choreograph
          (present solution
                   #:style (math-presentation #:history 'replace #:duration 1
                                              #:pause-between-groups 0))
          [subtract-five (prepare-space #:duration 1/2)
                         (reveal-created #:duration 2/5)]))
      (define step (derivation-step solution 'subtract-five))
      (define source-tokens (fixture-tokens (rewrite-step-before step)))
      (define target-tokens (fixture-tokens (rewrite-step-after step)))
      (define source-relation
        (findf (lambda (token) (eq? (prepared-token-role token) 'relation))
               source-tokens))
      (define target-relation
        (findf (lambda (token) (eq? (prepared-token-role token) 'relation))
               target-tokens))
      (define source-rhs
        (findf (lambda (token)
                 (and (equal? (prepared-token-path token) '(1))
                      (eq? (prepared-token-role token) 'atom)
                      (string=? (prepared-token-text token) "17")))
               source-tokens))
      (define target-rhs
        (findf (lambda (token)
                 (and (equal? (prepared-token-path token) '(1 0))
                      (eq? (prepared-token-role token) 'atom)
                      (string=? (prepared-token-text token) "17")))
               target-tokens))
      (check-true source-relation 'source-relation-is-explicit)
      (check-true target-relation 'target-relation-is-explicit)
      (check-true source-rhs 'source-rhs-is-explicit)
      (check-true target-rhs 'target-rhs-is-explicit)
      (check-false (equal? (prepared-token-asset source-rhs)
                           (prepared-token-asset target-rhs))
                   'fixture-requires-distinct-checkpoint-assets)
      (parameterize ([current-native-loader loader]
                     [current-math-typesetter fixture-typesetter])
        (define scn (adapter:math-plan->scene! plan))
        (define final-svg-assets
          (for/list ([visual (in-hash-values (scene-visuals scn))]
                     #:when (eq? (visual-kind visual) 'svg))
            (visual-content visual)))
        (check-true (member (prepared-token-asset source-relation) final-svg-assets)
                    'unchanged-relation-keeps-source-appearance)
        (check-false (member (prepared-token-asset target-relation) final-svg-assets)
                     'unchanged-relation-is-not-swapped-at-checkpoint)
        (check-true (member (prepared-token-asset source-rhs) final-svg-assets)
                    'unchanged-rhs-keeps-source-appearance)
        (check-false (member (prepared-token-asset target-rhs) final-svg-assets)
                     'unchanged-rhs-is-not-swapped-at-checkpoint))))
  (test-group "review: cancellation preserves separators between surviving addends"
    (lambda ()
      (define step (derivation-step qc:solution 'cancel-five))
      (define-values (plan old new) (fixture-plan step))
      (define target-plus
        (for/first ([token (in-list new)] [i (in-naturals)]
                    #:when (and (equal? (prepared-token-path token) '(0))
                                (eq? (prepared-token-role token) 'operator-1)
                                (string=? (prepared-token-text token) "+")))
          i))
      (check-true (exact-nonnegative-integer? target-plus) 'surviving-plus-present)
      (define match
        (findf (lambda (entry) (= (token-match-target entry) target-plus))
               (token-transition-matches plan)))
      (check-true match 'surviving-plus-is-preserved)
      (define source-plus (list-ref old (token-match-source match)))
      (check-equal (prepared-token-path source-plus) '(0 0) 'source-separator-from-old-sum)
      (check-equal (prepared-token-role source-plus) 'operator-1 'same-adjacent-survivors)
      (check-false (member (token-match-source match) (token-transition-outgoing plan))
                   'surviving-plus-never-fades)
      (check-false (member target-plus (token-transition-incoming plan))
                   'surviving-plus-never-recreated)))
  (test-group "review: numeric results replace entire focused expressions"
    (lambda ()
      (for ([name '(evaluate-twelve evaluate-four)])
        (define step (derivation-step lc:solution name))
        (define-values (plan old new) (fixture-plan step))
        (check-equal (token-transition-atomic-sources plan) '((1)))
        (check-equal (token-transition-outgoing plan) (tokens-at-path old '(1)))
        (check-equal (token-transition-incoming plan) (tokens-at-path new '(1))))
      (parameterize ([current-native-loader loader] [current-math-typesetter fixture-typesetter])
        (define linear (adapter:math-plan->scene! lc:plan))
        (for ([name '(evaluate-twelve evaluate-four)])
          (check-replacement-barrier linear (phase-by-name lc:plan name 'transition)))
        (define quadratic (adapter:math-plan->scene! qc:plan))
        (for ([name '(make-square evaluate-four evaluate-roots evaluate-answers)])
          (check-replacement-barrier quadratic (phase-by-name qc:plan name 'transition)))
        (check-raises
          (lambda () (adapter:math-plan->scene!
                        (choreograph lc:plan
                          [evaluate-twelve (reveal-created) (retire-removed) (compact)])))
          #rx"Retire"))))
  (test-group "review: split copies whole bases before introducing complete radicals"
    (lambda ()
      (define step (derivation-step qc:solution 'split-roots))
      (define-values (plan old new) (fixture-plan step))
      (check-equal (token-transition-kind plan) 'split)
      (for ([p '((0 1) (1 1))])
        (for ([i (in-list (tokens-at-path new p))])
          (check-true (member i (token-transition-incoming plan)) 'whole-radical-created)))
      (for ([m (in-list (token-transition-matches plan))])
        (check-true (path-prefix? '(0 0) (prepared-token-path (list-ref old (token-match-source m))))
                    'only-the-shared-base-moves))
      (check-true (< (length (remove-duplicates (map token-match-source (token-transition-matches plan))))
                     (length (token-transition-matches plan))) 'actual-source-copies)
      (parameterize ([current-native-loader loader] [current-math-typesetter fixture-typesetter])
        (define scn (adapter:math-plan->scene! qc:plan))
        (define copied (phase-by-name qc:plan 'split-roots 'compact))
        (define copied-clips (visibility-clips scn copied))
        (check-true (pair? copied-clips) 'branch-copy-phase-exists)
        (for ([c (in-list copied-clips)])
          (check-true (andmap (lambda (r)
                                (and (eq? (request-kind r) 'fade)
                                     (= (request-value r) 1)))
                              (clip-requests c))
                      'branch-copies-appear-at-destination)
          (check-false (ormap (lambda (r) (eq? (request-kind r) 'move))
                              (clip-requests c))
                       'branch-copies-never-cross)))))
  (test-group "review: reordered additive focuses crossfade as coherent units"
    (lambda ()
      (define branch (select-case-plan qg:plan '(quadratic two-real-roots)))
      (define step
        (derivation-step
         (plan-segment-derivation (car (presentation-plan-segments branch)))
         'order-numerators))
      (define-values (plan old new) (fixture-plan step))
      (check-equal (token-transition-kind plan) 'reorder)
      (check-equal (token-transition-atomic-sources plan) '((0 1 0) (1 1 0)))
      (check-equal (token-transition-atomic-targets plan) '((0 1 0) (1 1 0)))
      (for ([p (in-list (token-transition-atomic-sources plan))])
        (for ([i (in-list (tokens-at-path old p))])
          (check-true (member i (token-transition-outgoing plan))
                      'whole-old-additive-focus-retires)))
      (for ([p (in-list (token-transition-atomic-targets plan))])
        (for ([i (in-list (tokens-at-path new p))])
          (check-true (member i (token-transition-incoming plan))
                      'whole-new-additive-focus-arrives)))
      (for ([m (in-list (token-transition-matches plan))])
        (define source-path (prepared-token-path (list-ref old (token-match-source m))))
        (define target-path (prepared-token-path (list-ref new (token-match-target m))))
        (check-false
         (ormap (lambda (p) (path-prefix? p source-path))
                (token-transition-atomic-sources plan))
         'no-source-glyph-motion-inside-reorder-focus)
        (check-false
         (ormap (lambda (p) (path-prefix? p target-path))
                (token-transition-atomic-targets plan))
         'no-target-glyph-motion-inside-reorder-focus))
      (for ([datum '((+ -3 x) (+ x -3) (- x 3) (+ (- x) 3))])
        (define state (math datum #:context (math-context #:real '(x))))
        (define op (apply-math-operation state (reorder-addends #:order '(1 0))))
        (define-values (tp a b) (fixture-plan op))
        (check-partition tp a b)
        (check-true (pair? (token-transition-atomic-sources tp)))
        (check-true (pair? (token-transition-atomic-targets tp))))
      (parameterize ([current-native-loader loader] [current-math-typesetter fixture-typesetter])
        (define scn (adapter:math-plan->scene! branch))
        (define retire (phase-by-name branch 'order-numerators 'retire-removed))
        (define reveal (phase-by-name branch 'order-numerators 'reveal-created))
        (for ([c (in-list (append (visibility-clips scn retire)
                                  (visibility-clips scn reveal)))])
          (check-true (andmap (lambda (r) (eq? (request-kind r) 'fade))
                              (clip-requests c))
                      'reorder-focus-uses-opacity-not-glyph-swaps)))))
  (test-group "review: whole-relation replacement never leaves a bare relation glyph"
    (lambda ()
      (define branch (select-case-plan qg:plan '(quadratic one-real-root)))
      (define derivation (plan-segment-derivation (car (presentation-plan-segments branch))))
      (define step (derivation-step derivation 'single-root))
      (define-values (plan old new) (fixture-plan step))
      (check-equal (token-transition-atomic-sources plan) '(()) 'whole-old-equation-atomic)
      (check-equal (token-transition-atomic-targets plan) '(()) 'whole-new-equation-atomic)
      (check-equal (token-transition-outgoing plan) (range (length old)) 'whole-old-equation-retires)
      (check-equal (token-transition-incoming plan) (range (length new)) 'whole-new-equation-arrives)))
  (test-group "review: case-start copies appear at their destination row"
    (lambda ()
      (parameterize ([current-native-loader loader] [current-math-typesetter fixture-typesetter])
        (define scn (adapter:math-plan->scene! qg:plan))
        (define segment-index
          (for/first ([segment (in-list (presentation-plan-segments qg:plan))]
                      [i (in-naturals)]
                      #:when (equal? (plan-segment-path segment) '(quadratic one-real-root)))
            i))
        (define copy-phase
          (findf (lambda (phase)
                   (and (= (scheduled-phase-segment phase) segment-index)
                        (= (scheduled-phase-group phase) 0)
                        (eq? (scheduled-phase-kind phase) 'copy-group)))
                 (plan-schedule qg:plan)))
        (check-false copy-phase 'case-copy-phase-omitted)
        (define first-step-phase
          (findf (lambda (phase)
                   (and (= (scheduled-phase-segment phase) segment-index)
                        (= (scheduled-phase-group phase) 0)
                        (equal? (scheduled-phase-step phase) '(take-root single-root))
                        (eq? (scheduled-phase-kind phase) 'transition)))
                 (plan-schedule qg:plan)))
        (check-true first-step-phase 'case-first-step-present)
        (define clips (visibility-clips scn first-step-phase))
        (check-true (pair? clips) 'case-first-step-native-clip-present))))
  (test-group "review: one shared quadratic prefix and stand-alone case restoration"
    (lambda ()
      (check-equal (length (filter plan-segment-shared? (presentation-plan-segments qg:plan))) 1)
      (check-equal (count (lambda (p) (and (eq? (scheduled-phase-kind p) 'checkpoint)
                                          (equal? (scheduled-phase-step p) '(complete-square make-square))))
                          (plan-schedule qg:plan)) 1 'complete-square-once)
      (check-true (< (plan-duration qg:plan) 60) 'shorter-without-deleting-cases)
      (for ([path '((quadratic two-real-roots) (quadratic one-real-root) (quadratic no-real-roots))])
        (define selected (select-case-plan qg:plan path))
        (define d (plan-segment-derivation (car (presentation-plan-segments selected))))
        (check-equal (math-datum (derivation-initial d)) (math-datum qg:problem))
        (check-true (derivation-step d 'make-square)))))
  (test-group "review: clean assumptions retain genuine exclusions and inset keeps checkpoint"
    (lambda ()
      (parameterize ([current-native-loader loader] [current-math-typesetter fixture-typesetter])
        (define two (select-case-plan qg:plan '(quadratic two-real-roots)))
        (define scn (adapter:math-plan->scene! two))
        (define text (car (visual-content (hash-ref (scene-visuals scn) 'math-lesson.context))))
        (check-true (regexp-match? #rx"a ≠ 0" text))
        (check-true (regexp-match? #rx"Δ > 0" text))
        (check-false (regexp-match? #rx"2·a|≥" text) 'no-derived-obligation-clutter)
        (define problem (math '(/ x x) #:context (math-context #:real '(x))))
        (define honest (adapter:math-plan->scene! (present (derive problem))))
        (check-true (regexp-match? #rx"x ≠ 0" (car (visual-content (hash-ref (scene-visuals honest) 'math-lesson.context)))))
        (define explanation (phase-by-name qc:plan 'add-nine 'explain))
        (check-equal (math-datum (car (presentation-phase-annotation (scheduled-phase-phase explanation))))
                     '(= (expt (/ 6 2) 2) 9))
        (check-equal (math-checkpoint-state (checkpoint-at qc:plan (scheduled-phase-start explanation)))
                     (math-checkpoint-state (checkpoint-at qc:plan (+ (scheduled-phase-start explanation) 1))))
        (define native (adapter:math-plan->scene! qc:plan))
        (check-false (ormap (lambda (key) (regexp-match? #rx"inset" (symbol->string key)))
                            (hash-keys (scene-visuals native))) 'inset-cleanup)))))
