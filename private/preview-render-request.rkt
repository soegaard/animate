#lang racket/base

;;;
;;; Preview Render Job Protocol Values
;;;

(require "preview-cancellation.rkt"
         "preview-quality.rkt")

(provide preview-render-request
         preview-render-request?
         preview-render-request-id
         preview-render-request-document-generation
         preview-render-request-render-generation
         preview-render-request-sample
         preview-render-request-quality
         preview-render-request-priority
         preview-render-request-cancellation-token
         preview-render-result
         preview-render-result?
         preview-render-result-request-id
         preview-render-result-status
         preview-render-result-bitmap
         preview-render-result-diagnostics
         preview-render-result-error
         preview-render-status?)

(struct preview-render-request-value
  (id document-generation render-generation sample quality priority cancellation-token)
  #:transparent
  #:constructor-name make-preview-render-request)

(define preview-render-request? preview-render-request-value?)
(define preview-render-request-id preview-render-request-value-id)
(define preview-render-request-document-generation
  preview-render-request-value-document-generation)
(define preview-render-request-render-generation
  preview-render-request-value-render-generation)
(define preview-render-request-sample preview-render-request-value-sample)
(define preview-render-request-quality preview-render-request-value-quality)
(define preview-render-request-priority preview-render-request-value-priority)
(define preview-render-request-cancellation-token
  preview-render-request-value-cancellation-token)

(struct preview-render-result
  (request-id status bitmap diagnostics error)
  #:transparent)

(define (preview-render-request #:id id
                                #:document-generation document-generation
                                #:render-generation render-generation
                                #:sample sample
                                #:quality [quality full-preview-quality]
                                #:priority [priority 0]
                                #:cancellation-token
                                [cancellation-token (make-cancellation-token)])
  (for ([field (in-list (list id document-generation render-generation))])
    (unless (exact-nonnegative-integer? field)
      (raise-argument-error 'preview-render-request
                            "exact-nonnegative-integer?" field)))
  (unless (preview-quality? quality)
    (raise-argument-error 'preview-render-request "preview-quality?" quality))
  (unless (and (exact-nonnegative-integer? priority) (<= priority 5))
    (raise-argument-error 'preview-render-request "priority from 0 through 5" priority))
  (unless (cancellation-token? cancellation-token)
    (raise-argument-error 'preview-render-request "cancellation-token?" cancellation-token))
  (make-preview-render-request id document-generation render-generation sample
                               quality priority cancellation-token))

(define (preview-render-status? value)
  (memq value '(complete canceled superseded failed timed-out worker-restarted)))
