#lang racket/base

;;;
;;; Computer Algebra Service Descriptions
;;;
;; Defines validated service and response records without executing callbacks. Ordered
;; capabilities and immutable diagnostics make the protocol explicit.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "../private/validation.rkt" "../private/evidence.rkt")

;; Exports
(provide
  (struct-out cas-service) (struct-out cas-result) math-services math-services?
  math-services-local math-services-extended)

;;;
;;; Data Representation
;;;
(struct cas-service (name version capabilities query)
  #:transparent
  #:guard
  (lambda (name version capabilities query who)
    (check-symbol who name)
    (check-symbol-list who capabilities)
    (check-procedure who query 3)
    (values name (snapshot-metadata version) capabilities query)))
;; cas-service is an immutable record. Its fields have the following roles.
;;  - name  symbol?  backend identity
;;  - version  any/c  snapshotted backend version metadata
;;  - capabilities  (listof symbol?)  declared supported queries in declaration order
;;  - query  procedure?  three-argument adapter callback; runs only at explicit effect
;;    boundaries
(struct cas-result (status value evidence diagnostics)
  #:transparent
  #:guard
  (lambda (status value evidence diagnostics who)
    (unless (memq status '(ok unknown unsupported unavailable timeout error))
      (raise-argument-error who "CAS result status" status))
    (unless (or (not evidence) (verification? evidence))
      (raise-argument-error who "verification? or #f" evidence))
    (check-list-of who diagnostics string? "list of diagnostic strings")
    (values status value evidence (map string->immutable-string diagnostics))))
;; cas-result is an immutable record. Its fields have the following roles.
;;  - status  symbol?  ok, unknown, unsupported, unavailable, timeout, or error
;;  - value  any/c  adapter-native result; never inserted into semantic model
;;    automatically
;;  - evidence  (or/c verification? #f)  decision for the exact requested proposition
;;  - diagnostics  (listof immutable-string?)  ordered copied diagnostic strings
(struct services (local extended)
  #:transparent)
;; services is an immutable record. Its fields have the following roles.
;;  - local  (or/c cas-service? #f)  optional lightweight backend
;;  - extended  (or/c cas-service? #f)  optional extended backend

; math-services? : procedure?
;;   Recognizes a pair of configured CAS service descriptors.
(define math-services?
  services?)

; math-services-local : procedure?
;;   Returns the configured service without loading its backend.
(define math-services-local
  services-local)

; math-services-extended : procedure?
;;   Returns the configured service without loading its backend.
(define math-services-extended
  services-extended)

; math-services : [#:local (or/c cas-service? #f)] [#:extended (or/c cas-service? #f)]
;   -> math-services?
;;   Collects optional local and extended service descriptors without executing them.
(define (math-services #:local [local #f] #:extended [extended #f])
  (for ([s (in-list (list local extended))])
    (unless (or (not s) (cas-service? s))
      (raise-argument-error 'math-services "cas-service? or #f" s)))
  (services local extended))
