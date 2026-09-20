#lang racket/base

;;;
;;; Calculus Public API Audit
;;;

;; Keeps the complete ordinary-export inventory from the conformance matrix
;; executable.  Contextual forms remain declaration-only syntax; this test
;; checks the intentionally small ordinary Racket surface separately.


;;;
;;; Imports and Runtime Paths
;;;

(require rackunit
         racket/list)

(define calculus-module 'animate/calculus)
(define calculus-render-module 'animate/calculus/render)


;;;
;;; Export Inventory
;;;

;; calculus-ordinary-exports : (listof symbol?)
;;   Lists all core values and declaration macros promised by the API index.
(define calculus-ordinary-exports
  '(define-calculus-lesson
    define-calculus-model
    define-calculus-component
    calculus-lesson? calculus-model? calculus-component? calculus-plan?
    calculus-snapshot? calculus-result? calculus-moment?
    calculus-profile calculus-theme calculus-style calculus-layout calculus-motion
    calculus-timing calculus-computation
    calculus-profile? calculus-theme? calculus-style? calculus-layout? calculus-motion?
    calculus-timing? calculus-computation?
    calculus-px calculus-rel calculus-em calculus-length?
    light-calculus-theme dark-calculus-theme
    classroom-light-profile classroom-dark-profile textbook-profile
    default-calculus-profile default-calculus-computation
    calculus-lesson-model calculus-model-at compile-calculus-lesson
    calculus-plan-duration calculus-plan-diagnostics calculus-plan-sample
    calculus-step-start calculus-step-end calculus-checkpoint
    calculus-snapshot-ref calculus-snapshot-visible? calculus-snapshot-diagnostics
    calculus-result-status calculus-result-method calculus-result-approximate?
    calculus-result-value calculus-result-message calculus-result->datum))

;; calculus-render-only-exports : (listof symbol?)
;;   Lists the render adapter additions beyond its exact core re-export.
(define calculus-render-only-exports
  '(calculus-render-quality calculus-render-quality?
    prepared-calculus-lesson? prepare-calculus-lesson prepare-calculus-plan
    prepared-lesson-plan prepared-lesson->scene prepared-lesson->pict
    prepared-lesson->visual lesson->scene lesson->pict lesson->visual))

;; module-export-names : module-path? -> (listof symbol?)
;;   Collects phase-zero values and syntax exports after the module is loaded.
(define (module-export-names module-path)
  (dynamic-require module-path #f)
  (define-values (values syntax) (module->exports module-path))
  (sort
   (remove-duplicates
   (append
     (append-map (lambda (phase) (map car (rest phase))) values)
     (append-map (lambda (phase) (map car (rest phase))) syntax)))
   symbol<?))


;;;
;;; Tests
;;;

(module+ test
  (check-equal? (module-export-names calculus-module)
                (sort calculus-ordinary-exports symbol<?))
  (check-equal? (module-export-names calculus-render-module)
                (sort (append calculus-ordinary-exports calculus-render-only-exports)
                      symbol<?)))
