#lang racket/base

;; Complete immutable typography snapshots.  This module is deliberately pure:
;; it defines no current authoring theme and performs no font lookup.

(require file/sha1
         racket/list
         racket/port
         "color-expression.rkt"
         "color-style.rkt"
         "color-token.rkt"
         "geometry.rkt"
         "paint.rkt"
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
  ;; The portable style limit describes the complete inherited theme, not only
  ;; one extension delta. Otherwise an in-memory child could be accepted but
  ;; later fail its own decoder/round-trip limit.
  (when (> (hash-count merged) maximum-typography-style-count)
    (raise-arguments-error 'typography-theme
                           "at most the configured number of complete style definitions"
                           "maximum" maximum-typography-style-count
                           "count" (hash-count merged)))
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
  ;; Fingerprinting serializes the same complete style payload as portable
  ;; transport. Preflight it too, so constructing a theme cannot bypass the
  ;; serialization bound by putting a giant gradient only in its fingerprint.
  ;; The node shape and every source-owned atom are both checked before the
  ;; canonical writer allocates its output bytes.
  (define preflight
    (make-typography-serialization-budget
     'typography-theme
     #:maximum-nodes maximum-typography-serialization-nodes))
  (typography-serialization-budget-reserve!
   preflight (+ 4 (style-map-datum-node-count styles)))
  (preflight-style-map-atoms! preflight styles)
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
  ;; Check the exact output shape from the already-immutable theme before a
  ;; conversion allocates its derived style and gradient-stop datum lists.
  ;; In particular, a hostile but valid source gradient with many stops now
  ;; fails here rather than after duplicating every stop as portable data.
  (define preflight
    (make-typography-serialization-budget
     'typography-theme->datum
     #:maximum-nodes maximum-typography-serialization-nodes))
  (typography-serialization-budget-reserve!
   preflight (typography-theme-datum-node-count theme))
  (preflight-theme-datum-atoms! preflight theme)
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

;; Count the precise pair/atom tree that `typography-theme->datum` will emit,
;; without constructing that tree.  Keep this adjacent to the serializer so
;; any portable grammar change updates both the emitted datum and this compact
;; preflight description together.
(define (typography-theme-datum-node-count theme)
  ;; `(animate-typography-theme version id display-name styles provenance)`
  (+ 12 (style-map-datum-node-count
         (checked-theme 'typography-theme->datum theme typography-theme-value-styles))))

(define (style-map-datum-node-count styles)
  ;; Each spine pair and the terminal null are serialized nodes.
  (define keys (sort (hash-keys styles) symbol<?))
  (+ (length keys) 1
     (for/sum ([key (in-list keys)])
       ;; `(key text-style-datum)`
       (+ 4 (text-style-datum-node-count (hash-ref styles key))))))

(define (text-style-datum-node-count style)
  ;; The style wrapper contains twelve list elements.  Apart from color and
  ;; treatment, its tag and nine scalar properties occupy twenty-three nodes.
  (+ 23
     (color-spec-datum-node-count (text-style-color style))
     (treatment-datum-node-count (text-style-treatment style))))

(define (treatment-datum-node-count treatment)
  (cond [(not treatment) 1]
        [else
         ;; `(text-treatment background border border-width padding-x padding-y)`
         (+ 11
            (if (text-treatment-background treatment)
                (paint-datum-node-count (text-treatment-background treatment))
                1)
            (if (text-treatment-border-color treatment)
                (color-spec-datum-node-count
                 (text-treatment-border-color treatment))
                1))]))

(define (paint-datum-node-count paint)
  (cond
    [(color-spec? paint) (+ 4 (color-spec-datum-node-count paint))]
    [(linear-gradient-paint? paint)
     ;; tag + two points + stop list
     (+ 16 (stops-datum-node-count (linear-gradient-paint-stops paint)))]
    [(radial-gradient-paint? paint)
     ;; tag + two points + two radii + stop list
     (+ 20 (stops-datum-node-count (radial-gradient-paint-stops paint)))]
    [(checker-pattern-paint? paint)
     (+ 7
        (color-spec-datum-node-count (checker-pattern-paint-first paint))
        (color-spec-datum-node-count (checker-pattern-paint-second paint)))]
    [else
     (raise-arguments-error 'typography-theme->datum "paint?"
                            "background" paint)]))

(define (stops-datum-node-count stops)
  (+ (length stops) 1
     (for/sum ([stop (in-list stops)])
       ;; `(offset color-datum)`
       (+ 4 (color-spec-datum-node-count (paint-stop-color stop))))))

(define (color-spec-datum-node-count color)
  ;; `(animate-color-spec version body)` contributes six nodes.  Use an
  ;; explicit work list so a deeply nested color expression cannot consume the
  ;; host stack while we are trying to reject an oversized serialization.
  (let loop ([pending (list color)] [count 6])
    (cond
      [(null? pending) count]
      [else
       (define current (car pending))
       (cond
         [(rgba-color? current) (loop (cdr pending) (+ count 11))]
         [(or (palette-token? current)
              (role-token? current)
              (series-color? current))
          (loop (cdr pending) (+ count 5))]
         [(mix-color? current)
          ;; `(mix space alpha-mode amount from-body to-body)`
          (loop (cons (mix-color-from current)
                      (cons (mix-color-to current) (cdr pending)))
                (+ count 11))]
         [(alpha-color? current)
          ;; `(alpha operation amount source-body)`
          (loop (cons (alpha-color-source current) (cdr pending))
                (+ count 8))]
         [else
          ;; Theme construction already validates color specifications. Keep
          ;; this guard close to the serializer for a useful private failure if
          ;; that invariant is ever broken.
          (raise-arguments-error 'typography-theme->datum "color-spec?"
                                 "color" current)])])))

;; The exact node-count functions above protect against wide portable trees.
;; These helpers inspect the same source values before serializers build those
;; trees, protecting against one enormous atom (for example a display name,
;; font face, or token key). Static grammar tags are intentionally omitted:
;; they are small literals owned by this module.
(define (preflight-theme-datum-atoms! budget theme)
  (typography-serialization-budget-check-atom! budget (typography-theme-id theme))
  (typography-serialization-budget-check-atom!
   budget (typography-theme-display-name theme))
  (typography-serialization-budget-check-atom!
   budget (typography-theme-provenance theme))
  (preflight-style-map-atoms!
   budget
   (checked-theme 'typography-theme->datum theme typography-theme-value-styles)))

(define (preflight-style-map-atoms! budget styles)
  (for ([key (in-list (sort (hash-keys styles) symbol<?))])
    (typography-serialization-budget-check-atom! budget key)
    (preflight-text-style-atoms! budget (hash-ref styles key))))

(define (preflight-text-style-atoms! budget style)
  (for ([value (in-list
                (list (text-style-font-face style)
                      (text-style-font-family style)
                      (text-style-font-size style)
                      (text-style-font-style style)
                      (text-style-font-weight style)
                      (text-style-line-spacing style)
                      (text-style-line-alignment style)
                      (text-style-horizontal-alignment style)
                      (text-style-vertical-alignment style)))])
    (typography-serialization-budget-check-atom! budget value))
  (preflight-color-spec-atoms! budget (text-style-color style))
  (preflight-treatment-atoms! budget (text-style-treatment style)))

(define (preflight-treatment-atoms! budget treatment)
  (cond
    [(not treatment)
     (typography-serialization-budget-check-atom! budget #f)]
    [else
     (define background (text-treatment-background treatment))
     (define border-color (text-treatment-border-color treatment))
     (if background
         (preflight-paint-atoms! budget background)
         (typography-serialization-budget-check-atom! budget #f))
     (if border-color
         (preflight-color-spec-atoms! budget border-color)
         (typography-serialization-budget-check-atom! budget #f))
     (for ([value (in-list
                   (list (text-treatment-border-width treatment)
                         (text-treatment-padding-x treatment)
                         (text-treatment-padding-y treatment)))])
       (typography-serialization-budget-check-atom! budget value))]))

(define (preflight-paint-atoms! budget paint)
  (cond
    [(color-spec? paint)
     (preflight-color-spec-atoms! budget paint)]
    [(linear-gradient-paint? paint)
     (preflight-vec2-atoms! budget (linear-gradient-paint-start paint))
     (preflight-vec2-atoms! budget (linear-gradient-paint-end paint))
     (preflight-stops-atoms! budget (linear-gradient-paint-stops paint))]
    [(radial-gradient-paint? paint)
     (preflight-vec2-atoms! budget (radial-gradient-paint-focal-center paint))
     (typography-serialization-budget-check-atom!
      budget (radial-gradient-paint-focal-radius paint))
     (preflight-vec2-atoms! budget (radial-gradient-paint-center paint))
     (typography-serialization-budget-check-atom!
      budget (radial-gradient-paint-radius paint))
     (preflight-stops-atoms! budget (radial-gradient-paint-stops paint))]
    [(checker-pattern-paint? paint)
     (preflight-color-spec-atoms! budget (checker-pattern-paint-first paint))
     (preflight-color-spec-atoms! budget (checker-pattern-paint-second paint))
     (typography-serialization-budget-check-atom!
      budget (checker-pattern-paint-cell-size paint))]
    [else
     (raise-arguments-error 'typography-theme->datum "paint?"
                            "background" paint)]))

(define (preflight-vec2-atoms! budget point)
  (typography-serialization-budget-check-atom! budget (vec2-x point))
  (typography-serialization-budget-check-atom! budget (vec2-y point)))

(define (preflight-stops-atoms! budget stops)
  (for ([stop (in-list stops)])
    (typography-serialization-budget-check-atom! budget (paint-stop-offset stop))
    (preflight-color-spec-atoms! budget (paint-stop-color stop))))

(define (preflight-color-spec-atoms! budget color)
  ;; Keep this iterative for the same reason as color-spec-datum-node-count:
  ;; a valid, deeply nested expression must not consume the host stack while
  ;; we are checking a portable-data bound.
  (let loop ([pending (list color)])
    (cond
      [(null? pending) (void)]
      [else
       (define current (car pending))
       (cond
         [(rgba-color? current)
          (for ([value (in-list (list (rgba-color-red current)
                                      (rgba-color-green current)
                                      (rgba-color-blue current)
                                      (rgba-color-alpha current)))])
            (typography-serialization-budget-check-atom! budget value))
          (loop (cdr pending))]
         [(palette-token? current)
          (typography-serialization-budget-check-atom!
           budget (palette-token-key current))
          (loop (cdr pending))]
         [(role-token? current)
          (typography-serialization-budget-check-atom! budget (role-token-key current))
          (loop (cdr pending))]
         [(series-color? current)
          (typography-serialization-budget-check-atom!
           budget (series-color-index current))
          (loop (cdr pending))]
         [(mix-color? current)
          (for ([value (in-list (list (mix-color-space current)
                                      (mix-color-alpha-mode current)
                                      (mix-color-amount current)))])
            (typography-serialization-budget-check-atom! budget value))
          (loop (cons (mix-color-from current)
                      (cons (mix-color-to current) (cdr pending))))]
         [(alpha-color? current)
          (typography-serialization-budget-check-atom!
           budget (alpha-color-operation current))
          (typography-serialization-budget-check-atom!
           budget (alpha-color-amount current))
          (loop (cons (alpha-color-source current) (cdr pending)))]
         [else
          (raise-arguments-error 'typography-theme->datum "color-spec?"
                                 "color" current)])])))

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
