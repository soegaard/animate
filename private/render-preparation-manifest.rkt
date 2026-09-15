#lang racket/base

;;;
;;; Render Preparation Manifest
;;;

;; Builds and verifies the bounded, data-only handoff between one parent-side
;; source preparer and independently reconstructed worker builders.  This is
;; an effectful adapter: it hashes declared local files and never belongs in
;; the semantic scene model.


;;;
;;; Imports and Exports
;;;

;; Imports
(require file/sha1
         racket/file
         racket/list
         racket/path
         racket/string
         "render-source-model.rkt")

;; Exports
(provide render-input-manifest?
         render-input-manifest-identity
         build-render-input-manifest!
         verify-render-input-manifest!
         render-preparation-manifest?
         render-preparation-manifest-identity
         render-preparation-manifest-input-manifest
         render-preparation-manifest-persistent-cache-eligible?
         make-render-preparation-manifest!
         preparation-manifest->source-preparation!)


;;;
;;; Bounded Manifest Data
;;;

; manifest-schema : symbol?
;;   Names the current preparation manifest grammar.
(define manifest-schema 'animate-source-preparation-manifest-v1)

; input-manifest-schema : symbol?
;;   Names the current local-input manifest grammar.
(define input-manifest-schema 'animate-render-input-manifest-v1)

; maximum-manifest-files : exact-positive-integer?
;;   Bounds tracked source, dependency, asset, and artifact paths per session.
(define maximum-manifest-files 2048)

; render-input-manifest? : any/c -> boolean?
;;   Recognizes the bounded, deterministic local-file identity grammar.
(define (render-input-manifest? value)
  (and (immutable? value)
       (hash? value)
       (eq? (hash-ref value 'schema #f) input-manifest-schema)
       (bounded-sha1? (hash-ref value 'identity #f))
       (list? (hash-ref value 'entries #f))
       (andmap input-entry? (hash-ref value 'entries #f))
       (equal? (hash-ref value 'identity #f)
               (digest-datum
                (hasheq 'schema input-manifest-schema
                        'entries (hash-ref value 'entries #f)
                        'runtime (hash-ref value 'runtime #f))))))

; render-input-manifest-identity : render-input-manifest? -> string?
;;   Returns the content identity for a deterministic tracked-input snapshot.
(define (render-input-manifest-identity value)
  (unless (render-input-manifest? value)
    (raise-argument-error
     'render-input-manifest-identity "render-input-manifest?" value))
  (hash-ref value 'identity))

; build-render-input-manifest! : path-string? list? [#:dependencies list?]
;                                [#:runtime source-transfer-data?]
;                                -> render-input-manifest?
;;   Hashes a module entry, discoverable local module imports, and declared inputs.
(define (build-render-input-manifest! module-path assets
                                      #:dependencies [dependencies '()]
                                      #:runtime [runtime #hasheq()])
  (unless (path-string? module-path)
    (raise-argument-error 'build-render-input-manifest! "path-string?" module-path))
  (unless (list? assets)
    (raise-argument-error 'build-render-input-manifest! "list? as assets" assets))
  (unless (list? dependencies)
    (raise-argument-error
     'build-render-input-manifest! "list? as dependencies" dependencies))
  (unless (source-transfer-data? runtime)
    (raise-argument-error
     'build-render-input-manifest! "source-transfer-data? as runtime" runtime))
  (define entry-path (complete-existing-file 'build-render-input-manifest! module-path))
  (define module-paths (discover-local-module-files! entry-path))
  (define descriptors
    (append
     (for/list ([path (in-list module-paths)])
       (list path 'module))
     (for/list ([asset (in-list assets)])
       (list (descriptor-path 'build-render-input-manifest! asset 'asset)
             (descriptor-role asset 'visual)))
     (for/list ([dependency (in-list dependencies)])
       (list (descriptor-path 'build-render-input-manifest! dependency 'preparation-dependency)
             (descriptor-role dependency 'preparation-dependency)))))
  (define entries
    (deduplicate-input-entries!
     (for/list ([descriptor (in-list descriptors)])
       (make-input-entry! (car descriptor) (cadr descriptor)))))
  (when (> (length entries) maximum-manifest-files)
    (raise-arguments-error
     'build-render-input-manifest!
     "no more tracked local files than the manifest limit"
     "maximum-files" maximum-manifest-files
     "actual-files" (length entries)))
  (define immutable-runtime
    (source-transfer-data-snapshot 'build-render-input-manifest! runtime))
  (define identity
    (digest-datum
     (hasheq 'schema input-manifest-schema
             'entries entries
             'runtime immutable-runtime)))
  (hasheq 'schema input-manifest-schema
          'identity identity
          'entries entries
          'runtime immutable-runtime))

; verify-render-input-manifest! : render-input-manifest? -> void?
;;   Rejects changed, missing, or size-altered tracked local inputs before publication.
(define (verify-render-input-manifest! manifest)
  (unless (render-input-manifest? manifest)
    (raise-argument-error
     'verify-render-input-manifest! "render-input-manifest?" manifest))
  (for ([entry (in-list (hash-ref manifest 'entries))])
    (define path (hash-ref entry 'path))
    (unless (file-exists? path)
      (raise-arguments-error
       'verify-render-input-manifest!
       "every tracked input to remain an existing file"
       "changed-input" path
       "reason" 'missing))
    (define actual-size (file-size path))
    (define actual-digest (file-digest! path))
    (unless (and (= actual-size (hash-ref entry 'byte-count))
                 (equal? actual-digest (hash-ref entry 'sha1)))
      (raise-arguments-error
       'verify-render-input-manifest!
       "every tracked input to retain its prepared content identity"
       "changed-input" path
       "expected-byte-count" (hash-ref entry 'byte-count)
       "actual-byte-count" actual-size
       "expected-sha1" (hash-ref entry 'sha1)
       "actual-sha1" actual-digest)))
  (void))

; render-preparation-manifest? : any/c -> boolean?
;;   Recognizes one bounded parent-to-worker preparation descriptor.
(define (render-preparation-manifest? value)
  (and (immutable? value)
       (hash? value)
       (eq? (hash-ref value 'schema #f) manifest-schema)
       (bounded-sha1? (hash-ref value 'identity #f))
       (bounded-sha1? (hash-ref value 'payload-identity #f))
       (string? (hash-ref value 'base-fingerprint #f))
       (source-transfer-data? (hash-ref value 'payload #f))
       (list? (hash-ref value 'artifacts #f))
       (andmap artifact-entry? (hash-ref value 'artifacts #f))
       (list? (hash-ref value 'dependencies #f))
       (andmap input-entry? (hash-ref value 'dependencies #f))
       (or (not (hash-ref value 'frame-reuse #f))
           (source-transfer-data? (hash-ref value 'frame-reuse #f)))
       (render-input-manifest? (hash-ref value 'input-manifest #f))
       (source-transfer-data? (hash-ref value 'tool-identities #f))
       (equal? (hash-ref value 'payload-identity)
               (digest-datum (hash-ref value 'payload)))
       (equal? (hash-ref value 'identity)
               (manifest-identity value))))

; render-preparation-manifest-identity : render-preparation-manifest? -> string?
;;   Returns the completed preparation identity used by source/build and frame keys.
(define (render-preparation-manifest-identity value)
  (unless (render-preparation-manifest? value)
    (raise-argument-error
     'render-preparation-manifest-identity
     "render-preparation-manifest?" value))
  (hash-ref value 'identity))

; render-preparation-manifest-input-manifest : render-preparation-manifest?
;                                               -> render-input-manifest?
;;   Returns the verified local-input snapshot carried by one preparation handoff.
(define (render-preparation-manifest-input-manifest value)
  (unless (render-preparation-manifest? value)
    (raise-argument-error
     'render-preparation-manifest-input-manifest
     "render-preparation-manifest?" value))
  (hash-ref value 'input-manifest))

; render-preparation-manifest-persistent-cache-eligible? : render-preparation-manifest?
;                                                           source-preparation?
;                                                           -> boolean?
;;   Recognizes the deliberately explicit builder-cache eligibility declaration.
(define (render-preparation-manifest-persistent-cache-eligible? manifest preparation)
  (and (render-preparation-manifest? manifest)
       (source-preparation? preparation)
       (immutable? (source-preparation-diagnostics preparation))
       (eq? (hash-ref (source-preparation-diagnostics preparation)
                      'persistent-cache-eligible?
                      #f)
            #t)))

; make-render-preparation-manifest! : source-build-context? source-preparation?
;                                      [#:tool-identities source-transfer-data?]
;                                      -> render-preparation-manifest?
;;   Publishes a completed, content-addressed preparation manifest after hashing inputs.
(define (make-render-preparation-manifest! context preparation
                                           #:tool-identities [tool-identities #hasheq()])
  (unless (source-build-context? context)
    (raise-argument-error
     'make-render-preparation-manifest! "source-build-context?" context))
  (unless (source-preparation? preparation)
    (raise-argument-error
     'make-render-preparation-manifest! "source-preparation?" preparation))
  (unless (source-transfer-data? tool-identities)
    (raise-argument-error
     'make-render-preparation-manifest!
     "source-transfer-data? as tool-identities"
     tool-identities))
  (define artifacts
    (for/list ([descriptor (in-list (source-preparation-artifacts preparation))])
      (make-artifact-entry! context descriptor)))
  (define dependencies
    (for/list ([descriptor (in-list (source-preparation-dependencies preparation))])
      (make-input-entry!
       (descriptor-path 'make-render-preparation-manifest!
                        descriptor
                        'preparation-dependency)
       (descriptor-role descriptor 'preparation-dependency))))
  (define input-manifest
    (build-render-input-manifest!
     (source-build-context-module-path context)
     (source-build-context-assets context)
     #:dependencies (source-preparation-dependencies preparation)
     #:runtime tool-identities))
  (define payload
    (source-transfer-data-snapshot
     'make-render-preparation-manifest!
     (source-preparation-payload preparation)))
  (define manifest
    (hasheq 'schema manifest-schema
            'base-fingerprint (source-build-context-base-fingerprint context)
            'payload payload
            'payload-identity (digest-datum payload)
            'artifacts (sort-artifact-entries artifacts)
            'dependencies (sort-input-entries dependencies)
            'frame-reuse
            (and (source-preparation-frame-reuse preparation)
                 (source-transfer-data-snapshot
                  'make-render-preparation-manifest!
                  (source-preparation-frame-reuse preparation)))
            'input-manifest input-manifest
            'tool-identities
            (source-transfer-data-snapshot
             'make-render-preparation-manifest! tool-identities)))
  (hash-set manifest 'identity (manifest-identity manifest)))

; preparation-manifest->source-preparation! : render-preparation-manifest?
;                                             source-build-context?
;                                             -> source-preparation?
;;   Verifies a received manifest and reconstructs the documented builder payload.
(define (preparation-manifest->source-preparation! manifest context)
  (unless (render-preparation-manifest? manifest)
    (raise-argument-error
     'preparation-manifest->source-preparation!
     "render-preparation-manifest?"
     manifest))
  (unless (source-build-context? context)
    (raise-argument-error
     'preparation-manifest->source-preparation!
     "source-build-context?"
     context))
  (unless (equal? (hash-ref manifest 'base-fingerprint)
                  (source-build-context-base-fingerprint context))
    (raise-arguments-error
     'preparation-manifest->source-preparation!
     "a manifest matching the source-build context"
     "manifest-base-fingerprint" (hash-ref manifest 'base-fingerprint)
     "context-base-fingerprint"
     (source-build-context-base-fingerprint context)))
  (verify-render-input-manifest! (hash-ref manifest 'input-manifest))
  (for ([artifact (in-list (hash-ref manifest 'artifacts))])
    (verify-artifact-entry! context artifact))
  (for ([dependency (in-list (hash-ref manifest 'dependencies))])
    (verify-input-entry! 'preparation-manifest->source-preparation! dependency))
  (source-preparation
   #:payload (hash-ref manifest 'payload)
   #:artifacts (hash-ref manifest 'artifacts)
   #:dependencies (hash-ref manifest 'dependencies)
   #:frame-reuse (hash-ref manifest 'frame-reuse)
   #:diagnostics
   (hasheq 'manifest-schema manifest-schema
           'manifest-identity (hash-ref manifest 'identity)
           'tool-identities (hash-ref manifest 'tool-identities))))


;;;
;;; Local File and Identity Helpers
;;;

; complete-existing-file : symbol? path-string? -> path?
;;   Normalizes a manifest-tracked file before its content identity is read.
(define (complete-existing-file who value)
  (unless (path-string? value)
    (raise-argument-error who "path-string?" value))
  (define path (simplify-path (path->complete-path value) #t))
  (unless (file-exists? path)
    (raise-arguments-error who "an existing regular file" "path" value))
  path)

; discover-local-module-files! : path? -> immutable-list?
;;   Discovers loaded file-backed module imports without tracking Racket's own collects.
(define (discover-local-module-files! entry-path)
  (define visited (make-hash))
  (define (visit path)
    (define normalized (simplify-path (path->complete-path path) #t))
    (unless (hash-has-key? visited normalized)
      (hash-set! visited normalized #t)
      (with-handlers ([exn:fail? (lambda (_error) (void))])
        (dynamic-require normalized #f)
        (for ([phase-imports (in-list (module->imports normalized))])
          (for ([module-index (in-list (cdr phase-imports))])
            (define resolved
              (with-handlers ([exn:fail? (lambda (_error) #f)])
                (module-path-index-resolve module-index)))
            (define name
              (and resolved
                   (with-handlers ([exn:fail? (lambda (_error) #f)])
                     (resolved-module-path-name resolved))))
            (when (and (path? name) (file-exists? name))
              (visit name)))))))
  (visit entry-path)
  (sort (hash-keys visited) string<? #:key path->string))

; descriptor-path : symbol? any/c symbol? -> path?
;;   Reads the required file path from a declared project/preparation descriptor.
(define (descriptor-path who descriptor default-role)
  (cond
    [(path-string? descriptor) (complete-existing-file who descriptor)]
    [(and (hash? descriptor) (hash-has-key? descriptor 'path))
     (complete-existing-file who (hash-ref descriptor 'path))]
    [else
     (raise-arguments-error
      who
      "a path string or immutable descriptor hash containing 'path"
      "descriptor" descriptor
      "default-role" default-role)]))

; descriptor-role : any/c symbol? -> symbol?
;;   Reads one bounded semantic artifact/input role without accepting arbitrary values.
(define (descriptor-role descriptor fallback)
  (define role
    (if (and (hash? descriptor) (hash-has-key? descriptor 'role))
        (hash-ref descriptor 'role)
        fallback))
  (unless (symbol? role)
    (raise-arguments-error
     'render-preparation-manifest "a symbol descriptor role" "role" role))
  role)

; make-input-entry! : path? symbol? -> immutable-hash?
;;   Captures one file's current content identity for later verification.
(define (make-input-entry! path role)
  (define complete-path (complete-existing-file 'make-input-entry! path))
  (hasheq 'path (path->string complete-path)
          'role role
          'byte-count (file-size complete-path)
          'sha1 (file-digest! complete-path)))

; make-artifact-entry! : source-build-context? any/c -> immutable-hash?
;;   Captures a preparer-owned completed artifact only under the source asset root.
(define (make-artifact-entry! context descriptor)
  (cond
    [(or (path-string? descriptor)
         (and (hash? descriptor) (hash-has-key? descriptor 'path)))
     (define artifact-path
       (descriptor-path 'make-render-preparation-manifest! descriptor 'prepared-artifact))
     (unless (path-inside? artifact-path (source-build-context-asset-base context))
       (raise-arguments-error
        'make-render-preparation-manifest!
        "a preparation artifact inside the declared source asset root"
        "artifact-path" artifact-path
        "asset-base" (source-build-context-asset-base context)))
     (hasheq 'path (path->string artifact-path)
             'role (descriptor-role descriptor 'prepared-artifact)
             'byte-count (file-size artifact-path)
             'sha1 (file-digest! artifact-path))]
    ;; PR-A permitted descriptive artifact values before PR-E gave files an
    ;; integrity contract. Retain such values as bounded metadata, never as a
    ;; claimed file artifact or cacheable asset.
    [else
     (hasheq 'kind 'metadata
             'descriptor
             (source-transfer-data-snapshot
              'make-render-preparation-manifest! descriptor))]))

; verify-input-entry! : symbol? immutable-hash? -> void?
;;   Rechecks one expected file identity with a bounded failure diagnostic.
(define (verify-input-entry! who entry)
  (unless (input-entry? entry)
    (raise-argument-error who "input manifest entry" entry))
  (define path (hash-ref entry 'path))
  (unless (file-exists? path)
    (raise-arguments-error who "an existing tracked file" "changed-input" path))
  (unless (and (= (file-size path) (hash-ref entry 'byte-count))
               (equal? (file-digest! path) (hash-ref entry 'sha1)))
    (raise-arguments-error
     who "a tracked file with its manifest digest" "changed-input" path))
  (void))

; verify-artifact-entry! : source-build-context? immutable-hash? -> void?
;;   Rejects missing, corrupt, or source-root-escaping prepared artifacts.
(define (verify-artifact-entry! context entry)
  (unless (artifact-entry? entry)
    (raise-argument-error
     'preparation-manifest->source-preparation! "preparation artifact entry" entry))
  (unless (eq? (hash-ref entry 'kind 'file) 'metadata)
    (unless (path-inside? (hash-ref entry 'path)
                          (source-build-context-asset-base context))
      (raise-arguments-error
       'preparation-manifest->source-preparation!
       "a preparation artifact inside the declared source asset root"
       "artifact-path" (hash-ref entry 'path)))
    (verify-input-entry! 'preparation-manifest->source-preparation! entry)))

; input-entry? : any/c -> boolean?
;;   Recognizes one bounded path, role, byte-count, and digest record.
(define (input-entry? value)
  (and (immutable? value)
       (hash? value)
       (bounded-path-string? (hash-ref value 'path #f))
       (symbol? (hash-ref value 'role #f))
       (exact-nonnegative-integer? (hash-ref value 'byte-count #f))
       (bounded-sha1? (hash-ref value 'sha1 #f))))

; artifact-entry? : any/c -> boolean?
;;   Recognizes an artifact record with the same immutable content identity fields.
(define (artifact-entry? value)
  (or (input-entry? value)
      (and (immutable? value)
           (hash? value)
           (eq? (hash-ref value 'kind #f) 'metadata)
           (source-transfer-data? (hash-ref value 'descriptor #f)))))

; deduplicate-input-entries! : list? -> immutable-list?
;;   Collapses identical paths while rejecting contradictory content snapshots.
(define (deduplicate-input-entries! entries)
  (define by-path (make-hash))
  (for ([entry (in-list entries)])
    (define path (hash-ref entry 'path))
    (define previous (hash-ref by-path path #f))
    (when (and previous
               (not (and (= (hash-ref previous 'byte-count)
                            (hash-ref entry 'byte-count))
                         (equal? (hash-ref previous 'sha1)
                                 (hash-ref entry 'sha1)))))
      (raise-arguments-error
       'build-render-input-manifest!
       "one stable content identity for a repeated tracked path"
       "path" path))
    (hash-set! by-path path entry))
  (sort (hash-values by-path) string<? #:key (lambda (entry) (hash-ref entry 'path))))

; sort-input-entries : list? -> immutable-list?
;;   Canonically orders input identities without depending on hash iteration.
(define (sort-input-entries entries)
  (sort entries string<? #:key (lambda (entry) (hash-ref entry 'path))))

; sort-artifact-entries : list? -> immutable-list?
;;   Canonically orders artifact identities by role and normalized path.
(define (sort-artifact-entries entries)
  (sort entries string<?
        #:key (lambda (entry)
                (if (eq? (hash-ref entry 'kind 'file) 'metadata)
                    (format "metadata\0~s" (hash-ref entry 'descriptor))
                    (string-append (symbol->string (hash-ref entry 'role))
                                   "\0"
                                   (hash-ref entry 'path))))))

; path-inside? : path-string? path-string? -> boolean?
;;   Checks that a normalized artifact path remains under its declared source root.
(define (path-inside? candidate root)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (define complete-candidate
      (simplify-path (path->complete-path candidate) #t))
    (define complete-root
      (simplify-path (path->complete-path root) #t))
    (define relative (find-relative-path complete-root complete-candidate))
    (define relative-text (path->string relative))
    (and (relative-path? relative)
         (not (or (equal? relative-text "..")
                  (string-prefix? relative-text "../"))))))

; file-digest! : path-string? -> string?
;;   Computes a SHA-1 content digest for local integrity comparison.
(define (file-digest! path)
  (call-with-input-file path sha1))

; bounded-path-string? : any/c -> boolean?
;;   Recognizes one transferable absolute path spelling retained in a manifest.
(define (bounded-path-string? value)
  (and (string? value) (source-transfer-data? value)))

; bounded-sha1? : any/c -> boolean?
;;   Recognizes the fixed hexadecimal digest spelling used by all manifest identities.
(define (bounded-sha1? value)
  (and (string? value) (regexp-match? #px"^[0-9a-f]{40}$" value)))

; manifest-identity : immutable-hash? -> string?
;;   Computes a digest from semantic manifest fields while excluding diagnostics.
(define (manifest-identity manifest)
  (digest-datum
   (hasheq 'schema (hash-ref manifest 'schema)
           'base-fingerprint (hash-ref manifest 'base-fingerprint)
           'payload-identity (hash-ref manifest 'payload-identity)
           'artifacts (hash-ref manifest 'artifacts)
           'dependencies (hash-ref manifest 'dependencies)
           'frame-reuse (hash-ref manifest 'frame-reuse)
           'input-manifest-identity
           (render-input-manifest-identity (hash-ref manifest 'input-manifest))
           'tool-identities (hash-ref manifest 'tool-identities))))

; digest-datum : source-transfer-data? -> string?
;;   Hashes a canonical immutable datum without relying on hash iteration order.
(define (digest-datum value)
  (sha1 (open-input-string (format "~s" (canonical-datum value)))))

; canonical-datum : source-transfer-data? -> immutable-transfer-data?
;;   Sorts hashes recursively before a manifest identity is serialized for hashing.
(define (canonical-datum value)
  (cond
    [(hash? value)
     (cons 'hash
           (sort
            (for/list ([(key entry) (in-hash value)])
              (cons (canonical-datum key) (canonical-datum entry)))
            string<?
            #:key (lambda (entry) (format "~s" (car entry)))))]
    [(pair? value)
     (cons (canonical-datum (car value))
           (canonical-datum (cdr value)))]
    [(vector? value)
     (vector->immutable-vector
      (list->vector
       (for/list ([entry (in-vector value)])
         (canonical-datum entry))))]
    [else value]))
