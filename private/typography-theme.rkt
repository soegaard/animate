#lang racket/base

;; Complete immutable typography snapshots.  This module is deliberately pure:
;; it defines no current authoring theme and performs no font lookup.

(require file/sha1
         racket/list
         racket/port
         "text-style.rkt")

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
  (define inherited (if parent (typography-theme-value-styles parent) (hash)))
  (define merged
    (for/fold ([result inherited]) ([entry (in-list (normalize-style-entries styles))])
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
       (write `(animate-typography-appearance-v1
                ,(for/list ([key (in-list (sort (hash-keys styles) symbol<?))])
                   (list key (text-style->datum (hash-ref styles key)))))
              output))))))

(define (typography-theme->datum theme)
  (unless (typography-theme? theme)
    (raise-argument-error 'typography-theme->datum "typography-theme?" theme))
  `(animate-typography-theme ,typography-theme-schema-version
                             ,(typography-theme-id theme)
                             ,(typography-theme-display-name theme)
                             ,(for/list ([key (in-list (typography-style-keys theme))])
                                (list key (text-style->datum (typography-ref theme key))))
                             ,(typography-theme-provenance theme)))

(define (datum->typography-theme datum)
  (unless (and (list? datum) (= (length datum) 6)
               (eq? (car datum) 'animate-typography-theme))
    (raise-arguments-error 'datum->typography-theme
                           "an (animate-typography-theme version id name styles provenance) datum"
                           "datum" datum))
  (unless (= (list-ref datum 1) typography-theme-schema-version)
    (raise-arguments-error 'datum->typography-theme
                           "a supported typography theme schema version"
                           "version" (list-ref datum 1)))
  (define entries
    (for/list ([entry (in-list (list-ref datum 4))])
      (unless (and (list? entry) (= (length entry) 2))
        (raise-arguments-error 'datum->typography-theme "(style-key style-datum) entries"
                               "entry" entry))
      (cons (car entry) (datum->text-style (cadr entry)))))
  (typography-theme #:id (list-ref datum 2)
                    #:display-name (list-ref datum 3)
                    #:styles entries
                    #:provenance (list-ref datum 5)))
