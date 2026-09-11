#lang racket/base

;; The authoring forms are macros, not an eval-based interpreter. Geometry
;; expressions are a closed, checked language. Helper identifiers retain their
;; ordinary lexical Racket bindings across module boundaries.
(require "private/compiler.rkt"
         (for-syntax racket/base racket/list "private/vocabulary.rkt"))
(provide construction define-construction)

(begin-for-syntax
  (define (step-body->action-forms body)
    (let loop ([rest body])
      (cond
        [(null? rest) '()]
        [(keyword? (syntax-e (car rest)))
         (unless (pair? (cdr rest))
           (raise-syntax-error #f "step timing keyword needs a value" (car rest)))
         (loop (cddr rest))]
        [else (if (and (pair? rest) (string? (syntax-e (car rest)))) (cdr rest) rest)])))
  (define (helper-identifiers clauses)
    (define found '())
    (define (visit-expression e)
      (define xs (syntax->list e))
      (when (and xs (pair? xs))
        (define head (car xs))
        (define op (syntax-e head))
        (unless (eq? op 'quote)
          (when (and (identifier? head) (not (memq op expression-heads)))
            (unless (ormap (lambda (id) (free-identifier=? id head)) found)
              (set! found (cons head found))))
          (for-each visit-expression (cdr xs)))))
    (define (visit-action a)
      (define xs (syntax->list a))
      (when (and xs (pair? xs))
        (case (syntax-e (car xs))
          [(together) (for-each visit-action (cdr xs))]
          [(expand) (when (= (length xs) 2) (visit-action (cadr xs)))]
          [(show hide show-label hide-label deemphasize normalize highlight) (void)]
          [else (when (= (length xs) 2) (visit-expression (cadr xs)))])))
    (for ([clause (in-list clauses)])
      (define xs (syntax->list clause))
      (when (and xs (pair? xs))
        (case (syntax-e (car xs))
          [(given)
           (for ([binding (in-list (cdr xs))])
             (define bs (syntax->list binding))
             (when (and bs (= (length bs) 2)) (visit-expression (cadr bs))))]
          [(require assert)
           (for-each visit-expression (cdr xs))]
          [(step) (for-each visit-action (step-body->action-forms (cdr xs)))]
          [else (void)])))
    (reverse found))
  (define (expand-definition stx helper?)
    (syntax-case stx ()
      [(_ name clause ...)
       (identifier? #'name)
       (let* ([clauses (syntax->list #'(clause ...))]
              [ids (helper-identifiers clauses)]
              [source (format "~a:~a" (or (syntax-source stx) 'interactive) (or (syntax-line stx) 0))])
         (when (ormap (lambda (id) (free-identifier=? id #'name)) ids)
           (raise-syntax-error #f "recursive construction helpers are not supported" stx))
         (with-syntax ([maker (if helper? #'make-construction-helper #'make-construction-program)]
                       [source-value (datum->syntax stx source)]
                       [(entry ...) (for/list ([id (in-list ids)]) #`(cons '#,id #,id))])
           #'(define name
               (maker 'name '(clause ...) (make-immutable-hash (list entry ...)) source-value))))]
      [_ (raise-syntax-error #f "expected a construction name followed by clauses" stx)])))
(define-syntax (construction stx) (expand-definition stx #f))
(define-syntax (define-construction stx) (expand-definition stx #t))
