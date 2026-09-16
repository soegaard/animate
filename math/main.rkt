#lang racket/base

;;;
;;; Held Mathematics and Derivations
;;;
;; Exposes the pure held-expression, rewrite, derivation, and presentation APIs.
;; Rendering and CAS execution require separate adapters.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "private/datum.rkt"
  "private/context.rkt"
  "private/evidence.rkt"
  "private/model.rkt"
  "private/select.rkt"
  "private/operations.rkt"
  "private/derivation.rkt"
  "private/steps.rkt"
  "private/rules.rkt"
  "private/format.rkt"
  "private/presentation.rkt")

;; Exports
(provide
  ;; Held expressions and occurrence inspection.
  math math? math-datum math-id math-context-of math-occurrences math-revision
  math-with-context math-occurrence-at math-inspect math-datum? held-substitute free-of?
  datum-ref datum-paths occurrence? occurrence-id occurrence-path occurrence-datum
  exn:fail:math? exn:fail:math-code exn:fail:math-details current-math-validation
  current-math-prover
  ;; Mathematical contexts and evidence.
  math-context math-context? math-context-real math-context-assumptions
  math-context-definitions math-context-restrictions context-assume context-add-restrictions
  context-expand context-prove context-signs context-real? context-inconsistent?
  context-facts check-case-coverage verification? verification-status verification-method
  verification-proposition verification-obligations verification-message
  verification-details established unknown refuted merge-verifications
  ;; Occurrence selectors.
  whole lhs rhs numerator denominator at-path matching all-matching operator-of selector?
  resolve-selector resolve-one math-select
  ;; Explicit operations and traceable templates.
  math-operation? math-operation-name math-operation-selector apply-math-operation
  both-sides cancel-addends cancel-factor remove-unit reduce-identities evaluate rewrite-to
  reorder-addends zero-product square-solutions abbreviate each-branch substitute conclude
  assert-step define-math-rule make-math-rule math-rule? math-rule-name use-rule apply-rule
  apply-rewrite template-bindings
  ;; Composable mathematical moves and their inspection hierarchy.
  steps steps/proc step-sequence? derivation-tree derivation-node?
  derivation-node-path derivation-node-before derivation-node-after
  derivation-node-children derivation-node-step derivation-node-at
  derivation-node-relation derivation-node-verification derivation-step-paths
  ;; Derivations and their inspection data.
  derive derive/proc derive-cases make-case-derivation derivation? derivation-initial
  derivation-steps derivation-final case-branch? case-branch-name case-branch-guard
  case-branch-derivation case-derivation? case-derivation-prefix case-derivation-branches
  case-derivation-coverage solution-check? solution-check-problem solution-check-variable
  solution-check-value solution-check-derivation solution-check-verification after
  derivation-step derivation-states derivation-verification check-solution rewrite-step?
  rewrite-step-name rewrite-step-before rewrite-step-after rewrite-step-rule
  rewrite-step-focus rewrite-step-bindings rewrite-step-links rewrite-step-trace
  rewrite-step-relation rewrite-step-verification rewrite-step-details rewrite-step-version
  trace-descendants path-link? path-link-source path-link-target path-link-kind
  path-link-subtree? trace-relation? trace-relation-kind trace-relation-sources
  trace-relation-targets trace-relation-details
  ;; Complete formula source and occurrence ranges.
  math->tex datum->tex format-math-source math->string math-source? math-source-text
  math-source-spans math-source-span? math-source-span-start math-source-span-end
  math-source-span-path math-source-span-role
  ;; Presentation policy and deterministic phase schedules.
  math-presentation math-presentation? classroom present choreograph presentation-style?
  presentation-style-anchor presentation-style-history presentation-style-start-group
  presentation-style-new-parts presentation-style-removed-parts presentation-style-reflow
  presentation-style-multiplication presentation-style-pause-between-groups
  presentation-style-duration presentation-style-font-size presentation-style-row-gap
  presentation-style-max-visible-rows presentation-plan? presentation-plan-source
  presentation-plan-style presentation-plan-segments presentation-plan-choreography
  presentation-plan-allow-unverified? plan-segment? plan-segment-path
  plan-segment-derivation plan-segment-groups plan-segment-context plan-segment-verdict
  plan-segment-shared?
  presentation-phase? presentation-phase-kind presentation-phase-duration
  presentation-phase-effect presentation-phase-layout presentation-phase-annotation scheduled-phase?
  scheduled-phase-segment scheduled-phase-step scheduled-phase-kind scheduled-phase-start
  scheduled-phase-duration scheduled-phase-group scheduled-phase-phase math-checkpoint?
  math-checkpoint-index math-checkpoint-segment math-checkpoint-step math-checkpoint-time
  math-checkpoint-state math-checkpoint-case-path plan-checkpoints checkpoint-at
  plan-schedule plan-duration plan-inspect prepare-space reveal-created retire-cancelled
  retire-removed compact hold transition explain-math plan-with-choreography)
