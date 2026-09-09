#lang racket/base

;;;
;;; Immutable Color Palettes
;;;

;; Defines validated immutable literal swatch tables. A palette has no roles or
;; renderer dependency; semantic role expressions are owned by color themes.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "color-style.rkt"
         "color-token.rkt"
         "color-serialization-budget.rkt"
         "color-palette-data.rkt")

;; Exports
(provide color-palette
         color-palette?
         color-palette-id
         color-palette-display-name
         color-palette-version
         color-palette-provenance
         palette-ref
         palette-keys
         palette-groups
         palette->datum
         datum->palette
         color-palette-schema-version)


;;;
;;; Data Representation
;;;

;; The colors hash has canonical symbol keys and rgba-color values. Keys and
;; groups preserve review/display order separately from hash insertion order.
(struct color-palette-value (id display-name version keys colors groups provenance)
  #:transparent)


;;;
;;; Schema and Construction
;;;

;; color-palette-schema-version : exact-positive-integer?
;;   Identifies the external palette datum format.
(define color-palette-schema-version 1)

;; color-palette : #:id symbol? #:colors hash? ... -> color-palette?
;;   Constructs a complete immutable literal palette, optionally extending one.
(define (color-palette #:id id
                       #:colors colors
                       #:extends [parent #f]
                       #:display-name [display-name (symbol->string id)]
                       #:version [version animate-palette-version]
                       #:groups [groups #f]
                       #:provenance [provenance #f])
  (check-nonempty-symbol 'color-palette "id" id)
  (unless (color-palette? parent)
    (unless (not parent)
      (raise-argument-error 'color-palette "(or/c #f color-palette?)" parent)))
  (unless (hash? colors)
    (raise-argument-error 'color-palette "hash? as #:colors" colors))
  (unless (exact-positive-integer? version)
    (raise-argument-error 'color-palette "exact-positive-integer? as #:version" version))
  (define normalized-name (normalize-display-name display-name 'color-palette))
  (define normalized-provenance (normalize-provenance provenance 'color-palette))
  (define overrides (normalize-palette-colors colors 'color-palette))
  (define parent-colors (if parent (color-palette-value-colors parent) (hash)))
  (define merged-colors
    (for/fold ([result parent-colors]) ([(key color) (in-hash overrides)])
      (hash-set result key color)))
  (unless parent
    (for ([key (in-list standard-palette-keys)])
      (unless (hash-has-key? merged-colors key)
        (raise-arguments-error
         'color-palette
         "a root palette containing every standard palette key"
         "missing key" key))))
  (define ordered-keys (merged-palette-keys parent merged-colors))
  (define normalized-groups
    (normalize-palette-groups
     (or groups
         (and parent (color-palette-value-groups parent))
         animate-palette-groups)
     merged-colors
     'color-palette))
  (color-palette-value id
                       normalized-name
                       version
                       ordered-keys
                       (make-immutable-hash (hash->list merged-colors))
                       normalized-groups
                       normalized-provenance))

;; color-palette? : any/c -> boolean?
;;   Reports whether value is a validated immutable palette.
(define (color-palette? value) (color-palette-value? value))

;; color-palette-id : color-palette? -> symbol?
;;   Returns the palette's stable identifier.
(define (color-palette-id palette)
  (check-palette 'color-palette-id palette)
  (color-palette-value-id palette))

;; color-palette-display-name : color-palette? -> string?
;;   Returns the immutable human-readable palette name.
(define (color-palette-display-name palette)
  (check-palette 'color-palette-display-name palette)
  (color-palette-value-display-name palette))

;; color-palette-version : color-palette? -> exact-positive-integer?
;;   Returns the palette's declared data version.
(define (color-palette-version palette)
  (check-palette 'color-palette-version palette)
  (color-palette-value-version palette))

;; color-palette-provenance : color-palette? -> (or/c #f string? symbol?)
;;   Returns non-appearance metadata retained separately from swatches.
(define (color-palette-provenance palette)
  (check-palette 'color-palette-provenance palette)
  (color-palette-value-provenance palette))

;; palette-ref : color-palette? symbol? -> rgba-color?
;;   Returns the literal swatch for one canonical palette key.
(define (palette-ref palette key)
  (check-palette 'palette-ref palette)
  (define canonical-key (color-token-key (palette-color key)))
  (hash-ref (color-palette-value-colors palette)
            canonical-key
            (lambda ()
              (raise-arguments-error
               'palette-ref
               "palette containing the requested key"
               "palette" (color-palette-value-id palette)
               "key" canonical-key))))

;; palette-keys : color-palette? -> (listof symbol?)
;;   Returns the deterministic complete palette-key order.
(define (palette-keys palette)
  (check-palette 'palette-keys palette)
  (color-palette-value-keys palette))

;; palette-groups : color-palette? -> (listof (list/c symbol? (listof symbol?)))
;;   Returns immutable ordered group metadata for swatch browsing.
(define (palette-groups palette)
  (check-palette 'palette-groups palette)
  (color-palette-value-groups palette))


;;;
;;; Deterministic Data Conversion
;;;

;; palette->datum : color-palette?
;;                   [#:serialization-budget color-serialization-budget?]
;;                   -> datum?
;;   Converts a palette to a readable, deterministic, versioned data tree.
(define (palette->datum palette #:serialization-budget [serialization-budget #f])
  (check-palette 'palette->datum palette)
  (define budget
    (or serialization-budget
        (make-color-serialization-budget 'palette->datum)))
  (unless (color-serialization-budget? budget)
    (raise-argument-error 'palette->datum
                          "color-serialization-budget? as #:serialization-budget"
                          budget))
  (define keys (palette-keys palette))
  (define groups (color-palette-value-groups palette))
  ;; Account for the root's list cells and direct atomic fields now. Descendant
  ;; color entries and groups are counted as they are produced, so an enormous
  ;; shallow palette cannot first allocate a complete export tree.
  (count-list-container! budget 8)
  (for ([value (in-list (list 'animate-color-palette
                              color-palette-schema-version
                              (color-palette-value-id palette)
                              (color-palette-value-display-name palette)
                              (color-palette-value-version palette)
                              (color-palette-value-provenance palette)))])
    (color-serialization-budget-count-atom! budget value))
  (count-list-container! budget (length keys))
  (define colors
    (for/list ([key (in-list keys)])
      (define entry (list key (rgba->datum (palette-ref palette key))))
      (color-serialization-budget-count-datum! budget entry)
      entry))
  (count-list-container! budget (length groups))
  (for ([group (in-list groups)])
    (color-serialization-budget-count-datum! budget group))
  `(animate-color-palette ,color-palette-schema-version
                          ,(color-palette-value-id palette)
                          ,(color-palette-value-display-name palette)
                          ,(color-palette-value-version palette)
                          ,colors
                          ,groups
                          ,(color-palette-value-provenance palette)))

;; A proper list's serialized shape has one pair node per element and a null
;; terminator. Children are deliberately counted separately by the caller.
(define (count-list-container! budget count)
  (for ([ignored (in-range (add1 count))])
    (color-serialization-budget-count-node! budget)))

;; datum->palette : any/c -> color-palette?
;;   Reads a complete declarative palette without evaluating external input.
(define (datum->palette datum)
  (define fields (checked-proper-list datum 'datum->palette))
  (unless (and (= (length fields) 8)
               (eq? (car fields) 'animate-color-palette))
    (raise-arguments-error
     'datum->palette
     "an (animate-color-palette version id name palette-version colors groups provenance) datum"
     "datum" datum))
  (unless (exact-positive-integer? (list-ref fields 1))
    (raise-arguments-error
     'datum->palette
     "an exact positive palette schema version"
     "version" (list-ref fields 1)))
  (unless (= (list-ref fields 1) color-palette-schema-version)
    (raise-arguments-error
     'datum->palette
     "supported animate-color-palette schema version"
     "version" (list-ref fields 1)))
  (define colors
    (let loop ([entries (checked-proper-list (list-ref fields 5) 'datum->palette)]
               [index 0] [seen (hash)] [reversed '()])
      (cond
        [(null? entries) (make-immutable-hash (reverse reversed))]
        [else
         (define entry (car entries))
         (define pair (checked-proper-list entry 'datum->palette))
         (unless (and (= (length pair) 2) (symbol? (car pair)))
           (raise-arguments-error
            'datum->palette "(key rgba-datum) entries" "entry" entry "index" index))
         (define key (color-token-key (palette-color (car pair))))
         (when (hash-has-key? seen key)
           (raise-arguments-error
            'datum->palette "palette entries with no duplicate canonical keys"
            "key" key "first index" (hash-ref seen key) "duplicate index" index))
         (loop (cdr entries) (add1 index) (hash-set seen key index)
               (cons (cons key (datum->rgba (cadr pair))) reversed))])))
  (color-palette #:id (list-ref fields 2)
                 #:display-name (list-ref fields 3)
                 #:version (list-ref fields 4)
                 #:colors colors
                 #:groups (list-ref fields 6)
                 #:provenance (list-ref fields 7)))


;;;
;;; Normalization Helpers
;;;

;; normalize-palette-colors : hash? symbol? -> immutable-hash?
;;   Validates canonical non-reserved keys and normalizes all values to RGBA.
(define (normalize-palette-colors colors who)
  (for/fold ([result (hash)]) ([(key value) (in-hash colors)])
    (unless (portable-color-key? key)
      (raise-arguments-error who "nonempty interned symbol? palette keys" "key" key))
    (define canonical-key (color-token-key (palette-color key)))
    (when (memq canonical-key reserved-literal-palette-keys)
      (raise-arguments-error
       who
       "palette keys other than reserved fixed literal names"
       "key" canonical-key))
    (unless (literal-color-spec? value)
      (raise-arguments-error
       who
       "literal-color-spec? palette values"
       "key" canonical-key
       "value" value))
    (when (hash-has-key? result canonical-key)
      (raise-arguments-error
       who
       "at most one entry for each canonical palette key"
       "key" canonical-key))
    (hash-set result canonical-key (color-spec->rgba-color value who))))

;; merged-palette-keys : (or/c #f color-palette?) immutable-hash? -> (listof symbol?)
;; Presentation has one canonical order independent of extension history. The
;; built-in catalog remains first; all additional keys follow in symbol order.
;; This same sequence is serialized and fingerprinted, so equal palettes made
;; through different parent chains have equal appearance identities.
(define (merged-palette-keys parent colors)
  (define base
    (filter (lambda (key) (hash-has-key? colors key)) standard-palette-keys))
  (define custom-keys
    (sort (for/list ([key (in-hash-keys colors)]
                     #:unless (memq key base))
            key)
          symbol<?))
  (append base custom-keys))

;; normalize-palette-groups : any/c immutable-hash? symbol? -> list?
;;   Copies declarative group metadata and ensures listed keys have swatches.
(define (normalize-palette-groups groups colors who)
  (unless (list? groups)
    (raise-argument-error who "list? palette groups" groups))
  (for/list ([group (in-list groups)])
    (define fields (checked-proper-list group who))
    (unless (and (= (length fields) 2)
                 (list? (cadr fields)))
      (raise-arguments-error who "(list group-id (listof palette-key))" "group" group))
    (unless (portable-color-key? (car fields))
      (raise-arguments-error who "a nonempty interned symbol as palette group id"
                             "group id" (car fields)))
    (define keys
      (for/list ([key (in-list (cadr fields))])
        (define canonical-key (color-token-key (palette-color key)))
        (unless (hash-has-key? colors canonical-key)
          (raise-arguments-error
           who
           "palette groups containing only present palette keys"
           "group" (car fields)
           "missing key" canonical-key))
        canonical-key))
    (list (car fields) keys)))

;; rgba->datum : rgba-color? -> datum?
;;   Produces the literal color body used inside palette data.
(define (rgba->datum color)
  `(rgba ,(rgba-color-red color)
         ,(rgba-color-green color)
         ,(rgba-color-blue color)
         ,(rgba-color-alpha color)))

;; datum->rgba : any/c -> rgba-color?
;;   Reads only an exact RGBA literal body, never a token or expression.
(define (datum->rgba datum)
  (define result
    (datum->color-spec `(animate-color-spec 1 ,datum)))
  (unless (rgba-color? result)
    (raise-arguments-error 'datum->palette "RGBA literal datum" "datum" datum))
  result)

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
    [(symbol? value)
     (unless (portable-color-key? value)
       (raise-arguments-error who "an interned symbol or string provenance" "provenance" value))
     value]
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
;;   Validates identifiers without imposing a display-name convention.
(define (check-nonempty-symbol who label value)
  (unless (portable-color-key? value)
    (raise-arguments-error who "nonempty interned symbol?" label value)))

;; check-palette : symbol? any/c -> void?
;;   Raises a consistent contract error for palette queries.
(define (check-palette who value)
  (unless (color-palette? value)
    (raise-argument-error who "color-palette?" value)))
