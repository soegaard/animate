#lang racket/base

;; Complete immutable typography snapshots.  This module is deliberately pure:
;; it defines no current authoring theme and performs no font lookup.

(require file/sha1
         racket/list
         racket/port
         "text-style.rkt"
         "typography-serialization-budget.rkt")

(provide typography-theme
         typography-theme?
         typography-theme-id
         typography-theme-display-name
         typography-theme-provenance
         typography-ref
         typography-style-keys
         typography-theme-fingerprint
         typography-theme-schema-version
         typography-theme->datum
         datum->typography-theme
         typography-standard-style-keys)

(define typography-theme-schema-version 1)
(define maximum-typography-style-count 10000)
(define maximum-typography-serialization-nodes 100000)
(define typography-standard-style-keys
  '(title subtitle section-heading body caption label quotation code annotation))

(struct typography-theme-value (id display-name styles provenance fingerprint)
  #:transparent)

(define (portable-style-key? value)
  (and (symbol? value) (symbol-interned? value)
       (positive? (string-length (symbol->string value)))))

(define (typography-theme #:id id
                          #:styles [styles (hash)]
                          #:extends [parent #f]
                          #:display-name [display-name (and (symbol? id) (symbol->string id))]
                          #:provenance [provenance #f])
  (unless (portable-style-key? id)
    (raise-argument-error 'typography-theme "nonempty interned symbol? as #:id" id))
  (unless (or (not parent) (typography-theme? parent))
    (raise-argument-error 'typography-theme "(or/c #f typography-theme?) as #:extends" parent))
  (unless (string? display-name)
    (raise-argument-error 'typography-theme "string? as #:display-name" display-name))
  (unless (or (not provenance) (string? provenance) (symbol? provenance))
    (raise-argument-error 'typography-theme "(or/c #f string? symbol?) as #:provenance" provenance))
  (define normalized-entries (normalize-style-entries styles))
  (when (> (length normalized-entries) maximum-typography-style-count)
    (raise-arguments-error 'typography-theme
                           "at most the configured number of style definitions"
                           "maximum" maximum-typography-style-count
                           "count" (length normalized-entries)))
  (define inherited (if parent (typography-theme-value-styles parent) (hash)))
  (define merged
    (for/fold ([result inherited]) ([entry (in-list normalized-entries)])
      (hash-set result (car entry) (cdr entry))))
  (unless parent
    (for ([key (in-list typography-standard-style-keys)])
      (unless (hash-has-key? merged key)
        (raise-arguments-error 'typography-theme
                               "a root theme with every standard style"
                               "missing style" key))))
  (define immutable-styles (make-immutable-hash (hash->list merged)))
  (typography-theme-value
   id
   (string->immutable-string display-name)
   immutable-styles
   (if (string? provenance) (string->immutable-string provenance) provenance)
   (appearance-fingerprint immutable-styles)))

(define (typography-theme? value) (typography-theme-value? value))
(define (typography-theme-id theme) (checked-theme 'typography-theme-id theme typography-theme-value-id))
(define (typography-theme-display-name theme) (checked-theme 'typography-theme-display-name theme typography-theme-value-display-name))
(define (typography-theme-provenance theme) (checked-theme 'typography-theme-provenance theme typography-theme-value-provenance))
(define (typography-theme-fingerprint theme) (checked-theme 'typography-theme-fingerprint theme typography-theme-value-fingerprint))

(define (typography-ref theme key)
  (unless (portable-style-key? key)
    (raise-argument-error 'typography-ref "nonempty interned symbol?" key))
  (define styles (checked-theme 'typography-ref theme typography-theme-value-styles))
  (hash-ref styles key
            (lambda ()
              (raise-arguments-error 'typography-ref
                                     "theme containing the requested style"
                                     "theme" (typography-theme-id theme)
                                     "style" key))))

(define (typography-style-keys theme)
  (sort (hash-keys (checked-theme 'typography-style-keys theme typography-theme-value-styles))
        symbol<?))

(define (checked-theme who theme accessor)
  (unless (typography-theme? theme)
    (raise-argument-error who "typography-theme?" theme))
  (accessor theme))

(define (normalize-style-entries styles)
  (define entries
    (cond [(hash? styles)
           (for/list ([(key value) (in-hash styles)]) (cons key value))]
          [(list? styles) styles]
          [else (raise-argument-error 'typography-theme "hash? or association list? as #:styles" styles)]))
  (let loop ([remaining entries] [seen (hash)] [reversed '()] [index 0])
         (cond [(null? remaining) (reverse reversed)]
               [else
                (define entry (car remaining))
                (unless (and (pair? entry) (not (pair? (cdr entry))))
                  (raise-arguments-error 'typography-theme
                                         "(style-key . text-style?) entries"
                                         "entry" entry "index" index))
                (define key (car entry))
                (define style (cdr entry))
                (unless (portable-style-key? key)
                  (raise-argument-error 'typography-theme "nonempty interned style key" key))
                (unless (text-style? style)
                  (raise-argument-error 'typography-theme "text-style? as style value" style))
                (when (hash-has-key? seen key)
                  (raise-arguments-error 'typography-theme
                                         "style entries with no duplicate keys"
                                         "style" key "first index" (hash-ref seen key)
                                         "duplicate index" index))
                (loop (cdr remaining) (hash-set seen key index)
                      (cons (cons key style) reversed) (add1 index))])))

(define (appearance-fingerprint styles)
  (bytes->immutable-bytes
   (sha1-bytes
    (call-with-output-bytes
     (lambda (output)
       (canonical-typography-write
        `(animate-typography-appearance-v2
          ,(for/list ([key (in-list (sort (hash-keys styles) symbol<?))])
             (list key (text-style->datum (hash-ref styles key)))))
        output))))))

;; Typography fingerprints are persistent appearance identities. Keep their
;; byte encoding independent of ambient caller printer preferences.
(define (canonical-typography-write value output)
  (parameterize ([print-pair-curly-braces #f]
                 [print-graph #f]
                 [print-reader-abbreviations #f]
                 [print-boolean-long-form #f])
    (write value output)))

(define (typography-theme->datum theme)
  (unless (typography-theme? theme)
    (raise-argument-error 'typography-theme->datum "typography-theme?" theme))
  (define datum
    `(animate-typography-theme ,typography-theme-schema-version
                               ,(typography-theme-id theme)
                               ,(typography-theme-display-name theme)
                               ,(for/list ([key (in-list (typography-style-keys theme))])
                                  (list key (text-style->datum (typography-ref theme key))))
                               ,(typography-theme-provenance theme)))
  ;; One shared allowance counts the wrapper, metadata, every style property,
  ;; treatment paint/stops, and each nested color datum.
  (typography-serialization-budget-count-datum!
   (make-typography-serialization-budget
    'typography-theme->datum
    #:maximum-nodes maximum-typography-serialization-nodes)
   datum)
  datum)

(define (datum->typography-theme datum)
  ;; Bound the entire untrusted tree before even the outer-list helper creates
  ;; a reversed copy. The generic counter also rejects cyclic nested data.
  (typography-serialization-budget-count-datum!
   (make-typography-serialization-budget
    'datum->typography-theme
    #:maximum-nodes maximum-typography-serialization-nodes)
   datum)
  (define fields (proper-list-elements datum 'datum->typography-theme))
  (unless (and (= (length fields) 6)
               (eq? (car fields) 'animate-typography-theme))
    (raise-arguments-error 'datum->typography-theme
                           "an (animate-typography-theme version id name styles provenance) datum"
                           "datum" datum))
  (define schema-version (list-ref fields 1))
  (unless (exact-positive-integer? schema-version)
    (raise-arguments-error 'datum->typography-theme
                           "an exact positive typography schema version"
                           "version" schema-version))
  (unless (= schema-version typography-theme-schema-version)
    (raise-arguments-error 'datum->typography-theme
                           "a supported typography theme schema version"
                           "version" schema-version))
  (define style-data
    (proper-list-elements (list-ref fields 4) 'datum->typography-theme
                          #:maximum maximum-typography-style-count))
  (define entries
    (let loop ([remaining style-data] [index 0] [seen (hash)] [reversed '()])
      (cond
        [(null? remaining) (reverse reversed)]
        [else
         (define entry (car remaining))
         (define entry-fields
           (proper-list-elements entry 'datum->typography-theme #:maximum 2))
         (unless (= (length entry-fields) 2)
        (raise-arguments-error 'datum->typography-theme "(style-key style-datum) entries"
                               "entry" entry))
         (define key (car entry-fields))
         (unless (portable-style-key? key)
           (raise-arguments-error 'datum->typography-theme
                                  "a nonempty interned style key"
                                  "style" key "index" index))
         (when (hash-has-key? seen key)
           (raise-arguments-error 'datum->typography-theme
                                  "style entries with no duplicate keys"
                                  "style" key
                                  "first index" (hash-ref seen key)
                                  "duplicate index" index))
         (loop (cdr remaining) (add1 index) (hash-set seen key index)
               (cons (cons key (datum->text-style (cadr entry-fields))) reversed))])))
  (typography-theme #:id (list-ref fields 2)
                    #:display-name (list-ref fields 3)
                    #:styles entries
                    #:provenance (list-ref fields 5)))

;; Validates a bounded proper list before callers use list operations or
;; traverse untrusted style entries. This keeps decoding failures in typography
;; vocabulary instead of exposing an incidental list/number contract.
(define (proper-list-elements value who #:maximum [maximum #f])
  (let loop ([remaining value] [reversed '()] [seen (hasheq)] [count 0])
    (cond
      [(null? remaining) (reverse reversed)]
      [(not (pair? remaining))
       (raise-arguments-error who "an acyclic proper list datum" "datum" value)]
      [(hash-has-key? seen remaining)
       (raise-arguments-error who "an acyclic proper list datum" "datum" value)]
      [else
       (define next-count (add1 count))
       (when (and maximum (> next-count maximum))
         (raise-arguments-error who
                                "a typography datum within the configured style-count budget"
                                "maximum styles" maximum
                                "styles" next-count))
       (loop (cdr remaining) (cons (car remaining) reversed)
             (hash-set seen remaining #t) next-count)])))
