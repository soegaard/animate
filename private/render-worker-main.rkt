#lang racket/base

;;;
;;; Render Worker Entry Point
;;;

;; Runs one explicitly launched worker generation.  Requiring this module is
;; inert; only `run-render-worker!` owns the protocol loop and its source load.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         racket/draw
         racket/file
         racket/path
         (only-in pict pict->bitmap)
         "../main.rkt"
         "color-theme.rkt"
         "typography-theme.rkt"
         "camera.rkt"
         "frame-renderer.rkt"
         "ode-flow.rkt"
         (only-in "pict-adapter.rkt" default-pict-renderers scene-state->pict)
         "preview-model.rkt"
         "render-frame-job.rkt"
         "render-preparation-manifest.rkt"
         "render-source-loader.rkt"
         "render-source-model.rkt"
         "render-worker-protocol.rkt"
         "3d/preview-camera3d-override.rkt"
         "3d/ode-flow3d.rkt")

;; Exports
(provide run-render-worker!)


;;;
;;; Worker Generation State
;;;

; run-render-worker! : -> void?
;;   Serves one versioned source generation until its owned protocol port closes.
(define (run-render-worker!)
  (define protocol-input (current-input-port))
  (define protocol-output (current-output-port))
  (define author-log-output (current-error-port))
  (define loaded-scene #f)
  (define loaded-session-id #f)
  (define loaded-source-fingerprint #f)
  (define loaded-generation #f)
  (define loaded-final-output-root #f)
  (define decoded-themes (make-hash))
  (define decoded-typographies (make-hash))

  ; send-response! : render-worker-response? -> void?
  ;;   Writes one validated response only to the private protocol output port.
  (define (send-response! value)
    (write-render-worker-message! protocol-output value))

  ; send-failure! : render-worker-message? symbol? exn:fail? -> void?
  ;;   Reports one bounded worker failure without allowing author output on stdout.
  (define (send-failure! request phase error)
    (send-response!
     (render-worker-failed
      render-worker-protocol-version
      (render-worker-message-session-id request)
      (render-worker-message-source-fingerprint request)
      (render-worker-message-generation request)
      (render-worker-message-request-id request)
      phase
      (bounded-error-message error))))

  ; request-theme : transfer-data? -> theme?
  ;;   Decodes one immutable appearance snapshot once per worker generation.
  (define (request-theme datum)
    (hash-ref! decoded-themes datum (lambda () (datum->theme datum))))

  ; request-typography : transfer-data? -> typography-theme?
  ;;   Decodes one immutable typography snapshot once per worker generation.
  (define (request-typography datum)
    (hash-ref! decoded-typographies datum (lambda () (datum->typography-theme datum))))

  ; load-source! : render-worker-load-source -> void?
  ;;   Reconstructs one module value or PR-A builder source under redirected logs.
  (define (load-source! request)
    (define source (render-worker-load-source-source request))
    (define final-output-root
      (request-final-output-root request))
    ;; The parent and every child independently reject a changed declared input
    ;; before construction.  This deliberately verifies local tracked files,
    ;; not an imaginary hermetic module sandbox.
    (when (render-worker-load-source-input-manifest request)
      (verify-render-input-manifest!
       (render-worker-load-source-input-manifest request)))
    (define scene
      (parameterize ([current-output-port author-log-output]
                     [current-error-port author-log-output])
        (define source-value
          (cond
            [(render-worker-module-value-source? source)
             (load-module-source-value!
              (render-worker-module-value-source-module-path source)
              (render-worker-module-value-source-binding source))]
            [(render-worker-module-builder-source? source)
             (define builder-source
               (make-module-builder-source
                (render-worker-module-builder-source-module-path source)
                (render-worker-module-builder-source-binding source)
                (render-worker-module-builder-source-options source)
                (render-worker-module-builder-source-prepare source)
                (render-worker-module-builder-source-seed source)))
             (define context
               (worker-build-context->source-build-context source))
             (define completed-preparation
               (and (render-worker-module-builder-source-preparation-manifest source)
                    (preparation-manifest->source-preparation!
                     (render-worker-module-builder-source-preparation-manifest source)
                     context)))
             (define builder-context
               (if completed-preparation
                   (source-build-context-with-preparation
                    context completed-preparation)
                   context))
             (define-values (value _preparation _builder-context)
               (load-module-builder-source! builder-source builder-context))
             value]
            [else
             (raise-arguments-error
              'run-render-worker!
              "render-worker-source?"
              "source" source)]))
        (source-value->scene source-value)))
    (flush-output author-log-output)
    (set! loaded-scene scene)
    (set! loaded-session-id (render-worker-message-session-id request))
    (set! loaded-source-fingerprint
          (render-worker-message-source-fingerprint request))
    (set! loaded-generation (render-worker-message-generation request))
    (set! loaded-final-output-root final-output-root)
    (send-response!
     (render-worker-source-ready
      render-worker-protocol-version
      loaded-session-id
      loaded-source-fingerprint
      loaded-generation
      (render-worker-message-request-id request)
     (source-summary source))))

  ; render-preview-frame! : render-worker-render-preview-frame -> void?
  ;;   Samples and PNG-encodes one preview frame while preserving current semantics.
  (define (render-preview-frame! request)
    (unless (and loaded-scene
                 (equal? loaded-session-id
                         (render-worker-message-session-id request))
                 (equal? loaded-source-fingerprint
                         (render-worker-message-source-fingerprint request))
                 (= loaded-generation
                    (render-worker-message-generation request)))
      (raise-arguments-error
       'run-render-worker!
       "a source loaded for the request session, fingerprint, and generation"
       "request" request))
    (parameterize ([current-output-port author-log-output]
                   [current-error-port author-log-output])
      (send-response!
       (render-worker-frame-started
      render-worker-protocol-version
      (render-worker-message-session-id request)
      (render-worker-message-source-fingerprint request)
      (render-worker-message-generation request)
      (render-worker-message-request-id request)))
    (define started (current-inexact-monotonic-milliseconds))
    (define sample (datum->sample (render-worker-render-preview-frame-sample request)))
    (define time
      (if (frame-sample? sample)
          (/ (frame-sample-frame-index sample) (frame-sample-fps sample))
          (time-sample-time sample)))
    (define camera (scene-camera-at loaded-scene time))
    (define scaled-camera
      (make-camera
       #:width
       (max 1
            (inexact->exact
             (round (* (camera-width camera)
                       (render-worker-render-preview-frame-pixel-scale request)))))
       #:height
       (max 1
            (inexact->exact
             (round (* (camera-height camera)
                       (render-worker-render-preview-frame-pixel-scale request)))))
       #:world-width (camera-world-width camera)
       #:center (camera-center camera)
       #:background (camera-background camera)))
    (define rendered-state
      (for/fold ([state (scene-sample loaded-scene time)])
                ([override-datum
                  (in-list
                   (render-worker-render-preview-frame-camera3d-overrides request))])
        (preview-camera3d-override-apply
         state
         (datum->preview-camera3d-override override-datum))))
    (define bitmap
      ;; Freeze ordinary and spatial flow samples before rendering.  The shared
      ;; supervisor changes process transport only; it does not change sampling.
      (call-with-ode-frame-samples
       (prepare-ode-frame-samples (list rendered-state))
       (lambda ()
         (call-with-ode3d-frame-samples
          (prepare-ode3d-frame-samples (list rendered-state))
          (lambda ()
            (pict->bitmap
             (scene-state->pict
              rendered-state
              #:camera
              (camera-with-supersampling
               scaled-camera
               (render-worker-render-preview-frame-supersample request))
              #:renderers default-pict-renderers
              #:theme
              (request-theme
               (render-worker-render-preview-frame-theme-datum request))
              #:typography
              (request-typography
               (render-worker-render-preview-frame-typography-datum request)))
             'smoothed))))))
    (define output (make-temporary-file "animate-render-worker-~a.png"))
    (define png-bytes
      (dynamic-wind
       void
       (lambda ()
         (unless (send bitmap save-file output 'png)
           (raise-arguments-error
            'run-render-worker!
            "a writable temporary PNG path"
            "path" output))
         (file->bytes output))
       (lambda ()
         (when (file-exists? output)
           (delete-file output)))))
    (flush-output author-log-output)
    (send-response!
     (render-worker-frame-complete
      render-worker-protocol-version
      (render-worker-message-session-id request)
      (render-worker-message-source-fingerprint request)
      (render-worker-message-generation request)
      (render-worker-message-request-id request)
      png-bytes
       (hasheq 'render-milliseconds
               (- (current-inexact-monotonic-milliseconds) started))))))

  ; render-final-frame! : render-worker-render-final-frame? -> void?
  ;;   Renders, atomically publishes, and reports one parent-assigned final PNG.
  (define (render-final-frame! request)
    (unless (source-loaded-for-request?
             loaded-scene
             loaded-session-id
             loaded-source-fingerprint
             loaded-generation
             request)
      (raise-arguments-error
       'run-render-worker!
       "a source loaded for the request session, fingerprint, and generation"
       "request" request))
    (unless loaded-final-output-root
      (raise-arguments-error
       'run-render-worker!
       "a worker source loaded with a parent-owned final-output root"
       "request" request))
    (parameterize ([current-output-port author-log-output]
                   [current-error-port author-log-output])
      (send-response!
       (render-worker-frame-started
        render-worker-protocol-version
        (render-worker-message-session-id request)
        (render-worker-message-source-fingerprint request)
        (render-worker-message-generation request)
        (render-worker-message-request-id request)))
      (define started (current-inexact-monotonic-milliseconds))
      (define bitmap
        ;; This is the ordinary final frame adapter used by the in-process PNG
        ;; renderer.  It preserves source-index sampling, ODE preparation,
        ;; camera, appearance, and supersampling semantics without a second
        ;; raster pipeline in the worker.
        (scene-frame->bitmap
         loaded-scene
         (render-worker-render-final-frame-source-frame-index request)
         #:fps (render-worker-render-final-frame-fps request)
         #:camera
         (datum->final-render-camera
          (render-worker-render-final-frame-camera-datum request))
         #:renderers default-pict-renderers
         #:supersample (render-worker-render-final-frame-supersample request)
         #:theme
         (request-theme
          (render-worker-render-final-frame-theme-datum request))
         #:typography
         (request-typography
          (render-worker-render-final-frame-typography-datum request))))
      (define output-path
        (final-output-path
         loaded-final-output-root
         (render-worker-render-final-frame-output-name request)))
      (define write-started (current-inexact-monotonic-milliseconds))
      (write-final-bitmap! bitmap output-path)
      (flush-output author-log-output)
      (send-response!
       (render-worker-final-frame-complete
        render-worker-protocol-version
        (render-worker-message-session-id request)
        (render-worker-message-source-fingerprint request)
        (render-worker-message-generation request)
        (render-worker-message-request-id request)
        (render-worker-render-final-frame-source-frame-index request)
        (render-worker-render-final-frame-output-frame-index request)
        (render-worker-render-final-frame-output-name request)
        (send bitmap get-width)
        (send bitmap get-height)
        (file-size output-path)
        (hasheq 'render-milliseconds
                (- write-started started)
                'write-milliseconds
                (- (current-inexact-monotonic-milliseconds) write-started))))))

  ; handle-request! : render-worker-request? -> boolean?
  ;;   Dispatches one request and reports whether the worker should continue.
  (define (handle-request! request)
    (cond
      [(render-worker-hello? request)
       (send-response!
        (render-worker-hello
         render-worker-protocol-version
         (render-worker-message-session-id request)
         (render-worker-message-source-fingerprint request)
         (render-worker-message-generation request)
         (render-worker-message-request-id request)
         (path->string (find-system-path 'exec-file))
         (path->string (collection-file-path "main.rkt" "animate"))))
       #t]
      [(render-worker-load-source? request)
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (send-failure! request 'source-load error))])
         (load-source! request))
       #t]
      [(render-worker-render-preview-frame? request)
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (send-failure! request 'preview-render error))])
         (render-preview-frame! request))
       #t]
      [(render-worker-render-final-frame? request)
       (with-handlers ([exn:fail?
                        (lambda (error)
                          (send-failure! request 'final-render error))])
         (render-final-frame! request))
       #t]
      [(render-worker-cancel? request)
       ;; A frame executes on this process's main thread.  The supervisor sends
       ;; this observable request, then owns hard replacement after its grace.
       (send-response!
        (render-worker-log
         render-worker-protocol-version
         (render-worker-message-session-id request)
         (render-worker-message-source-fingerprint request)
         (render-worker-message-generation request)
         (render-worker-message-request-id request)
         'info
         "cancel received; supervisor may replace this worker"))
       #t]
      [(render-worker-shutdown? request)
       (send-response!
        (render-worker-stopped
         render-worker-protocol-version
         (render-worker-message-session-id request)
         (render-worker-message-source-fingerprint request)
         (render-worker-message-generation request)
         (render-worker-message-request-id request)
         'shutdown))
       ;; Keep the group leader alive until its supervisor performs the owned
       ;; reap. This lets `subprocess-kill` cover descendants on platforms
       ;; where Racket process groups support that operation.
       (let wait-for-owner-close ()
         (define next-byte (read-byte protocol-input))
         (unless (eof-object? next-byte)
           (wait-for-owner-close)))
       #f]
      [else
       (send-failure! request 'protocol
                      (exn:fail "unknown worker request"
                                (current-continuation-marks)))
       #t]))

  (let loop ()
    (define request
      (with-handlers ([exn:fail?
                       (lambda (error)
                         (eprintf "render worker protocol error: ~a\n"
                                  (bounded-error-message error))
                         eof)])
        (read-render-worker-message protocol-input)))
    (unless (eof-object? request)
      (when (handle-request! request)
        (loop)))))


;;;
;;; Source and Rendering Helpers
;;;

; worker-build-context->source-build-context : render-worker-module-builder-source?
;                                               -> source-build-context?
;;   Rebuilds the documented PR-A context from protocol-safe appearance snapshots.
(define (worker-build-context->source-build-context source)
  (define context (render-worker-module-builder-source-context source))
  (make-source-build-context
   (render-worker-module-builder-source-module-path source)
   (render-worker-module-builder-source-binding source)
   (render-worker-module-builder-source-options source)
   (render-worker-build-context-asset-base context)
   (render-worker-build-context-assets context)
   (render-worker-build-context-width context)
   (render-worker-build-context-height context)
   (render-worker-build-context-camera-policy context)
   (datum->theme (render-worker-build-context-theme-datum context))
   (datum->typography-theme
    (render-worker-build-context-typography-datum context))
   (render-worker-build-context-fps context)
   (render-worker-build-context-quality context)
   (render-worker-build-context-seed context)
   (render-worker-build-context-base-fingerprint context)
   #f))

; source-summary : render-worker-source? -> immutable-hash?
;;   Reports bounded reconstruction identity without serializing the loaded Scene.
(define (source-summary source)
  (cond
    [(render-worker-module-value-source? source)
     (hasheq 'kind 'module-value
             'module-path (render-worker-module-value-source-module-path source)
             'binding (render-worker-module-value-source-binding source))]
    [else
     (hasheq 'kind 'module-builder
             'module-path (render-worker-module-builder-source-module-path source)
             'binding (render-worker-module-builder-source-binding source)
             'base-fingerprint
             (render-worker-build-context-base-fingerprint
              (render-worker-module-builder-source-context source))
             'preparation-identity
             (and (render-worker-module-builder-source-preparation-manifest source)
                  (render-preparation-manifest-identity
                   (render-worker-module-builder-source-preparation-manifest source))))]))

; source-loaded-for-request? : (or/c scene? false/c) any/c any/c any/c
;                               render-worker-message? -> boolean?
;;   Checks that a request belongs to the one source generation in memory.
(define (source-loaded-for-request? scene session-id source-fingerprint generation request)
  (and scene
       (equal? session-id (render-worker-message-session-id request))
       (equal? source-fingerprint
               (render-worker-message-source-fingerprint request))
       (= generation (render-worker-message-generation request))))

; request-final-output-root : render-worker-load-source? -> (or/c path? false/c)
;;   Accepts only an existing parent-owned directory for final worker staging.
(define (request-final-output-root request)
  (define root (render-worker-load-source-final-output-root request))
  (cond
    [(not root) #f]
    [else
     (define complete-root (simplify-path (path->complete-path root) #t))
     (unless (directory-exists? complete-root)
       (raise-arguments-error
        'run-render-worker!
        "an existing parent-owned final-output directory"
        "final-output-root" root))
     complete-root]))

; final-output-path : path? string? -> path?
;;   Resolves one canonical basename inside the source-load staging root only.
(define (final-output-path root output-name)
  (unless (final-render-output-name? output-name)
    (raise-argument-error 'final-output-path "final-render-output-name?" output-name))
  (define normalized-root (simplify-path root #t))
  (define candidate
    (simplify-path (build-path normalized-root output-name) #f))
  candidate)

; write-final-bitmap! : bitmap% path? -> void?
;;   Saves through a sibling temporary file and atomically publishes one PNG.
(define (write-final-bitmap! bitmap output-path)
  (when (file-exists? output-path)
    (raise-arguments-error
     'write-final-bitmap!
     "an unused parent-assigned final-output path"
     "output-path" output-path))
  (define temporary-path
    (make-temporary-file ".animate-final-render-~a.tmp" #f (path-only output-path)))
  (dynamic-wind
   void
   (lambda ()
     (unless (send bitmap save-file temporary-path 'png)
       (raise-arguments-error
        'write-final-bitmap!
        "a writable final PNG staging path"
        "output-path" output-path))
     (rename-file-or-directory temporary-path output-path #f))
   (lambda ()
     (when (file-exists? temporary-path)
       (delete-file temporary-path)))))

; datum->sample : source-transfer-data? -> (or/c frame-sample? time-sample?)
;;   Rebuilds one validated preview sample without changing source-time semantics.
(define (datum->sample value)
  (cond
    [(and (list? value)
          (= (length value) 3)
          (eq? (car value) 'frame)
          (exact-nonnegative-integer? (cadr value))
          (exact-positive-integer? (caddr value)))
     (frame-sample (cadr value) (caddr value))]
    [(and (list? value)
          (= (length value) 2)
          (eq? (car value) 'time)
          (real? (cadr value))
          (not (negative? (cadr value))))
     (time-sample (cadr value))]
    [else
     (raise-arguments-error 'datum->sample "a serialized preview sample" "sample" value)]))

; camera-with-supersampling : camera? exact-positive-integer? -> camera?
;;   Applies the existing preview supersampling policy before Pict rendering.
(define (camera-with-supersampling camera supersample)
  (if (= supersample 1)
      camera
      (make-camera #:width (* supersample (camera-width camera))
                   #:height (* supersample (camera-height camera))
                   #:world-width (camera-world-width camera)
                   #:center (camera-center camera)
                   #:background (camera-background camera))))

; bounded-error-message : exn:fail? -> string?
;;   Limits error text before it becomes a protocol payload or captured log.
(define (bounded-error-message error)
  (define message (exn-message error))
  (if (> (string-length message) 4096)
      (string-append (substring message 0 4096) " …")
      message))

(module+ main
  (run-render-worker!))
