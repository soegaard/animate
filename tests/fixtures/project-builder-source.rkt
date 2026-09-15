#lang racket/base

;;;
;;; Module-builder Project Fixture
;;;

;; Exercises fixed module-builder preparation and construction contracts without
;; starting a renderer or creating output files.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../../main.rkt"
         "../../project.rkt")

;; Exports
(provide build-test-source!
         build-without-preparer!
         build-wrong-arity!
         build-multiple-values!
         build-invalid-result!
         prepare-test-inputs!
         prepare-wrong-arity!
         prepare-multiple-values!
         prepare-invalid-result!
         reset-builder-observations!
         builder-observations)


;;;
;;; Observations
;;;

; observed-builder-calls : (listof immutable-hash?)
;;   Accumulates test-only preparation and builder invocation snapshots.
(define observed-builder-calls '())

; reset-builder-observations! : -> void?
;;   Clears fixture observations before one isolated contract assertion.
(define (reset-builder-observations!)
  (set! observed-builder-calls '()))

; builder-observations : -> (listof immutable-hash?)
;;   Returns invocation observations in their original call order.
(define (builder-observations)
  (reverse observed-builder-calls))

; record-builder-call! : symbol? source-build-context? immutable-hash? any/c -> void?
;;   Records the contract-visible portion of one fixed source callback.
(define (record-builder-call! phase context options payload)
  (set! observed-builder-calls
        (cons
         (hasheq 'phase phase
                 'context context
                 'options options
                 'payload payload)
         observed-builder-calls)))


;;;
;;; Fixed-contract Exports
;;;

; prepare-test-inputs! : source-build-context? immutable-hash? -> source-preparation?
;;   Produces a small data-only preparation result for project contract tests.
(define (prepare-test-inputs! context options)
  (record-builder-call! 'prepare context options #f)
  (source-preparation
   #:payload (hasheq 'schema 'project-builder-fixture-v1
                     'base-fingerprint
                     (source-build-context-base-fingerprint context))
   #:artifacts (list (hasheq 'role 'fixture 'digest "fixture-digest"))
   #:diagnostics (hasheq 'prepared? #t)))

; build-test-source! : source-build-context? immutable-hash? any/c -> scene?
;;   Builds a deterministic Scene while recording its fixed three arguments.
(define (build-test-source! context options payload)
  (record-builder-call! 'build context options payload)
  (fixture-scene))

; build-without-preparer! : source-build-context? immutable-hash? false/c -> scene?
;;   Builds the same fixture Scene when no module preparer was declared.
(define (build-without-preparer! context options payload)
  (record-builder-call! 'build context options payload)
  (fixture-scene))

; build-wrong-arity! : source-build-context? immutable-hash? -> scene?
;;   Deliberately violates the required module-builder arity for loader tests.
(define (build-wrong-arity! context options)
  (fixture-scene))

; build-multiple-values! : source-build-context? immutable-hash? any/c -> any/c any/c
;;   Deliberately returns two values for loader result-count validation.
(define (build-multiple-values! context options payload)
  (values (fixture-scene) 'extra))

; build-invalid-result! : source-build-context? immutable-hash? any/c -> symbol?
;;   Deliberately returns a value outside the supported source-result union.
(define (build-invalid-result! context options payload)
  'not-a-render-source)

; prepare-wrong-arity! : source-build-context? -> source-preparation?
;;   Deliberately violates the required preparer arity for loader tests.
(define (prepare-wrong-arity! context)
  (source-preparation))

; prepare-multiple-values! : source-build-context? immutable-hash? -> any/c any/c
;;   Deliberately returns two values for preparer result-count validation.
(define (prepare-multiple-values! context options)
  (values (source-preparation) 'extra))

; prepare-invalid-result! : source-build-context? immutable-hash? -> symbol?
;;   Deliberately returns an unsupported preparation result for loader tests.
(define (prepare-invalid-result! context options)
  'not-source-preparation)

; fixture-scene : -> scene?
;;   Constructs the small deterministic Scene shared by fixture builders.
(define (fixture-scene)
  (scene-wait
   (scene-add
    (make-scene)
    (circle #:id 'builder-dot #:radius 1 #:fill "tomato"))
   1))
