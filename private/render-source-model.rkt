#lang racket/base

;;;
;;; Restartable Render Source Model
;;;

;; Defines immutable source declarations and bounded transfer data shared by
;; project preparation and future rendering workers.  This module is pure: it
;; neither loads author modules nor starts processes.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         (only-in racket/math nan? infinite?))

;; Exports
(provide module-builder-source-value?
         module-builder-source-value-module-path
         module-builder-source-value-binding
         module-builder-source-value-options
         module-builder-source-value-prepare
         module-builder-source-value-seed
         make-module-builder-source
         source-build-seed?
         source-transfer-data?
         source-transfer-data-snapshot
         source-build-context?
         source-build-context-module-path
         source-build-context-binding
         source-build-context-options
         source-build-context-asset-base
         source-build-context-assets
         source-build-context-width
         source-build-context-height
         source-build-context-camera-policy
         source-build-context-theme
         source-build-context-typography
         source-build-context-fps
         source-build-context-quality
         source-build-context-seed
         source-build-context-base-fingerprint
         source-build-context-preparation
         make-source-build-context
         source-build-context-with-preparation
         source-preparation
         source-preparation?
         source-preparation-payload
         source-preparation-artifacts
         source-preparation-dependencies
         source-preparation-frame-reuse
         source-preparation-diagnostics)


;;;
;;; Bounded Transfer Data
;;;

; maximum-source-transfer-depth : exact-positive-integer?
;;   Bounds nesting in data that may later cross a worker-process boundary.
(define maximum-source-transfer-depth 64)

; maximum-source-transfer-nodes : exact-positive-integer?
;;   Bounds container and scalar nodes in one transferable value.  Complete
;;   math preparation carries every validated token layout for a reviewed
;;   lesson, which legitimately exceeds 10,000 scalar nodes while remaining
;;   well within this finite process-message budget.
(define maximum-source-transfer-nodes 100000)

; maximum-source-transfer-byte-length : exact-positive-integer?
;;   Bounds one string or byte sequence in transferable source data.
(define maximum-source-transfer-byte-length (* 1024 1024))

; source-build-seed? : any/c -> boolean?
;;   Recognizes a seed accepted by Racket CS's pseudo-random generator API.
(define (source-build-seed? value)
  (and (exact-nonnegative-integer? value)
       (<= value #x7fffffff)))

; source-transfer-data? : any/c -> boolean?
;;   Recognizes bounded, acyclic data that can be copied without live aliases.
(define (source-transfer-data? value)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (source-transfer-data-snapshot 'source-transfer-data? value)
    #t))

; source-transfer-data-snapshot : symbol? any/c -> immutable-transfer-data?
;;   Copies and validates bounded source data without retaining mutable aliases.
(define (source-transfer-data-snapshot who value)
  (unless (symbol? who)
    (raise-argument-error 'source-transfer-data-snapshot "symbol?" who))
  (define active-containers (make-hasheq))
  (define node-count 0)
  (define (visit value depth)
    (set! node-count (add1 node-count))
    (when (> node-count maximum-source-transfer-nodes)
      (raise-arguments-error
       who
       "bounded transferable source data"
       "maximum-node-count" maximum-source-transfer-nodes))
    (when (> depth maximum-source-transfer-depth)
      (raise-arguments-error
       who
       "transferable source data within the nesting limit"
       "maximum-depth" maximum-source-transfer-depth))
    (cond
      [(or (null? value) (boolean? value) (symbol? value) (keyword? value)
           (char? value))
       value]
      [(finite-real? value) value]
      [(string? value)
       (check-source-transfer-byte-length who "string" (string-length value))
       (string->immutable-string (string-copy value))]
      [(bytes? value)
       (check-source-transfer-byte-length who "bytes" (bytes-length value))
       (bytes->immutable-bytes (bytes-copy value))]
      ;; A proper list is one ordered collection, not a semantic nesting level
      ;; per cons cell.  Treat its elements like vector entries so a valid
      ;; preparation manifest can name more than 64 independent artifacts
      ;; without defeating the bounded-depth contract.  The node limit still
      ;; bounds the total list size; improper pairs retain structural depth.
      [(list? value)
       (visit-container
        who active-containers value
        (lambda ()
          (for/list ([entry (in-list value)])
            (visit entry (add1 depth)))))]
      [(pair? value)
       (visit-container
        who active-containers value
        (lambda ()
          (cons (visit (car value) (add1 depth))
                (visit (cdr value) (add1 depth)))))]
      [(vector? value)
       (visit-container
        who active-containers value
        (lambda ()
          (vector->immutable-vector
           (list->vector
            (for/list ([entry (in-vector value)])
              (visit entry (add1 depth)))))))]
      [(hash? value)
       (visit-container
        who active-containers value
        (lambda ()
          (for/fold ([copy (empty-immutable-hash-like value)])
                    ([(key entry) (in-hash value)])
            (hash-set copy
                      (visit key (add1 depth))
                      (visit entry (add1 depth))))))]
      [else
       (raise-arguments-error
        who
        "bounded data made from finite reals, booleans, symbols, keywords, characters, strings, bytes, pairs, vectors, and hashes"
        "value" value)]))
  (visit value 0))

; finite-real? : any/c -> boolean?
;;   Recognizes one real number suitable for deterministic transfer data.
(define (finite-real? value)
  (and (real? value) (not (nan? value)) (not (infinite? value))))

; check-source-transfer-byte-length : symbol? string? exact-nonnegative-integer? -> void?
;;   Rejects one scalar transfer value that exceeds the bounded-data limit.
(define (check-source-transfer-byte-length who kind length)
  (when (> length maximum-source-transfer-byte-length)
    (raise-arguments-error
     who
     "a string or byte sequence within the transfer-data size limit"
     "kind" kind
     "maximum-byte-length" maximum-source-transfer-byte-length
     "actual-length" length)))

; visit-container : symbol? mutable-hasheq? any/c (-> any/c) -> any/c
;;   Evaluates one container copy while detecting cyclic source data.
(define (visit-container who active-containers value thunk)
  (when (hash-has-key? active-containers value)
    (raise-arguments-error
     who
     "acyclic transferable source data"
     "cyclic-container" value))
  (hash-set! active-containers value #t)
  (dynamic-wind
   void
   thunk
   (lambda () (hash-remove! active-containers value))))

; empty-immutable-hash-like : hash? -> immutable-hash?
;;   Preserves a source hash's equality discipline while making a fresh map.
(define (empty-immutable-hash-like value)
  (cond
    [(hash-eq? value) #hasheq()]
    [(hash-eqv? value) #hasheqv()]
    [else #hash()]))


;;;
;;; Source Declarations and Preparation
;;;

(struct module-builder-source-value (module-path binding options prepare seed)
  #:transparent)

;; module-builder-source-value represents a module-backed reconstruction recipe.
;;  - module-path  path-string?            normalized later by project planning.
;;  - binding      symbol?                 exports the fixed three-argument builder.
;;  - options      immutable-hash?         snapshots builder configuration.
;;  - prepare      (or/c symbol? #f)       optionally exports the fixed preparer.
;;  - seed         source-build-seed?      deterministic pseudo-random seed.

; make-module-builder-source : path-string? symbol? hash? (or/c symbol? #f) source-build-seed?
;                               -> module-builder-source-value?
;;   Validates and snapshots one restartable module-builder declaration.
(define (make-module-builder-source module-path binding options prepare seed)
  (unless (path-string? module-path)
    (raise-argument-error 'module-builder-source "path-string?" module-path))
  (unless (symbol? binding)
    (raise-argument-error 'module-builder-source "symbol? as builder binding" binding))
  (unless (hash? options)
    (raise-argument-error 'module-builder-source "hash? as #:options" options))
  (unless (or (not prepare) (symbol? prepare))
    (raise-argument-error 'module-builder-source "symbol? or #f as #:prepare" prepare))
  (unless (source-build-seed? seed)
    (raise-arguments-error
     'module-builder-source
     "an exact seed in [0, #x7fffffff] accepted by random-seed"
     "seed" seed))
  (module-builder-source-value
   module-path
   binding
   (source-transfer-data-snapshot 'module-builder-source options)
   prepare
   seed))

(struct source-preparation-value
  (payload artifacts dependencies frame-reuse diagnostics)
  #:transparent)

;; source-preparation-value records completed shared preparation without a scene.
;;  - payload       immutable-transfer-data?        adapter-owned versioned data.
;;  - artifacts     immutable-list?                 completed artifact manifests.
;;  - dependencies  immutable-list?                 additional declared input identities.
;;  - frame-reuse   (or/c immutable-transfer-data? #f) optional domain reuse data.
;;  - diagnostics   immutable-hash?                 bounded immutable evidence.

(define source-preparation? source-preparation-value?)
(define source-preparation-payload source-preparation-value-payload)
(define source-preparation-artifacts source-preparation-value-artifacts)
(define source-preparation-dependencies source-preparation-value-dependencies)
(define source-preparation-frame-reuse source-preparation-value-frame-reuse)
(define source-preparation-diagnostics source-preparation-value-diagnostics)

; source-preparation : [#:payload source-transfer-data?] [#:artifacts list?]
;                      [#:dependencies list?] [#:frame-reuse (or/c source-transfer-data? #f)]
;                      [#:diagnostics hash?] -> source-preparation?
;;   Creates validated immutable output from one module-builder preparer.
(define (source-preparation #:payload [payload #f]
                            #:artifacts [artifacts '()]
                            #:dependencies [dependencies '()]
                            #:frame-reuse [frame-reuse #f]
                            #:diagnostics [diagnostics #hasheq()])
  (unless (list? artifacts)
    (raise-argument-error 'source-preparation "list? as #:artifacts" artifacts))
  (unless (list? dependencies)
    (raise-argument-error 'source-preparation "list? as #:dependencies" dependencies))
  (unless (or (not frame-reuse) (source-transfer-data? frame-reuse))
    (raise-argument-error
     'source-preparation
     "source-transfer-data? or #f as #:frame-reuse"
     frame-reuse))
  (unless (hash? diagnostics)
    (raise-argument-error 'source-preparation "hash? as #:diagnostics" diagnostics))
  (source-preparation-value
   (source-transfer-data-snapshot 'source-preparation payload)
   (source-transfer-data-snapshot 'source-preparation artifacts)
   (source-transfer-data-snapshot 'source-preparation dependencies)
   (and frame-reuse
        (source-transfer-data-snapshot 'source-preparation frame-reuse))
   (source-transfer-data-snapshot 'source-preparation diagnostics)))

(struct source-build-context-value
  (module-path binding options asset-base assets width height camera-policy
               theme typography fps quality seed base-fingerprint preparation)
  #:transparent)

;; source-build-context-value snapshots construction-relevant project data.
;;  - module-path       string?                 normalized source location.
;;  - binding           symbol?                 selected module-builder export.
;;  - options           immutable-hash?         copied builder options.
;;  - asset-base        string?                 stable source-relative asset base.
;;  - assets            immutable-list?         normalized declared asset descriptors.
;;  - width/height      exact-positive-integer? target raster dimensions.
;;  - camera-policy     immutable-transfer-data? explicit or scene-camera policy.
;;  - theme/typography  immutable semantic values complete appearance snapshots.
;;  - fps/quality       semantic sampling settings.
;;  - seed              source-build-seed?      scoped builder random seed.
;;  - base-fingerprint  string?                 pre-preparation construction identity.
;;  - preparation       (or/c source-preparation? #f) completed shared resources.

(define source-build-context? source-build-context-value?)
(define source-build-context-module-path source-build-context-value-module-path)
(define source-build-context-binding source-build-context-value-binding)
(define source-build-context-options source-build-context-value-options)
(define source-build-context-asset-base source-build-context-value-asset-base)
(define source-build-context-assets source-build-context-value-assets)
(define source-build-context-width source-build-context-value-width)
(define source-build-context-height source-build-context-value-height)
(define source-build-context-camera-policy source-build-context-value-camera-policy)
(define source-build-context-theme source-build-context-value-theme)
(define source-build-context-typography source-build-context-value-typography)
(define source-build-context-fps source-build-context-value-fps)
(define source-build-context-quality source-build-context-value-quality)
(define source-build-context-seed source-build-context-value-seed)
(define source-build-context-base-fingerprint source-build-context-value-base-fingerprint)
(define source-build-context-preparation source-build-context-value-preparation)

; make-source-build-context : string? symbol? immutable-hash? string? immutable-list?
;                              exact-positive-integer? exact-positive-integer? transfer-data?
;                              any/c any/c exact-positive-integer? symbol? source-build-seed?
;                              string? (or/c source-preparation? #f) -> source-build-context?
;;   Constructs the internal immutable context supplied to preparers and builders.
(define (make-source-build-context module-path binding options asset-base assets
                                   width height camera-policy theme typography fps quality
                                   seed base-fingerprint preparation)
  (source-build-context-value
   module-path binding options asset-base assets width height camera-policy theme typography
   fps quality seed base-fingerprint preparation))

; source-build-context-with-preparation : source-build-context? source-preparation?
;                                          -> source-build-context?
;;   Returns the builder context with one completed shared-preparation snapshot.
(define (source-build-context-with-preparation context preparation)
  (unless (source-build-context? context)
    (raise-argument-error
     'source-build-context-with-preparation
     "source-build-context?"
     context))
  (unless (source-preparation? preparation)
    (raise-argument-error
     'source-build-context-with-preparation
     "source-preparation?"
     preparation))
  (struct-copy source-build-context-value context
               [preparation preparation]))
