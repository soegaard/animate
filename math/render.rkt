#lang racket/base

;;;
;;; Mathematical Rendering Adapter
;;;
;; Exposes explicit native scene preparation and rendering effects. Prepared geometry is
;; adapter data, not mathematical expression state.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "private/animate-adapter.rkt" "private/typeset.rkt")

;; Exports
(provide
  math-plan->scene! prepare-math-plan! math->visual! math-plan->pict! prepared-math-plan?
  prepared-math-plan-plan prepared-math-plan-layouts prepared-math-plan-schedule
  prepared-math-plan-camera prepared-math-plan-foreground prepared-math-plan-background
  prepared-math-plan-row-gap prepared-math-plan-max-rows prepared-math-plan-diagnostics
  prepared-layout? prepared-layout-state prepared-layout-tokens prepared-layout-source
  prepared-layout-diagnostics prepared-token? prepared-token-path prepared-token-role
  prepared-token-text prepared-token-asset prepared-token-x prepared-token-y
  prepared-token-width prepared-token-height prepared-token-id default-math-cache-directory)
