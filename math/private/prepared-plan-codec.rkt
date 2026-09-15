#lang racket/base

;;;
;;; Portable Prepared Mathematical Plans
;;;
;; Encodes parent-owned formula layout decisions as bounded data and rebinds them
;; to worker-local mathematical states without typesetting or layout measurement.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/list remove-duplicates)
         file/sha1
         "context.rkt"
         "datum.rkt"
         "derivation.rkt"
         "format.rkt"
         "model.rkt"
         "prepared-plan-model.rkt"
         "presentation.rkt"
         "typeset-model.rkt"
         "validation.rkt")

;; Exports
(provide math-preparation-payload-schema
         math-state-layout-key
         prepared-math-plan->portable-payload
         portable-payload->prepared-math-plan
         portable-payload-artifact-paths)


;;;
;;; Stable Identities
;;;

; math-preparation-payload-schema : symbol?
;;   Names the versioned portable prepared-plan payload grammar.
(define math-preparation-payload-schema 'animate-math-prepared-plan-v1)

; math-context->datum : math-context? -> immutable-hash?
;;   Canonicalizes the semantic state context without relying on hash iteration.
(define (math-context->datum context)
  (hasheq 'real (math-context-real context)
          'assumptions (math-context-assumptions context)
          'restrictions (math-context-restrictions context)
          'definitions
          (vector->immutable-vector
           (list->vector
            (for/list ([name (in-list (sort (hash-keys (math-context-definitions context))
                                        symbol<?))])
              (cons name (hash-ref (math-context-definitions context) name)))))))

; math-state-layout-key : math? -> immutable-hash?
;;   Gives a deterministic semantic state identity independent of process object identity.
(define (math-state-layout-key state)
  (unless (math? state)
    (raise-argument-error 'math-state-layout-key "math?" state))
  (hasheq 'schema 'animate-math-state-layout-key-v1
          'id (math-id state)
          ;; Revisions intentionally retain their complete rewrite ancestry.  A
          ;; digest preserves that identity without letting a long derivation
          ;; exceed the generic bounded source-transfer nesting contract.
          'fingerprint
          (sha1
           (open-input-string
            (format "~s"
                    (list (math-revision state)
                          (math-datum state)
                          (math-context->datum (math-context-of state))))))))

; presentation-style->datum : presentation-style? -> immutable-hash?
;;   Captures every style decision consumed by native scene compilation.
(define (presentation-style->datum style)
  (hasheq 'anchor (presentation-style-anchor style)
          'history (presentation-style-history style)
          'start-group (presentation-style-start-group style)
          'new-parts (presentation-style-new-parts style)
          'removed-parts (presentation-style-removed-parts style)
          'reflow (presentation-style-reflow style)
          'multiplication (presentation-style-multiplication style)
          'pause-between-groups (presentation-style-pause-between-groups style)
          'duration (presentation-style-duration style)
          'font-size (presentation-style-font-size style)
          'row-gap (presentation-style-row-gap style)
          'max-visible-rows (presentation-style-max-visible-rows style)))

; scheduled-phase->datum : scheduled-phase? -> immutable-hash?
;;   Captures the frozen schedule and its explanation-state identity as data.
(define (scheduled-phase->datum entry)
  (define phase (scheduled-phase-phase entry))
  (hasheq 'segment (scheduled-phase-segment entry)
          'step (scheduled-phase-step entry)
          'kind (scheduled-phase-kind entry)
          'start (scheduled-phase-start entry)
          'duration (scheduled-phase-duration entry)
          'group (scheduled-phase-group entry)
          'annotation
          (and phase
               (presentation-phase-annotation phase)
               (let ([annotation (presentation-phase-annotation phase)])
                 (hasheq 'state-key (math-state-layout-key (car annotation))
                         'caption (cadr annotation))))))

; presentation-plan->datum : presentation-plan? -> immutable-hash?
;;   Captures plan/case/schedule decisions that a worker must reproduce exactly.
(define (presentation-plan->datum plan)
  (define segments
    (for/list ([segment (in-list (presentation-plan-segments plan))])
      (hasheq 'path (plan-segment-path segment)
              'shared? (plan-segment-shared? segment)
              'groups (plan-segment-groups segment)
              'states
              (vector->immutable-vector
               (list->vector
                (map math-state-layout-key
                     (derivation-states
                      (plan-segment-derivation segment))))))))
  (hasheq 'schema 'animate-math-presentation-plan-v1
          'style (presentation-style->datum (presentation-plan-style plan))
          'segments
          (vector->immutable-vector (list->vector segments))
          'schedule
          (vector->immutable-vector
           (list->vector (map scheduled-phase->datum (plan-schedule plan))))
          'duration (plan-duration plan)))


;;;
;;; Parent Encoding
;;;

; prepared-token->datum : prepared-token? immutable-hash? -> immutable-hash?
;;   Snapshots one measured token and substitutes its verified staged SVG path.
(define (prepared-token->datum token asset-paths)
  (define staged-asset (hash-ref asset-paths (prepared-token-asset token) #f))
  (unless staged-asset
    (raise-arguments-error
     'prepared-math-plan->portable-payload
     "a staged preparation artifact for every token"
     "asset" (prepared-token-asset token)))
  (hasheq 'path (prepared-token-path token)
          'role (prepared-token-role token)
          'text (prepared-token-text token)
          'asset staged-asset
          'x (prepared-token-x token)
          'y (prepared-token-y token)
          'width (prepared-token-width token)
          'height (prepared-token-height token)
          'id (prepared-token-id token)))

; prepared-layout->datum : prepared-layout? immutable-hash? -> immutable-hash?
;;   Encodes one layout in deterministic token order with its semantic source key.
(define (prepared-layout->datum layout asset-paths)
  (hasheq 'state-key (math-state-layout-key (prepared-layout-state layout))
          'source-text (math-source-text (prepared-layout-source layout))
          'diagnostics (vector->immutable-vector
                        (list->vector (prepared-layout-diagnostics layout)))
          'tokens
          (vector->immutable-vector
           (list->vector
            (map (lambda (token) (prepared-token->datum token asset-paths))
                 (prepared-layout-tokens layout))))))

; prepared-math-plan->portable-payload : prepared-math-plan? immutable-hash?
;                                           immutable-hash? -> immutable-hash?
;;   Produces the versioned data-only preparation payload used by parent and workers.
(define (prepared-math-plan->portable-payload prepared options asset-paths)
  (unless (prepared-math-plan? prepared)
    (raise-argument-error
     'prepared-math-plan->portable-payload "prepared-math-plan?" prepared))
  (unless (and (immutable? options) (hash? options))
    (raise-argument-error
     'prepared-math-plan->portable-payload "immutable hash? as options" options))
  (unless (and (immutable? asset-paths) (hash? asset-paths))
    (raise-argument-error
     'prepared-math-plan->portable-payload "immutable asset-path hash?" asset-paths))
  (define plan (prepared-math-plan-plan prepared))
  (define states (math-preparation-states plan))
  (hasheq 'schema math-preparation-payload-schema
          'options options
          'plan (presentation-plan->datum plan)
          'foreground (prepared-math-plan-foreground prepared)
          'background (prepared-math-plan-background prepared)
          'row-gap (prepared-math-plan-row-gap prepared)
          'max-rows (prepared-math-plan-max-rows prepared)
          'diagnostics (vector->immutable-vector
                        (list->vector (prepared-math-plan-diagnostics prepared)))
          'artifacts
          (vector->immutable-vector
           (list->vector
            (sort (remove-duplicates (hash-values asset-paths)) string<?)))
          'layouts
          (vector->immutable-vector
           (list->vector
            (for/list ([state (in-list states)])
              (prepared-layout->datum
               (hash-ref (prepared-math-plan-layouts prepared) state)
               asset-paths))))))


;;;
;;; Worker Rebinding
;;;

; vector-list : symbol? any/c -> list?
;;   Converts a portable immutable vector while rejecting malformed list encodings.
(define (vector-list who value)
  (unless (and (immutable? value) (vector? value))
    (raise-argument-error who "immutable vector?" value))
  (vector->list value))

; payload-hash : symbol? any/c -> immutable-hash?
;;   Validates one payload record before any mathematical layout is reconstructed.
(define (payload-hash who value)
  (unless (and (immutable? value) (hash? value))
    (raise-argument-error who "immutable hash?" value))
  value)

; portable-payload-artifact-paths : immutable-hash? -> (listof string?)
;;   Returns the declared verified SVG paths in a portable preparation payload.
(define (portable-payload-artifact-paths payload)
  (define value (payload-hash 'portable-payload-artifact-paths payload))
  (unless (eq? (hash-ref value 'schema #f) math-preparation-payload-schema)
    (raise-arguments-error
     'portable-payload-artifact-paths "the current math preparation codec schema"
     "schema" (hash-ref value 'schema #f)))
  (define paths (vector-list 'portable-payload-artifact-paths
                             (hash-ref value 'artifacts #f)))
  (unless (andmap string? paths)
    (raise-arguments-error
     'portable-payload-artifact-paths "a vector of SVG artifact paths" "artifacts" paths))
  (unless (= (length paths) (length (remove-duplicates paths)))
    (raise-arguments-error
     'portable-payload-artifact-paths "unique SVG artifact paths" "artifacts" paths))
  paths)

; expected-token-span : math-source? prepared-token? -> math-source-span?
;;   Resolves one token's exact worker-local semantic source ownership.
(define (expected-token-span source token)
  (define source-role
    (if (eq? (prepared-token-role token) 'structure)
        'expression
        (prepared-token-role token)))
  (define matches
    (filter
     (lambda (span)
       (and (equal? (math-source-span-path span) (prepared-token-path token))
            (eq? (math-source-span-role span) source-role)
            (string=? (substring (math-source-text source)
                                  (math-source-span-start span)
                                  (math-source-span-end span))
                      (prepared-token-text token))))
     (math-source-spans source)))
  (unless (= (length matches) 1)
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "one matching worker-local semantic token span"
     "token" token
     "matches" matches))
  (car matches))

; token-datum->prepared-token : immutable-hash? math-source? math? list? -> prepared-token?
;;   Validates one portable token against its worker-local state and declared SVG set.
(define (token-datum->prepared-token entry source state artifacts)
  (define value (payload-hash 'portable-payload->prepared-math-plan entry))
  (define token
    (prepared-token (hash-ref value 'path #f)
                    (hash-ref value 'role #f)
                    (hash-ref value 'text #f)
                    (hash-ref value 'asset #f)
                    (hash-ref value 'x #f)
                    (hash-ref value 'y #f)
                    (hash-ref value 'width #f)
                    (hash-ref value 'height #f)
                    (hash-ref value 'id #f)))
  (unless (member (prepared-token-asset token) artifacts)
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "a token SVG declared as a verified preparation artifact"
     "asset" (prepared-token-asset token)))
  (math-occurrence-at state (prepared-token-path token))
  (expected-token-span source token)
  token)

; layout-datum->prepared-layout : immutable-hash? math? symbol? list? -> prepared-layout?
;;   Rebinds one layout to the worker's corresponding immutable mathematical state.
(define (layout-datum->prepared-layout entry state multiplication artifacts)
  (define value (payload-hash 'portable-payload->prepared-math-plan entry))
  (unless (equal? (hash-ref value 'state-key #f) (math-state-layout-key state))
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "a layout attached to its matching worker-local mathematical state"
     "layout-key" (hash-ref value 'state-key #f)
     "worker-state-key" (math-state-layout-key state)))
  (define source (format-math-source state #:multiplication multiplication))
  (unless (equal? (hash-ref value 'source-text #f) (math-source-text source))
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "layout source matching the worker-local mathematical notation"
     "layout-source" (hash-ref value 'source-text #f)
     "worker-source" (math-source-text source)))
  (define tokens
    (for/list ([token (in-list (vector-list 'portable-payload->prepared-math-plan
                                             (hash-ref value 'tokens #f)))])
      (token-datum->prepared-token token source state artifacts)))
  (prepared-layout
   state
   tokens
   source
   (for/list ([diagnostic
               (in-list (vector-list 'portable-payload->prepared-math-plan
                                     (hash-ref value 'diagnostics #f)))])
     (unless (string? diagnostic)
       (raise-argument-error
        'portable-payload->prepared-math-plan "string? layout diagnostic" diagnostic))
     diagnostic)))

; portable-payload->prepared-math-plan : immutable-hash? presentation-plan? any/c
;                                         immutable-hash? -> prepared-math-plan?
;;   Validates and rebinds parent preparation data without calling the typesetter.
(define (portable-payload->prepared-math-plan payload plan camera expected-options)
  (define value (payload-hash 'portable-payload->prepared-math-plan payload))
  (unless (eq? (hash-ref value 'schema #f) math-preparation-payload-schema)
    (raise-arguments-error
     'portable-payload->prepared-math-plan "the current math preparation codec schema"
     "schema" (hash-ref value 'schema #f)))
  (unless (presentation-plan? plan)
    (raise-argument-error
     'portable-payload->prepared-math-plan "presentation-plan?" plan))
  (unless (equal? (hash-ref value 'options #f) expected-options)
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "preparation options matching the requested lesson/case/theme/camera"
     "payload-options" (hash-ref value 'options #f)
     "expected-options" expected-options))
  (unless (equal? (hash-ref value 'plan #f) (presentation-plan->datum plan))
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "preparation data for the reconstructed lesson and selected case"
     "payload-plan" (hash-ref value 'plan #f)))
  (define artifacts (portable-payload-artifact-paths value))
  (define states (math-preparation-states plan))
  (define by-key (make-hash))
  (for ([state (in-list states)])
    (define key (math-state-layout-key state))
    (when (hash-has-key? by-key key)
      (raise-arguments-error
       'portable-payload->prepared-math-plan
       "unique stable mathematical layout keys"
       "key" key))
    (hash-set! by-key key state))
  (define entries
    (vector-list 'portable-payload->prepared-math-plan (hash-ref value 'layouts #f)))
  (unless (= (length entries) (hash-count by-key))
    (raise-arguments-error
     'portable-payload->prepared-math-plan
     "exactly one prepared layout for every worker-local state"
     "layout-count" (length entries)
     "state-count" (hash-count by-key)))
  (define seen (make-hash))
  (define multiplication
    (presentation-style-multiplication (presentation-plan-style plan)))
  (define layouts
    (for/hash ([entry (in-list entries)])
      (define record (payload-hash 'portable-payload->prepared-math-plan entry))
      (define key (hash-ref record 'state-key #f))
      (when (hash-has-key? seen key)
        (raise-arguments-error
         'portable-payload->prepared-math-plan "unique prepared state keys" "key" key))
      (hash-set! seen key #t)
      (define state (hash-ref by-key key #f))
      (unless state
        (raise-arguments-error
         'portable-payload->prepared-math-plan "a layout key in the worker-local plan"
         "key" key))
      (values state (layout-datum->prepared-layout record state multiplication artifacts))))
  (unless (= (hash-count layouts) (hash-count by-key))
    (raise-arguments-error
     'portable-payload->prepared-math-plan "complete worker-local layout coverage"
     "layouts" (hash-count layouts)
     "states" (hash-count by-key)))
  (define foreground (hash-ref value 'foreground #f))
  (define background (hash-ref value 'background #f))
  (unless (and (string? foreground) (string? background))
    (raise-arguments-error
     'portable-payload->prepared-math-plan "string foreground/background values"
     "foreground" foreground
     "background" background))
  (define row-gap (hash-ref value 'row-gap #f))
  (check-positive-real 'portable-payload->prepared-math-plan row-gap)
  (define max-rows (hash-ref value 'max-rows #f))
  (unless (and (exact-integer? max-rows) (>= max-rows 2))
    (raise-argument-error
     'portable-payload->prepared-math-plan
     "exact integer visible-row bound >= 2"
     max-rows))
  (prepared-math-plan
   plan
   layouts
   (plan-schedule plan)
   camera
   foreground
   background
   row-gap
   max-rows
   (for/list ([diagnostic
               (in-list (vector-list 'portable-payload->prepared-math-plan
                                     (hash-ref value 'diagnostics #f)))])
     (unless (string? diagnostic)
       (raise-argument-error
        'portable-payload->prepared-math-plan "string? preparation diagnostic" diagnostic))
     diagnostic)))
