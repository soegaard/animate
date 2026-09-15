#lang racket/base

;;;
;;; Preview Facade for the Shared Render Worker
;;;

;; Adapts existing preview requests to the common process supervisor. Preview
;; keeps its PNG-byte transport and parent-side decode guard; process ownership,
;; protocol framing, source loading, logs, deadlines, and shutdown live in the
;; shared render-worker modules.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/async-channel
         racket/class
         racket/draw
         racket/path
         "preview-cancellation.rkt"
         "preview-model.rkt"
         "preview-quality.rkt"
         "preview-render-request.rkt"
         "render-worker-process.rkt"
         "render-worker-protocol.rkt"
         "color-theme.rkt"
         "typography-theme.rkt"
         "3d/preview-camera3d-override.rkt")

;; Exports
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


;;;
;;; Preview Worker Values
;;;

;; `read-bitmap` delegates PNG decoding to the native drawing toolkit. On
;; macOS in Racket 9.3 concurrent decoding can corrupt its atomic-mode state.
;; Rendering remains multi-process; this short parent-side conversion stays
;; serialized exactly as before the supervisor extraction.
(define worker-frame-png-decode-lock (make-semaphore 1))

(struct exn:fail:preview-worker-timed-out exn:fail (request-id)
  #:transparent)
(struct exn:fail:preview-worker-restarted exn:fail (request-id)
  #:transparent)

;; exn:fail:preview-worker-* preserves the public controller outcomes while
;; the underlying shared service records a more precise lifecycle reason.

(struct preview-worker-process
  (module-path binding fingerprint document-generation worker)
  #:mutable
  #:transparent)

;; preview-worker-process owns one shared render-worker-process for a module
;; value source. document-generation is mirrored into the worker identity on
;; every reload, while render requests retain their controller request ids.

(struct project-worker-producer
  (module-path binding fingerprint workers available next-request-id-lock next-request-id)
  #:mutable
  #:transparent)

;; project-worker-producer owns a small pool of independent preview facades.
;; Its available queue has one checked-out worker per controller lane.


;;;
;;; Preview Worker Lifecycle
;;;

; start-project-preview-worker : path-string? symbol?
;                                [#:racket path-string?] [#:fingerprint transfer-data?]
;                                [#:document-generation exact-nonnegative-integer?]
;                                -> preview-worker-process?
;;   Starts one module-value preview worker through the shared supervisor.
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
    (raise-argument-error
     'start-project-preview-worker
     "exact-nonnegative-integer?"
     document-generation))
  (define complete-module-path (path->complete-path module-path))
  (preview-worker-process
   complete-module-path
   binding
   fingerprint
   document-generation
   (start-render-worker!
    (render-worker-module-value-source (path->string complete-module-path) binding)
    #:racket racket
    #:source-fingerprint fingerprint
    #:generation document-generation)))

; preview-worker-open? : preview-worker-process? -> boolean?
;;   Reports whether the current preview generation still owns a live child.
(define (preview-worker-open? worker)
  (check-preview-worker 'preview-worker-open? worker)
  (render-worker-open? (preview-worker-process-worker worker)))

; preview-worker-render-frame! : preview-worker-process? preview-render-request?
;                                preview-render-spec?
;                                [#:timeout-milliseconds exact-positive-integer?]
;                                -> bitmap% immutable-transfer-data?
;;   Renders one current request and decodes its worker-produced PNG in the parent.
(define (preview-worker-render-frame! worker request render-spec
                                      #:timeout-milliseconds [timeout-milliseconds 10000])
  (check-preview-worker 'preview-worker-render-frame! worker)
  (unless (preview-render-request? request)
    (raise-argument-error
     'preview-worker-render-frame! "preview-render-request?" request))
  (unless (preview-render-spec? render-spec)
    (raise-argument-error
     'preview-worker-render-frame! "preview-render-spec?" render-spec))
  (unless (exact-positive-integer? timeout-milliseconds)
    (raise-argument-error
     'preview-worker-render-frame! "exact-positive-integer?" timeout-milliseconds))
  (unless (= (preview-render-request-document-generation request)
             (preview-worker-process-document-generation worker))
    (raise-arguments-error
     'preview-worker-render-frame!
     "a request for the worker's current document generation"
     "request-generation" (preview-render-request-document-generation request)
     "worker-generation" (preview-worker-process-document-generation worker)))
  (unless (preview-worker-open? worker)
    (preview-worker-restart! worker))
  (define token (preview-render-request-cancellation-token request))
  (with-handlers
      ([exn:fail:render-worker-canceled?
        (lambda (_canceled)
          (preview-worker-cancel! worker request)
          (preview-worker-restart! worker)
          (check-cancellation token))]
       [exn:fail:render-worker-timeout?
        (lambda (_timeout)
          (preview-worker-restart! worker)
          (raise
           (exn:fail:preview-worker-timed-out
            "project preview worker timed out; a fresh worker has been started"
            (current-continuation-marks)
            (preview-render-request-id request))))]
       [exn:fail:render-worker-crashed?
        (lambda (_crash)
          (preview-worker-restart! worker)
          (raise
           (exn:fail:preview-worker-restarted
            "project preview worker crashed; a fresh worker has been started"
            (current-continuation-marks)
            (preview-render-request-id request))))])
    (define-values (png-bytes diagnostics)
      (render-worker-render-preview-frame!
       (preview-worker-process-worker worker)
       (preview-render-request-id request)
       (sample->datum (preview-render-request-sample request))
       (preview-render-spec-pixel-scale render-spec)
       (preview-render-spec-supersample render-spec)
       (theme->datum (preview-render-spec-theme render-spec))
       (typography-theme->datum (preview-render-spec-typography render-spec))
       (camera-overrides->datum render-spec)
       #:timeout-milliseconds timeout-milliseconds
       #:canceled? (lambda () (cancellation-requested? token))))
    (values
     (call-with-semaphore
      worker-frame-png-decode-lock
      (lambda ()
        (read-bitmap (open-input-bytes png-bytes))))
     diagnostics)))

; preview-worker-cancel! : preview-worker-process? preview-render-request? -> void?
;;   Sends the preview cancellation identity before replacing blocked worker code.
(define (preview-worker-cancel! worker request)
  (check-preview-worker 'preview-worker-cancel! worker)
  (unless (preview-render-request? request)
    (raise-argument-error 'preview-worker-cancel! "preview-render-request?" request))
  (render-worker-cancel!
   (preview-worker-process-worker worker)
   (preview-render-request-id request)
   (or (cancellation-reason (preview-render-request-cancellation-token request))
       'preview-canceled))
  (void))

; preview-worker-reload! : preview-worker-process?
;                           [#:document-generation exact-nonnegative-integer?] -> void?
;;   Replaces a worker module instance for one new source document generation.
(define (preview-worker-reload! worker #:document-generation document-generation)
  (check-preview-worker 'preview-worker-reload! worker)
  (unless (exact-nonnegative-integer? document-generation)
    (raise-argument-error
     'preview-worker-reload! "exact-nonnegative-integer?" document-generation))
  (set-preview-worker-process-document-generation! worker document-generation)
  (preview-worker-restart! worker))

; preview-worker-restart! : preview-worker-process? -> void?
;;   Recreates the shared child for the preview's current document generation.
(define (preview-worker-restart! worker)
  (check-preview-worker 'preview-worker-restart! worker)
  (render-worker-restart!
   (preview-worker-process-worker worker)
   #:generation (preview-worker-process-document-generation worker))
  (void))

; preview-worker-stop! : preview-worker-process? -> void?
;;   Releases the preview facade's process, ports, reader threads, and logs.
(define (preview-worker-stop! worker)
  (check-preview-worker 'preview-worker-stop! worker)
  (render-worker-stop! (preview-worker-process-worker worker))
  (void))


;;;
;;; Controller Producer Adapter
;;;

; make-project-worker-producer : path-string? symbol?
;                               [#:fingerprint transfer-data?] [#:workers exact-positive-integer?]
;                               -> project-worker-producer?
;;   Starts the configured independent preview-worker facades for controller lanes.
(define (make-project-worker-producer module-path binding
                                      #:fingerprint [fingerprint 'project]
                                      #:workers [workers 2])
  (unless (path-string? module-path)
    (raise-argument-error 'make-project-worker-producer "path-string?" module-path))
  (unless (symbol? binding)
    (raise-argument-error 'make-project-worker-producer "symbol?" binding))
  (unless (exact-positive-integer? workers)
    (raise-argument-error
     'make-project-worker-producer "exact-positive-integer?" workers))
  (define complete-module-path (path->complete-path module-path))
  (define available (make-async-channel))
  (define started '())
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (for ([worker (in-list started)])
            (preview-worker-stop! worker))
          (raise error))])
    (for ([ignored (in-range workers)])
      (define worker
        (start-project-preview-worker complete-module-path binding
                                      #:fingerprint fingerprint
                                      #:document-generation 0))
      (set! started (cons worker started))
      (async-channel-put available worker))
    (project-worker-producer
     complete-module-path binding fingerprint (reverse started) available
     (make-semaphore 1) 0)))

; project-worker-producer-produce : project-worker-producer? preview-document?
;                                    (or/c frame-sample? time-sample?) preview-render-spec?
;                                    cancellation-token? -> bitmap%
;;   Borrows one worker cancellation-aware and returns the parent-decoded preview bitmap.
(define (project-worker-producer-produce producer document sample render-spec token)
  (unless (project-worker-producer? producer)
    (raise-argument-error
     'project-worker-producer-produce "project-worker-producer?" producer))
  (unless (preview-document? document)
    (raise-argument-error 'project-worker-producer-produce "preview-document?" document))
  (unless (preview-render-spec? render-spec)
    (raise-argument-error
     'project-worker-producer-produce "preview-render-spec?" render-spec))
  (unless (cancellation-token? token)
    (raise-argument-error
     'project-worker-producer-produce "cancellation-token?" token))
  (define generation (preview-document-generation document))
  (define worker
    (let wait-for-worker ()
      (check-cancellation token)
      (define available-worker
        (sync/timeout 1/100 (project-worker-producer-available producer)))
      (or available-worker (wait-for-worker))))
  (dynamic-wind
   void
   (lambda ()
     ;; Each borrowed worker is exclusive, so generation replacement cannot
     ;; invalidate a sibling frame currently owned by another controller lane.
     (when (not (= generation (preview-worker-process-document-generation worker)))
       (preview-worker-reload! worker #:document-generation generation))
     (define next-id
       (call-with-semaphore
        (project-worker-producer-next-request-id-lock producer)
        (lambda ()
          (define next (add1 (project-worker-producer-next-request-id producer)))
          (set-project-worker-producer-next-request-id! producer next)
          next)))
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
   (lambda ()
     (async-channel-put (project-worker-producer-available producer) worker))))

; project-worker-producer-close! : project-worker-producer? -> void?
;;   Stops every worker owned by one controller producer exactly once.
(define (project-worker-producer-close! producer)
  (unless (project-worker-producer? producer)
    (raise-argument-error
     'project-worker-producer-close! "project-worker-producer?" producer))
  (for ([worker (in-list (project-worker-producer-workers producer))])
    (preview-worker-stop! worker))
  (set-project-worker-producer-workers! producer '())
  (void))


;;;
;;; Preview Wire Adapters
;;;

; sample->datum : (or/c frame-sample? time-sample?) -> source-transfer-data?
;;   Preserves the existing source-index or arbitrary-time preview sample form.
(define (sample->datum sample)
  (cond
    [(frame-sample? sample)
     (list 'frame (frame-sample-frame-index sample) (frame-sample-fps sample))]
    [(time-sample? sample) (list 'time (time-sample-time sample))]
    [else
     (raise-argument-error
      'preview-worker-render-frame!
      "(or/c frame-sample? time-sample?)"
      sample)]))

; camera-overrides->datum : preview-render-spec? -> immutable-list?
;;   Orders 3D overrides deterministically before their protocol transfer.
(define (camera-overrides->datum render-spec)
  (for/list
      ([view-id
        (in-list
         (sort (hash-keys (preview-render-spec-camera3d-overrides render-spec))
               symbol<?))])
    (preview-camera3d-override->datum
     (hash-ref (preview-render-spec-camera3d-overrides render-spec) view-id))))

; check-preview-worker : symbol? any/c -> void?
;;   Validates one preview facade before its public lifecycle operation.
(define (check-preview-worker who value)
  (unless (preview-worker-process? value)
    (raise-argument-error who "preview-worker-process?" value)))
