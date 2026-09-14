#lang racket/base

;;;
;;; Optional Racket CAS Adapter
;;;
;; Builds a lazy service descriptor for racket-cas calculations. Loading and calculation
;; occur only at the explicit query boundary.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/match match-define)
  "model.rkt"
  "../private/validation.rkt"
  "../private/context.rkt"
  "../private/evidence.rkt")

;; Exports
(provide racket-cas-service)

;;;
;;; Construction and Operations
;;;
; racket-cas-service : [#:module any/c] [#:version any/c] [#:loader procedure?] ->
;   cas-service?
;;   Configures a lazy racket-cas bridge without importing it during construction.
(define (racket-cas-service
          #:module [module 'racket-cas]
          #:version [version 'installed]
          #:loader [loader dynamic-require])
  (check-procedure 'racket-cas-service loader 2)
  (define (function name) (loader module name))
  (cas-service 'racket-cas version '(calculate proposition)
    (lambda (capability payload context)
      (case capability
        [(calculate)
         (match-define (list op datum) payload)
         (define name
           (case op
             [(normalize) 'normalize]
             [(expand) 'expand]
             [(simplify) 'simplify]
             [(together) 'together]
             [else #f]))
         (if name
           (cas-result 'ok
             ((function name) (context-expand context datum))
             #f
             '("A CAS result is a proposed value, not an explanatory trace."))
           (cas-result 'unsupported #f #f (list (format "Unsupported calculation: ~a" op))))]
        [(proposition)
         (define normalized ((function 'normalize) (context-expand context payload)))
         (cond
           [(eq? normalized #t)
            (cas-result 'ok #t (established 'racket-cas-normalization payload) '())]
           [(eq? normalized #f)
            (cas-result 'ok #f (refuted 'racket-cas-normalization payload) '())]
           [else
            (cas-result 'unknown normalized
              (unknown 'racket-cas-normalization payload)
              '("Normalization did not decide the proposition."))])]))))
