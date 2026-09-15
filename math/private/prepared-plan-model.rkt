#lang racket/base

;;;
;;; Prepared Mathematical Plan Model
;;;
;; Defines the immutable prepared-plan record and deterministic state enumeration
;; shared by the parent preparation adapter and portable worker reconstruction.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/list append-map remove-duplicates)
         "typeset-model.rkt"
         "model.rkt"
         "derivation.rkt"
         "presentation.rkt")

;; Exports
(provide (struct-out prepared-math-plan)
         math-preparation-states)


;;;
;;; Data Representation
;;;

(struct prepared-math-plan
  (plan layouts schedule camera foreground background row-gap max-rows diagnostics)
  #:transparent)

;; prepared-math-plan is an immutable record. Its fields have the following roles.
;;  - plan  presentation-plan?  worker-local or parent-local immutable lesson plan.
;;  - layouts  immutable-hash?  mathematical state to prepared-layout mapping.
;;  - schedule  (listof scheduled-phase?)  ordered frozen presentation phases.
;;  - camera  any/c  native camera frozen while the layouts were prepared.
;;  - foreground  string?  prepared mathematical foreground appearance value.
;;  - background  string?  prepared mathematical background appearance value.
;;  - row-gap  positive-real?  measured world-unit row spacing.
;;  - max-rows  exact-positive-integer?  visible-row bound derived once per plan.
;;  - diagnostics  (listof immutable-string?)  ordered preparation observations.


;;;
;;; Deterministic State Enumeration
;;;

; math-preparation-states : presentation-plan? -> (listof math?)
;;   Lists every derivation and explanation state requiring one prepared layout.
(define (math-preparation-states plan)
  (unless (presentation-plan? plan)
    (raise-argument-error 'math-preparation-states "presentation-plan?" plan))
  (define schedule (plan-schedule plan))
  (define explanation-states
    (for/list ([entry (in-list schedule)]
               #:when (eq? (scheduled-phase-kind entry) 'explain))
      (car (presentation-phase-annotation (scheduled-phase-phase entry)))))
  (remove-duplicates
   (append
    (append-map
     (lambda (segment)
       (derivation-states (plan-segment-derivation segment)))
     (presentation-plan-segments plan))
    explanation-states)))
