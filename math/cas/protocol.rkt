#lang racket/base

;;;
;;; Bounded Computer Algebra Queries
;;;
;; Executes optional services with explicit failure states and time limits. Results
;; cannot silently relabel or mutate held derivations.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  "../private/validation.rkt"
  "model.rkt"
  (only-in racket/list append-map)
  (only-in racket/math infinite? nan?)
  "../private/context.rkt"
  "../private/evidence.rkt"
  "../private/model.rkt"
  "../private/derivation.rkt"
  "../private/datum.rkt")

;; Exports
(provide
  cas-query! cas-calculate! verify-derivation! verify-proposition! call-with-math-services!)

;;;
;;; Construction and Operations
;;;
; cas-query! : cas-service? symbol? any/c math-context? [#:timeout positive-real?] ->
;   cas-result?
;;   Runs one bounded backend query and shuts down its custodian after every outcome.
(define (cas-query! service capability payload context #:timeout [timeout 10])
  (unless (and (cas-service? service) (math-context? context))
    (raise-argument-error 'cas-query!
      "service and mathematical context"
      (list service context)))
  (unless (and (real? timeout) (not (nan? timeout)) (not (infinite? timeout)) (> timeout 0))
    (raise-argument-error 'cas-query! "positive timeout in seconds" timeout))
  (cond
    [(not (memq capability (cas-service-capabilities service)))
     (cas-result 'unsupported #f #f
       (list (format "~a does not offer ~a." (cas-service-name service) capability)))]
    [else
     (define custodian (make-custodian))
     (define channel (make-channel))
     (dynamic-wind
       void
       (lambda ()
         (parameterize ([current-custodian custodian])
           (thread
             (lambda ()
               (define result
                 (with-handlers ([exn:fail? (lambda (e) (cas-result 'error #f #f (list (exn-message e))))])
                   ((cas-service-query service) capability payload context)))
               (channel-put channel (list result)))))
         (define result (sync/timeout timeout channel))
         (cond
           [(not result)
            (cas-result 'timeout #f #f (list "CAS query reached its time limit."))]
           [(cas-result? (car result))
            (define report (car result))
            (define evidence (cas-result-evidence report))
            (cond
              [(and evidence
                 (eq? capability 'proposition)
                 (not (equal? payload (verification-proposition evidence))))
               (cas-result 'error #f #f
                 '("Service evidence refers to a different proposition."))]
              [(and evidence
                 (not (eq? (cas-result-status report) 'ok))
                 (not (eq? (verification-status evidence) 'unknown)))
               (cas-result 'error #f #f
                 '("Only a successful CAS result may supply a decision."))]
              [else report])]
           [else
            (cas-result 'error #f #f (list "Service violated the cas-result contract."))]))
       (lambda () (custodian-shutdown-all custodian)))]))

; cas-calculate! : cas-service? symbol? math-datum? [#:context math-context?] [#:timeout
;   positive-real?] -> cas-result?
;;   Requests a backend calculation without changing held presentation syntax.
(define (cas-calculate! service operation datum
          #:context [context (math-context)]
          #:timeout [timeout 10])
  (cas-query! service 'calculate (list operation datum) context #:timeout timeout))

;;;
;;; Evidence Verification
;;;
; cas-result->metadata : cas-result? -> immutable-hash?
;;   Keeps provider status and evidence while excluding its opaque native result value.
(define (cas-result->metadata result)
  (hash 'status
    (cas-result-status result)
    'evidence
    (cas-result-evidence result)
    'diagnostics
    (cas-result-diagnostics result)))

; verify-proposition/defined! : math-datum? math-context? [#:services math-services?]
;   [#:timeout positive-real?] -> verification?
;;   Consults explicit services for a proposition whose definedness was checked first.
(define (verify-proposition/defined! proposition context
          #:services [backends (math-services)]
          #:timeout [timeout 10])
  (define local (context-prove context proposition))
  (cond
    [(not (eq? (verification-status local) 'unknown)) local]
    [else
     (define results
       (for/list ([service
                   (in-list
                     (filter values
                       (list
                         (math-services-local backends)
                         (math-services-extended backends))))])
         (cas-query! service 'proposition proposition context #:timeout timeout)))
     (define summaries (map cas-result->metadata results))
     (define evidence
       (filter verification?
         (for/list ([report (in-list results)] #:when (eq? (cas-result-status report) 'ok))
           (cas-result-evidence report))))
     (define statuses (map verification-status evidence))
     (cond
       [(and (memq 'established statuses) (memq 'refuted statuses))
        (unknown 'conflicting-CAS-results proposition
          (list proposition)
          "The CAS services disagree; neither answer was silently preferred."
          summaries)]
       [(memq 'established statuses) (established 'CAS-supported proposition summaries)]
       [(memq 'refuted statuses)
        (refuted 'CAS-supported proposition
          "A CAS reports this proposition false."
          summaries)]
       [else
        (unknown 'CAS-services proposition
          (list proposition)
          "No service established or refuted the proposition."
          summaries)])]))

; verify-proposition! : math-datum? math-context? [#:services math-services?] [#:timeout
;   positive-real?] -> verification?
;;   Checks definedness and queries explicit CAS services without silently resolving
;;   disagreements.
(define (verify-proposition! proposition context
          #:services [backends (math-services)]
          #:timeout [timeout 10])
  ;; A simplifier returning True must not erase an undefined point such as x=0
  ;; in x/x=1. Resolve definedness before accepting a backend decision.
  (define requirements
    (domain-requirements (definition-expand proposition (math-context-definitions context))))
  (define reports
    (for/list ([p (in-list requirements)])
      (verify-proposition/defined! p context #:services backends #:timeout timeout)))
  (cond
    [(andmap (lambda (r) (eq? (verification-status r) 'established)) reports)
     (verify-proposition/defined! proposition context #:services backends #:timeout timeout)]
    [else
     (unknown 'definedness proposition
       (for/list ([p (in-list requirements)]
                   [r (in-list reports)]
                   #:unless (eq? (verification-status r) 'established))
         p)
       "Definedness is not established; an expression simplifier cannot remove this obligation."
       reports)]))

; verify-derivation! : (or/c derivation? case-derivation?) [#:services math-services?]
;   [#:timeout positive-real?] -> verification?
;;   Rechecks pending obligations without mutating the recorded derivation or its
;;   evidence.
(define (verify-derivation! d #:services [backends (math-services)] #:timeout [timeout 10])
  ;; Rechecks recorded obligations and returns a report. It does not rewrite or
  ;; retroactively relabel the caller's immutable derivation.
  (define (check-step step)
    (define v (rewrite-step-verification step))
    (if (or (not (eq? (verification-status v) 'unknown)) (null? (verification-obligations v)))
      v
      (merge-verifications
        (for/list ([p (in-list (verification-obligations v))])
          (verify-proposition! p
            (math-context-of (rewrite-step-before step))
            #:services backends
            #:timeout timeout))
        (verification-proposition v))))
  (define (walk d)
    (cond
      [(derivation? d) (map check-step (derivation-steps d))]
      [(case-derivation? d)
       (append
         (list (case-derivation-coverage d))
         (walk (case-derivation-prefix d))
         (append-map
           (lambda (b) (walk (case-branch-derivation b)))
           (case-derivation-branches d)))]
      [else (raise-argument-error 'verify-derivation! "derivation or case derivation" d)]))
  (merge-verifications (walk d) 'verified-derivation))

;;;
;;; Explicit Construction-Time Service Scope
;;;
; call-with-math-services! : math-services? procedure? [#:timeout positive-real?] -> any
;;   Installs explicit CAS services only for the dynamic extent of one construction
;;   callback.
(define (call-with-math-services! backends thunk #:timeout [timeout 10])
  (unless (math-services? backends)
    (raise-argument-error 'call-with-math-services! "math-services?" backends))
  (unless (and (procedure? thunk) (procedure-arity-includes? thunk 0))
    (raise-argument-error 'call-with-math-services! "zero-argument procedure" thunk))
  (parameterize ([current-math-prover
                  (lambda (context proposition)
                    (verify-proposition! proposition context
                      #:services backends
                      #:timeout timeout))])
    (thunk)))
