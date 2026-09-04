#lang racket/base

;;;
;;; Source-Located Scene Program Syntax
;;;

(require (for-syntax racket/base
                     racket/list
                     syntax/parse)
         "scene-program.rkt")

(provide define-scene-program
         scene-block)

(begin-for-syntax
  (define (literal-version? syntax)
    ;; Versions form part of conservative invalidation metadata, so evaluating
    ;; an arbitrary expression here would make the declaration unstable. A
    ;; quoted datum (the common `'v2` form) and simple literal values are fine.
    (define datum (syntax->datum syntax))
    (or (boolean? datum)
        (string? datum)
        (number? datum)
        (and (pair? datum)
             (eq? (car datum) 'quote)
             (= (length datum) 2))))
  (define-syntax-class scene-block-clause
    (pattern (scene-block id:id (input:id)
                          (~optional (~seq #:assets (asset:string ...))
                                     #:defaults ([(asset 1) '()]))
                          (~optional (~seq #:version version:expr)
                                     #:defaults ([version #'#f]))
                          body:expr ...+)
      #:attr id-symbol (syntax-e #'id)
      #:attr source (syntax-source this-syntax)
      #:attr line (or (syntax-line this-syntax) 0)
      #:attr column (or (syntax-column this-syntax) 0)
      #:attr position (or (syntax-position this-syntax) 0)
      #:attr span (or (syntax-span this-syntax) 0))))

(define-syntax (scene-block stx)
  (raise-syntax-error #f "scene-block is valid only inside define-scene-program" stx))

(define-syntax (define-scene-program stx)
  (syntax-parse stx
    [(_ name:id #:initial initial:expr block:scene-block-clause ...)
     (define ids (attribute block.id-symbol))
     (define duplicate (check-duplicates ids))
     (when duplicate
       (raise-syntax-error #f (format "duplicate scene-block ID: ~a" duplicate) stx))
     (for ([version (in-list (attribute block.version))])
       (unless (literal-version? version)
         (raise-syntax-error #f "#:version must be a literal or quoted datum" version)))
     (define blocks
       (for/list ([id (in-list (syntax->list #'(block.id ...)))]
                  [input (in-list (syntax->list #'(block.input ...)))]
                  [body-list (in-list (attribute block.body))]
                  [assets-list (in-list (attribute block.asset))]
                  [version (in-list (attribute block.version))]
                  [source (in-list (attribute block.source))]
                  [line (in-list (attribute block.line))]
                  [column (in-list (attribute block.column))]
                  [position (in-list (attribute block.position))]
                  [span (in-list (attribute block.span))])
         #`(make-scene-block
            '#,(syntax-e id)
            (lambda (#,input) #,@body-list)
            #:source-location
            (source-location '#,source #,line #,column #,position #,span)
            #:assets (list #,@assets-list)
            #:version #,version)))
     #`(define name
         (make-scene-program
          '#,(syntax-e #'name)
          (lambda () initial)
          (list #,@blocks)))]))
