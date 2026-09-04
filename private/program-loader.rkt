#lang racket/base

;;;
;;; Isolated, Atomic Scene-Program Loading
;;;

;; A loader never mutates the last known-good program.  A reload constructs a
;; candidate in a fresh namespace and custodian, fingerprints it, compiles its
;; verified prefix, and only then returns a replacement loader.  Callers keep
;; the old loader if an exception is raised.

(require racket/list
         racket/path
         "program-fingerprint.rkt"
         "scene-program.rkt")

(provide (struct-out exn:fail:scene-program-loader)
         (struct-out scene-program-loader)
         load-scene-program
         reload-scene-program
         scene-program-loader-close!)

(struct exn:fail:scene-program-loader exn:fail (category)
  #:transparent)

(struct scene-program-loader
  (module-path binding source-path fingerprint compiled namespace custodian)
  #:transparent)

(define host-namespace (current-namespace))
(define host-module-paths '(animate animate/authoring))

(define (load-scene-program module-path binding)
  (check-module-path 'load-scene-program module-path)
  (check-symbol 'load-scene-program binding)
  (load-candidate module-path binding #f))

(define (reload-scene-program loader)
  (unless (scene-program-loader? loader)
    (raise-argument-error 'reload-scene-program "scene-program-loader?" loader))
  (load-candidate (scene-program-loader-module-path loader)
                  (scene-program-loader-binding loader)
                  loader))

(define (scene-program-loader-close! loader)
  (unless (scene-program-loader? loader)
    (raise-argument-error 'scene-program-loader-close! "scene-program-loader?" loader))
  (custodian-shutdown-all (scene-program-loader-custodian loader)))

(define (load-candidate module-path binding previous)
  (define source-path (module-path->source-path module-path))
  (define custodian (make-custodian))
  (with-handlers
      ([exn:fail:scene-program-loader?
        (lambda (error)
          (custodian-shutdown-all custodian)
          (raise error))]
       [exn:fail?
        (lambda (error)
          (custodian-shutdown-all custodian)
          (raise-loader-error (classify-load-error error) error))])
    (define namespace
      (parameterize ([current-custodian custodian])
        (make-base-namespace)))
    (attach-host-animate-modules! namespace)
    (define program
      (parameterize ([current-namespace namespace]
                     [current-custodian custodian]
                     ;; A hot reload must read the edited source even when a
                     ;; filesystem has coarse modification timestamps.
                     [use-compiled-file-paths null])
        (dynamic-require source-path binding)))
    (unless (scene-program? program)
      (raise-loader-error
       'wrong-binding-type
       (format "binding ~a did not produce a scene-program value" binding)))
    (define fingerprint
      (fingerprint-scene-program program #:source-path source-path))
    (define fingerprinted-program
      (scene-program-with-fingerprints program fingerprint))
    (define first-changed-index
      (cond
        [(not previous) 0]
        [else
         (or (scene-program-first-changed-index
              (scene-program-loader-fingerprint previous)
              fingerprint)
             (length (scene-program-blocks fingerprinted-program)))]))
    (define generation
      (if previous
          (add1 (compiled-scene-program-generation
                 (scene-program-loader-compiled previous)))
          0))
    (define compiled
      (compile-scene-program/incremental
       fingerprinted-program
       (and previous (scene-program-loader-compiled previous))
       first-changed-index
       #:generation generation))
    ;; The caller now owns both generations. It retires `previous` only after
    ;; atomically installing this candidate in its preview session. Keeping it
    ;; alive until then is what makes a controller-install failure harmless.
    (scene-program-loader module-path binding source-path fingerprint compiled
                          namespace custodian)))

(define (attach-host-animate-modules! target-namespace)
  ;; `namespace-attach-module` preserves the host instances of animate and
  ;; animate/authoring.  Consequently scene values produced by a reloaded
  ;; source program satisfy the controller's existing `scene?` predicate.
  (for ([module-path (in-list host-module-paths)])
    (dynamic-require module-path #f)
    (namespace-attach-module host-namespace module-path target-namespace)))

(define (module-path->source-path module-path)
  (cond
    [(path-string? module-path)
     (simplify-path (path->complete-path module-path))]
    [else
     ;; Automatic block fingerprinting needs a real source file. Supporting a
     ;; collection module here would require resolving the module declaration
     ;; first, which would compromise the clean-load boundary. Authors can use
     ;; the file path that the CLI and watcher already operate on.
     (raise-argument-error 'load-scene-program "path-string? source module" module-path)]))

(define (check-module-path who value)
  (unless (path-string? value)
    (raise-argument-error who "path-string? source module" value)))

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (classify-load-error error)
  (cond
    [(regexp-match? #rx"binding .* not provided" (exn-message error))
     'missing-binding]
    [(regexp-match? #rx"read-syntax|read:" (exn-message error))
     'read-syntax]
    [(regexp-match? #rx"scene-program compilation failed" (exn-message error))
     'scene-block-failure]
    [(regexp-match? #rx"source span|source file|asset" (exn-message error))
     'fingerprint]
    [else 'module-instantiation]))

(define (raise-loader-error category error-or-message)
  (define message
    (if (exn? error-or-message)
        (exn-message error-or-message)
        error-or-message))
  (raise
   (exn:fail:scene-program-loader
    (format "scene-program load failed (~a): ~a" category message)
    (if (exn? error-or-message)
        (exn-continuation-marks error-or-message)
        (current-continuation-marks))
    category)))
