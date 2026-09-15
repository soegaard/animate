#lang racket/base

;;;
;;; Generic Frame Reuse Plan
;;;

;; Defines the pure, domain-neutral consumer for a source preparation's
;; identical-frame witness.  Geometry and other domain adapters remain
;; responsible for producing a witness; this module only validates and
;; restricts it to the caller's requested source-frame list.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "render-source-model.rkt")

;; Exports
(provide frame-reuse-witness?
         frame-reuse-witness-base-fingerprint
         frame-reuse-witness-representatives
         make-frame-reuse-witness
         frame-reuse-witness->datum
         datum->frame-reuse-witness
         render-frame-reuse-plan?
         render-frame-reuse-plan-source-frame-indices
         render-frame-reuse-plan-representative-output-indices
         render-frame-reuse-plan-output->representative
         render-frame-reuse-plan-alias-count
         make-render-frame-reuse-plan)


;;;
;;; Data Representation
;;;

(struct frame-reuse-witness-value (base-fingerprint representatives)
  #:transparent)

;; frame-reuse-witness-value records a domain assertion about equal source
;; frames.
;;  - base-fingerprint  string?              binds the assertion to pre-preparation source inputs.
;;  - representatives   immutable-list/vector? ordered (list source-frame representative-frame) pairs.
;;                                      Pair order is significant for diagnostics only; mappings are unique.

(define frame-reuse-witness? frame-reuse-witness-value?)
(define frame-reuse-witness-base-fingerprint
  frame-reuse-witness-value-base-fingerprint)
(define frame-reuse-witness-representatives
  frame-reuse-witness-value-representatives)

(struct render-frame-reuse-plan-value
  (source-frame-indices representative-output-indices output->representative)
  #:transparent)

;; render-frame-reuse-plan-value is one fully restricted execution plan.
;;  - source-frame-indices             immutable-list?      requested source indices in local output order.
;;  - representative-output-indices    immutable-list?      increasing local slots that need rasterization.
;;  - output->representative           immutable-list?      one (cons local-slot representative-slot) for every slot.
;;                                                    Local ordering is significant and deterministic.

(define render-frame-reuse-plan? render-frame-reuse-plan-value?)
(define render-frame-reuse-plan-source-frame-indices
  render-frame-reuse-plan-value-source-frame-indices)
(define render-frame-reuse-plan-representative-output-indices
  render-frame-reuse-plan-value-representative-output-indices)
(define render-frame-reuse-plan-output->representative
  render-frame-reuse-plan-value-output->representative)


;;;
;;; Witness Construction and Planning
;;;

; make-frame-reuse-witness : string? (or/c (listof (list/c exact-nonnegative-integer?
;                                                    exact-nonnegative-integer?))
;                                            (vectorof (list/c exact-nonnegative-integer?
;                                                               exact-nonnegative-integer?)))
;                             -> frame-reuse-witness?
;;   Validates one domain-produced, source-frame-to-representative witness.
(define (make-frame-reuse-witness base-fingerprint representatives)
  (unless (and (string? base-fingerprint) (source-transfer-data? base-fingerprint))
    (raise-argument-error 'make-frame-reuse-witness "bounded string?" base-fingerprint))
  (unless (or (list? representatives) (vector? representatives))
    (raise-argument-error
     'make-frame-reuse-witness
     "a list? or vector? of source-frame representative pairs"
     representatives))
  (define entries
    (if (vector? representatives)
        (vector->list representatives)
        representatives))
  (define pairs
    (for/list ([entry (in-list entries)])
      (unless (and (list? entry)
                   (= (length entry) 2)
                   (exact-nonnegative-integer? (car entry))
                   (exact-nonnegative-integer? (cadr entry)))
        (raise-arguments-error
         'make-frame-reuse-witness
         "a list of (list source-frame-index representative-frame-index) pairs"
         "entry" entry))
      (list (car entry) (cadr entry))))
  (define source-indices (map car pairs))
  (unless (= (length source-indices) (length (remove-duplicates source-indices)))
    (raise-arguments-error
     'make-frame-reuse-witness
     "at most one representative mapping per source frame"
     "source-frame-indices" source-indices))
  (frame-reuse-witness-value
   (string->immutable-string (string-copy base-fingerprint))
   ;; A long linked list would consume one transfer-depth level per frame.
   ;; Preserve a vector so large ordinary frame grids stay bounded by pair depth,
   ;; not by their length, while retaining their canonical order.
   (source-transfer-data-snapshot 'make-frame-reuse-witness
                                  (list->vector pairs))))

; frame-reuse-witness->datum : frame-reuse-witness? -> immutable-transfer-data?
;;   Encodes one witness as the bounded preparation payload grammar.
(define (frame-reuse-witness->datum witness)
  (unless (frame-reuse-witness? witness)
    (raise-argument-error
     'frame-reuse-witness->datum "frame-reuse-witness?" witness))
  (hasheq 'schema 'animate-frame-reuse-witness-v1
          'base-fingerprint (frame-reuse-witness-base-fingerprint witness)
          'representatives (frame-reuse-witness-representatives witness)))

; datum->frame-reuse-witness : immutable-transfer-data? -> frame-reuse-witness?
;;   Decodes the only generic reuse-witness representation accepted by the executor.
(define (datum->frame-reuse-witness datum)
  (unless (and (hash? datum)
               (eq? (hash-ref datum 'schema #f) 'animate-frame-reuse-witness-v1)
               (string? (hash-ref datum 'base-fingerprint #f))
               (or (list? (hash-ref datum 'representatives #f))
                   (vector? (hash-ref datum 'representatives #f))))
    (raise-arguments-error
     'datum->frame-reuse-witness
     "an animate-frame-reuse-witness-v1 datum"
     "datum" datum))
  (make-frame-reuse-witness
   (hash-ref datum 'base-fingerprint)
   (hash-ref datum 'representatives)))

; render-frame-reuse-plan-alias-count : render-frame-reuse-plan? -> exact-nonnegative-integer?
;;   Counts requested local slots materialized from another representative slot.
(define (render-frame-reuse-plan-alias-count plan)
  (unless (render-frame-reuse-plan? plan)
    (raise-argument-error
     'render-frame-reuse-plan-alias-count "render-frame-reuse-plan?" plan))
  (for/sum ([mapping (in-list (render-frame-reuse-plan-output->representative plan))])
    (if (= (car mapping) (cdr mapping)) 0 1)))

; make-render-frame-reuse-plan : (listof exact-nonnegative-integer?) string?
;                                (or/c frame-reuse-witness? false/c)
;                                -> render-frame-reuse-plan?
;;   Restricts an optional domain witness to explicit local output slots.
(define (make-render-frame-reuse-plan source-frame-indices base-fingerprint witness)
  (unless (and (list? source-frame-indices)
               (andmap exact-nonnegative-integer? source-frame-indices))
    (raise-argument-error
     'make-render-frame-reuse-plan
     "(listof exact-nonnegative-integer?)"
     source-frame-indices))
  (unless (and (string? base-fingerprint) (source-transfer-data? base-fingerprint))
    (raise-argument-error 'make-render-frame-reuse-plan "bounded string?" base-fingerprint))
  (unless (or (not witness) (frame-reuse-witness? witness))
    (raise-argument-error
     'make-render-frame-reuse-plan
     "(or/c frame-reuse-witness? #f)"
     witness))
  (when (and witness
             (not (equal? base-fingerprint
                          (frame-reuse-witness-base-fingerprint witness))))
    (raise-arguments-error
     'make-render-frame-reuse-plan
     "a witness for this source-build base fingerprint"
     "expected-base-fingerprint" base-fingerprint
     "witness-base-fingerprint"
     (frame-reuse-witness-base-fingerprint witness)))
  (define representative-entries
    (let ([representatives (and witness
                                (frame-reuse-witness-representatives witness))])
      (cond [(not representatives) '()]
            [(vector? representatives) (vector->list representatives)]
            [else representatives])))
  (define representative-by-source
    (for/fold ([mapping #hasheq()])
              ([entry (in-list representative-entries)])
      (hash-set mapping (car entry) (cadr entry))))
  ;; A requested representative is the first requested local slot for its
  ;; source-frame identity.  This also makes repeated source indices cheap
  ;; without asking a domain witness to mention duplicate output slots.
  (define first-slot-by-source
    (for/fold ([mapping #hasheq()])
              ([source-index (in-list source-frame-indices)]
               [output-index (in-naturals)])
      (if (hash-has-key? mapping source-index)
          mapping
          (hash-set mapping source-index output-index))))
  (define (representative-source source-index)
    (let loop ([current source-index] [seen #hasheq()])
      (when (hash-has-key? seen current)
        (raise-arguments-error
         'make-render-frame-reuse-plan
         "an acyclic frame-reuse witness"
         "cycle-at-source-frame" current))
      (define next (hash-ref representative-by-source current #f))
      (if (or (not next) (= next current))
          current
          (loop next (hash-set seen current #t)))))
  (define output->representative
    (for/list ([source-index (in-list source-frame-indices)]
               [output-index (in-naturals)])
      (define representative-source-index
        (representative-source source-index))
      (cons output-index
            ;; A witness may name a source frame outside this particular range.
            ;; It cannot be rasterized here, so retain this request as its own
            ;; representative rather than reaching beyond the selected output.
            (hash-ref first-slot-by-source representative-source-index output-index))))
  (define representatives
    (for/list ([mapping (in-list output->representative)]
               #:when (= (car mapping) (cdr mapping)))
      (car mapping)))
  (render-frame-reuse-plan-value
   ;; This plan stays in the parent executor; unlike the source-preparation
   ;; witness it never crosses the process protocol. Keep ordinary immutable
   ;; lists here so a long frame grid is not rejected merely for linked-list
   ;; depth. All entries were validated/constructed above and contain numbers.
   (append source-frame-indices '())
   (append representatives '())
   (append output->representative '())))
