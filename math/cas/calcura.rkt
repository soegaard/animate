#lang racket/base

;;;
;;; Optional Calcura Adapter
;;;
;; Transports supported scalar expressions through Calcura input parsing and evaluation.
;; Only recognized literal truth results supply decisions.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  racket/list
  (only-in racket/match match)
  (only-in racket/string string-join)
  "model.rkt"
  "../private/validation.rkt"
  "../private/context.rkt"
  "../private/evidence.rkt"
  "../private/datum.rkt")

;; Exports
(provide calcura-service datum->calcura-input)

;;;
;;; Construction and Operations
;;;
; operator-names : immutable-hash?
;;   Names the deliberately supported Calcura transport operators.
(define operator-names
  (hash '+ "Plus" '- "Subtract" '* "Times" '/ "Divide" 'expt "Power" 'sqrt "Sqrt" 'abs "Abs" '= "Equal" '< "Less" '<= "LessEqual" '> "Greater" '>= "GreaterEqual" 'and "And" 'or "Or" 'not "Not" 'sin "Sin" 'cos "Cos" 'tan "Tan" 'ln "Log" 'exp "Exp"))

; datum->calcura-input : math-datum? -> string?
;;   Serializes the supported exact fragment with collision-resistant variable names.
(define (datum->calcura-input datum)
  (define recur datum->calcura-input)
  (match datum
    [#t "True"]
    [#f "False"]
    [(? number?)
     (unless (and (exact? datum) (rational? datum))
       (error 'datum->calcura-input
         "Only exact rational constants are transported in this adapter."))
     (number->string datum)]
    [(? symbol?)
     (cond
       [(eq? datum '@pi) "Pi"]
       [(eq? datum '@e) "E"]
       [(regexp-match? #px"^[A-Za-z$][A-Za-z0-9$]*$" (symbol->string datum))
        (string-append "animateMathVariable"
          (apply string-append
            (for/list ([b (in-bytes (string->bytes/utf-8 (symbol->string datum)))])
              (define h (number->string b 16))
              (if (= (string-length h) 1) (string-append "0" h) h))))]
       [else
        (error 'datum->calcura-input
          "Expand definitions or supply #:query for the symbol ~s."
          datum)])]
    [(list 'real? u) (format "Element[~a,Reals]" (recur u))]
    [(list 'parens u) (recur u)]
    [(list '- u) (format "Times[-1,~a]" (recur u))]
    [(list f args ...)
     (define name (hash-ref operator-names f #f))
     (unless name
       (error 'datum->calcura-input
         "Unsupported transported operator ~s; supply #:query for extensions."
         f))
     (format "~a[~a]" name (string-join (map recur args) ","))]))

; calcura-service : [#:module any/c] [#:version any/c] [#:query (or/c procedure? #f)]
;   [#:loader procedure?] -> cas-service?
;;   Configures a lazy Calcura parser/Eval bridge without claiming unavailable
;;   capabilities.
(define (calcura-service
          #:module [module #f]
          #:version [version 'configured]
          #:query [query #f]
          #:loader [loader dynamic-require])
  (check-procedure 'calcura-service loader 2)
  (define module-path (if (path-string? module) (path->complete-path module) module))
  (cas-service 'calcura version '(proposition)
    (or query
      (lambda (capability payload context)
        (cond
          [(not module)
           (cas-result 'unavailable #f #f
             '("Configure calcura-service with #:module pointing to calcura.rkt, or supply #:query."))]
          [else
           (define parse (loader module-path 'parse-input-form-string))
           (define eval-expression (loader module-path 'Eval))
           (define proposition (datum->calcura-input (context-expand context payload)))
           (define conditions
             (cons 'and
               (append
                 (map (lambda (x) `(real? ,x)) (math-context-real context))
                 (map
                   (lambda (p) (definition-expand p (math-context-definitions context)))
                   (context-facts context)))))
           (define request
             (format "Simplify[~a,Assumptions->~a]" proposition
               (datum->calcura-input conditions)))
           (define answer (eval-expression (parse request)))
           (define printed (format "~s" answer))
           (cond
             [(or (eq? answer #t) (member printed '("True" "true")))
              (cas-result 'ok answer
                (established 'calcura payload (list request printed))
                '())]
             [(or (eq? answer #f) (member printed '("False" "false")))
              (cas-result 'ok answer
                (refuted 'calcura payload "Calcura returned False." (list request printed))
                '())]
             [else
              (cas-result 'unknown answer
                (unknown 'calcura payload
                  (list payload)
                  "Calcura did not return a recognized literal truth value."
                  (list request printed))
                '("No decision inferred from an unevaluated or opaque native result."))])])))))
