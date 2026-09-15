#lang racket/base

;;;
;;; Restartable Render Source Loader
;;;

;; Loads module-builder exports through one fixed invocation contract.  This is
;; an effectful adapter: source declarations and construction contexts remain in
;; the pure render-source-model module.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "../authoring.rkt"
         "../main.rkt"
         "render-source-model.rkt")

;; Exports
(provide load-module-source-value!
         load-module-builder-source!
         source-value->scene)


;;;
;;; Module-builder Loading
;;;

; load-module-source-value! : path-string? symbol? -> source-value?
;;   Loads one module value source through the same validation boundary as builders.
(define (load-module-source-value! module-path binding)
  (unless (path-string? module-path)
    (raise-argument-error 'load-module-source-value! "path-string?" module-path))
  (unless (symbol? binding)
    (raise-argument-error 'load-module-source-value! "symbol?" binding))
  (define source-value
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (raise-arguments-error
                        'load-module-source-value!
                        "could not load the declared module export"
                        "module-path" module-path
                        "binding" binding
                        "detail" (exn-message error)))])
      (dynamic-require (module-path->require-path module-path) binding)))
  (unless (source-value? source-value)
    (raise-arguments-error
     'load-module-source-value!
     "the module export must be a scene?, authored-timeline?, scene-program?, or compiled-scene-program?"
     "module-path" module-path
     "binding" binding
     "source-value" source-value))
  source-value)

; load-module-builder-source! : module-builder-source-value? source-build-context?
;                               -> source-value? source-preparation? source-build-context?
;;   Loads, prepares, and constructs one restartable module-backed render source.
(define (load-module-builder-source! source context)
  (unless (module-builder-source-value? source)
    (raise-argument-error
     'load-module-builder-source!
     "module-builder-source-value?"
     source))
  (unless (source-build-context? context)
    (raise-argument-error
     'load-module-builder-source!
     "source-build-context?"
     context))
  ;; A parent may already have completed and verified a preparation manifest.
  ;; In that case workers consume exactly that immutable value and must never
  ;; invoke the optional preparer again.  The ordinary parent path has no
  ;; preparation in its input context, so it still performs the one documented
  ;; preparation invocation before its local target construction.
  (define supplied-preparation
    (source-build-context-preparation context))
  (when (and supplied-preparation
             (not (module-builder-source-value-prepare source)))
    (raise-source-loading-error
     source
     'preparer
     #f
     "a completed preparation was supplied for a builder declaration without #:prepare"
     supplied-preparation))
  (define preparation
    (or supplied-preparation
        (and (module-builder-source-value-prepare source)
             (invoke-source-preparer!
              source
              context
              (module-builder-source-value-prepare source)))))
  (define builder-context
    (if preparation
        (source-build-context-with-preparation context preparation)
        context))
  (define builder
    (load-source-procedure!
     source
     (module-builder-source-value-binding source)
     'builder
     3))
  (define source-value
    (call-source-procedure!
     source
     'builder
     (module-builder-source-value-binding source)
     builder
     (list builder-context
           (module-builder-source-value-options source)
           (and preparation (source-preparation-payload preparation)))))
  (unless (source-value? source-value)
    (raise-source-loading-error
     source
     'builder
     (module-builder-source-value-binding source)
     "the builder result must be a scene?, authored-timeline?, scene-program?, or compiled-scene-program?"
     source-value))
  (values source-value preparation builder-context))

; invoke-source-preparer! : module-builder-source-value? source-build-context? symbol?
;                            -> source-preparation?
;;   Invokes one optional preparer with the fixed two-argument contract.
(define (invoke-source-preparer! source context binding)
  (define preparer
    (load-source-procedure! source binding 'preparer 2))
  (define result
    (call-source-procedure!
     source
     'preparer
     binding
     preparer
     (list context (module-builder-source-value-options source))))
  (unless (source-preparation? result)
    (raise-source-loading-error
     source
     'preparer
     binding
     "the preparer result must be source-preparation?"
     result))
  result)

; load-source-procedure! : module-builder-source-value? symbol? symbol? exact-positive-integer?
;                           -> procedure?
;;   Retrieves and validates one fixed-arity module export before invocation.
(define (load-source-procedure! source binding phase arity)
  (define exported
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (raise-source-loading-error
                        source
                        phase
                        binding
                        "could not load the declared module export"
                        (exn-message error)))])
      (dynamic-require
       (module-path->require-path (module-builder-source-value-module-path source))
       binding)))
  (unless (procedure? exported)
    (raise-source-loading-error
     source phase binding "the declared export must be a procedure" exported))
  (unless (procedure-arity-includes? exported arity)
    (raise-source-loading-error
     source
     phase
     binding
     (format "the declared export must accept exactly the fixed ~a-argument invocation" arity)
     (procedure-arity exported)))
  exported)

; call-source-procedure! : module-builder-source-value? symbol? symbol? procedure? list?
;                           -> any/c
;;   Invokes one source function under a deterministic scoped random generator.
(define (call-source-procedure! source phase binding procedure arguments)
  (define values
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (raise-source-loading-error
                        source phase binding "the declared export raised an exception" (exn-message error)))])
      (call-with-source-random-seed
       source
       (lambda ()
         (call-with-values
          (lambda () (apply procedure arguments))
          list)))))
  (unless (= (length values) 1)
    (raise-source-loading-error
     source
     phase
     binding
     "the declared export must return exactly one value"
     values))
  (car values))

; call-with-source-random-seed : module-builder-source-value? (-> any/c) -> any/c
;;   Runs one preparation or build phase with its declared deterministic seed.
(define (call-with-source-random-seed source thunk)
  (define generator (make-pseudo-random-generator))
  (parameterize ([current-pseudo-random-generator generator])
    (random-seed (module-builder-source-value-seed source))
    (thunk)))

; source-value? : any/c -> boolean?
;;   Recognizes one result that project preparation can normalize into a scene.
(define (source-value? value)
  (or (scene? value)
      (authored-timeline? value)
      (scene-program? value)
      (compiled-scene-program? value)))

; source-value->scene : source-value? -> scene?
;;   Normalizes one supported module result to the Scene used by preview rendering.
(define (source-value->scene value)
  (cond
    [(scene? value) value]
    [(authored-timeline? value) (authored-timeline-scene value)]
    [(scene-program? value)
     (compiled-scene-program-scene (compile-scene-program value))]
    [(compiled-scene-program? value) (compiled-scene-program-scene value)]
    [else
     (raise-argument-error 'source-value->scene "source-value?" value)]))

; module-path->require-path : path-string? -> path?
;;   Converts serialized module strings to the path representation dynamic-require accepts.
(define (module-path->require-path value)
  (if (path? value) value (string->path value)))

; raise-source-loading-error : module-builder-source-value? symbol? symbol? string? any/c -> none/c
;;   Raises one diagnostic that preserves module, binding, and loading phase.
(define (raise-source-loading-error source phase binding problem detail)
  (raise-arguments-error
   'load-module-builder-source!
   problem
   "module-path" (module-builder-source-value-module-path source)
   "binding" binding
   "phase" phase
   "detail" detail))
