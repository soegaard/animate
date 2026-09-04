#lang racket/base

;;;
;;; Resolvable Visual Protocol
;;;

;; A resolvable Visual is a persistent semantic Visual definition whose
;; concrete result is obtained from one immutable sampled scene state.  This
;; deliberately says nothing about *how* dependencies are declared: the older
;; `derived-visual` discovers them through its context, while `relation-visual`
;; declares them explicitly.

(require racket/generic
         "visual-model.rkt")

(provide gen:resolvable-visual
         resolvable-visual?
         resolvable-visual-template
         resolvable-visual-dependencies
         resolvable-visual-phase
         resolve-resolvable-visual)

;; resolvable-visual-template : resolvable-visual? -> visual?
;; Returns the persistent template carrying the ordinary outer Visual identity
;; and envelope.
;;
;; resolvable-visual-dependencies : resolvable-visual? -> (listof any/c)
;; Returns declared dependency descriptions.  A derived Visual has no declared
;; descriptions and therefore returns the empty list.
;;
;; resolvable-visual-phase : resolvable-visual? -> symbol?
;; Returns the resolution phase.  EL-1 supports only `'semantic`; the generic
;; is present now so later renderer-aware layout relations do not require a
;; second resolver protocol.
;;
;; resolve-resolvable-visual : resolvable-visual? any/c -> visual?
;; Resolves one definition against the read-only sampled-state context supplied
;; by scene-state.  Concrete result validation remains the responsibility of
;; each implementation because relation output contracts grow in later stages.
(define-generics resolvable-visual
  (resolvable-visual-template resolvable-visual)
  (resolvable-visual-dependencies resolvable-visual)
  (resolvable-visual-phase resolvable-visual)
  (resolve-resolvable-visual resolvable-visual context))
