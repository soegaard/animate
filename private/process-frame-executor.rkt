#lang racket/base

;;;
;;; Subprocess Final Frame Executor
;;;

;; Owns the bounded final-frame scheduler, session staging directory, and final
;; publication.  Worker process lifecycle and protocol transport remain in the
;; shared render-worker supervisor.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/async-channel
         racket/file
         racket/list
         racket/path
         "camera.rkt"
         "render-frame-job.rkt"
         "render-job-plan.rkt"
         "render-preparation-manifest.rkt"
         "render-source-model.rkt"
         "render-worker-process.rkt"
         "render-worker-protocol.rkt")

;; Exports
(provide process-frame-assignment?
         process-frame-assignment-source-frame-index
         process-frame-assignment-output-frame-index
         process-frame-assignment-request-id
         process-frame-assignment-worker-pid
         process-frame-assignment-elapsed-milliseconds
         process-frame-failure?
         process-frame-failure-source-frame-index
         process-frame-failure-output-frame-index
         process-frame-failure-phase
         process-frame-failure-message
         process-frame-execution-report?
         process-frame-execution-report-output-paths
         process-frame-execution-report-requested-workers
         process-frame-execution-report-workers-started
         process-frame-execution-report-workers-completing
         process-frame-execution-report-requested-frame-count
         process-frame-execution-report-completed-frame-count
         process-frame-execution-report-source-frame-indices
         process-frame-execution-report-output-frame-indices
         process-frame-execution-report-assignments
         process-frame-execution-report-worker-pids
         process-frame-execution-report-worker-resource-statuses
         process-frame-execution-report-startup-milliseconds
         process-frame-execution-report-worker-timings
         process-frame-execution-report-raster-execution-milliseconds
         process-frame-execution-report-publication-milliseconds
         process-frame-execution-report-elapsed-milliseconds
         process-frame-execution-report-failure
         process-frame-execution-report-canceled?
         process-frame-execution-report-persistent-cache-hit-count
         process-frame-execution-report-frame-reuse-alias-count
         process-frame-execution-report-representative-frame-count
         process-frame-execution-report-rasterized-frame-count
         process-frame-execution-report-materialized-frame-count
         process-frame-execution-report-input-verification-events
         process-frame-execution-report-input-verification-failures
         exn:fail:process-frame-execution?
         exn:fail:process-frame-execution-report
         render-final-frame-jobs!)


;;;
;;; Immutable Diagnostics
;;;

(struct process-frame-assignment
  (source-frame-index output-frame-index request-id worker-pid elapsed-milliseconds)
  #:transparent)

;; process-frame-assignment records one accepted worker completion.
;;  - source-frame-index is the original sampled source index.
;;  - output-frame-index is the caller-visible local sequence slot.
;;  - request-id/worker-pid are execution evidence, not visual inputs.
;;  - elapsed-milliseconds is the parent-observed request duration.

(struct process-frame-failure
  (source-frame-index output-frame-index phase message)
  #:transparent)

;; process-frame-failure records the first fail-fast session error.
;;  - source-frame-index/output-frame-index are #f when no frame was assigned.
;;  - phase classifies startup, render, protocol, timeout, cancellation, or
;;    publication failure without embedding unbounded worker output.
;;  - message is a bounded diagnostic copied from the responsible exception.

(struct process-frame-execution-report
  (output-paths requested-workers workers-started workers-completing
                requested-frame-count completed-frame-count source-frame-indices
                output-frame-indices assignments worker-pids worker-resource-statuses
                startup-milliseconds elapsed-milliseconds failure canceled?
                persistent-cache-hit-count frame-reuse-alias-count
                representative-frame-count rasterized-frame-count
                materialized-frame-count input-verification-events
                input-verification-failures worker-timings
                raster-execution-milliseconds publication-milliseconds)
  #:transparent)

;; process-frame-execution-report describes one closed subprocess frame session.
;;  - output-paths are in increasing local output-frame-index order on success.
;;  - requested-workers is capacity; workers-started is the actual child count.
;;  - workers-completing counts distinct PIDs with at least one accepted frame.
;;  - source-frame-indices/output-frame-indices preserve the canonical output map.
;;  - assignments retain completion evidence in deterministic output-slot order.
;;  - worker-pids/resource-statuses are parent-observable lifecycle evidence.
;;  - worker-timings records parent-observed spawn/hello/source-ready latencies
;;    and each worker's all-ready-to-loop-exit raster span in start order.
;;  - raster-execution-milliseconds spans all workers ready through their final
;;    raster completion; publication-milliseconds covers final materialization
;;    and publication after raster work is complete.
;;  - failure/canceled? describe an unsuccessful fail-fast session.

(struct exn:fail:process-frame-execution exn:fail (report)
  #:transparent)

(struct exn:fail:process-frame-input exn:fail (detail)
  #:transparent)

;; exn:fail:process-frame-execution carries the closed failure report after all
;; owned workers and staging files have been cleaned.


;;;
;;; Final Frame Session
;;;

; render-final-frame-jobs! : render-worker-source? (listof final-render-frame-job?)
;                            path-string? [#:workers exact-positive-integer?]
;                            [#:racket path-string?]
;                            [#:startup-timeout-milliseconds exact-positive-integer?]
;                            [#:frame-timeout-milliseconds exact-positive-integer?]
;                            [#:input-manifest (or/c render-input-manifest? false/c)]
;                            [#:reuse-plan (or/c render-frame-reuse-plan? false/c)]
;                            [#:persistent-cache-output-indices (listof exact-nonnegative-integer?)]
;                            [#:canceled? (-> boolean?)]
;                            -> process-frame-execution-report?
;;   Renders all jobs through persistent child processes and publishes only a
;;   complete ordered PNG set. One failure or cancellation aborts the session.
(define (render-final-frame-jobs! source jobs output-directory
                                  #:workers [requested-workers 1]
                                  #:racket [racket (find-system-path 'exec-file)]
                                  #:startup-timeout-milliseconds
                                  [startup-timeout-milliseconds 10000]
                                  #:frame-timeout-milliseconds
                                  [frame-timeout-milliseconds 60000]
                                  #:input-manifest [input-manifest #f]
                                  #:reuse-plan [reuse-plan #f]
                                  #:persistent-cache-output-indices
                                  [persistent-cache-output-indices '()]
                                  #:canceled? [canceled? (lambda () #f)])
  (unless (render-worker-source? source)
    (raise-argument-error 'render-final-frame-jobs! "render-worker-source?" source))
  (unless (and (list? jobs) (andmap final-render-frame-job-valid? jobs))
    (raise-argument-error
     'render-final-frame-jobs! "(listof final-render-frame-job?)" jobs))
  (unless (path-string? output-directory)
    (raise-argument-error 'render-final-frame-jobs! "path-string?" output-directory))
  (unless (exact-positive-integer? requested-workers)
    (raise-argument-error
     'render-final-frame-jobs! "exact-positive-integer? as #:workers" requested-workers))
  (unless (path-string? racket)
    (raise-argument-error 'render-final-frame-jobs! "path-string? as #:racket" racket))
  (unless (exact-positive-integer? startup-timeout-milliseconds)
    (raise-argument-error
     'render-final-frame-jobs!
     "exact-positive-integer? as #:startup-timeout-milliseconds"
     startup-timeout-milliseconds))
  (unless (exact-positive-integer? frame-timeout-milliseconds)
    (raise-argument-error
     'render-final-frame-jobs!
     "exact-positive-integer? as #:frame-timeout-milliseconds"
     frame-timeout-milliseconds))
  (unless (or (not input-manifest) (render-input-manifest? input-manifest))
    (raise-argument-error
     'render-final-frame-jobs!
     "(or/c render-input-manifest? false/c) as #:input-manifest"
     input-manifest))
  (unless (or (not reuse-plan) (render-frame-reuse-plan? reuse-plan))
    (raise-argument-error
     'render-final-frame-jobs!
     "(or/c render-frame-reuse-plan? false/c) as #:reuse-plan"
     reuse-plan))
  (unless (and (list? persistent-cache-output-indices)
               (andmap exact-nonnegative-integer?
                       persistent-cache-output-indices)
               (= (length persistent-cache-output-indices)
                  (length (remove-duplicates persistent-cache-output-indices))))
    (raise-argument-error
     'render-final-frame-jobs!
     "a duplicate-free list of exact-nonnegative-integer? persistent cache output slots"
     persistent-cache-output-indices))
  (unless (procedure? canceled?)
    (raise-argument-error 'render-final-frame-jobs! "procedure? as #:canceled?" canceled?))
  (define ordered-jobs
    (sort jobs < #:key final-render-frame-job-output-frame-index))
  (if (null? ordered-jobs)
      (empty-session-report requested-workers)
      (begin
        (validate-job-set! ordered-jobs)
        (validate-reuse-plan! ordered-jobs reuse-plan)
        (render-nonempty-final-frame-jobs!
         source ordered-jobs output-directory requested-workers racket
         startup-timeout-milliseconds frame-timeout-milliseconds input-manifest
         reuse-plan persistent-cache-output-indices canceled?))))

; render-nonempty-final-frame-jobs! : render-worker-source? nonempty-list? path-string?
;                                       exact-positive-integer? path-string?
;                                       exact-positive-integer? exact-positive-integer?
;                                       (or/c render-input-manifest? false/c)
;                                       (or/c render-frame-reuse-plan? false/c)
;                                       (listof exact-nonnegative-integer?)
;                                       (-> boolean?) -> process-frame-execution-report?
;;   Owns staging, dynamic scheduling, shutdown, validation, and publication.
(define (render-nonempty-final-frame-jobs! source ordered-jobs output-directory
                                           requested-workers racket
                                           startup-timeout-milliseconds
                                           frame-timeout-milliseconds input-manifest
                                           reuse-plan persistent-cache-output-indices
                                           canceled?)
  (define started-at (current-inexact-monotonic-milliseconds))
  (define session-id (final-render-frame-job-session-id (car ordered-jobs)))
  (define source-fingerprint
    (final-render-frame-job-source-fingerprint (car ordered-jobs)))
  (define generation (final-render-frame-job-generation (car ordered-jobs)))
  (define representative-output-indices
    (if reuse-plan
        (render-frame-reuse-plan-representative-output-indices reuse-plan)
        (map final-render-frame-job-output-frame-index ordered-jobs)))
  (define cached-output-indices
    (sort persistent-cache-output-indices <))
  (define all-output-indices
    (map final-render-frame-job-output-frame-index ordered-jobs))
  (unless (andmap (lambda (output-index)
                    (member output-index all-output-indices))
                  cached-output-indices)
    (raise-arguments-error
     'render-final-frame-jobs!
     "persistent cache hits within this output plan"
     "persistent-cache-output-indices" cached-output-indices))
  (define raster-jobs
    (for/list ([job (in-list ordered-jobs)]
               #:when (member (final-render-frame-job-output-frame-index job)
                              representative-output-indices)
               #:unless (member (final-render-frame-job-output-frame-index job)
                                cached-output-indices))
      job))
  (define reuse-mapping
    (if reuse-plan
        (render-frame-reuse-plan-output->representative reuse-plan)
        (for/list ([job (in-list ordered-jobs)])
          (cons (final-render-frame-job-output-frame-index job)
                (final-render-frame-job-output-frame-index job)))))
  (define worker-capacity (min requested-workers (length raster-jobs)))
  (define workers '())
  (define published-paths '())
  (define staging-root #f)
  (define state-lock (make-semaphore 1))
  (define next-job-index 0)
  (define failure #f)
  (define canceled-session? #f)
  (define completions (make-hash))
  (define assignments (make-hash))
  (define input-verification-events 0)
  (define input-verification-failures '())
  (define startup-milliseconds #f)
  (define worker-ready-timings '())
  (define worker-raster-spans (make-hash))
  (define raster-execution-milliseconds #f)
  (define publication-milliseconds #f)

  ; verify-inputs! : symbol? -> void?
  ;;   Checks the known local input snapshot at every session integrity boundary.
  (define (verify-inputs! phase)
    (when input-manifest
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (set! input-verification-failures
                               (cons (string->immutable-string
                                      (format "~a: ~a" phase (exn-message error)))
                                     input-verification-failures))
                         (raise
                          (exn:fail:process-frame-input
                           (format "tracked input changed during ~a: ~a"
                                   phase (exn-message error))
                           (current-continuation-marks)
                           phase)))])
        (verify-render-input-manifest! input-manifest)
        (set! input-verification-events (add1 input-verification-events))))
    (void))

  ; make-report : (listof path?) -> process-frame-execution-report?
  ;;   Freezes current scheduler evidence after owned processes are stopped.
  (define (make-report output-paths)
    (define completed-output-indices (sort (hash-keys completions) <))
    (define ordered-assignments
      (for/list ([output-index (in-list completed-output-indices)])
        (hash-ref assignments output-index)))
    (define completed-pids
      (remove-duplicates
       (map process-frame-assignment-worker-pid ordered-assignments)))
    (process-frame-execution-report
     output-paths
     requested-workers
     (length workers)
     (length completed-pids)
     (length ordered-jobs)
     (length completed-output-indices)
     (map final-render-frame-job-source-frame-index ordered-jobs)
     (map final-render-frame-job-output-frame-index ordered-jobs)
     ordered-assignments
     (map render-worker-pid workers)
     (for/list ([worker (in-list workers)])
       (render-worker-resource-status worker))
     startup-milliseconds
     (- (current-inexact-monotonic-milliseconds) started-at)
     failure
     canceled-session?
     (length cached-output-indices)
     (for/sum ([mapping (in-list reuse-mapping)])
       (if (= (car mapping) (cdr mapping)) 0 1))
     (length raster-jobs)
     (length completed-output-indices)
     (length output-paths)
     input-verification-events
     (reverse input-verification-failures)
     (for/list ([timing (in-list worker-ready-timings)])
       (hash-set timing
                 'raster-execution-span-milliseconds
                 (hash-ref worker-raster-spans (hash-ref timing 'pid) #f)))
     raster-execution-milliseconds
     publication-milliseconds))

  ; stop-workers! : -> void?
  ;;   Reaps every process before any owned staging directory is removed.
  (define (stop-workers!)
    (for ([worker (in-list workers)])
      (with-handlers ([exn:fail? (lambda (_error) (void))])
        (render-worker-stop! worker))))

  ; remove-staging! : -> void?
  ;;   Removes only the session directory allocated by this executor.
  (define (remove-staging!)
    (when (and staging-root (directory-exists? staging-root))
      (delete-directory/files staging-root)))

  ; abort! : process-frame-failure? -> none/c
  ;;   Releases every owned resource before exposing a report-bearing failure.
  (define (abort! session-failure)
    (set! failure session-failure)
    (stop-workers!)
    (remove-staging!)
    (raise
     (exn:fail:process-frame-execution
      (format "final subprocess frame session failed during ~a: ~a"
              (process-frame-failure-phase session-failure)
              (process-frame-failure-message session-failure))
      (current-continuation-marks)
      (make-report '()))))

  (with-handlers
      ([exn:fail:process-frame-execution? raise]
       [exn:fail?
        (lambda (error)
          (abort! (exception->process-frame-failure #f error)))])
    (make-directory* output-directory)
    (ensure-output-slots-available!
     ordered-jobs output-directory cached-output-indices)
    (verify-inputs! 'before-worker-startup)
    (set! staging-root
          (make-temporary-file ".animate-process-frame-~a" 'directory output-directory))
    (stage-persistent-cache-hits!
     ordered-jobs output-directory staging-root cached-output-indices)
    (define startup-started (current-inexact-monotonic-milliseconds))
    ;; Starting every child before waiting for all source-ready handshakes avoids
    ;; multiplying independent process/module initialization by worker capacity.
    ;; Results are collected by slot, not completion race, so report ordering and
    ;; subsequent dynamic raster scheduling remain deterministic.
    (define startup-events (make-async-channel))
    (define startup-results (make-vector worker-capacity #f))
    (define startup-threads
      (for/list ([slot (in-range worker-capacity)])
        (thread
         (lambda ()
           (with-handlers
               ([exn:fail?
                 (lambda (error)
                   (async-channel-put startup-events (cons slot error)))])
             (define worker-started (current-inexact-monotonic-milliseconds))
             (define worker
               (start-render-worker!
                source
                #:racket racket
                #:session-id session-id
                #:source-fingerprint source-fingerprint
                #:generation generation
                #:final-output-root staging-root
                #:input-manifest input-manifest
                #:startup-timeout-milliseconds startup-timeout-milliseconds))
             (async-channel-put
              startup-events
              (cons slot
                    (hasheq
                     'worker worker
                     'ready-latency-milliseconds
                     (- (current-inexact-monotonic-milliseconds) startup-started)
                     'worker-startup-milliseconds
                     (- (current-inexact-monotonic-milliseconds) worker-started)))))))))
    (for ([ignored (in-range worker-capacity)])
      (define event (async-channel-get startup-events))
      (vector-set! startup-results (car event) (cdr event)))
    (for ([startup-thread (in-list startup-threads)])
      (thread-wait startup-thread))
    (for ([result (in-vector startup-results)])
      (cond
        [(exn:fail? result)
         ;; Successful peers are already in workers, so the outer failure path
         ;; stops and reaps them before it removes the staging directory.
         (raise result)]
        [else
         (define worker (hash-ref result 'worker))
         (set! workers (append workers (list worker)))
         (set! worker-ready-timings
               (append
                worker-ready-timings
                (list
                 (hasheq
                  'pid (render-worker-pid worker)
                  'ready-latency-milliseconds
                  (hash-ref result 'ready-latency-milliseconds)
                  'startup-milliseconds
                  (hash-ref result 'worker-startup-milliseconds)
                  'spawn-milliseconds (render-worker-spawn-milliseconds worker)
                  'hello-milliseconds (render-worker-hello-milliseconds worker)
                  'source-ready-milliseconds
                  (render-worker-source-ready-milliseconds worker)))))
         ;; Every child verifies the manifest before reporting ready. Repeat the
         ;; parent-side check for every accepted worker before assigning frames.
         (verify-inputs! 'after-worker-ready)]))
    (set! startup-milliseconds
          (- (current-inexact-monotonic-milliseconds) startup-started))

    ; mark-failure! : (or/c final-render-frame-job? false/c) exn:fail? -> void?
    ;;   Records only the first fail-fast outcome and stops future assignment.
    (define (mark-failure! job error)
      (call-with-semaphore
       state-lock
       (lambda ()
         (unless failure
           (set! failure (exception->process-frame-failure job error)))))
      (void))

    ; next-job! : -> (or/c final-render-frame-job? false/c)
    ;;   Assigns one pending job dynamically while preserving a canonical plan.
    (define (next-job!)
      (call-with-semaphore
       state-lock
       (lambda ()
         (cond
           [failure #f]
           [(canceled?)
            (set! canceled-session? #t)
            (set! failure
                  (process-frame-failure #f #f 'canceled
                                         "final subprocess frame session was canceled"))
            #f]
           [(>= next-job-index (length raster-jobs)) #f]
           [else
            (define job (list-ref raster-jobs next-job-index))
            (set! next-job-index (add1 next-job-index))
            job]))))

    ; accept-completion! : render-worker-process? final-render-frame-job?
    ;                       render-worker-final-frame-complete? nonnegative-real? -> void?
    ;;   Validates one metadata-only response before its staging file is accepted.
    (define (accept-completion! worker job completion elapsed-milliseconds)
      (validate-final-completion! completion job staging-root)
      (call-with-semaphore
       state-lock
       (lambda ()
         (unless failure
           (define output-index (final-render-frame-job-output-frame-index job))
           (hash-set! completions output-index completion)
           (hash-set!
            assignments
            output-index
            (process-frame-assignment
             (final-render-frame-job-source-frame-index job)
             output-index
             (final-render-frame-job-request-id job)
             (render-worker-pid worker)
             elapsed-milliseconds)))))
      (void))

    ; worker-loop : render-worker-process? -> void?
    ;;   Lets one persistent child take one job at a time until the queue closes.
    (define (worker-loop worker)
      (define loop-started (current-inexact-monotonic-milliseconds))
      (dynamic-wind
       void
       (lambda ()
         (let loop ()
           (define job (next-job!))
           (when job
             (with-handlers ([exn:fail?
                              (lambda (error) (mark-failure! job error))])
               (define frame-started (current-inexact-monotonic-milliseconds))
               (define completion
                 (render-worker-render-final-frame!
                  worker job
                  #:timeout-milliseconds frame-timeout-milliseconds
                  #:canceled? canceled?))
               (accept-completion!
                worker job completion
                (- (current-inexact-monotonic-milliseconds) frame-started)))
             (loop))))
       (lambda ()
         (call-with-semaphore
          state-lock
          (lambda ()
            (hash-set! worker-raster-spans
                       (render-worker-pid worker)
                       (- (current-inexact-monotonic-milliseconds) loop-started)))))))

    (define raster-started (current-inexact-monotonic-milliseconds))
    (define worker-threads
      (for/list ([worker (in-list workers)])
        (thread (lambda () (worker-loop worker)))))
    (for ([worker-thread (in-list worker-threads)])
      (thread-wait worker-thread))
    (set! raster-execution-milliseconds
          (- (current-inexact-monotonic-milliseconds) raster-started))
    (when failure
      (abort! failure))
    (define publication-started (current-inexact-monotonic-milliseconds))
    (verify-inputs! 'before-reuse-materialization)
    (materialize-frame-reuse! reuse-mapping staging-root)
    (verify-inputs! 'before-publication)
    (stop-workers!)
    (define output-paths
      (publish-complete-output-set!
       ordered-jobs staging-root output-directory cached-output-indices))
    (set! publication-milliseconds
          (- (current-inexact-monotonic-milliseconds) publication-started))
    (remove-staging!)
    (make-report output-paths)))


;;;
;;; Validation and Publication
;;;

; validate-job-set! : nonempty-list? -> void?
;;   Requires one session identity and a contiguous deterministic output plan.
(define (validate-job-set! ordered-jobs)
  (define first-job (car ordered-jobs))
  (define expected-output-indices (build-list (length ordered-jobs) values))
  (unless (equal? (map final-render-frame-job-output-frame-index ordered-jobs)
                  expected-output-indices)
    (raise-arguments-error
     'render-final-frame-jobs!
     "jobs with each contiguous output-frame-index exactly once"
     "output-frame-indices"
     (map final-render-frame-job-output-frame-index ordered-jobs)))
  (for ([job (in-list ordered-jobs)])
    (unless (and (equal? (final-render-frame-job-session-id job)
                         (final-render-frame-job-session-id first-job))
                 (equal? (final-render-frame-job-source-fingerprint job)
                         (final-render-frame-job-source-fingerprint first-job))
                 (= (final-render-frame-job-generation job)
                    (final-render-frame-job-generation first-job)))
      (raise-arguments-error
       'render-final-frame-jobs!
       "jobs with one session, source fingerprint, and generation"
       "job" job)))
  (define request-ids (map final-render-frame-job-request-id ordered-jobs))
  (unless (= (length request-ids) (length (remove-duplicates request-ids)))
    (raise-arguments-error
     'render-final-frame-jobs!
     "jobs with distinct request identities"
     "request-ids" request-ids)))

; validate-reuse-plan! : nonempty-list? (or/c render-frame-reuse-plan? false/c) -> void?
;;   Ensures a generic reuse map covers exactly this caller's source/output plan.
(define (validate-reuse-plan! ordered-jobs reuse-plan)
  (when reuse-plan
    (define expected-source-indices
      (map final-render-frame-job-source-frame-index ordered-jobs))
    (define expected-output-indices
      (map final-render-frame-job-output-frame-index ordered-jobs))
    (unless (and (equal? expected-source-indices
                        (render-frame-reuse-plan-source-frame-indices reuse-plan))
                 (equal? expected-output-indices
                         (map car
                              (render-frame-reuse-plan-output->representative
                               reuse-plan))))
      (raise-arguments-error
       'render-final-frame-jobs!
       "a reuse plan for this exact ordered source/output frame list"
       "reuse-plan" reuse-plan))
    (for ([mapping (in-list
                    (render-frame-reuse-plan-output->representative reuse-plan))])
      (unless (member (cdr mapping) expected-output-indices)
        (raise-arguments-error
         'render-final-frame-jobs!
         "reuse representatives within the requested output slots"
         "mapping" mapping)))))

; empty-session-report : exact-positive-integer? -> process-frame-execution-report?
;;   Describes a zero-job plan without creating a worker or output directory.
(define (empty-session-report requested-workers)
  (process-frame-execution-report
   '() requested-workers 0 0 0 0 '() '() '() '() '() 0 0 #f #f
   0 0 0 0 0 0 '() '() 0 0))

; ensure-output-slots-available! : nonempty-list? path-string? immutable-list? -> void?
;;   Refuses to overwrite paths that this session did not create or verify as hits.
(define (ensure-output-slots-available! ordered-jobs output-directory cached-output-indices)
  (for ([job (in-list ordered-jobs)])
    (define output-path
      (build-path output-directory (final-render-frame-job-output-name job)))
    (define cached?
      (member (final-render-frame-job-output-frame-index job)
              cached-output-indices))
    (when (and (or (file-exists? output-path)
                   (directory-exists? output-path))
               (not cached?))
      (raise-arguments-error
       'render-final-frame-jobs!
       "unused output paths for every requested frame"
       "output-path" output-path))
    (when (and cached? (not (file-exists? output-path)))
      (raise-arguments-error
       'render-final-frame-jobs!
       "an existing regular file for every declared persistent cache hit"
       "output-path" output-path))))

; stage-persistent-cache-hits! : nonempty-list? path-string? path? immutable-list? -> void?
;;   Copies verified existing frame hits into owned staging for reuse materialization.
(define (stage-persistent-cache-hits! ordered-jobs output-directory staging-root cached-output-indices)
  (for ([job (in-list ordered-jobs)]
        #:when (member (final-render-frame-job-output-frame-index job)
                       cached-output-indices))
    (copy-file
     (build-path output-directory (final-render-frame-job-output-name job))
     (build-path staging-root (final-render-frame-job-output-name job))
     #f))
  (void))

; validate-final-completion! : render-worker-final-frame-complete?
;                              final-render-frame-job? path? -> void?
;;   Accepts only an assigned metadata response and its complete staging PNG.
(define (validate-final-completion! completion job staging-root)
  (unless (and (equal? (render-worker-final-frame-complete-source-frame-index completion)
                       (final-render-frame-job-source-frame-index job))
               (= (render-worker-final-frame-complete-output-frame-index completion)
                  (final-render-frame-job-output-frame-index job))
               (equal? (render-worker-final-frame-complete-output-name completion)
                       (final-render-frame-job-output-name job)))
    (raise-arguments-error
     'render-final-frame-jobs!
     "a completion matching the assigned source and output frame identity"
     "completion" completion))
  (define staged-path
    (build-path staging-root (final-render-frame-job-output-name job)))
  (define png-dimensions (png-file-dimensions staged-path))
  (unless (and (file-exists? staged-path)
               (= (file-size staged-path)
                  (render-worker-final-frame-complete-byte-count completion))
               png-dimensions
               (= (car png-dimensions)
                  (render-worker-final-frame-complete-width completion))
               (= (cdr png-dimensions)
                  (render-worker-final-frame-complete-height completion)))
    (raise-arguments-error
     'render-final-frame-jobs!
     "a complete worker-published PNG matching its completion metadata"
     "staging-path" staged-path))
  (define expected-dimensions (job-pixel-dimensions job))
  (when expected-dimensions
    (unless (and (= (car expected-dimensions)
                    (render-worker-final-frame-complete-width completion))
                 (= (cdr expected-dimensions)
                    (render-worker-final-frame-complete-height completion)))
      (raise-arguments-error
       'render-final-frame-jobs!
       "completion dimensions matching the requested static camera and supersample"
       "completion" completion))))

; job-pixel-dimensions : final-render-frame-job? -> (or/c pair? false/c)
;;   Computes the expected raster size when a job carries a static camera.
(define (job-pixel-dimensions job)
  (define camera (datum->final-render-camera (final-render-frame-job-camera-datum job)))
  (and camera
       (cons (* (camera-width camera) (final-render-frame-job-supersample job))
             (* (camera-height camera) (final-render-frame-job-supersample job)))))

; png-file-dimensions : path? -> (or/c pair? false/c)
;;   Reads PNG signature, IHDR dimensions, and no pixels from worker output.
(define (png-file-dimensions path)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (call-with-input-file
     path
     (lambda (input)
       (define header (read-bytes 24 input))
       (and (bytes? header)
            (= (bytes-length header) 24)
            (bytes=? (subbytes header 0 8) #"\211PNG\r\n\032\n")
            (bytes=? (subbytes header 12 16) #"IHDR")
            (cons (png-header-natural header 16)
                  (png-header-natural header 20)))))))

; png-header-natural : bytes? exact-nonnegative-integer? -> exact-nonnegative-integer?
;;   Decodes one four-byte big-endian PNG integer after the header length check.
(define (png-header-natural header start)
  (+ (arithmetic-shift (bytes-ref header start) 24)
     (arithmetic-shift (bytes-ref header (+ start 1)) 16)
     (arithmetic-shift (bytes-ref header (+ start 2)) 8)
     (bytes-ref header (+ start 3))))

; materialize-frame-reuse! : immutable-list? path? -> void?
;;   Copies validated representative staging PNGs into their requested alias slots.
(define (materialize-frame-reuse! mappings staging-root)
  (for ([mapping (in-list mappings)]
        #:unless (= (car mapping) (cdr mapping)))
    (define representative-path
      (build-path staging-root (final-render-output-name (cdr mapping))))
    (define alias-path
      (build-path staging-root (final-render-output-name (car mapping))))
    (unless (file-exists? representative-path)
      (raise-arguments-error
       'materialize-frame-reuse!
       "a completed representative staging PNG"
       "representative-output-index" (cdr mapping)))
    (when (directory-exists? alias-path)
      (raise-arguments-error
       'materialize-frame-reuse!
       "a file alias staging path, not a directory"
       "alias-output-index" (car mapping)))
    ;; A persistent cache hit can already occupy an alias slot.  Keep that
    ;; verified staged file; otherwise materialize from its representative.
    (unless (file-exists? alias-path)
      ;; A copy, rather than a hard link, preserves the established ownership
      ;; model for later individual replacement and cross-filesystem installation.
      (copy-file representative-path alias-path #f)))
  (void))

; publish-complete-output-set! : nonempty-list? path? path-string? immutable-list?
;                                 -> (listof path?)
;;   Moves only a validated complete staging set into final slot order.
(define (publish-complete-output-set! ordered-jobs staging-root output-directory
                                      cached-output-indices)
  (define published '())
  (with-handlers
      ([exn:fail?
        (lambda (error)
          ;; Every path here was created by this session after the preflight
          ;; no-overwrite check, so rollback cannot remove user-owned output.
          (for ([path (in-list published)])
            (when (file-exists? path)
              (delete-file path)))
          (raise error))])
    (for/list ([job (in-list ordered-jobs)])
      (define staged-path
        (build-path staging-root (final-render-frame-job-output-name job)))
      (define final-path
        (build-path output-directory (final-render-frame-job-output-name job)))
      (define cached?
        (member (final-render-frame-job-output-frame-index job)
                cached-output-indices))
      (when (and (or (file-exists? final-path)
                     (directory-exists? final-path))
                 (not cached?))
        (raise-arguments-error
         'publish-complete-output-set!
         "an output path that remained unused until publication"
         "output-path" final-path))
      (unless (file-exists? staged-path)
        (raise-arguments-error
         'publish-complete-output-set!
         "a complete staging PNG for every requested output slot"
         "staged-path" staged-path))
      (unless cached?
        (rename-file-or-directory staged-path final-path #f)
        (set! published (cons final-path published)))
      final-path)))

; exception->process-frame-failure : (or/c final-render-frame-job? false/c)
;                                     exn:fail? -> process-frame-failure?
;;   Preserves a bounded typed failure reason for one failed scheduler session.
(define (exception->process-frame-failure job error)
  (define-values (source-index output-index)
    (if job
        (values (final-render-frame-job-source-frame-index job)
                (final-render-frame-job-output-frame-index job))
        (values #f #f)))
  (define phase
    (cond
      [(exn:fail:render-worker-startup? error) 'startup]
      [(exn:fail:render-worker-timeout? error) 'timeout]
      [(exn:fail:render-worker-canceled? error) 'canceled]
      [(exn:fail:render-worker-crashed? error) 'crash]
      [(exn:fail:render-worker-failed? error)
       (exn:fail:render-worker-failed-phase error)]
      [(exn:fail:process-frame-input? error) 'input-integrity]
      [else 'executor]))
  (process-frame-failure source-index output-index phase
                         (bounded-exception-message error)))

; bounded-exception-message : exn:fail? -> immutable-string?
;;   Keeps reports useful without retaining an unbounded child diagnostic.
(define (bounded-exception-message error)
  (define message (exn-message error))
  (string->immutable-string
   (if (> (string-length message) 4096)
       (string-append (substring message 0 4096) " …")
       message)))
