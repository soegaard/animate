#lang racket/base

;;;
;;; SCENE-EP Preview Cancellation and Quality Tests
;;;

(require rackunit
         "../preview.rkt")

(module+ test
  (define token (make-cancellation-token))
  (check-false (cancellation-requested? token))
  (check-equal? (cancellation-reason token) #f)
  (cancel! token 'scrubbed)
  (cancel! token 'later-request)
  (check-true (cancellation-requested? token))
  (check-equal? (cancellation-reason token) 'scrubbed)
  (check-exn exn:fail:preview-canceled?
             (lambda () (check-cancellation token)))

  (check-true
   (preview-quality-satisfies? full-preview-quality draft-preview-quality))
  (check-false
   (preview-quality-satisfies? draft-preview-quality full-preview-quality))
  (check-true
   (> (preview-quality-rank full-preview-quality)
      (preview-quality-rank thumbnail-preview-quality)))

  (define request
    (preview-render-request
     #:id 9
     #:document-generation 2
     #:render-generation 5
     #:sample 'sample
     #:quality draft-preview-quality
     #:priority 3
     #:cancellation-token token))
  (check-equal? (preview-render-request-id request) 9)
  (check-eq? (preview-render-request-cancellation-token request) token)
  (check-not-false (preview-render-status? 'complete))
  (check-false (preview-render-status? 'unknown)))
