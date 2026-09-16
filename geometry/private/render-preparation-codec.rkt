#lang racket/base

;; A closed, data-only protocol. No eval, deserialize hooks, arbitrary struct
;; construction, module names, closures, Picts, or font binaries in the wire data.
;; Exact rationals stay exact. Hash ordering is canonical and is not geometry.
(require racket/list racket/match file/sha1
         (prefix-in c: "../../colors.rkt")
         "math.rkt" "data.rkt" "marker-shapes.rkt" "reveal.rkt"
         "../labels.rkt" "../theme.rkt" "render-preparation.rkt")
(provide prepared-geometry-render->datum datum->prepared-geometry-render
         snapshot-geometry-render-preparation geometry-source-fingerprint)

(struct record-codec (tag predicate constructor arity) #:transparent)
(define records
  (list
   (record-codec 'prepared prepared-geometry-render? prepared-geometry-render 17)
   (record-codec 'view geometry-view? geometry-view 4)
   (record-codec 'playback geometry-timeline? geometry-timeline 8)
   (record-codec 'event geometry-event? geometry-event 5)
   (record-codec 'cue geometry-cue? geometry-cue 3)
   (record-codec 'action geometry-action? geometry-action 3)
   (record-codec 'presentation presentation? presentation 3)
   (record-codec 'point point? point 2)
   (record-codec 'line line? line 2)
   (record-codec 'segment segment? segment 2)
   (record-codec 'ray ray? ray 2)
   (record-codec 'circle circle? circle 2)
   (record-codec 'angle angle-spec? angle-spec 3)
   (record-codec 'perpendicular-marker perpendicular-marker? perpendicular-marker 3)
   (record-codec 'parallel-marker parallel-marker? parallel-marker 2)
   (record-codec 'equal-length-marker equal-length-marker? equal-length-marker 1)
   (record-codec 'angle-marker angle-marker? angle-marker 1)
   (record-codec 'equal-angle-marker equal-angle-marker? equal-angle-marker 1)
   (record-codec 'midpoint-marker midpoint-marker? midpoint-marker 2)
   (record-codec 'marker-placement marker-placement? marker-placement 3)
   (record-codec 'compass-source compass-source? compass-source 2)))
(define schema 'animate-geometry-render-preparation-v1)
(define maximum-depth 128)
(define maximum-nodes 2000000)
(define (fail message value)
  (raise-arguments-error 'geometry-render-codec message "value" value))
(define (id? v)
  (and (symbol? v) (symbol-interned? v) (positive? (string-length (symbol->string v)))))
(define (nonnegative? v) (and (finite-real? v) (>= v 0)))
(define (positive?* v) (and (finite-real? v) (> v 0)))
(define (immutable-table? v) (and (hash? v) (immutable? v)))
(define (same-keys? a b)
  (and (= (hash-count a) (hash-count b))
       (for/and ([key (in-hash-keys a)]) (hash-has-key? b key))))

;; The raw record constructor remains private; both effectful preparation and
;; decoding pass through this structural contract before a sampler can use it.
(define (validate-preparation p)
  (unless (prepared-geometry-render? p) (fail "expected a prepared geometry render" p))
  (define view (prepared-geometry-render-view p))
  (define order (prepared-geometry-render-order p))
  (define env (prepared-geometry-render-environment p))
  (define timeline (prepared-geometry-render-playback p))
  (unless (and (exact-positive-integer? (prepared-geometry-render-pixels p))
               (boolean? (prepared-geometry-render-captions? p))
               (geometry-view? view) (point? (geometry-view-center view))
               (positive?* (geometry-view-width view)) (positive?* (geometry-view-aspect view))
               (nonnegative? (geometry-view-margin view))
               (list? order) (andmap id? order)
               (= (length order) (length (remove-duplicates order)))
               (immutable-table? env) (= (hash-count env) (length order))
               (for/and ([id (in-list order)]) (hash-has-key? env id))
               (geometry-timeline? timeline)
               (not (geometry-timeline-realization timeline))
               (not (geometry-timeline-theme timeline))
               (null? (geometry-timeline-steps timeline))
               (nonnegative? (geometry-timeline-duration timeline)))
    (fail "invalid prepared viewport, drawable identities, or source-free playback" p))
  (define duration (geometry-timeline-duration timeline))
  (define initial (geometry-timeline-initial timeline))
  (define (state? state)
    (and (immutable-table? state)
         (for/and ([(id value) (in-hash state)])
           (and (id? id) (presentation? value)
                (boolean? (presentation-shown? value))
                (boolean? (presentation-label? value))
                (boolean? (presentation-secondary? value))))))
  (unless (and (state? initial) (state? (geometry-timeline-final timeline))
               (same-keys? initial (geometry-timeline-final timeline))
               (for/and ([id (in-list order)]) (hash-has-key? initial id)))
    (fail "invalid geometry presentation state" initial))
  (define (time? t) (and (nonnegative? t) (<= t duration)))
  (define events (geometry-timeline-events timeline))
  (define cues (geometry-timeline-cues timeline))
  (unless (and (list? events)
               (for/and ([e (in-list events)])
                 (and (geometry-event? e) (time? (geometry-event-start e))
                      (time? (geometry-event-end e)) (<= (geometry-event-start e) (geometry-event-end e))
                      (state? (geometry-event-before e)) (state? (geometry-event-after e))
                      (same-keys? initial (geometry-event-before e)) (same-keys? initial (geometry-event-after e))
                      (list? (geometry-event-actions e))
                      (for/and ([action (in-list (geometry-event-actions e))])
                        (and (geometry-action? action) (not (geometry-action-payload action))
                             (memq (geometry-action-kind action)
                                   '(reveal show hide show-label hide-label deemphasize normalize highlight))
                             (list? (geometry-action-targets action))
                             (for/and ([id (in-list (geometry-action-targets action))])
                               (hash-has-key? initial id))))))
               (for/and ([a (in-list events)] [b (in-list (if (null? events) '() (cdr events)))])
                 (<= (geometry-event-end a) (geometry-event-start b)))
               (list? cues)
               (for/and ([cue (in-list cues)])
                 (and (geometry-cue? cue) (time? (geometry-cue-start cue)) (time? (geometry-cue-end cue))
                      (<= (geometry-cue-start cue) (geometry-cue-end cue)) (string? (geometry-cue-text cue)))))
    (fail "invalid geometry event or caption schedule" timeline))
  (define styles (prepared-geometry-render-styles p))
  (define reveals (prepared-geometry-render-reveals p))
  (unless (and (immutable-table? styles) (same-keys? env styles)
               (immutable-table? reveals) (same-keys? env reveals))
    (fail "prepared styles and reveals must cover exactly the drawable identities" p))
  (for ([id (in-list order)])
    (define value (hash-ref env id))
    (define four (hash-ref styles id))
    (define reveal (hash-ref reveals id))
    (unless (and (or (point? value) (curve? value) (marker? value) (semantic-label? value))
                 (list? four) (= (length four) 4) (andmap immutable-table? four)
                 (pair? reveal) (symbol? (car reveal))
                 (reveal-mode-valid? (geometry-kind value) (car reveal))
                 (or (not (cdr reveal))
                     (and (compass-source? (cdr reveal))
                          (point? (compass-source-a (cdr reveal))) (point? (compass-source-b (cdr reveal)))))
                 (or (not (eq? (car reveal) 'compass))
                     (and (circle? value) (compass-source? (cdr reveal)))))
      (fail "invalid drawable, resolved styles, or compass provenance" id)))
  (for ([table (in-list (list (prepared-geometry-render-labels p) (prepared-geometry-render-texts p)
                             (prepared-geometry-render-placements p) (prepared-geometry-render-counts p)))])
    (unless (and (immutable-table? table)
                 (for/and ([id (in-hash-keys table)]) (hash-has-key? env id)))
      (fail "annotation table references an unknown drawable" table)))
  (unless (and (for/and ([v (in-hash-values (prepared-geometry-render-labels p))]) (point? v))
               (for/and ([v (in-hash-values (prepared-geometry-render-texts p))]) (string? v))
               (for/and ([v (in-hash-values (prepared-geometry-render-placements p))])
                 (and (marker-placement? v) (nonnegative? (marker-placement-position v))
                      (<= (marker-placement-position v) 1) (memv (marker-placement-quadrant v) '(1 2 3 4))
                      (nonnegative? (marker-placement-radius v))))
               (for/and ([v (in-hash-values (prepared-geometry-render-counts p))]) (exact-positive-integer? v))
               (nonnegative? (prepared-geometry-render-caption-size p))
               (finite-real? (prepared-geometry-render-caption-y p))
               (nonnegative? (prepared-geometry-render-caption-height p))
               (immutable-table? (prepared-geometry-render-guide-style p))
               (immutable-table? (prepared-geometry-render-attention-style p)))
    (fail "invalid frozen annotation geometry" p))
  p)

(define (make-budget)
  (define n 0)
  (lambda (depth)
    (set! n (add1 n))
    (when (or (> depth maximum-depth) (> n maximum-nodes))
      (fail "geometry preparation exceeds the bounded data protocol" n))))
(define (encode-prepared value)
  (define active (make-hasheq))
  (define budget! (make-budget))
  (define (walk value depth)
    (budget! depth)
    (define (recur v) (walk v (add1 depth)))
    (define compound? (or (pair? value) (hash? value) (vector? value) (struct? value)))
    (when compound?
      (when (hash-ref active value #f) (fail "cyclic geometry preparation is not portable" value))
      (hash-set! active value #t))
    (define encoded
      (cond
        [(or (boolean? value) (char? value) (keyword? value)) value]
        [(finite-real? value) value]
        [(and (symbol? value) (symbol-interned? value)) value]
        [(string? value) (string->immutable-string value)]
        [(null? value) '()]
        [(list? value) (list 'list (map recur value))]
        [(pair? value) (list 'pair (recur (car value)) (recur (cdr value)))]
        [(vector? value) (list 'vector (map recur (vector->list value)))]
        [(hash? value)
         (when (hash-weak? value) (fail "weak tables cannot own prepared geometry" value))
         (define mode (cond [(hash-eq? value) 'eq] [(hash-eqv? value) 'eqv] [else 'equal]))
         (list 'hash mode
               (sort (for/list ([(key v) (in-hash value)]) (list (recur key) (recur v)))
                     string<? #:key (lambda (entry) (format "~s" (car entry)))))]
        [(semantic-label? value)
         (list 'label (semantic-label-kind value) (recur (semantic-label-target value))
               (string->immutable-string (semantic-label-text value)) (semantic-label-arc? value))]
        [(and (struct? value) (c:color-spec? value))
         (list 'color (recur (c:color-spec->datum value)))]
        [else
         (define codec (findf (lambda (r) ((record-codec-predicate r) value)) records))
         (unless codec (fail "unsupported value in portable geometry preparation" value))
         (define fields (cdr (vector->list (struct->vector value))))
         (unless (= (length fields) (record-codec-arity codec))
           (fail "unsupported geometry record extension" value))
         (list 'record (record-codec-tag codec) (map recur fields))]))
    (when compound? (hash-remove! active value))
    encoded)
  (walk value 0))

(define (decode-prepared encoded)
  (define budget! (make-budget))
  (define (walk value depth)
    (budget! depth)
    (define (recur v) (walk v (add1 depth)))
    (cond
      [(or (boolean? value) (char? value) (keyword? value) (finite-real? value)) value]
      [(and (symbol? value) (symbol-interned? value)) value]
      [(string? value) (string->immutable-string value)]
      [(null? value) '()]
      [else
       (match value
         [(list 'list (? list? entries)) (map recur entries)]
         [(list 'pair a b) (cons (recur a) (recur b))]
         [(list 'vector (? list? entries)) (vector->immutable-vector (list->vector (map recur entries)))]
         [(list 'hash mode (? list? entries))
          (define pairs
            (for/list ([entry (in-list entries)])
              (match entry [(list k v) (cons (recur k) (recur v))]
                    [_ (fail "invalid prepared hash entry" entry)])))
          (define table
            (case mode [(eq) (make-immutable-hasheq pairs)] [(eqv) (make-immutable-hasheqv pairs)]
                  [(equal) (make-immutable-hash pairs)] [else (fail "unsupported prepared hash comparator" mode)]))
          (unless (= (length entries) (hash-count table)) (fail "duplicate prepared hash key" value))
          table]
         [(list 'color datum) (c:datum->color-spec (recur datum))]
         [(list 'label kind target (? string? text) (? boolean? arc?))
          (define v (recur target))
          (case kind
            [(point) (point-label v text)] [(segment) (segment-label v text)]
            [(length) (length-label v text)] [(angle) (angle-label v text #:arc? arc?)]
            [else (fail "unsupported semantic geometry label" kind)])]
         [(list 'record tag (? list? fields))
          (define codec (findf (lambda (r) (eq? tag (record-codec-tag r))) records))
          (unless (and codec (= (length fields) (record-codec-arity codec)))
            (fail "unknown geometry record tag or wrong field count" tag))
          (apply (record-codec-constructor codec) (map recur fields))]
         [_ (fail "invalid portable geometry datum" value)])]))
  (walk encoded 0))

(define (prepared-geometry-render->datum prepared)
  ;; Encoding also snapshots mutable strings/tables supplied through public
  ;; procedural APIs. Validation is repeated after decoding the immutable tree.
  (unless (prepared-geometry-render? prepared) (fail "expected prepared geometry" prepared))
  (hash 'schema schema 'racket-version (version) 'data (encode-prepared prepared)))
(define (datum->prepared-geometry-render datum)
  (unless (and (hash? datum) (eq? (hash-ref datum 'schema #f) schema)
               (equal? (hash-ref datum 'racket-version #f) (version))
               (hash-has-key? datum 'data))
    (fail "geometry preparation schema or Racket runtime differs" datum))
  (validate-preparation (decode-prepared (hash-ref datum 'data))))
(define (snapshot-geometry-render-preparation prepared)
  (datum->prepared-geometry-render (prepared-geometry-render->datum prepared)))

;; Fingerprint source semantics, not source-location/inspector identity. This is
;; inspection only: it never evaluates a construction or measures a label.
;; Source files are additionally protected by the normal project input manifest.
(define (geometry-source-fingerprint source)
  (define (action-data action)
    (list (geometry-action-kind action) (geometry-action-targets action)
          (case (geometry-action-kind action)
            [(expanded) (map step-data (geometry-action-payload action))]
            [(together) (map action-data (geometry-action-payload action))]
            [else (geometry-action-payload action)])))
  (define (step-data step)
    (list (geometry-step-narration step) (map action-data (geometry-step-actions step))
          (geometry-step-timing step)))
  (define (program-data program)
    (define timing (geometry-program-timing program))
    (list
     (geometry-program-name program)
     (for/list ([node (in-list (geometry-program-nodes program))])
       (list (geometry-node-id node) (geometry-node-type node) (geometry-node-expression node)
             (geometry-node-given? node) (geometry-node-public? node)))
     (map step-data (geometry-program-steps program))
     (map action-data (geometry-program-initial program))
     (map geometry-check-expression (geometry-program-checks program))
     (map geometry-check-expression (geometry-program-assertions program))
     (geometry-program-layout program) (geometry-program-styles program)
     (and timing (list (geometry-timing-opening-pause timing) (geometry-timing-read-delay timing)
                       (geometry-timing-action-duration timing) (geometry-timing-step-pause timing)))
     (geometry-program-reveals program) (geometry-program-results program)))
  (define data
    (cond
      [(geometry-program? source) (list 'program (program-data source))]
      [(geometry-timeline? source)
       (define realization (geometry-timeline-realization source))
       (define program (geometry-realization-program realization))
       (define env (geometry-realization-values realization))
       (list 'timeline (program-data program) (geometry-realization-view realization)
             (for/list ([node (in-list (geometry-program-nodes program))]
                        #:when (memq (geometry-node-type node) '(Point Line Segment Ray Circle Marker Label)))
               (list (geometry-node-id node) (hash-ref env (geometry-node-id node))))
             (geometry-theme-rules (geometry-timeline-theme source))
             (for/list ([geometry-event* (in-list (geometry-timeline-events source))])
               (list (geometry-event-start geometry-event*) (geometry-event-end geometry-event*)
                     (map action-data (geometry-event-actions geometry-event*))
                     (geometry-event-before geometry-event*) (geometry-event-after geometry-event*)))
             (geometry-timeline-initial source) (geometry-timeline-final source)
             (geometry-timeline-cues source) (geometry-timeline-duration source)
             (for/list ([span (in-list (geometry-timeline-steps source))])
               (list (geometry-step-span-id span) (geometry-step-span-path span)
                     (geometry-step-span-start span) (geometry-step-span-action-start span)
                     (geometry-step-span-action-end span) (geometry-step-span-end span))))]
      [else (fail "expected a geometry program or timeline as source" source)]))
  (sha1 (open-input-string (format "~s" (encode-prepared data)))))
