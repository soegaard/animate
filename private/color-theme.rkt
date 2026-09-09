#lang racket/base

;;;
;;; Immutable Color Themes
;;;

;; Defines complete immutable theme snapshots, role dependency validation, and
;; deterministic pure resolution. It has no renderer, GUI, or global-theme
;; dependency.


;;;
;;; Imports and Exports
;;;

;; Imports
(require file/sha1
         (only-in racket/port call-with-output-bytes)
         "color-style.rkt"
         "color-token.rkt"
         "color-expression.rkt"
         "color-palette.rkt")

;; Exports
(provide color-theme
         color-theme?
         color-theme-id
         color-theme-display-name
         color-theme-palette
         color-theme-provenance
         theme-ref
         theme-role-keys
         theme-series
         color-theme-fingerprint
         theme->datum
         datum->theme
         resolve-color-in-theme
         color-theme-resolved-roles
         color-theme-schema-version)


;;;
;;; Data Representation
;;;

;; Roles retain normalized authored specifications. Resolved role and series
;; tables are immutable snapshots for deterministic queries and fingerprints.
(struct color-theme-value
  (id display-name palette roles series provenance resolved-roles resolved-series
      resolved-series-vector fingerprint)
  #:transparent)


;;;
;;; Schema and Construction
;;;

;; color-theme-schema-version : exact-positive-integer?
;;   Identifies the external complete-theme datum format.
(define color-theme-schema-version 1)

;; standard-role-keys : (listof symbol?)
;;   Names every standard semantic role required by a root theme.
(define standard-role-keys
  '(background foreground muted axis grid surface surface-edge accent highlight
               selection warning success error))

(define maximum-theme-definition-count 10000)
(define maximum-theme-expression-depth 64)

;; color-theme : #:id symbol? #:palette color-palette? #:roles hash? ...
;;   Constructs and validates a complete immutable role-resolution snapshot.
(define (color-theme #:id id
                     #:palette [palette #f]
                     #:roles [roles (hash)]
                     #:extends [parent #f]
                     #:display-name [display-name (symbol->string id)]
                     #:series [series #f]
                     #:provenance [provenance #f])
  (check-nonempty-symbol 'color-theme "id" id)
  (unless (or (not parent) (color-theme? parent))
    (raise-argument-error 'color-theme "(or/c #f color-theme?) as #:extends" parent))
  (unless (hash? roles)
    (raise-argument-error 'color-theme "hash? as #:roles" roles))
  (define selected-palette
    (or palette (and parent (color-theme-value-palette parent))))
  (unless (color-palette? selected-palette)
    (raise-argument-error 'color-theme "color-palette? as #:palette" selected-palette))
  (define normalized-name (normalize-display-name display-name 'color-theme))
  (define normalized-provenance (normalize-provenance provenance 'color-theme))
  (define inherited-roles (if parent (color-theme-value-roles parent) (hash)))
  (define merged-roles
    (for/fold ([result inherited-roles]) ([(key spec) (in-hash roles)])
      (check-nonempty-symbol 'color-theme "role key" key)
      (hash-set result key (normalize-color-spec spec 'color-theme))))
  (unless parent
    (for ([key (in-list standard-role-keys)])
      (unless (hash-has-key? merged-roles key)
        (raise-arguments-error
         'color-theme
         "a root theme containing every standard semantic role"
         "missing role" key))))
  (define normalized-series
    (cond
      [(not series) (if parent (color-theme-value-series parent) '())]
      [else (normalize-series series 'color-theme)]))
  (unless (<= (hash-count merged-roles) maximum-theme-definition-count)
    (raise-arguments-error
     'color-theme "at most the configured number of role definitions"
     "maximum" maximum-theme-definition-count
     "count" (hash-count merged-roles)))
  (unless (<= (length normalized-series) maximum-theme-definition-count)
    (raise-arguments-error
     'color-theme "at most the configured number of series definitions"
     "maximum" maximum-theme-definition-count
     "count" (length normalized-series)))
  ;; A theme's role and series definitions are resolved before its categorical
  ;; series snapshot exists.  Series tokens therefore have no meaningful
  ;; dependency direction here: accepting one used to reach the provisional
  ;; `#f` vector and fail with an incidental vector contract error.  Reject the
  ;; complete nested expression route at the authoring boundary instead.
  (reject-series-dependencies! merged-roles normalized-series)
  ;; The provisional snapshot is immutable and is used only to validate all
  ;; role dependencies before the final resolved table is retained.
  (define provisional
    (color-theme-value id normalized-name selected-palette
                       (make-immutable-hash (hash->list merged-roles))
                       normalized-series normalized-provenance #f #f #f #f))
  (define resolved-roles (resolve-all-theme-roles provisional))
  (define resolved-series
    (for/list ([spec (in-list normalized-series)])
      (resolve-color-in-theme spec provisional resolved-roles)))
  (define resolved-series-vector
    (vector->immutable-vector (list->vector resolved-series)))
  (define fingerprint
    (theme-appearance-fingerprint provisional resolved-roles resolved-series))
  (color-theme-value id normalized-name selected-palette
                     (color-theme-value-roles provisional)
                     normalized-series normalized-provenance
                     resolved-roles resolved-series resolved-series-vector fingerprint))

;; color-theme? : any/c -> boolean?
;;   Reports whether value is a validated complete immutable theme snapshot.
(define (color-theme? value) (color-theme-value? value))

;; color-theme-id : color-theme? -> symbol?
;;   Returns the stable theme identifier, which is not its appearance identity.
(define (color-theme-id theme)
  (check-theme 'color-theme-id theme)
  (color-theme-value-id theme))

;; color-theme-display-name : color-theme? -> string?
;;   Returns immutable human-readable theme metadata.
(define (color-theme-display-name theme)
  (check-theme 'color-theme-display-name theme)
  (color-theme-value-display-name theme))

;; color-theme-palette : color-theme? -> color-palette?
;;   Returns the complete palette snapshot owned by the theme.
(define (color-theme-palette theme)
  (check-theme 'color-theme-palette theme)
  (color-theme-value-palette theme))

;; color-theme-provenance : color-theme? -> (or/c #f string? symbol?)
;;   Returns non-appearance metadata retained separately from the fingerprint.
(define (color-theme-provenance theme)
  (check-theme 'color-theme-provenance theme)
  (color-theme-value-provenance theme))

;; theme-ref : color-theme? symbol? -> color-spec?
;;   Returns a normalized authored role specification without resolving it.
(define (theme-ref theme role-key)
  (check-theme 'theme-ref theme)
  (check-nonempty-symbol 'theme-ref "role key" role-key)
  (hash-ref (color-theme-value-roles theme)
            role-key
            (lambda ()
              (raise-arguments-error
               'theme-ref
               "theme containing the requested role"
               "theme" (color-theme-value-id theme)
               "role" role-key))))

;; theme-role-keys : color-theme? -> (listof symbol?)
;;   Returns role names in deterministic symbol order.
(define (theme-role-keys theme)
  (check-theme 'theme-role-keys theme)
  (sort (hash-keys (color-theme-value-roles theme)) symbol<?))

;; theme-series : color-theme? -> (listof rgba-color?)
;;   Returns the fully resolved immutable categorical series snapshot.
(define (theme-series theme)
  (check-theme 'theme-series theme)
  (color-theme-value-resolved-series theme))

;; color-theme-fingerprint : color-theme? -> immutable-bytes?
;;   Returns a deterministic appearance identity independent of display metadata.
(define (color-theme-fingerprint theme)
  (check-theme 'color-theme-fingerprint theme)
  (color-theme-value-fingerprint theme))

;; color-theme-resolved-roles : color-theme? -> immutable-hash?
;; Internal snapshot accessor for render-color-context construction.  The
;; public theme API intentionally exposes authored role specifications instead.
(define (color-theme-resolved-roles theme)
  (check-theme 'color-theme-resolved-roles theme)
  (color-theme-value-resolved-roles theme))


;;;
;;; Resolution
;;;

;; resolve-color-in-theme : color-spec? color-theme? [immutable-hash?] -> rgba-color?
;;   Resolves literals, tokens, and supported expressions under one explicit theme.
(define (resolve-color-in-theme spec theme [resolved-roles #f])
  (check-theme 'resolve-color-in-theme theme)
  (define roles (or resolved-roles (color-theme-value-resolved-roles theme)))
  (unless (hash? roles)
    (raise-arguments-error
     'resolve-color-in-theme
     "a fully validated theme role table"
     "theme" (color-theme-value-id theme)))
  (resolve-color-spec (normalize-color-spec spec 'resolve-color-in-theme)
                      theme roles))

;; resolve-all-theme-roles : color-theme? -> immutable-hash?
;;   Resolves every role with a tri-color DFS and reports indirect cycles.
(define (resolve-all-theme-roles theme)
  (define authored (color-theme-value-roles theme))
  (define states (make-hash))
  (define resolved (make-hash))
  (define (visit key chain)
    (case (hash-ref states key 'unseen)
      [(resolved) (hash-ref resolved key)]
      [(active)
       (raise-arguments-error
        'color-theme
        "theme roles without dependency cycles"
        "cycle" (reverse (cons key chain)))]
      [else
       (unless (hash-has-key? authored key)
         (raise-arguments-error
          'color-theme
          "theme containing every referenced role"
          "missing role" key
          "dependency chain" (reverse chain)))
       (hash-set! states key 'active)
       (define result
         (resolve-color-spec (hash-ref authored key)
                             theme
                             #f
                             visit
                             (cons key chain)))
       (hash-set! resolved key result)
       (hash-set! states key 'resolved)
       result]))
  (for ([key (in-list (sort (hash-keys authored) symbol<?))])
    (visit key '()))
  (make-immutable-hash (hash->list resolved)))

;; resolve-color-spec : color-spec? color-theme? (or/c #f hash?) ... -> rgba-color?
;;   Implements recursive literal/token/expression evaluation without global state.
(define (resolve-color-spec spec theme resolved-roles [visit-role #f] [chain '()])
  (cond
    [(rgba-color? spec) spec]
    [(palette-token? spec)
     (palette-ref (color-theme-value-palette theme) (palette-token-key spec))]
    [(role-token? spec)
     (define key (role-token-key spec))
     (cond
       [resolved-roles
        (hash-ref resolved-roles key
                  (lambda ()
                    (raise-arguments-error
                     'resolve-color-in-theme
                     "theme containing the requested role"
                     "theme" (color-theme-value-id theme)
                     "role" key)))]
       [visit-role (visit-role key chain)]
       [else
        (raise-arguments-error
         'resolve-color-in-theme
         "a resolved role table or a role resolver"
         "role" key)])]
    [(series-color? spec)
     (define series (color-theme-value-resolved-series-vector theme))
     (when (zero? (vector-length series))
       (raise-arguments-error
        'resolve-color-in-theme
        "theme with a nonempty categorical series"
        "theme" (color-theme-value-id theme)
        "series index" (series-color-index spec)))
     (vector-ref series
                 (modulo (series-color-index spec) (vector-length series)))]
    [(mix-color? spec)
     (mix-rgba-colors
      (resolve-color-spec (mix-color-from spec) theme resolved-roles visit-role chain)
      (resolve-color-spec (mix-color-to spec) theme resolved-roles visit-role chain)
      (mix-color-amount spec)
      (mix-color-space spec)
      (mix-color-alpha-mode spec))]
    [(alpha-color? spec)
     (define source
       (resolve-color-spec (alpha-color-source spec) theme resolved-roles visit-role chain))
     (define alpha
       (case (alpha-color-operation spec)
         [(replace) (alpha-color-amount spec)]
         [(multiply) (* (rgba-color-alpha source) (alpha-color-amount spec))]
         [else
          (raise-arguments-error
           'resolve-color-in-theme
           "supported alpha operation"
           "operation" (alpha-color-operation spec))]))
     (rgba-color (rgba-color-red source)
                 (rgba-color-green source)
                 (rgba-color-blue source)
                 alpha)]
    [else
     (raise-arguments-error
      'resolve-color-in-theme
      "color-spec?"
      "value" spec)]))

;; mix-rgba-colors : rgba-color? rgba-color? unit-real? symbol? symbol? -> rgba-color?
;;   Evaluates a declared mix with encoded or linear-light sRGB components.
(define (mix-rgba-colors from to amount space alpha-mode)
  (cond
    [(zero? amount) from]
    [(= amount 1) to]
    [else
     (rgba-color-mix from to amount #:space space #:alpha-mode alpha-mode)]))


;;;
;;; Deterministic Data and Identity
;;;

;; color-theme-fingerprint : color-theme? -> immutable-bytes?
;;   Uses complete resolved appearance values rather than display metadata.
(define (theme-appearance-fingerprint theme resolved-roles resolved-series)
  (bytes->immutable-bytes
   (sha1-bytes
    (call-with-output-bytes
     (lambda (out)
       (write
        (list 'animate-color-theme-appearance-v2
              (palette-appearance-datum (color-theme-value-palette theme))
              (for/list ([key (in-list (sort (hash-keys resolved-roles) symbol<?))])
                (list key (rgba->datum (hash-ref resolved-roles key))))
              (map rgba->datum resolved-series))
        out))))))

;; theme->datum : color-theme? -> datum?
;;   Converts a complete normalized theme to a readable evaluator-free datum.
(define (theme->datum theme)
  (check-theme 'theme->datum theme)
  `(animate-color-theme ,color-theme-schema-version
                        ,(color-theme-value-id theme)
                        ,(color-theme-value-display-name theme)
                        ,(palette->datum (color-theme-value-palette theme))
                        ,(for/list ([key (in-list (theme-role-keys theme))])
                           (list key (color-spec->datum (theme-ref theme key))))
                        ,(for/list ([spec (in-list (color-theme-value-series theme))])
                           (color-spec->datum spec))
                        ,(color-theme-value-provenance theme)))

;; datum->theme : any/c -> color-theme?
;;   Reads a complete theme datum without evaluating its contents.
(define (datum->theme datum)
  (define fields (checked-proper-list datum 'datum->theme))
  (unless (and (= (length fields) 8) (eq? (car fields) 'animate-color-theme))
    (raise-arguments-error
     'datum->theme
     "an (animate-color-theme version id name palette roles series provenance) datum"
     "datum" datum))
  (unless (exact-positive-integer? (list-ref fields 1))
    (raise-arguments-error
     'datum->theme
     "an exact positive theme schema version"
     "version" (list-ref fields 1)))
  (unless (= (list-ref fields 1) color-theme-schema-version)
    (raise-arguments-error
     'datum->theme
     "supported animate-color-theme schema version"
     "version" (list-ref fields 1)))
  (define roles
    (let loop ([entries (checked-proper-list (list-ref fields 5) 'datum->theme)]
               [index 0] [seen (hash)] [reversed '()])
      (cond
        [(null? entries) (make-immutable-hash (reverse reversed))]
        [else
         (define entry (car entries))
         (define pair (checked-proper-list entry 'datum->theme))
         (unless (and (= (length pair) 2) (symbol? (car pair)))
           (raise-arguments-error
            'datum->theme "(role-key color-spec-datum) entries" "entry" entry "index" index))
         (define key (car pair))
         (when (hash-has-key? seen key)
           (raise-arguments-error
            'datum->theme "role entries with no duplicate keys"
            "role" key "first index" (hash-ref seen key) "duplicate index" index))
         (loop (cdr entries) (add1 index) (hash-set seen key index)
               (cons (cons key (datum->color-spec (cadr pair))) reversed))])))
  (define series
    (for/list ([entry (in-list (checked-proper-list (list-ref fields 6) 'datum->theme))])
      (datum->color-spec entry)))
  (color-theme #:id (list-ref fields 2)
               #:display-name (list-ref fields 3)
               #:palette (datum->palette (list-ref fields 4))
               #:roles roles
               #:series series
               #:provenance (list-ref fields 7)))

;; palette-appearance-datum : color-palette? -> datum?
;;   Excludes non-appearance palette id, name, and provenance from identity.
(define (palette-appearance-datum palette)
  (list 'animate-color-palette-appearance-v1
        (color-palette-version palette)
        (for/list ([key (in-list (palette-keys palette))])
          (list key (rgba->datum (palette-ref palette key))))))

;; rgba->datum : rgba-color? -> datum?
;;   Produces a compact literal color datum used only for identity and storage.
(define (rgba->datum color)
  `(rgba ,(rgba-color-red color)
         ,(rgba-color-green color)
         ,(rgba-color-blue color)
         ,(rgba-color-alpha color)))


;;;
;;; Normalization Helpers
;;;

;; normalize-series : any/c symbol? -> (listof color-spec?)
;;   Copies a finite ordered authored categorical series.
(define (normalize-series series who)
  (unless (list? series)
    (raise-argument-error who "list? as #:series" series))
  (for/list ([spec (in-list series)])
    (normalize-color-spec spec who)))

;; reject-series-dependencies! : immutable-hash? (listof color-spec?) -> void?
;; The allowed graph is palette/literal -> role/series expressions. A
;; `series-color` token can be consumed only after that entire graph has been
;; completed, never while defining it.
(define (reject-series-dependencies! roles series)
  (for ([(key spec) (in-hash roles)])
    (reject-series-dependency! 'role key spec '()))
  (for ([spec (in-list series)] [index (in-naturals)])
    (reject-series-dependency! 'series index spec '())))

(define (reject-series-dependency! owner-kind owner spec route)
  (when (> (length route) maximum-theme-expression-depth)
    (raise-arguments-error
     'color-theme "a color definition within the configured expression-depth budget"
     "definition kind" owner-kind
     "definition" owner
     "maximum depth" maximum-theme-expression-depth))
  (cond
    [(series-color? spec)
     (raise-arguments-error
      'color-theme
      "role and series definitions without series-color dependencies"
      "definition kind" owner-kind
      "definition" owner
      "series index" (series-color-index spec)
      "dependency route" (reverse (cons 'series-color route)))]
    [(mix-color? spec)
     (reject-series-dependency! owner-kind owner (mix-color-from spec) (cons 'mix-from route))
     (reject-series-dependency! owner-kind owner (mix-color-to spec) (cons 'mix-to route))]
    [(alpha-color? spec)
     (reject-series-dependency! owner-kind owner (alpha-color-source spec) (cons 'alpha route))]
    [else (void)]))

;; normalize-display-name : any/c symbol? -> string?
;;   Copies human-readable metadata into an immutable string.
(define (normalize-display-name value who)
  (unless (string? value)
    (raise-argument-error who "string? display name" value))
  (string->immutable-string (string-copy value)))

;; normalize-provenance : any/c symbol? -> (or/c #f string? symbol?)
;;   Copies optional non-appearance provenance metadata.
(define (normalize-provenance value who)
  (cond
    [(not value) #f]
    [(symbol? value) value]
    [(string? value) (string->immutable-string (string-copy value))]
    [else (raise-argument-error who "(or/c #f symbol? string?) provenance" value)]))

;; checked-proper-list : any/c symbol? -> list?
;;   Rejects improper or cyclic external list data without evaluating it.
(define (checked-proper-list value who)
  (let loop ([rest value] [reversed '()] [seen (hasheq)])
    (cond
      [(null? rest) (reverse reversed)]
      [(not (pair? rest))
       (raise-argument-error who "proper list datum" value)]
      [(hash-has-key? seen rest)
       (raise-arguments-error who "acyclic proper-list datum" "cyclic value" value)]
      [else
       (loop (cdr rest) (cons (car rest) reversed) (hash-set seen rest #t))])))

;; check-nonempty-symbol : symbol? string? any/c -> void?
;;   Validates identifiers and role names without a display-name convention.
(define (check-nonempty-symbol who label value)
  (unless (and (symbol? value) (not (eq? value '||)))
    (raise-arguments-error who "nonempty symbol?" label value)))

;; check-theme : symbol? any/c -> void?
;;   Raises a consistent contract error for theme queries.
(define (check-theme who value)
  (unless (color-theme? value)
    (raise-argument-error who "color-theme?" value)))
