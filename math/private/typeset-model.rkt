#lang racket/base

;;;
;;; Prepared Formula Geometry
;;;
;; Defines immutable adapter geometry and ordered token ownership. Source files are
;; references only; these records perform no I/O.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/list remove-duplicates)
         "validation.rkt"
         "datum.rkt"
         "model.rkt"
         "format.rkt")

;; Exports
(provide
  (struct-out prepared-token) (struct-out prepared-layout) token-with-position token-with-id
  token-scaled fraction-bar-token? prepared-token-role-for-source-span)

;;;
;;; Data Representation
;;;
(struct prepared-token (path role text asset x y width height id)
  #:transparent
  #:guard
  (lambda (path role text asset x y width height id who)
    (check-path who path)
    (check-symbol who role)
    (unless (string? text) (raise-argument-error who "string?" text))
    (unless (path-string? asset) (raise-argument-error who "path-string?" asset))
    (values path role
      (string->immutable-string text)
      (string->immutable-string (if (path? asset) (path->string asset) asset))
      (check-finite-real who x)
      (check-finite-real who y)
      (check-positive-real who width)
      (check-positive-real who height)
      (check-symbol who id))))
;; prepared-token is an immutable record. Its fields have the following roles.
;;  - path  operand-path?  mathematical owner in one checkpoint
;;  - role  symbol?  owned mathematical/operator role; 'fraction-bar denotes
;;    residual structural ink for one persistent division expression
;;  - text  immutable-string?  copied complete source fragment
;;  - asset  immutable-string?  frozen SVG asset reference, not a live renderer
;;  - x  finite-real?  center coordinate in local y-up world units
;;  - y  finite-real?  center coordinate in local y-up world units
;;  - width  positive-real?  measured prepared width in world units
;;  - height  positive-real?  measured prepared height in world units
;;  - id  symbol?  unique prepared/view identity
(struct prepared-layout (state tokens source diagnostics)
  #:transparent
  #:guard
  (lambda (state tokens source diagnostics who)
    (unless (math? state) (raise-argument-error who "math?" state))
    (unless (math-source? source) (raise-argument-error who "math-source?" source))
    (check-list-of who tokens prepared-token? "ordered list of prepared tokens")
    (when (null? tokens)
      (raise-arguments-error who "at least one visible token is required"))
    (unless (= (length tokens) (length (remove-duplicates (map prepared-token-id tokens))))
      (raise-arguments-error who "prepared token identities must be unique"))
    (check-list-of who diagnostics string? "list of diagnostic strings")
    (values state tokens source (map string->immutable-string diagnostics))))
;; prepared-layout is an immutable record. Its fields have the following roles.
;;  - state  math?  exact input checkpoint
;;  - tokens  (listof prepared-token?)  parts in deterministic drawing order with unique
;;    IDs
;;  - source  math-source?  complete source and semantic ranges
;;  - diagnostics  (listof immutable-string?)  ordered preparation notes

; fraction-bar-token? : any/c -> boolean?
;;   Recognizes the explicit structural role for one prepared division bar.
(define (fraction-bar-token? value)
  (and (prepared-token? value)
       (eq? (prepared-token-role value) 'fraction-bar)))

; prepared-token-role-for-source-span : math? math-source-span? -> symbol?
;;   Preserves division-bar identity while retaining other residual ink as structure.
(define (prepared-token-role-for-source-span state span)
  (unless (math? state)
    (raise-argument-error 'prepared-token-role-for-source-span "math?" state))
  (unless (math-source-span? span)
    (raise-argument-error 'prepared-token-role-for-source-span "math-source-span?" span))
  (define source-role (math-source-span-role span))
  (if (eq? source-role 'expression)
      (if (eq? (head (datum-ref (math-datum state) (math-source-span-path span))) '/)
          'fraction-bar
          'structure)
      source-role))

; token-with-position : prepared-token? any/c any/c -> prepared-token?
;;   Returns an immutable prepared-token update while preserving all unrelated fields.
(define (token-with-position token x y)
  (struct-copy prepared-token token [x x] [y y]))

; token-with-id : prepared-token? symbol? -> prepared-token?
;;   Returns an immutable prepared-token update while preserving all unrelated fields.
(define (token-with-id token id)
  (struct-copy prepared-token token [id id]))

; token-scaled : prepared-token? any/c [any/c] [any/c] -> prepared-token?
;;   Returns an immutable prepared-token update while preserving all unrelated fields.
(define (token-scaled token scale [dx 0] [dy 0])
  (struct-copy prepared-token token
    [x (+ dx (* scale (prepared-token-x token)))]
    [y (+ dy (* scale (prepared-token-y token)))]
    [width (* scale (prepared-token-width token))]
    [height (* scale (prepared-token-height token))]))
