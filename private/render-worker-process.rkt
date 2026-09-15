#lang racket/base

;;;
;;; Owned Render Worker Supervisor
;;;

;; Owns one child process, its protocol ports, bounded log drains, reader
;; threads, monotonic deadlines, and process-group shutdown.  Preview is the
;; first client; later frame export can use this lifecycle without another
;; source loader or subprocess wrapper.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/async-channel
         racket/path
         racket/runtime-path
         "render-frame-job.rkt"
         "render-preparation-manifest.rkt"
         "render-source-model.rkt"
         "render-worker-protocol.rkt")

;; Exports
(provide render-worker-process?
         start-render-worker!
         render-worker-open?
         render-worker-pid
         render-worker-spawn-milliseconds
         render-worker-hello-milliseconds
         render-worker-source-ready-milliseconds
         render-worker-render-preview-frame!
         render-worker-render-final-frame!
         render-worker-cancel!
         render-worker-restart!
         render-worker-stop!
         render-worker-log-bytes
         render-worker-resource-status
         render-worker-write-raw-for-test!
         exn:fail:render-worker-startup?
         exn:fail:render-worker-startup-reason
         exn:fail:render-worker-timeout?
         exn:fail:render-worker-timeout-request-id
         exn:fail:render-worker-canceled?
         exn:fail:render-worker-canceled-request-id
         exn:fail:render-worker-crashed?
         exn:fail:render-worker-crashed-reason
         exn:fail:render-worker-failed?
         exn:fail:render-worker-failed-phase
         exn:fail:render-worker-failed-message)

(define-runtime-path worker-main-path "render-worker-main.rkt")


;;;
;;; Supervisor State
;;;

; render-worker-maximum-log-bytes : exact-positive-integer?
;;   Caps retained worker stderr and protocol-log evidence per live worker.
(define render-worker-maximum-log-bytes (* 64 1024))

; render-worker-maximum-events : exact-positive-integer?
;;   Caps queued protocol responses before a malicious worker is terminated.
(define render-worker-maximum-events 128)

(struct exn:fail:render-worker-startup exn:fail (reason)
  #:transparent)
(struct exn:fail:render-worker-timeout exn:fail (request-id)
  #:transparent)
(struct exn:fail:render-worker-canceled exn:fail (request-id)
  #:transparent)
(struct exn:fail:render-worker-crashed exn:fail (reason)
  #:transparent)
(struct exn:fail:render-worker-failed exn:fail (phase message)
  #:transparent)

;; The event records never cross a process boundary.  They distinguish EOF,
;; malformed transport, and valid protocol responses for the owning session.
(struct render-worker-event (kind value)
  #:transparent)

(struct render-worker-process
  (racket source source-fingerprint session-id generation expected-animate-main
          final-output-root input-manifest
          custodian process pid output input error events event-slots
          reader error-reader alive? log-lock log-bytes
          spawn-milliseconds hello-milliseconds source-ready-milliseconds)
  #:mutable
  #:transparent)

;; render-worker-process owns exactly one child generation.
;;  - source/source-fingerprint  immutable reconstruction identity.
;;  - session-id/generation      execution identity, never source semantics.
;;  - final-output-root          optional parent-owned staging directory for
;;                                final PNG jobs; preview workers leave it #f.
;;  - input-manifest             optional tracked local input identity checked
;;                                by the parent and child before source loading.
;;  - process/ports/threads      effectful resources closed by stop!.
;;  - events/event-slots         bounded parent-side protocol queue.
;;  - log-bytes                  bounded retained stderr/protocol diagnostics.


;;;
;;; Public Lifecycle
;;;

; start-render-worker! : render-worker-source? [#:racket path-string?]
;                        [#:source-fingerprint transfer-data?] [#:session-id string?]
;                        [#:generation exact-nonnegative-integer?]
;                        [#:final-output-root (or/c path-string? false/c)]
;                        [#:input-manifest (or/c render-input-manifest? false/c)]
;                        [#:startup-timeout-milliseconds exact-positive-integer?]
;                        -> render-worker-process?
;;   Starts, handshakes, and loads one explicitly owned worker generation.
(define (start-render-worker! source
                              #:racket [racket (find-system-path 'exec-file)]
                              #:source-fingerprint [source-fingerprint 'render-source]
                              #:session-id [session-id (fresh-session-id)]
                              #:generation [generation 0]
                              #:final-output-root [final-output-root #f]
                              #:input-manifest [input-manifest #f]
                              #:startup-timeout-milliseconds
                              [startup-timeout-milliseconds 5000])
  (unless (render-worker-source? source)
    (raise-argument-error 'start-render-worker! "render-worker-source?" source))
  (unless (path-string? racket)
    (raise-argument-error 'start-render-worker! "path-string? as #:racket" racket))
  (unless (source-transfer-data? source-fingerprint)
    (raise-argument-error
     'start-render-worker! "source-transfer-data? as #:source-fingerprint" source-fingerprint))
  (unless (bounded-session-id? session-id)
    (raise-argument-error 'start-render-worker! "bounded string? as #:session-id" session-id))
  (unless (exact-nonnegative-integer? generation)
    (raise-argument-error
     'start-render-worker! "exact-nonnegative-integer? as #:generation" generation))
  (unless (or (not final-output-root) (path-string? final-output-root))
    (raise-argument-error
     'start-render-worker! "(or/c path-string? false/c) as #:final-output-root"
     final-output-root))
  (unless (or (not input-manifest) (render-input-manifest? input-manifest))
    (raise-argument-error
     'start-render-worker!
     "(or/c render-input-manifest? false/c) as #:input-manifest"
     input-manifest))
  (unless (exact-positive-integer? startup-timeout-milliseconds)
    (raise-argument-error
     'start-render-worker! "exact-positive-integer? as #:startup-timeout-milliseconds"
     startup-timeout-milliseconds))
  (define worker
    (render-worker-process
     (path->complete-path racket)
     source
     source-fingerprint
     session-id
     generation
     (path->string (collection-file-path "main.rkt" "animate"))
     (and final-output-root (path->complete-path final-output-root))
     input-manifest
     #f #f #f #f #f #f
     (make-async-channel)
     (make-semaphore render-worker-maximum-events)
     #f #f (box #f) (make-semaphore 1) #"" #f #f #f))
  (with-handlers ([exn:fail:render-worker-startup?
                   (lambda (error)
                     (render-worker-stop! worker)
                     (raise error))]
                  [exn:fail?
                   (lambda (error)
                     (render-worker-stop! worker)
                     (raise
                      (exn:fail:render-worker-startup
                       (format "render worker failed during startup: ~a"
                               (exn-message error))
                       (current-continuation-marks)
                       'handshake)))])
    (spawn-render-worker! worker startup-timeout-milliseconds))
  worker)

; render-worker-open? : render-worker-process? -> boolean?
;;   Reports whether the owned child is still usable for the current generation.
(define (render-worker-open? worker)
  (check-worker 'render-worker-open? worker)
  (and (unbox (render-worker-process-alive? worker))
       (render-worker-process-process worker)
       (eq? (subprocess-status (render-worker-process-process worker)) 'running)))

; render-worker-pid : render-worker-process? -> (or/c exact-positive-integer? #f)
;;   Returns the OS PID recorded for process-identity diagnostics.
(define (render-worker-pid worker)
  (check-worker 'render-worker-pid worker)
  (render-worker-process-pid worker))

; render-worker-spawn-milliseconds : render-worker-process? -> (or/c real? false/c)
;;   Returns the parent-observed subprocess creation duration for this generation.
(define (render-worker-spawn-milliseconds worker)
  (check-worker 'render-worker-spawn-milliseconds worker)
  (render-worker-process-spawn-milliseconds worker))

; render-worker-hello-milliseconds : render-worker-process? -> (or/c real? false/c)
;;   Returns the parent-observed post-spawn hello handshake duration.
(define (render-worker-hello-milliseconds worker)
  (check-worker 'render-worker-hello-milliseconds worker)
  (render-worker-process-hello-milliseconds worker))

; render-worker-source-ready-milliseconds : render-worker-process? -> (or/c real? false/c)
;;   Returns the parent-observed load/build/ready round-trip duration.
(define (render-worker-source-ready-milliseconds worker)
  (check-worker 'render-worker-source-ready-milliseconds worker)
  (render-worker-process-source-ready-milliseconds worker))

; render-worker-render-preview-frame! : render-worker-process? exact-nonnegative-integer?
;                                       source-transfer-data? positive-finite-real?
;                                       exact-positive-integer? transfer-data? transfer-data?
;                                       transfer-data? [#:timeout-milliseconds exact-positive-integer?]
;                                       [#:canceled? (-> boolean?)]
;                                       -> bytes? immutable-transfer-data?
;;   Requests one PNG-byte preview frame and rejects stale or malformed replies.
(define (render-worker-render-preview-frame! worker request-id sample pixel-scale supersample
                                             theme-datum typography-datum camera3d-overrides
                                             #:timeout-milliseconds
                                             [timeout-milliseconds 10000]
                                             #:canceled? [canceled? (lambda () #f)])
  (check-worker 'render-worker-render-preview-frame! worker)
  (unless (exact-nonnegative-integer? request-id)
    (raise-argument-error
     'render-worker-render-preview-frame! "exact-nonnegative-integer?" request-id))
  (unless (exact-positive-integer? timeout-milliseconds)
    (raise-argument-error
     'render-worker-render-preview-frame! "exact-positive-integer?" timeout-milliseconds))
  (unless (procedure? canceled?)
    (raise-argument-error 'render-worker-render-preview-frame! "procedure?" canceled?))
  (unless (render-worker-open? worker)
    (raise
     (exn:fail:render-worker-crashed
      "render worker is not open"
      (current-continuation-marks)
      'not-open)))
  (define message
    (render-worker-render-preview-frame
     render-worker-protocol-version
     (render-worker-process-session-id worker)
     (render-worker-process-source-fingerprint worker)
     (render-worker-process-generation worker)
     request-id
     sample pixel-scale supersample theme-datum typography-datum camera3d-overrides))
  (send-message! worker message)
  (define response
    (await-response!
     worker request-id timeout-milliseconds
     (lambda (value)
       (or (render-worker-frame-complete? value)
           (render-worker-failed? value)))
     #:canceled? canceled?))
  (cond
    [(render-worker-frame-complete? response)
     (values (render-worker-frame-complete-png-bytes response)
             (render-worker-frame-complete-diagnostics response))]
    [else
     (raise
      (exn:fail:render-worker-failed
       (format "render worker failed during ~a: ~a"
               (render-worker-failed-phase response)
               (render-worker-failed-message response))
       (current-continuation-marks)
       (render-worker-failed-phase response)
       (render-worker-failed-message response)))]))

; render-worker-render-final-frame! : render-worker-process? final-render-frame-job?
;                                      [#:timeout-milliseconds exact-positive-integer?]
;                                      [#:canceled? (-> boolean?)]
;                                      -> render-worker-final-frame-complete?
;;   Requests one worker-local final PNG and returns only validated file metadata.
(define (render-worker-render-final-frame! worker job
                                           #:timeout-milliseconds
                                           [timeout-milliseconds 60000]
                                           #:canceled? [canceled? (lambda () #f)])
  (check-worker 'render-worker-render-final-frame! worker)
  (unless (final-render-frame-job-valid? job)
    (raise-argument-error
     'render-worker-render-final-frame! "final-render-frame-job?" job))
  (unless (exact-positive-integer? timeout-milliseconds)
    (raise-argument-error
     'render-worker-render-final-frame! "exact-positive-integer?" timeout-milliseconds))
  (unless (procedure? canceled?)
    (raise-argument-error 'render-worker-render-final-frame! "procedure?" canceled?))
  (unless (render-worker-process-final-output-root worker)
    (raise-arguments-error
     'render-worker-render-final-frame!
     "a worker started with a parent-owned final-output root"
     "worker" worker))
  (unless (and (equal? (final-render-frame-job-session-id job)
                       (render-worker-process-session-id worker))
               (equal? (final-render-frame-job-source-fingerprint job)
                       (render-worker-process-source-fingerprint worker))
               (= (final-render-frame-job-generation job)
                  (render-worker-process-generation worker)))
    (raise-arguments-error
     'render-worker-render-final-frame!
     "a job for the worker's current session, source fingerprint, and generation"
     "job" job))
  (unless (render-worker-open? worker)
    (raise
     (exn:fail:render-worker-crashed
      "render worker is not open"
      (current-continuation-marks)
      'not-open)))
  (define message
    (render-worker-render-final-frame
     render-worker-protocol-version
     (final-render-frame-job-session-id job)
     (final-render-frame-job-source-fingerprint job)
     (final-render-frame-job-generation job)
     (final-render-frame-job-request-id job)
     (final-render-frame-job-source-frame-index job)
     (final-render-frame-job-output-frame-index job)
     (final-render-frame-job-fps job)
     (final-render-frame-job-camera-datum job)
     (final-render-frame-job-supersample job)
     (final-render-frame-job-theme-datum job)
     (final-render-frame-job-typography-datum job)
     (final-render-frame-job-renderer-kind job)
     (final-render-frame-job-renderer-inputs job)
     (final-render-frame-job-output-name job)))
  (send-message! worker message)
  (define response
    (await-response!
     worker
     (final-render-frame-job-request-id job)
     timeout-milliseconds
     (lambda (value)
       (or (render-worker-final-frame-complete? value)
           (render-worker-failed? value)))
     #:canceled? canceled?))
  (cond
    [(render-worker-final-frame-complete? response) response]
    [else
     (raise
      (exn:fail:render-worker-failed
       (format "render worker failed during ~a: ~a"
               (render-worker-failed-phase response)
               (render-worker-failed-message response))
       (current-continuation-marks)
       (render-worker-failed-phase response)
       (render-worker-failed-message response)))]))

; render-worker-cancel! : render-worker-process? exact-nonnegative-integer? any/c -> void?
;;   Sends a cooperative cancellation boundary before the owner performs hard stop/restart.
(define (render-worker-cancel! worker request-id reason)
  (check-worker 'render-worker-cancel! worker)
  (unless (exact-nonnegative-integer? request-id)
    (raise-argument-error 'render-worker-cancel! "exact-nonnegative-integer?" request-id))
  (unless (source-transfer-data? reason)
    (raise-argument-error 'render-worker-cancel! "source-transfer-data?" reason))
  (when (render-worker-open? worker)
    (with-handlers ([exn:fail? (lambda (_error) (void))])
      (send-message!
       worker
       (render-worker-cancel
        render-worker-protocol-version
        (render-worker-process-session-id worker)
        (render-worker-process-source-fingerprint worker)
        (render-worker-process-generation worker)
        request-id
        reason))))
  (void))

; render-worker-restart! : render-worker-process?
;                          [#:generation exact-nonnegative-integer?]
;                          [#:startup-timeout-milliseconds exact-positive-integer?]
;                          -> void?
;;   Reaps the current process and creates a fresh module instance for a generation.
(define (render-worker-restart! worker
                                #:generation
                                [generation (add1 (render-worker-process-generation worker))]
                                #:startup-timeout-milliseconds
                                [startup-timeout-milliseconds 5000])
  (check-worker 'render-worker-restart! worker)
  (unless (exact-nonnegative-integer? generation)
    (raise-argument-error
     'render-worker-restart! "exact-nonnegative-integer?" generation))
  (render-worker-stop! worker)
  (set-render-worker-process-generation! worker generation)
  (spawn-render-worker! worker startup-timeout-milliseconds)
  (void))

; render-worker-stop! : render-worker-process? -> void?
;;   Shuts down, kills, reaps, closes, and releases all resources owned by one worker.
(define (render-worker-stop! worker)
  (check-worker 'render-worker-stop! worker)
  (define process (render-worker-process-process worker))
  (when (render-worker-open? worker)
    (with-handlers ([exn:fail? (lambda (_error) (void))])
      (send-message!
       worker
       (render-worker-shutdown
        render-worker-protocol-version
        (render-worker-process-session-id worker)
        (render-worker-process-source-fingerprint worker)
        (render-worker-process-generation worker)
        0))
      (await-response!
       worker 0 500
       (lambda (value) (render-worker-stopped? value))))
    ;; The child acknowledges shutdown while remaining group leader until the
    ;; owner reaps it.  Kill before observing a completed status: on Unix and
    ;; macOS Racket can then terminate its complete owned process group.
    (when process
      (with-handlers ([exn:fail? (lambda (_error) (void))])
        (subprocess-kill process #t)))
    (when process
      (sync/timeout 1 process)))
  (set-box! (render-worker-process-alive? worker) #f)
  (close-worker-ports! worker)
  (define custodian (render-worker-process-custodian worker))
  (when custodian
    (custodian-shutdown-all custodian))
  (void))

; render-worker-log-bytes : render-worker-process? -> immutable-bytes?
;;   Returns bounded stderr and protocol-log evidence accumulated by the supervisor.
(define (render-worker-log-bytes worker)
  (check-worker 'render-worker-log-bytes worker)
  (call-with-semaphore
   (render-worker-process-log-lock worker)
   (lambda ()
     (bytes->immutable-bytes (bytes-copy (render-worker-process-log-bytes worker))))))

; render-worker-resource-status : render-worker-process? -> immutable-hash?
;;   Reports parent-observable process, port, and reader-thread cleanup state.
(define (render-worker-resource-status worker)
  (check-worker 'render-worker-resource-status worker)
  (hasheq 'open? (render-worker-open? worker)
          'pid (render-worker-process-pid worker)
          'input-closed?
          (closed-output-port? (render-worker-process-input worker))
          'output-closed?
          (closed-input-port? (render-worker-process-output worker))
          'error-closed?
          (closed-input-port? (render-worker-process-error worker))
          'reader-dead?
          (thread-finished? (render-worker-process-reader worker))
          'error-reader-dead?
          (thread-finished? (render-worker-process-error-reader worker))))

; render-worker-write-raw-for-test! : render-worker-process? bytes? -> void?
;;   Injects raw framed bytes only for malformed-transport integration tests.
(define (render-worker-write-raw-for-test! worker bytes)
  (check-worker 'render-worker-write-raw-for-test! worker)
  (unless (bytes? bytes)
    (raise-argument-error 'render-worker-write-raw-for-test! "bytes?" bytes))
  (write-bytes bytes (render-worker-process-input worker))
  (flush-output (render-worker-process-input worker)))


;;;
;;; Spawn, Transport, and Deadlines
;;;

; spawn-render-worker! : render-worker-process? exact-positive-integer? -> void?
;;   Starts one grouped child and completes hello plus source-load handshakes.
(define (spawn-render-worker! worker startup-timeout-milliseconds)
  (unless (exact-positive-integer? startup-timeout-milliseconds)
    (raise-argument-error
     'spawn-render-worker! "exact-positive-integer?" startup-timeout-milliseconds))
  (define custodian (make-custodian))
  (set-render-worker-process-custodian! worker custodian)
  (define spawn-started (current-inexact-monotonic-milliseconds))
  (define-values (process output input error)
    (with-handlers ([exn:fail?
                     (lambda (exception)
                       (raise
                        (exn:fail:render-worker-startup
                         (format "could not launch render worker: ~a"
                                 (exn-message exception))
                         (current-continuation-marks)
                         'launch)))])
      (parameterize ([current-custodian custodian]
                     [subprocess-group-enabled #t])
        (subprocess #f #f #f
                    (render-worker-process-racket worker)
                    "-t" worker-main-path "-m"))))
  (set-render-worker-process-spawn-milliseconds!
   worker
   (- (current-inexact-monotonic-milliseconds) spawn-started))
  (set-render-worker-process-process! worker process)
  (set-render-worker-process-pid! worker (subprocess-pid process))
  (set-render-worker-process-output! worker output)
  (set-render-worker-process-input! worker input)
  (set-render-worker-process-error! worker error)
  (set-render-worker-process-events! worker (make-async-channel))
  (set-render-worker-process-event-slots!
   worker (make-semaphore render-worker-maximum-events))
  (set-box! (render-worker-process-alive? worker) #t)
  (start-reader-threads! worker)
  (define hello-started (current-inexact-monotonic-milliseconds))
  (send-message!
   worker
   (render-worker-hello
    render-worker-protocol-version
    (render-worker-process-session-id worker)
    (render-worker-process-source-fingerprint worker)
    (render-worker-process-generation worker)
    0
    "" ""))
  (define hello
    (await-response!
     worker 0 startup-timeout-milliseconds
     (lambda (value) (render-worker-hello? value))))
  (set-render-worker-process-hello-milliseconds!
   worker
   (- (current-inexact-monotonic-milliseconds) hello-started))
  (unless (equal? (render-worker-hello-animate-main-path hello)
                  (render-worker-process-expected-animate-main worker))
    (raise
     (exn:fail:render-worker-startup
      (format "worker resolved animate from ~a, expected ~a"
              (render-worker-hello-animate-main-path hello)
              (render-worker-process-expected-animate-main worker))
      (current-continuation-marks)
      'animate-collection-mismatch)))
  (define source-ready-started (current-inexact-monotonic-milliseconds))
  (send-message!
   worker
   (render-worker-load-source
    render-worker-protocol-version
    (render-worker-process-session-id worker)
    (render-worker-process-source-fingerprint worker)
    (render-worker-process-generation worker)
    0
    (render-worker-process-source worker)
    (and (render-worker-process-final-output-root worker)
         (path->string (render-worker-process-final-output-root worker)))
    (render-worker-process-input-manifest worker)))
  (define ready
    (await-response!
     worker 0 startup-timeout-milliseconds
     (lambda (value)
       (or (render-worker-source-ready? value)
           (render-worker-failed? value)))))
  (set-render-worker-process-source-ready-milliseconds!
   worker
   (- (current-inexact-monotonic-milliseconds) source-ready-started))
  (when (render-worker-failed? ready)
    (raise
     (exn:fail:render-worker-startup
      (format "worker could not load the declared source (~a): ~a"
              (render-worker-failed-phase ready)
              (render-worker-failed-message ready))
      (current-continuation-marks)
      'source-load)))
  (unless (source-ready-matches? worker ready)
    (raise
     (exn:fail:render-worker-startup
      "worker source-ready summary did not confirm the expected preparation identity"
      (current-continuation-marks)
      'source-summary-mismatch))))

; source-ready-matches? : render-worker-process? render-worker-source-ready? -> boolean?
;;   Confirms a worker loaded the parent-selected preparation manifest identity.
(define (source-ready-matches? worker ready)
  (define source (render-worker-process-source worker))
  (cond
    [(render-worker-module-builder-source? source)
     (define manifest
       (render-worker-module-builder-source-preparation-manifest source))
     (equal?
      (hash-ref (render-worker-source-ready-source-summary ready)
                'preparation-identity
                #f)
      (and manifest (render-preparation-manifest-identity manifest)))]
    [else #t]))

; start-reader-threads! : render-worker-process? -> void?
;;   Continuously drains protocol and stderr pipes under the worker custodian.
(define (start-reader-threads! worker)
  (define custodian (render-worker-process-custodian worker))
  (set-render-worker-process-reader!
   worker
   (parameterize ([current-custodian custodian])
     (thread
      (lambda ()
        (with-handlers ([exn:fail?
                         (lambda (error)
                           (queue-event!
                            worker
                            (render-worker-event 'transport-error
                                                 (exn-message error))))])
          (let loop ()
            (define value
              (read-render-worker-message (render-worker-process-output worker)))
            (if (eof-object? value)
                (queue-event! worker (render-worker-event 'eof 'eof))
                (begin
                  (queue-event! worker (render-worker-event 'message value))
                  (loop)))))))))
  (set-render-worker-process-error-reader!
   worker
   (parameterize ([current-custodian custodian])
     (thread
     (lambda ()
       (define buffer (make-bytes 4096))
       (let loop ()
         (define count
           (read-bytes-avail!*
            buffer
            (render-worker-process-error worker)))
         (cond
           [(eof-object? count) (void)]
           [(positive? count)
            (append-worker-log! worker (subbytes buffer 0 count))
            (loop)]
           [else
            (sync (render-worker-process-error worker))
            (loop)])))))))

; queue-event! : render-worker-process? render-worker-event? -> void?
;;   Enqueues one bounded transport event or terminates an overflowing worker.
(define (queue-event! worker event)
  (if (semaphore-try-wait? (render-worker-process-event-slots worker))
      (async-channel-put (render-worker-process-events worker) event)
      (begin
        (append-worker-log! worker #"render worker event queue exceeded limit\n")
        (set-box! (render-worker-process-alive? worker) #f)
        (let ([process (render-worker-process-process worker)])
          (when (and process (eq? (subprocess-status process) 'running))
            (subprocess-kill process #t))))))

; send-message! : render-worker-process? render-worker-message? -> void?
;;   Writes one validated request to the owned child input port.
(define (send-message! worker message)
  (unless (render-worker-open? worker)
    (raise
     (exn:fail:render-worker-crashed
      "render worker is not open"
      (current-continuation-marks)
      'not-open)))
  (with-handlers ([exn:fail?
                   (lambda (error)
                     (set-box! (render-worker-process-alive? worker) #f)
                     (raise
                      (exn:fail:render-worker-crashed
                       (format "could not write worker protocol message: ~a"
                               (exn-message error))
                       (current-continuation-marks)
                       'write)))])
    (write-render-worker-message! (render-worker-process-input worker) message)))

; await-response! : render-worker-process? exact-nonnegative-integer?
;                   exact-positive-integer? (-> render-worker-response? boolean?)
;                   [#:canceled? (-> boolean?)] -> render-worker-response?
;;   Waits against a monotonic deadline while rejecting stale or malformed replies.
(define (await-response! worker request-id timeout-milliseconds accept?
                         #:canceled? [canceled? (lambda () #f)])
  (define deadline
    (+ (current-inexact-monotonic-milliseconds) timeout-milliseconds))
  (let loop ()
    (when (canceled?)
      (raise
       (exn:fail:render-worker-canceled
        (format "render worker request ~a was canceled" request-id)
        (current-continuation-marks)
        request-id)))
    (define remaining (- deadline (current-inexact-monotonic-milliseconds)))
    (when (<= remaining 0)
      (raise
       (exn:fail:render-worker-timeout
        (format "render worker request ~a timed out" request-id)
        (current-continuation-marks)
        request-id)))
    (define event
      (sync/timeout (/ (min remaining 50) 1000)
                    (render-worker-process-events worker)))
    (cond
      [(not event) (loop)]
      [else
       (semaphore-post (render-worker-process-event-slots worker))
       (case (render-worker-event-kind event)
         [(transport-error)
          (set-box! (render-worker-process-alive? worker) #f)
          (raise
           (exn:fail:render-worker-crashed
            (format "render worker protocol failed: ~a"
                    (render-worker-event-value event))
            (current-continuation-marks)
            'protocol))]
         [(eof)
          (set-box! (render-worker-process-alive? worker) #f)
          (raise
           (exn:fail:render-worker-crashed
            "render worker closed its protocol output"
            (current-continuation-marks)
            'eof))]
         [else
          (define value (render-worker-event-value event))
          (cond
            [(not (render-worker-message-matches?
                   value
                   (render-worker-process-session-id worker)
                   (render-worker-process-source-fingerprint worker)
                   (render-worker-process-generation worker)
                   request-id))
             (append-worker-log!
              worker
              #"discarded stale worker response with a mismatched identity\n")
             (loop)]
            [(render-worker-log? value)
             (append-worker-log!
              worker
              (string->bytes/utf-8
               (string-append (render-worker-log-message value) "\n")))
             (loop)]
            [(accept? value) value]
            [else (loop)])])])))

; append-worker-log! : render-worker-process? bytes? -> void?
;;   Retains only the newest bounded log suffix while continuously draining pipes.
(define (append-worker-log! worker bytes)
  (call-with-semaphore
   (render-worker-process-log-lock worker)
   (lambda ()
     (define combined
       (bytes-append (render-worker-process-log-bytes worker) bytes))
     (set-render-worker-process-log-bytes!
      worker
      (if (> (bytes-length combined) render-worker-maximum-log-bytes)
          (subbytes combined
                    (- (bytes-length combined) render-worker-maximum-log-bytes))
          combined)))))

; close-worker-ports! : render-worker-process? -> void?
;;   Closes every parent endpoint so blocked child and reader operations release.
(define (close-worker-ports! worker)
  (for ([port (in-list (list (render-worker-process-input worker)
                             (render-worker-process-output worker)
                             (render-worker-process-error worker)))])
    (when port
      (with-handlers ([exn:fail? (lambda (_error) (void))])
        (if (output-port? port)
            (close-output-port port)
            (close-input-port port))))))

; fresh-session-id : -> string?
;;   Creates an execution-only identifier outside source/build identity.
(define (fresh-session-id)
  (format "render-worker-~a" (current-inexact-monotonic-milliseconds)))

; bounded-session-id? : any/c -> boolean?
;;   Recognizes one bounded protocol session string.
(define (bounded-session-id? value)
  (and (string? value) (source-transfer-data? value)))

; closed-input-port? : any/c -> boolean?
;;   Reports closed status without assuming an absent port is an open resource.
(define (closed-input-port? value)
  (or (not value) (and (input-port? value) (port-closed? value))))

; closed-output-port? : any/c -> boolean?
;;   Reports closed status without assuming an absent port is an open resource.
(define (closed-output-port? value)
  (or (not value) (and (output-port? value) (port-closed? value))))

; thread-finished? : any/c -> boolean?
;;   Treats an absent reader as finished after startup or cleanup failure.
(define (thread-finished? value)
  (or (not value) (and (thread? value) (thread-dead? value))))

; check-worker : symbol? any/c -> void?
;;   Validates one supervisor value at the public lifecycle boundary.
(define (check-worker who value)
  (unless (render-worker-process? value)
    (raise-argument-error who "render-worker-process?" value)))
