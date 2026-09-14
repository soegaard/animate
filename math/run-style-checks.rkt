#lang racket/base

;;;
;;; Mathematics Source and Reference Audit
;;;

;; Checks source-level house-style boundaries and actual public export coverage.
;; This is a filesystem audit, not a replacement for Scribble compilation or
;; actual native renderer integration. It never calls a renderer or a CAS.

;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/file
         racket/list
         racket/match
         racket/path
         racket/string
         racket/runtime-path
         json
         "tests/check.rkt")

;;;
;;; Source Inventory
;;;

; math-directory : path?
;;   Locates the source subcollection independently of the caller's directory.
(define-runtime-path math-directory ".")

; public-modules : (listof string?)
;;   Gives the explicitly supported facades in documentation order.
(define public-modules
  '("main.rkt" "render.rkt" "cas.rkt" "cas/calcura.rkt" "cas/racket-cas.rkt"))

; forbidden-imports : (listof symbol?)
;;   Lists external-effect dependencies excluded from the pure model closure.
(define forbidden-imports
  '(pict racket/draw racket/file racket/system racket/port racket/runtime-path
         racket/class svg/svg ffi/unsafe))

; read-module : path? -> list?
;;   Reads top-level source syntax without executing the inspected module.
(define (read-module path)
  (parameterize ([read-accept-reader #t])
    (call-with-input-file path
      (lambda (in)
        (define source (read-syntax path in))
        (syntax-case source ()
          [(module name language (body statement ...))
           (syntax->list #'(statement ...))])))))

; binding-name : syntax? -> (or/c symbol? #f)
;;   Extracts the defined name of a top-level procedure, constant, or syntax form.
(define (binding-name form)
  (match (syntax->datum form)
    [(list (or 'define 'define-syntax 'define-syntax-rule 'define-runtime-path
               'define-math-rule) signature body ...)
     (if (pair? signature) (car signature) signature)]
    [_ #f]))

; actual-exports : path? -> (listof symbol?)
;;   Reads runtime and syntax export names, including keyword-function bindings.
(define (actual-exports path)
  (dynamic-require path #f)
  (define-values (runtime syntax) (module->exports path))
  (sort
   (remove-duplicates
    (for*/list ([group (in-list (append runtime syntax))]
                #:when (eq? (car group) 0)
                [entry (in-list (cdr group))])
      (car entry)))
   symbol<?))

; import-targets : any/c -> list?
;;   Removes import wrappers while retaining explicit module targets.
(define (import-targets specification)
  (match specification
    [(or (? string?) (? symbol?)) (list specification)]
    [(list (or 'only-in 'except-in 'rename-in) target rest ...)
     (import-targets target)]
    [(list 'prefix-in prefix target) (import-targets target)]
    [(list (or 'for-syntax 'for-template 'for-label 'combine-in) specs ...)
     (append-map import-targets specs)]
    [_ '()]))

; pure-closure : path? -> (listof path?)
;;   Traverses local imports once and checks that no effect dependency is reachable.
(define (pure-closure root)
  (define seen (make-hash))
  (define ordered '())
  (define (visit path)
    (unless (hash-ref seen path #f)
      (hash-set! seen path #t)
      (set! ordered (cons path ordered))
      (for ([form (in-list (read-module path))])
        (match (syntax->datum form)
          [(list 'require specs ...)
           (for ([target (in-list (append-map import-targets specs))])
             (cond
               [(string? target)
                (visit (simplify-path (build-path (path-only path) target) #f))]
               [else
                (check-false (and (memq target forbidden-imports) #t)
                             (list 'pure-import path target))]))]
          [_ (void)]))))
  (visit root)
  (reverse ordered))

; source-documentation-checks! : -> void?
;;   Checks module introductions, top-level contracts, and immediate field descriptions.
(define (source-documentation-checks!)
  (for ([path (in-directory math-directory)]
         #:when (regexp-match? #rx"[.]rkt$" (path->string path)))
    (define text (file->string path))
    (define forms (read-module path))
    (check-true (regexp-match? #rx";;;\n;;; [^\n]+\n;;;" text)
                (list 'module-introduction path))
    (for ([form (in-list forms)] [next (in-list (append (cdr forms) (list #f)))])
      (define name (binding-name form))
      (when name
        (define prefix (substring text 0 (sub1 (syntax-position form))))
        (define pattern
          (pregexp (string-append "(?m:^; " (regexp-quote (symbol->string name))
                                  " : [^\n]*(?:\n;   [^\n]*)*\n;;   )")))
        (check-true (regexp-match? pattern prefix) (list 'contract-and-purpose path name)))
      (match (syntax->datum form)
        [(list 'struct name fields-or-parent rest ...)
         (define fields
           (if (symbol? fields-or-parent) (car rest) fields-or-parent))
         (define finish (+ (sub1 (syntax-position form)) (syntax-span form)))
         (define end (if next (sub1 (syntax-position next)) (string-length text)))
         (define docs (substring text finish end))
         (for ([field (in-list fields)])
           (define field-name (if (pair? field) (car field) field))
           (check-true
            (regexp-match?
             (regexp (string-append ";;  - " (regexp-quote (symbol->string field-name)) "  "))
             docs)
            (list 'immediate-field-documentation path name field-name)))]
        [_ (void)]))))

; source-direct-exports : path? -> (listof symbol?)
;;   Collects plain identifier exports written directly in provide forms.
(define (source-direct-exports path)
  (sort
   (remove-duplicates
    (append-map
     (lambda (form)
       (match (syntax->datum form)
         [(list 'provide specifications ...)
          (filter symbol? specifications)]
         [_ '()]))
     (read-module path)))
   symbol<?))

; check-loaded-export-cache! : path? (listof symbol?) -> void?
;;   Rejects a loaded module whose exports lag behind direct source declarations.
(define (check-loaded-export-cache! path exported)
  (define missing
    (filter (lambda (name) (not (memq name exported)))
            (source-direct-exports path)))
  (when (pair? missing)
    (raise-user-error
     'run-style-checks
     (string-append
      "loaded module exports do not match the source on disk; "
      "a stale Racket compiled/.zo cache is likely\n"
      "missing loaded exports: ~s\n"
      "remove caches with: find math -type d -name compiled -prune -exec rm -rf {} +")
     missing)))

; reference-coverage-checks! : -> void?
;;   Compares actual exports with the reference index and defining Scribble forms.
(define (reference-coverage-checks!)
  (define api
    (call-with-input-file (build-path math-directory "docs/public-api.json") read-json))
  (define manual (file->string (build-path math-directory "scribblings/math.scrbl")))
  (for ([relative (in-list public-modules)])
    (define module-path (build-path math-directory relative))
    (define exported (actual-exports module-path))
    (check-loaded-export-cache! module-path exported)
    (define entry
      (findf (lambda (record) (equal? (hash-ref record 'module) relative))
             (hash-ref api 'modules)))
    (define documented
      (sort (map (lambda (binding) (string->symbol (hash-ref binding 'name)))
                 (hash-ref entry 'bindings)) symbol<?))
    (check-equal exported documented (list 'reference-index relative))
    (for ([name (in-list exported)])
      (define word (symbol->string name))
      (define defining-name
        (cond [(regexp-match? #rx"^(struct:)?cas-service([?-]|$)" word) "cas-service"]
              [(regexp-match? #rx"^(struct:)?cas-result([?-]|$)" word) "cas-result"]
              [else word]))
      (check-true
       (regexp-match?
        (pregexp
         (string-append "@def(?:proc|thing|param|form|struct\\*)\\[\\(?"
                         (regexp-quote defining-name) "[[:space:]\\[\\(\\)]"))
        manual)
       (list 'defining-reference relative name)))))

;;;
;;; Audit Entry Point
;;;

(test-group "house style: source contracts and immediate struct-field documentation"
            source-documentation-checks!)
(test-group "house style: pure model dependency closure"
  (lambda ()
    (define paths (pure-closure (build-path math-directory "main.rkt")))
    (check-true (> (length paths) 8))
    (for ([path (in-list paths)])
      (check-false
       (regexp-match? #rx"dynamic-require|find-system-path|make-temporary-file"
                      (file->string path))
       (list 'no-hidden-effect-import path)))))
(test-group "house style: explicit public facade and removed raw constructors"
  (lambda ()
    (define main (build-path math-directory "main.rkt"))
    (define exports (actual-exports main))
    (for ([forbidden '(mathematical-state derivation rewrite-step presentation-plan
                       presentation-style path-link trace-event finish-step make-edit
                       prepare-math-plan math-plan->scene cas-query verify-derivation
                       prepare-math-plan! math-plan->scene! cas-query!)])
      (check-false (and (memq forbidden exports) #t) (list 'not-public-in-main forbidden)))
    (for ([relative (in-list public-modules)])
      (check-false
       (regexp-match? #rx"all-defined-out|all-from-out"
                      (file->string (build-path math-directory relative)))
       (list 'explicit-public-exports relative)))))
(test-group "house style: defining reference coverage" reference-coverage-checks!)
(report!)
