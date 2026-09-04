#lang racket/base

;;;
;;; Immutable Source-Block Scene Programs
;;;

;; A block is an explicitly named source/evaluation unit, while an authored
;; section remains output metadata.  Compilation retains complete immutable
;; prefix scenes; no mutable mobjects or copied renderer objects are involved.

(require racket/list
         racket/string
         "geometry.rkt"
         "scene.rkt")

(provide (struct-out source-location)
         (struct-out scene-block-spec)
         (struct-out scene-program)
         (struct-out scene-block-run)
         (struct-out compiled-scene-program)
         make-scene-block
         make-scene-program
         compile-scene-program
         compile-scene-program/incremental
         compiled-program-block
         compiled-program-block-input-scene
         compiled-program-block-output-scene
         compiled-program-block-start
         compiled-program-block-end
         compiled-program-prefix-scene
         scene-block-run-duration)


;;;
;;; Immutable Representation
;;;

(struct source-location (source line column position span)
  #:transparent)

(struct scene-block-spec (id builder source-location source-fingerprint assets version)
  #:transparent)

(struct scene-program (id initial-builder blocks)
  #:transparent)

(struct scene-block-run (id input-scene output-scene start-time end-time
                            reused? source-location diagnostics build-milliseconds)
  #:transparent)

(struct compiled-scene-program (program scene block-runs generation)
  #:transparent)


;;;
;;; Public Construction
;;;

(define (make-scene-block id builder
                          #:source-location [location #f]
                          #:source-fingerprint [fingerprint #f]
                          #:assets [assets '()]
                          #:version [version #f])
  (check-symbol 'make-scene-block id)
  (unless (procedure-arity-includes? builder 1)
    (raise-argument-error 'make-scene-block "procedure accepting one scene argument" builder))
  (unless (or (not location) (source-location? location))
    (raise-argument-error 'make-scene-block "(or/c #f source-location?)" location))
  (unless (or (not fingerprint) (bytes? fingerprint) (string? fingerprint))
    (raise-argument-error 'make-scene-block "(or/c #f bytes? string?)" fingerprint))
  (unless (and (list? assets) (andmap path-string? assets))
    (raise-argument-error 'make-scene-block "(listof path-string?)" assets))
  (scene-block-spec id builder location fingerprint (map immutable-copy-path assets) version))

(define (make-scene-program id initial-builder blocks)
  (check-symbol 'make-scene-program id)
  (unless (procedure-arity-includes? initial-builder 0)
    (raise-argument-error 'make-scene-program "procedure accepting zero arguments" initial-builder))
  (unless (and (list? blocks) (andmap scene-block-spec? blocks))
    (raise-argument-error 'make-scene-program "(listof scene-block-spec?)" blocks))
  (check-unique-block-ids 'make-scene-program blocks)
  (scene-program id initial-builder blocks))


;;;
;;; Compilation and Prefix Reuse
;;;

;; A normal compile evaluates every block from a fresh initial scene.  The
;; incremental form may reuse only the exact retained prefix before
;; `first-changed-index`; callers select that index conservatively from source
;; fingerprints and declared dependencies.
(define (compile-scene-program program #:generation [generation 0])
  (compile-scene-program/incremental program #f 0 #:generation generation))

(define (compile-scene-program/incremental program previous first-changed-index
                                           #:generation [generation 0])
  (unless (scene-program? program)
    (raise-argument-error 'compile-scene-program/incremental "scene-program?" program))
  (unless (or (not previous) (compiled-scene-program? previous))
    (raise-argument-error
     'compile-scene-program/incremental
     "(or/c #f compiled-scene-program?)"
     previous))
  (unless (exact-nonnegative-integer? first-changed-index)
    (raise-argument-error
     'compile-scene-program/incremental
     "exact-nonnegative-integer?"
     first-changed-index))
  (unless (exact-nonnegative-integer? generation)
    (raise-argument-error
     'compile-scene-program/incremental
     "exact-nonnegative-integer?"
     generation))
  (define blocks (scene-program-blocks program))
  (when (> first-changed-index (length blocks))
    (raise-arguments-error
     'compile-scene-program/incremental
     "first changed index is inside the program"
     "first-changed-index" first-changed-index
     "block-count" (length blocks)))
  (define reuse-count
    (safe-reuse-count program previous first-changed-index))
  (define-values (initial-scene prefix-runs)
    (if (positive? reuse-count)
        (let ([prior-runs (compiled-scene-program-block-runs previous)])
          (values (scene-block-run-output-scene (list-ref prior-runs (sub1 reuse-count)))
                  (for/list ([run (in-list (take prior-runs reuse-count))])
                    (struct-copy scene-block-run run [reused? #t]))))
        (values (run-initial-builder program) '())))
  (define all-runs
    (let loop ([remaining (drop blocks reuse-count)]
               [input initial-scene]
               [runs prefix-runs])
      (cond
        [(null? remaining) runs]
        [else
         (define next-run (run-scene-block (car remaining) input))
         (loop (cdr remaining)
               (scene-block-run-output-scene next-run)
               (append runs (list next-run)))])))
  (define final-scene
    (if (null? all-runs)
        initial-scene
        (scene-block-run-output-scene (last all-runs))))
  (compiled-scene-program program final-scene all-runs generation))

(define (safe-reuse-count program previous first-changed-index)
  (cond
    [(not previous) 0]
    [(not (eq? (scene-program-id program)
               (scene-program-id (compiled-scene-program-program previous))))
     0]
    [else
     (define old-blocks
       (scene-program-blocks (compiled-scene-program-program previous)))
     (define new-blocks (scene-program-blocks program))
     (define candidate (min first-changed-index (length old-blocks) (length new-blocks)))
     ;; Reuse requires stable IDs and identical declared metadata.  We never
     ;; compare arbitrary builder procedures, so a caller must choose zero when
     ;; ambient source changed or a block body cannot be verified unchanged.
     (let loop ([index 0])
       (cond
         [(= index candidate) candidate]
         [(same-block-declaration? (list-ref old-blocks index)
                                   (list-ref new-blocks index))
          (loop (add1 index))]
         [else index]))]))

(define (same-block-declaration? first second)
  (and (eq? (scene-block-spec-id first) (scene-block-spec-id second))
       (equal? (scene-block-spec-source-fingerprint first)
               (scene-block-spec-source-fingerprint second))
       (equal? (scene-block-spec-assets first) (scene-block-spec-assets second))
       (equal? (scene-block-spec-version first) (scene-block-spec-version second))
       ;; Location equality is important when an edit moved a source block but
       ;; left nearby bytes coincidentally unchanged.
       (equal? (scene-block-spec-source-location first)
               (scene-block-spec-source-location second))))

(define (run-initial-builder program)
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (raise-program-error (scene-program-id program) #f #f error))])
    (define initial ((scene-program-initial-builder program)))
    (unless (scene? initial)
      (error 'compile-scene-program "initial builder returned a non-scene value: ~e"
             initial))
    initial))

(define (run-scene-block block input)
  (define started (current-inexact-monotonic-milliseconds))
  (define output
    (with-handlers
        ([exn:fail?
          (lambda (error)
            (raise-program-error #f (scene-block-spec-id block)
                                 (scene-block-spec-source-location block) error))])
      (define candidate ((scene-block-spec-builder block) input))
      (unless (scene? candidate)
        (error 'compile-scene-program "scene block returned a non-scene value: ~e"
               candidate))
      (when (< (scene-duration candidate) (scene-duration input))
        (error 'compile-scene-program
               "scene block shortened its timeline (from ~e to ~e)"
               (scene-duration input)
               (scene-duration candidate)))
      candidate))
  (scene-block-run (scene-block-spec-id block)
                   input output
                   (scene-duration input)
                   (scene-duration output)
                   #f
                   (scene-block-spec-source-location block)
                   '()
                   (- (current-inexact-monotonic-milliseconds) started)))


;;;
;;; Inspection Queries
;;;

(define (compiled-program-block compiled id)
  (unless (compiled-scene-program? compiled)
    (raise-argument-error 'compiled-program-block "compiled-scene-program?" compiled))
  (check-symbol 'compiled-program-block id)
  (or (findf (lambda (run) (eq? (scene-block-run-id run) id))
             (compiled-scene-program-block-runs compiled))
      (raise-arguments-error 'compiled-program-block "known scene block ID" "id" id)))

(define (compiled-program-block-input-scene compiled id)
  (scene-block-run-input-scene (compiled-program-block compiled id)))

(define (compiled-program-block-output-scene compiled id)
  (scene-block-run-output-scene (compiled-program-block compiled id)))

(define (compiled-program-block-start compiled id)
  (scene-block-run-start-time (compiled-program-block compiled id)))

(define (compiled-program-block-end compiled id)
  (scene-block-run-end-time (compiled-program-block compiled id)))

(define (compiled-program-prefix-scene compiled id)
  (compiled-program-block-output-scene compiled id))

(define (scene-block-run-duration run)
  (unless (scene-block-run? run)
    (raise-argument-error 'scene-block-run-duration "scene-block-run?" run))
  (- (scene-block-run-end-time run) (scene-block-run-start-time run)))

;;;
;;; Validation and Diagnostics
;;;

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-unique-block-ids who blocks)
  (define duplicate
    (check-duplicates (map scene-block-spec-id blocks)))
  (when duplicate
    (raise-arguments-error who "distinct scene block IDs" "duplicate-id" duplicate)))

(define (immutable-copy-path path)
  (cond
    [(path? path) (string->path (path->string path))]
    [else (string->immutable-string path)]))

(define (raise-program-error program-id block-id location error)
  (define details
    (append
     (if program-id (list (format "program ~a" program-id)) '())
     (if block-id (list (format "block ~a" block-id)) '())
     (if location
         (list
          (format "~a:~a:~a"
                  (or (source-location-source location) "<unknown>")
                  (or (source-location-line location) 0)
                  (or (source-location-column location) 0)))
         '())))
  (raise
   (exn:fail
    (format "scene-program compilation failed~a: ~a"
            (if (null? details) "" (format " (~a)" (string-join details ", ")))
            (exn-message error))
    (exn-continuation-marks error))))
