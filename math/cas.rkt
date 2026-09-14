#lang racket/base

;;;
;;; Computer Algebra Service Adapter
;;;
;; Exposes validated service descriptions and bounded effectful queries. The pure
;; mathematical facade does not import this module.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "cas/model.rkt" "cas/protocol.rkt")

;; Exports
(provide
  (struct-out cas-service) (struct-out cas-result) math-services math-services?
  math-services-local math-services-extended cas-query! cas-calculate! verify-derivation!
  verify-proposition! call-with-math-services!)
