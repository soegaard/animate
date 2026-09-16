#lang racket/base
(require (for-syntax racket/base racket/path racket/list)
         racket/path racket/runtime-path
         (only-in "../project.rkt" module-builder-source)
         "private/check.rkt")
(provide storyboard-source make-storyboard-source)
(define-runtime-path runtime-source "private/project-runtime.rkt")
(define (make-storyboard-source module binding #:asset-base [base #f] #:seed [seed 0])
  (unless (path-string? module) (raise-argument-error 'storyboard-source "module path" module))
  (check-id 'storyboard-source binding)
  (define path
    (cond [(complete-path? module) module]
          [base (path->complete-path module base)]
          [else (slides-error 'source-base-required '() "programmatic relative sources need #:asset-base")]))
  (module-builder-source runtime-source 'slides-source-builder #:prepare 'slides-source-preparer #:seed seed
                         #:options (hash 'module (path->string (simplify-path path #f)) 'binding binding)))
(define-syntax (storyboard-source stx)
  (syntax-case stx ()
    [(_ module binding . options)
     (let* ([xs (syntax->list #'options)]
            [source (syntax-source stx)]
            [base (and (path-string? source) (complete-path? source)
                       (path-only source) (path->string (path-only source)))])
       (if (ormap (lambda (x) (eq? (syntax-e x) '#:asset-base)) xs)
           #`(make-storyboard-source module binding #,@xs)
           #`(make-storyboard-source module binding #,@xs #:asset-base '#,base)))]))
