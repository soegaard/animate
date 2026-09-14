#lang racket/base

;;;
;;; Mathematical Evidence
;;;
;; Defines immutable three-valued verification reports. Unresolved obligations remain
;; explicit and never count as successful proofs.
;;;
;;; Imports and Exports
;;;
;; Imports
(require "validation.rkt")

;; Exports
(provide (struct-out verification) established unknown refuted merge-verifications)

;;;
;;; Data Representation
;;;
(struct verification (status method proposition obligations message details)
  #:transparent
  #:guard
  (lambda (status method proposition obligations message details who)
    (unless (memq status '(established refuted unknown))
      (raise-argument-error who "verification status" status))
    (check-symbol who method)
    (unless (list? obligations) (raise-argument-error who "list?" obligations))
    (unless (string? message) (raise-argument-error who "string?" message))
    (when (and (not (eq? status 'unknown)) (pair? obligations))
      (raise-arguments-error who
        "decided evidence cannot retain pending obligations"
        "obligations"
        obligations))
    (values status method
      (snapshot-metadata proposition)
      (snapshot-metadata obligations)
      (string->immutable-string message)
      (snapshot-metadata details #:atomic? verification?))))

;; verification is an immutable record. Its fields have the following roles.
;;  - status  (or/c 'established 'refuted 'unknown)  three-valued decision
;;  - method  symbol?  evidence source, not a formal-proof claim
;;  - proposition  any/c  the exact proposition being checked
;;  - obligations  list?  pending requirements in diagnostic order; empty after a
;;    decision
;;  - message  immutable-string?  copied diagnostic text
;;  - details  any/c  snapshotted supporting metadata
; established : symbol? math-datum? [any/c] -> verification?
;;   Creates immutable evidence for an established proposition.
(define (established method proposition [details '()])
  (verification 'established method proposition '()
    "Established within the stated domain."
    details))

; unknown : symbol? math-datum? [list?] [string?] [any/c] -> verification?
;;   Creates pending evidence with explicit obligations and an immutable diagnostic.
(define (unknown method proposition
          [obligations (list proposition)]
          [message "Not established."]
          [details '()])
  (verification 'unknown method proposition obligations message details))

; refuted : symbol? math-datum? [string?] [any/c] -> verification?
;;   Creates immutable evidence for a refuted proposition.
(define (refuted method proposition [message "Refuted."] [details '()])
  (verification 'refuted method proposition '() message details))

; merge-verifications : (listof verification?) [math-datum?] -> verification?
;;   Combines ordered reports with refutation taking precedence over uncertainty.
(define (merge-verifications checks [proposition 'derivation])
  (define bad (filter (lambda (v) (eq? (verification-status v) 'refuted)) checks))
  (define pending (filter (lambda (v) (eq? (verification-status v) 'unknown)) checks))
  (cond
    [(pair? bad) (refuted 'combined proposition "At least one check was refuted." checks)]
    [(pair? pending)
     (unknown 'combined proposition
       (apply append (map verification-obligations pending))
       "Some obligations remain unresolved."
       checks)]
    [else (established 'combined proposition checks)]))
