#lang racket/base

;;;
;;; Program-Aware Preview Operations
;;;

;; This adapter deliberately keeps the renderer controller generic. It adds
;; source-program ownership, hot reload, block navigation, and the explicit
;; manual-checkpoint branch mode without giving GUI widgets any semantic scene
;; state to mutate.

(require racket/list
         (only-in "pict-adapter.rkt" default-pict-renderers)
         "preview-controller.rkt"
         "preview-repl.rkt"
         "preview-transaction.rkt"
         "program-loader.rkt"
         "program-watcher.rkt"
         "scene-program.rkt"
         "scene.rkt")

(provide open-program-preview-controller
         attach-program-preview!
         program-preview-session?
         preview-program
         preview-program-loader
         preview-program-generation
         preview-program-blocks
         preview-program-block-ranges
         preview-current-block
         preview-jump-to-block!
         preview-restore-block-input!
         preview-rerun-block!
         preview-reload!
         preview-current-block-source-location
         preview-selection-source-location
         preview-open-current-block-source!
         preview-open-selection-source!
         preview-auto-reload-enabled?
         preview-set-auto-reload!
         preview-program-reset-to-source!
         preview-program-branch-mode)

(struct program-preview-context (loader lock auto-reload? watcher branch-mode open-source)
  #:mutable
  #:transparent)

;; A weak table makes program awareness an optional attachment to the existing
;; public preview-session value, so ordinary previews stay exactly as they are.
(define contexts (make-weak-hasheq))

(define (program-preview-session? value)
  (and (preview-session? value) (hash-has-key? contexts value)))

(define (open-program-preview-controller module-path binding
                                         #:auto-reload? [auto-reload? #f]
                                         #:fps [fps 30]
                                         #:start [start #f]
                                         #:section [section #f]
                                         #:camera [camera #f]
                                         #:renderers [renderers default-pict-renderers]
                                         #:pixel-scale [pixel-scale 1]
                                         #:supersample [supersample 1]
                                         #:cache-megabytes [cache-megabytes 128]
                                         #:prefetch [prefetch 3]
                                         #:producer [producer #f]
                                         #:byte-size [byte-size #f]
                                         #:open-source [open-source #f]
                                         #:on-event [on-event void])
  (define loader (load-scene-program module-path binding))
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (scene-program-loader-close! loader)
          (raise error))])
    (define source
      (compiled-scene-program-scene (scene-program-loader-compiled loader)))
    (define (open producer-argument byte-size-argument)
      (open-preview-controller
       source #:fps fps #:start start #:section section #:camera camera
       #:renderers renderers #:pixel-scale pixel-scale #:supersample supersample
       #:cache-megabytes cache-megabytes #:prefetch prefetch
       #:producer producer-argument #:byte-size byte-size-argument #:on-event on-event))
    ;; Supplying #f as a producer/byte-size is not valid. The small branch set
    ;; keeps the normal controller defaults intact while still supporting the
    ;; deterministic fake producers used by headless integration tests.
    (define session
      (cond
        [(and producer byte-size) (open producer byte-size)]
        [producer
         (open-preview-controller
          source #:fps fps #:start start #:section section #:camera camera
          #:renderers renderers #:pixel-scale pixel-scale #:supersample supersample
          #:cache-megabytes cache-megabytes #:prefetch prefetch
          #:producer producer #:on-event on-event)]
        [byte-size
         (open-preview-controller
          source #:fps fps #:start start #:section section #:camera camera
          #:renderers renderers #:pixel-scale pixel-scale #:supersample supersample
          #:cache-megabytes cache-megabytes #:prefetch prefetch
          #:byte-size byte-size #:on-event on-event)]
        [else
         (open-preview-controller
          source #:fps fps #:start start #:section section #:camera camera
          #:renderers renderers #:pixel-scale pixel-scale #:supersample supersample
          #:cache-megabytes cache-megabytes #:prefetch prefetch #:on-event on-event)]))
    (attach-program-preview! session loader
                             #:auto-reload? auto-reload?
                             #:open-source open-source)
    session))

(define (attach-program-preview! session loader
                                 #:auto-reload? [auto-reload? #f]
                                 #:open-source [open-source #f])
  (unless (preview-session? session)
    (raise-argument-error 'attach-program-preview! "preview-session?" session))
  (unless (scene-program-loader? loader)
    (raise-argument-error 'attach-program-preview! "scene-program-loader?" loader))
  (unless (boolean? auto-reload?)
    (raise-argument-error 'attach-program-preview! "boolean?" auto-reload?))
  (unless (or (not open-source) (procedure? open-source))
    (raise-argument-error 'attach-program-preview! "(or/c #f procedure?)" open-source))
  (when (hash-has-key? contexts session)
    (raise-arguments-error 'attach-program-preview!
                           "a preview without a program attachment"
                           "session" session))
  (define context
    (program-preview-context loader (make-semaphore 1) auto-reload? #f 'verified open-source))
  (hash-set! contexts session context)
  (attach-preview-transactions!
   session
   #:initial-scene (compiled-scene-program-scene
                    (scene-program-loader-compiled loader)))
  (preview-add-close-hook!
   session
   (lambda ()
     (with-context context
       (lambda ()
         (define watcher (program-preview-context-watcher context))
         (when watcher (program-watcher-close! watcher))
         (scene-program-loader-close! (program-preview-context-loader context))
         (hash-remove! contexts session)))))
  (when auto-reload? (start-watcher! session context))
  session)

(define (preview-program session)
  (compiled-scene-program-program
   (scene-program-loader-compiled
    (program-preview-context-loader
     (program-context 'preview-program session)))))

(define (preview-program-loader session)
  (program-preview-context-loader
   (program-context 'preview-program-loader session)))

(define (preview-program-generation session)
  (compiled-scene-program-generation
   (scene-program-loader-compiled
    (program-preview-context-loader
     (program-context 'preview-program-generation session)))))

(define (preview-program-blocks session)
  (scene-program-blocks (preview-program session)))

;; Source-block names alone are enough for the chooser, but the production
;; timeline also needs the exact compiled half-open interval for every block.
;; Exposing it here keeps both views tied to the retained compilation rather
;; than asking GUI code to reconstruct timings from the source declarations.
(define (preview-program-block-ranges session)
  (define context (program-context 'preview-program-block-ranges session))
  (with-context context
    (lambda ()
      (for/list ([run (in-list
                        (compiled-scene-program-block-runs
                         (scene-program-loader-compiled
                          (program-preview-context-loader context))))])
        (list (scene-block-run-id run)
              (scene-block-run-start-time run)
              (scene-block-run-end-time run))))))

(define (preview-program-branch-mode session)
  (program-preview-context-branch-mode
   (program-context 'preview-program-branch-mode session)))

(define (preview-current-block session)
  (define context (program-context 'preview-current-block session))
  (with-context context
    (lambda ()
      (define compiled (scene-program-loader-compiled
                        (program-preview-context-loader context)))
      (define time (preview-current-time session))
      (define selected
        (for/fold ([answer #f]) ([run (in-list (compiled-scene-program-block-runs compiled))])
          (if (and (<= (scene-block-run-start-time run) time)
                   (or (< time (scene-block-run-end-time run))
                       (and (= time (scene-block-run-end-time run))
                            (= time (scene-duration (compiled-scene-program-scene compiled))))))
              (scene-block-run-id run)
              answer)))
      selected)))

(define (preview-jump-to-block! session id)
  (define context (program-context 'preview-jump-to-block! session))
  (with-context context
    (lambda ()
      (preview-seek! session
                     (compiled-program-block-start
                      (scene-program-loader-compiled
                       (program-preview-context-loader context))
                      id)))))

;; This is intentionally an editing-base operation, not a time jump. The
;; renderer receives the retained exact input scene, while the program context
;; records that the author is now viewing a manual checkpoint branch.
(define (preview-restore-block-input! session id)
  (define context (program-context 'preview-restore-block-input! session))
  (with-context context
    (lambda ()
      (define compiled (scene-program-loader-compiled
                        (program-preview-context-loader context)))
      (define input (compiled-program-block-input-scene compiled id))
      (define result (preview-set-source! session input))
      (set-program-preview-context-branch-mode! context 'manual-checkpoint-branch)
      (preview-rebase-transactions! session input)
      result)))

;; Reloads to obtain the new source block, but deliberately invokes it against
;; the retained old input checkpoint.  This is a useful experimental branch,
;; never labelled as a verified incremental rebuild.
(define (preview-rerun-block! session id #:from-retained-input? [retained? #t])
  (unless retained?
    (raise-arguments-error 'preview-rerun-block!
                           "#:from-retained-input? #t in the first release"
                           "from-retained-input?" retained?))
  (define context (program-context 'preview-rerun-block! session))
  (with-context context
    (lambda ()
      (define old-loader (program-preview-context-loader context))
      (define old-compiled (scene-program-loader-compiled old-loader))
      (define retained-input (compiled-program-block-input-scene old-compiled id))
      (define replacement (reload-scene-program old-loader))
      (with-handlers
          ([exn:fail?
            (lambda (error)
              (scene-program-loader-close! replacement)
              (preview-report-error! session error)
              (raise error))])
        (define replacement-block
          (findf (lambda (block) (eq? (scene-block-spec-id block) id))
                 (scene-program-blocks
                  (compiled-scene-program-program
                   (scene-program-loader-compiled replacement)))))
        (unless replacement-block
          (raise-arguments-error 'preview-rerun-block!
                                 "a block present in the replacement source"
                                 "id" id))
        (define manual
          (compile-scene-program
           (make-scene-program
            'manual-checkpoint-branch
            (lambda () retained-input)
            (list replacement-block))
           #:generation (compiled-scene-program-generation
                         (scene-program-loader-compiled replacement))))
        (preview-set-source! session (compiled-scene-program-scene manual))
        (set-program-preview-context-loader! context replacement)
        (set-program-preview-context-branch-mode! context 'manual-checkpoint-branch)
        (preview-rebase-transactions! session (compiled-scene-program-scene manual))
        (preview-repls-refresh-source! session replacement)
        (scene-program-loader-close! old-loader)
        (update-watcher! context replacement)
        manual))))

(define (preview-reload! session)
  (define context (program-context 'preview-reload! session))
  (with-context context
    (lambda ()
      (define previous (program-preview-context-loader context))
      (with-handlers
          ([exn:fail?
            (lambda (error)
              (preview-report-error! session error)
              (raise error))])
        (define replacement (reload-scene-program previous))
        (with-handlers
            ([exn:fail?
              (lambda (error)
                (scene-program-loader-close! replacement)
                (preview-report-error! session error)
                (raise error))])
          ;; Controller installation retains display time and atomically bumps
          ;; the preview generation, which rejects all stale render results.
          (define status
            (preview-set-source!
             session
             (compiled-scene-program-scene
              (scene-program-loader-compiled replacement))))
          (set-program-preview-context-loader! context replacement)
          (set-program-preview-context-branch-mode! context 'verified)
          (preview-rebase-transactions!
           session
           (compiled-scene-program-scene
            (scene-program-loader-compiled replacement)))
          (preview-repls-refresh-source! session replacement)
          (scene-program-loader-close! previous)
          (update-watcher! context replacement)
          status)))))

;; A selection is a path in the sampled Visual tree.  Source blocks establish
;; the meaningful author-level provenance available without trying to infer a
;; Racket expression for every generated Visual: the selected element belongs
;; to the block covering the current display time.
(define (preview-current-block-source-location session)
  (define id (preview-current-block session))
  (define context (program-context 'preview-current-block-source-location session))
  (with-context context
    (lambda ()
      (and id
           (for/first ([block (in-list
                               (scene-program-blocks
                                (compiled-scene-program-program
                                 (scene-program-loader-compiled
                                  (program-preview-context-loader context)))))]
                       #:when (eq? id (scene-block-spec-id block)))
             (scene-block-spec-source-location block))))))

(define (preview-selection-source-location session)
  (and (preview-selection session)
       (preview-current-block-source-location session)))

(define (call-source-opener who session location opener)
  (unless location
    (raise-arguments-error who "a selected or current source block" "session" session))
  (define configured
    (or opener
        (program-preview-context-open-source
         (program-context who session))))
  ;; A headless integration can omit an opener and use the location directly;
  ;; an editor integration supplies a procedure that receives that value.
  (if configured
      (configured location)
      location))

(define (preview-open-current-block-source! session #:open [opener #f])
  (unless (or (not opener) (procedure? opener))
    (raise-argument-error 'preview-open-current-block-source!
                          "(or/c #f procedure?)" opener))
  (call-source-opener 'preview-open-current-block-source!
                      session
                      (preview-current-block-source-location session)
                      opener))

(define (preview-open-selection-source! session #:open [opener #f])
  (unless (or (not opener) (procedure? opener))
    (raise-argument-error 'preview-open-selection-source!
                          "(or/c #f procedure?)" opener))
  (call-source-opener 'preview-open-selection-source!
                      session
                      (preview-selection-source-location session)
                      opener))

(define (preview-program-reset-to-source! session)
  (define context (program-context 'preview-program-reset-to-source! session))
  (with-context context
    (lambda ()
      (set-program-preview-context-branch-mode! context 'verified)
      (define scene
        (compiled-scene-program-scene
         (scene-program-loader-compiled (program-preview-context-loader context))))
      (define result (preview-set-source! session scene))
      (preview-rebase-transactions! session scene)
      result)))

(define (preview-auto-reload-enabled? session)
  (program-preview-context-auto-reload?
   (program-context 'preview-auto-reload-enabled? session)))

(define (preview-set-auto-reload! session enabled?)
  (unless (boolean? enabled?)
    (raise-argument-error 'preview-set-auto-reload! "boolean?" enabled?))
  (define context (program-context 'preview-set-auto-reload! session))
  (with-context context
    (lambda ()
      (unless (equal? enabled? (program-preview-context-auto-reload? context))
        (set-program-preview-context-auto-reload?! context enabled?)
        (if enabled?
            (start-watcher! session context)
            (let ([watcher (program-preview-context-watcher context)])
              (when watcher (program-watcher-close! watcher))
              (set-program-preview-context-watcher! context #f))))
      enabled?)))

(define (start-watcher! session context)
  (unless (program-preview-context-watcher context)
    (set-program-preview-context-watcher!
     context
     (open-program-watcher
      (program-preview-context-loader context)
      (lambda ()
        ;; Reloading is an actor-facing operation; this watcher never touches
        ;; GUI widgets. Errors are reported into controller status by the
        ;; reload operation and are intentionally non-fatal to the watcher.
        (with-handlers ([exn:fail? (lambda (_error) (void))])
          (preview-reload! session)))))))

(define (update-watcher! context replacement)
  (define watcher (program-preview-context-watcher context))
  (when watcher
    (program-watcher-update-loader! watcher replacement)))

(define (program-context who session)
  (unless (preview-session? session)
    (raise-argument-error who "preview-session?" session))
  (or (hash-ref contexts session #f)
      (raise-arguments-error who "program-aware preview session" "session" session)))

(define (with-context context thunk)
  (call-with-semaphore (program-preview-context-lock context) thunk))
