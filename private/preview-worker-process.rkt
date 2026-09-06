#lang racket/base

;;;
;;; Subprocess Supervisor for Module-backed Preview Rendering
;;;

;; A project worker is deliberately a small, owned resource. The parent can
;; kill and recreate it when a render blocks; this is the safe hard-cancellation
;; boundary that an in-process scene containing arbitrary closures cannot have.

(require racket/async-channel
         racket/class
         racket/draw
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         "preview-cancellation.rkt"
         "preview-model.rkt"
         "preview-quality.rkt"
         "preview-render-request.rkt"
         "preview-worker-protocol.rkt"
         "3d/preview-camera3d-override.rkt")

(provide preview-worker-process?
         start-project-preview-worker
         preview-worker-open?
         preview-worker-render-frame!
         preview-worker-reload!
         preview-worker-cancel!
         preview-worker-stop!
         preview-worker-restart!
         project-worker-producer?
         make-project-worker-producer
         project-worker-producer-produce
         project-worker-producer-close!
         exn:fail:preview-worker-timed-out?
         exn:fail:preview-worker-timed-out-request-id
         exn:fail:preview-worker-restarted?
         exn:fail:preview-worker-restarted-request-id)

(define-runtime-path worker-main-path "preview-worker-main.rkt")

(struct exn:fail:preview-worker-timed-out exn:fail (request-id)
  #:transparent)

(struct exn:fail:preview-worker-restarted exn:fail (request-id)
  #:transparent)

(struct preview-worker-process
  (racket module-path binding fingerprint document-generation
          process output input events reader alive?)
  #:mutable
  #:transparent)

;; The controller's general producer contract predates subprocess workers and
;; deliberately exposes only document/sample/spec/token. This adapter creates
;; protocol request identities internally while preserving that small contract.
;; It is used only by module-backed projects; in-memory scenes retain their
;; cooperative in-process producer.
(struct project-worker-producer
  (module-path binding fingerprint worker document-generation next-request-id)
  #:mutable
  #:transparent)

(define (make-project-worker-producer module-path binding
                                      #:fingerprint [fingerprint 'project])
  (unless (path-string? module-path)
    (raise-argument-error 'make-project-worker-producer "path-string?" module-path))
  (unless (symbol? binding)
    (raise-argument-error 'make-project-worker-producer "symbol?" binding))
  (project-worker-producer
   (path->complete-path module-path) binding fingerprint #f #f 0))

(define (project-worker-producer-produce producer document sample render-spec token)
  (unless (project-worker-producer? producer)
    (raise-argument-error 'project-worker-producer-produce
                          "project-worker-producer?" producer))
  (unless (preview-document? document)
    (raise-argument-error 'project-worker-producer-produce "preview-document?" document))
  (unless (preview-render-spec? render-spec)
    (raise-argument-error 'project-worker-producer-produce "preview-render-spec?" render-spec))
  (unless (cancellation-token? token)
    (raise-argument-error 'project-worker-producer-produce "cancellation-token?" token))
  (define generation (preview-document-generation document))
  (define worker (project-worker-producer-worker producer))
  (cond
    [(not worker)
     (set! worker
           (start-project-preview-worker
            (project-worker-producer-module-path producer)
            (project-worker-producer-binding producer)
            #:fingerprint (project-worker-producer-fingerprint producer)
            #:document-generation generation))
     (set-project-worker-producer-worker! producer worker)
     (set-project-worker-producer-document-generation! producer generation)]
    [(not (= generation (project-worker-producer-document-generation producer)))
     (preview-worker-reload! worker #:document-generation generation)
     (set-project-worker-producer-document-generation! producer generation)]
    [else (void)])
  (define next-id (add1 (project-worker-producer-next-request-id producer)))
  (set-project-worker-producer-next-request-id! producer next-id)
  (define request
    (preview-render-request
     #:id next-id
     #:document-generation generation
     #:render-generation 0
     #:sample sample
     #:quality
     (preview-quality #:name 'project-worker
                      #:pixel-scale (preview-render-spec-pixel-scale render-spec)
                      #:supersample (preview-render-spec-supersample render-spec))
     #:priority 0
     #:cancellation-token token))
  (define-values (bitmap _diagnostics)
    (preview-worker-render-frame! worker request render-spec))
  bitmap)

(define (project-worker-producer-close! producer)
  (unless (project-worker-producer? producer)
    (raise-argument-error 'project-worker-producer-close!
                          "project-worker-producer?" producer))
  (define worker (project-worker-producer-worker producer))
  (when worker (preview-worker-stop! worker))
  (set-project-worker-producer-worker! producer #f)
  (void))

(define (start-project-preview-worker module-path binding
                                      #:racket
                                      [racket (find-system-path 'exec-file)]
                                      #:fingerprint [fingerprint 'project]
                                      #:document-generation
                                      [document-generation 0])
  (unless (path-string? module-path)
    (raise-argument-error 'start-project-preview-worker "path-string?" module-path))
  (unless (symbol? binding)
    (raise-argument-error 'start-project-preview-worker "symbol?" binding))
  (unless (path-string? racket)
    (raise-argument-error 'start-project-preview-worker "path-string?" racket))
  (unless (exact-nonnegative-integer? document-generation)
    (raise-argument-error 'start-project-preview-worker
                          "exact-nonnegative-integer?" document-generation))
  (define worker
    (preview-worker-process racket
                            (path->complete-path module-path)
                            binding fingerprint document-generation
                            #f #f #f (make-async-channel) #f (box #f)))
  (spawn-worker! worker)
  worker)

(define (preview-worker-open? worker)
  (check-worker 'preview-worker-open? worker)
  (unbox (preview-worker-process-alive? worker)))

;; The return value is a bitmap loaded from a parent-owned temporary PNG. The
;; file is removed after it is read; durable frame caching remains the project
;; executor's separate responsibility.
(define (preview-worker-render-frame! worker request render-spec
                                      #:timeout-milliseconds [timeout-milliseconds 10000])
  (check-worker 'preview-worker-render-frame! worker)
  (unless (preview-render-request? request)
    (raise-argument-error 'preview-worker-render-frame! "preview-render-request?" request))
  (unless (preview-render-spec? render-spec)
    (raise-argument-error 'preview-worker-render-frame! "preview-render-spec?" render-spec))
  (unless (exact-positive-integer? timeout-milliseconds)
    (raise-argument-error 'preview-worker-render-frame!
                          "exact-positive-integer?" timeout-milliseconds))
  (unless (preview-worker-open? worker)
    (preview-worker-restart! worker))
  (define temporary (make-temporary-file "animate-preview-worker-~a.png"))
  ;; bitmap% cannot always replace a pre-existing temporary file on every
  ;; platform, while the worker owns the single later write.
  (delete-file temporary)
  (define token (preview-render-request-cancellation-token request))
  (define message
    (worker-render-frame
     (preview-worker-process-fingerprint worker)
     (preview-render-request-document-generation request)
     (preview-render-request-render-generation request)
     (preview-render-request-id request)
     (sample->datum (preview-render-request-sample request))
     (preview-render-spec-pixel-scale render-spec)
     (preview-render-spec-supersample render-spec)
     (for/list
         ([view-id
           (in-list
            (sort (hash-keys (preview-render-spec-camera3d-overrides render-spec))
                  symbol<?))])
       (preview-camera3d-override->datum
        (hash-ref (preview-render-spec-camera3d-overrides render-spec) view-id)))
     (path->string temporary)))
  (dynamic-wind
   void
   (lambda ()
     (send-worker! worker message)
     (let loop ([remaining timeout-milliseconds])
       (cond
         [(cancellation-requested? token)
          (preview-worker-cancel! worker request)
          (preview-worker-restart! worker)
          (check-cancellation token)]
         [(zero? remaining)
          (preview-worker-restart! worker)
          (raise
           (exn:fail:preview-worker-timed-out
            "project preview worker timed out; a fresh worker has been started"
            (current-continuation-marks)
            (preview-render-request-id request)))]
         [else
          (define response
            (sync/timeout 1/1000 (preview-worker-process-events worker)))
          (cond
            [(not response) (loop (sub1 remaining))]
            [(and (worker-frame-complete? response)
                  (= (worker-frame-complete-request-id response)
                     (preview-render-request-id request)))
             (values (read-bitmap temporary)
                     (worker-frame-complete-diagnostics response))]
            [(and (worker-frame-failed? response)
                  (= (worker-frame-failed-request-id response)
                     (preview-render-request-id request)))
             (raise-arguments-error 'preview-worker-render-frame!
                                    "a successful project worker frame"
                                    "worker-error"
                                    (worker-frame-failed-message response))]
            [else (loop remaining)])])))
   (lambda ()
     (when (file-exists? temporary) (delete-file temporary)))))

(define (preview-worker-cancel! worker request)
  (check-worker 'preview-worker-cancel! worker)
  (unless (preview-render-request? request)
    (raise-argument-error 'preview-worker-cancel! "preview-render-request?" request))
  (when (preview-worker-open? worker)
    (send-worker!
     worker
     (worker-cancel
      (preview-worker-process-fingerprint worker)
      (preview-render-request-document-generation request)
      (preview-render-request-render-generation request)
      (preview-render-request-id request))))
  (void))

(define (preview-worker-reload! worker #:document-generation document-generation)
  (check-worker 'preview-worker-reload! worker)
  (unless (exact-nonnegative-integer? document-generation)
    (raise-argument-error 'preview-worker-reload!
                          "exact-nonnegative-integer?" document-generation))
  (set-preview-worker-process-document-generation! worker document-generation)
  (preview-worker-restart! worker))

(define (preview-worker-restart! worker)
  (check-worker 'preview-worker-restart! worker)
  (preview-worker-stop! worker)
  (spawn-worker! worker)
  (void))

(define (preview-worker-stop! worker)
  (check-worker 'preview-worker-stop! worker)
  (when (preview-worker-open? worker)
    (with-handlers ([exn:fail? (lambda (_error) (void))])
      (send-worker! worker (worker-shutdown)))
    (define process (preview-worker-process-process worker))
    (when (and process (eq? (subprocess-status process) 'running))
      (subprocess-kill process #t))
    (set-box! (preview-worker-process-alive? worker) #f))
  (void))

(define (spawn-worker! worker)
  (define-values (process output input _error)
    (subprocess #f #f #f
                (preview-worker-process-racket worker)
                "-t" worker-main-path))
  (set-preview-worker-process-process! worker process)
  (set-preview-worker-process-output! worker output)
  (set-preview-worker-process-input! worker input)
  (set-box! (preview-worker-process-alive? worker) #t)
  (set-preview-worker-process-reader!
   worker
   (thread
    (lambda ()
      (let loop ()
        (define value (with-handlers ([exn:fail? (lambda (_error) eof)])
                        (read output)))
        (unless (eof-object? value)
          (async-channel-put (preview-worker-process-events worker) value)
          (loop))))))
  (send-worker!
   worker
   (worker-load-project
    (preview-worker-process-fingerprint worker)
    (path->string (preview-worker-process-module-path worker))
    (preview-worker-process-binding worker)
    (preview-worker-process-document-generation worker)))
  (await-ready! worker))

(define (send-worker! worker message)
  (write message (preview-worker-process-input worker))
  (newline (preview-worker-process-input worker))
  (flush-output (preview-worker-process-input worker)))

(define (await-ready! worker)
  (let loop ([remaining 5000])
    (cond
      [(zero? remaining)
       (preview-worker-stop! worker)
       (raise-arguments-error 'start-project-preview-worker
                              "a worker that can load the declared source"
                              "module-path" (preview-worker-process-module-path worker))]
      [else
       (define response
         (sync/timeout 1/1000 (preview-worker-process-events worker)))
       (cond
         [(and (worker-ready? response)
               (equal? (worker-ready-plan-fingerprint response)
                       (preview-worker-process-fingerprint worker)))
          (void)]
         [(worker-log? response)
          (preview-worker-stop! worker)
          (raise-arguments-error 'start-project-preview-worker
                                 "a loadable project module"
                                 "message" (worker-log-message response))]
         [else (loop (sub1 remaining))])])))

(define (sample->datum sample)
  (cond
    [(frame-sample? sample)
     (list 'frame (frame-sample-frame-index sample) (frame-sample-fps sample))]
    [(time-sample? sample) (list 'time (time-sample-time sample))]
    [else
     (raise-argument-error 'preview-worker-render-frame!
                           "(or/c frame-sample? time-sample?)" sample)]))

(define (check-worker who value)
  (unless (preview-worker-process? value)
    (raise-argument-error who "preview-worker-process?" value)))
