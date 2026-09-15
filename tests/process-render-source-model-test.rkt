#lang racket/base

;;;
;;; Process Rendering Source-model Tests
;;;

;; Covers PR-A's pure restartability declarations, fixed module-builder
;; invocation contract, immutable snapshots, and worker-policy decisions.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         racket/runtime-path
         "../colors.rkt"
         "../main.rkt"
         "../project.rkt"
         "../typography.rkt")

(define-runtime-path builder-fixture "fixtures/project-builder-source.rkt")
(define-runtime-path value-fixture "fixtures/preview-worker-scene.rkt")


;;;
;;; Fixture Helpers
;;;

; fixture-binding : symbol? -> any/c
;;   Retrieves one fixture export in this test process.
(define (fixture-binding binding)
  (dynamic-require builder-fixture binding))

; make-builder-project : module-builder-source? render-spec? -> animate-project?
;;   Constructs a no-output project suitable for plan/prepare contract tests.
(define (make-builder-project source render)
  (animate-project
   #:id 'process-render-source-model
   #:source source
   #:render render
   #:output (output-spec #:root "process-render-source-output"
                         #:name "fixture"
                         #:format 'png-sequence)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root "process-render-source-cache")))

; prepare-builder-project : module-builder-source? render-spec? -> prepared-project?
;;   Plans and prepares one module builder without rendering any frames.
(define (prepare-builder-project source render)
  (prepare-project!
   (plan-project (make-builder-project source render))))

; prepared-build-key : prepared-project? -> string?
;;   Extracts the pre-preparation construction identity from a prepared project.
(define (prepared-build-key prepared)
  (source-build-context-base-fingerprint
   (prepared-project-source-build-context prepared)))


;;;
;;; Source Declarations and Invocation
;;;

(module+ test
  ;; A proper artifact/dependency list is one collection.  Its length must be
  ;; bounded by node count, not accidentally rejected as 65 nested cdr cells.
  (check-true
   (source-transfer-data?
    (for/list ([index (in-range 128)])
      #hasheq((path . "prepared.svg") (role . math-prepared-svg))))))

(module+ test
  (define reset! (fixture-binding 'reset-builder-observations!))
  (define observations (fixture-binding 'builder-observations))
  (define mutable-options
    (make-hasheq (list (cons 'case 'first)
                        (cons 'nested (vector "one")))))
  (define source
    (module-builder-source
     builder-fixture
     'build-test-source!
     #:options mutable-options
     #:prepare 'prepare-test-inputs!
     #:seed 17))
  (hash-set! mutable-options 'case 'changed-after-declaration)
  (vector-set! (hash-ref mutable-options 'nested) 0 "changed-after-declaration")
  (reset!)
  (define project (make-builder-project source (render-spec #:fps 2 #:width 80 #:height 50)))
  (define planned (plan-project project))
  ;; Pure planning normalizes source data and resolves policy without loading
  ;; the author fixture or invoking either source callback.
  (check-true (project-plan? planned))
  (check-equal? (observations) '())
  (define prepared (prepare-project! planned))
  (check-true (prepared-project? prepared))
  (check-eq? (cacheability-mode (prepared-project-cache-identities prepared))
             'memory-only)
  (check-true (source-build-context?
               (prepared-project-source-build-context prepared)))
  (check-true (source-preparation?
               (prepared-project-source-preparation prepared)))
  (check-equal?
   (map (lambda (entry) (hash-ref entry 'phase)) (observations))
   '(prepare build))
  (define preparation-call (car (observations)))
  (define builder-call (cadr (observations)))
  (check-false
   (source-build-context-preparation
    (hash-ref preparation-call 'context)))
  (check-eq?
   (source-build-context-preparation
    (hash-ref builder-call 'context))
   (prepared-project-source-preparation prepared))
  (check-equal? (hash-ref (hash-ref builder-call 'options) 'case) 'first)
  (check-equal?
   (vector-ref (hash-ref (hash-ref builder-call 'options) 'nested) 0)
   "one")
  (check-equal?
   (hash-ref (hash-ref builder-call 'payload) 'schema)
   'project-builder-fixture-v1)
  (check-equal?
   (source-build-context-seed
    (prepared-project-source-build-context prepared))
   17)
  (check-equal?
   (source-build-context-width
    (prepared-project-source-build-context prepared))
   80)
  (check-equal?
   (source-build-context-height
    (prepared-project-source-build-context prepared))
   50))

(module+ test
  (define without-preparer
    (module-builder-source builder-fixture 'build-without-preparer!))
  (define prepared-without-preparer
    (prepare-builder-project without-preparer (render-spec #:workers 1)))
  (check-false (prepared-project-source-preparation prepared-without-preparer))
  (check-false
   (source-build-context-preparation
    (prepared-project-source-build-context prepared-without-preparer)))
  ;; Existing module value declarations retain their original loading behavior.
  (define value-project
    (animate-project
     #:id 'module-value-source
     #:source (module-binding-source value-fixture 'worker-scene)
     #:render (render-spec #:fps 2)
     #:output (output-spec #:root "process-render-source-output"
                           #:name "value"
                           #:format 'png-sequence)
     #:encoder (encoder-spec #:codec 'none)))
  (check-true
   (scene?
    (prepared-project-scene
     (prepare-project! (plan-project value-project))))))


;;;
;;; Validation and Identity
;;;

(module+ test
  (check-exn exn:fail?
             (lambda ()
               (module-builder-source builder-fixture 'build-test-source!
                                      #:options (hasheq 'callback (lambda () #t)))))
  (define cyclic (make-vector 1 #f))
  (vector-set! cyclic 0 cyclic)
  (check-exn exn:fail?
             (lambda ()
               (module-builder-source builder-fixture 'build-test-source!
                                      #:options (hasheq 'cycle cyclic))))
  (check-exn exn:fail?
             (lambda () (module-builder-source builder-fixture 'build-test-source! #:seed -1)))
  (check-exn exn:fail?
             (lambda () (module-builder-source builder-fixture 'build-test-source! #:seed #x80000000)))
  (check-exn exn:fail?
             (lambda () (source-preparation #:payload (lambda () #t))))
  (for ([binding (in-list '(build-wrong-arity!
                            build-multiple-values!
                            build-invalid-result!))])
    (check-exn
     exn:fail?
     (lambda ()
       (prepare-builder-project
        (module-builder-source builder-fixture binding)
        (render-spec)))))
  (for ([binding (in-list '(prepare-wrong-arity!
                            prepare-multiple-values!
                            prepare-invalid-result!))])
    (check-exn
     exn:fail?
     (lambda ()
       (prepare-builder-project
        (module-builder-source builder-fixture 'build-test-source! #:prepare binding)
        (render-spec)))))
  (define baseline-source
    (module-builder-source builder-fixture 'build-without-preparer!
                           #:options #hasheq((case . first)) #:seed 1))
  (define changed-options-source
    (module-builder-source builder-fixture 'build-without-preparer!
                           #:options #hasheq((case . second)) #:seed 1))
  (define changed-seed-source
    (module-builder-source builder-fixture 'build-without-preparer!
                           #:options #hasheq((case . first)) #:seed 2))
  (define baseline-key
    (prepared-build-key
     (prepare-builder-project baseline-source (render-spec #:workers 1))))
  (check-not-equal?
   baseline-key
   (prepared-build-key
    (prepare-builder-project changed-options-source (render-spec #:workers 1))))
  (check-not-equal?
   baseline-key
   (prepared-build-key
    (prepare-builder-project changed-seed-source (render-spec #:workers 1))))
  (check-not-equal?
   baseline-key
   (prepared-build-key
    (prepare-builder-project baseline-source
                             (render-spec #:workers 1 #:theme animate-dark-theme))))
  (check-equal?
   baseline-key
   (prepared-build-key
    (prepare-builder-project baseline-source (render-spec #:workers 2))))
  (check-equal?
   (render-spec-worker-mode
    (render-spec-with-theme
     (render-spec #:worker-mode 'subprocess)
     animate-dark-theme))
   'subprocess)
  (check-equal?
   (render-spec-worker-mode
    (render-spec-with-typography
     (render-spec #:worker-mode 'subprocess)
     animate-typography-theme))
   'subprocess))


;;;
;;; Worker Policy
;;;

(module+ test
  (define direct-source (scene-source (scene-wait (make-scene) 1)))
  (define restartable-source
    (module-builder-source builder-fixture 'build-without-preparer!))
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy direct-source (render-spec #:workers 1)))
   'in-process)
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy direct-source
                                  (render-spec #:workers 4 #:worker-mode 'in-process)))
   'in-process)
  (check-exn exn:fail?
             (lambda ()
               (resolve-render-worker-policy direct-source (render-spec #:workers 2))))
  (check-exn exn:fail?
             (lambda ()
               (resolve-render-worker-policy
                direct-source
                (render-spec #:worker-mode 'subprocess))))
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy restartable-source (render-spec #:workers 1)))
   'in-process)
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy restartable-source (render-spec #:workers 2)))
   'subprocess)
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy
     restartable-source
     (render-spec #:workers 1 #:worker-mode 'subprocess)))
   'subprocess)
  (check-eq?
   (render-worker-policy-resolved-mode
    (resolve-render-worker-policy
     restartable-source
     (render-spec #:workers 4 #:worker-mode 'in-process)))
   'in-process)
  (check-exn exn:fail?
             (lambda ()
               (resolve-render-worker-policy
                restartable-source
                (render-spec #:workers 2 #:renderers '())))))
