#lang racket/base

;;;
;;; Isolated Project-Frame Worker
;;;

;; This executable end of the preview protocol intentionally has no GUI
;; dependency. It is launched only for a module-backed source and receives
;; reader-safe requests over standard input.

(require racket/class
         racket/draw
         racket/file
         racket/path
         (only-in pict pict->bitmap)
         "../main.rkt"
         "../authoring.rkt"
         "camera.rkt"
         "ode-flow.rkt"
         (only-in "pict-adapter.rkt" default-pict-renderers scene-state->pict)
         "preview-model.rkt"
         "preview-worker-protocol.rkt"
         "3d/preview-camera3d-override.rkt"
         "3d/ode-flow3d.rkt"
         "scene-program.rkt")

(define loaded-scene #f)
(define loaded-fingerprint #f)
(define loaded-generation #f)

(define (send-response value)
  (write value)
  (newline)
  (flush-output))

(define (load-source! fingerprint module-path binding generation)
  (define source-value
    (dynamic-require (string->path module-path) binding))
  (set! loaded-scene (source-value->scene source-value))
  (set! loaded-fingerprint fingerprint)
  (set! loaded-generation generation)
  (send-response (worker-ready fingerprint generation)))

(define (source-value->scene value)
  (cond
    [(scene? value) value]
    [(authored-timeline? value) (authored-timeline-scene value)]
    [(scene-program? value) (compiled-scene-program-scene (compile-scene-program value))]
    [(compiled-scene-program? value) (compiled-scene-program-scene value)]
    [else
     (raise-arguments-error
      'preview-worker
      "a scene, authored timeline, scene program, or compiled scene program"
      "source-value" value)]))

(define (render-frame! request)
  (unless (and loaded-scene
               (equal? loaded-fingerprint
                       (worker-render-frame-plan-fingerprint request))
               (= loaded-generation
                  (worker-render-frame-document-generation request)))
    (raise-arguments-error
     'preview-worker "a matching loaded project"
     "request" request))
  (send-response
   (worker-frame-started
    (worker-render-frame-plan-fingerprint request)
    (worker-render-frame-document-generation request)
    (worker-render-frame-render-generation request)
    (worker-render-frame-request-id request)))
  (define started (current-inexact-monotonic-milliseconds))
  (define sample (datum->sample (worker-render-frame-sample request)))
  (define time
    (if (frame-sample? sample)
        (/ (frame-sample-frame-index sample) (frame-sample-fps sample))
        (time-sample-time sample)))
  (define camera (scene-camera-at loaded-scene time))
  (define scaled-camera
    (make-camera
     #:width (max 1 (inexact->exact
                     (round (* (camera-width camera)
                               (worker-render-frame-pixel-scale request)))))
     #:height (max 1 (inexact->exact
                      (round (* (camera-height camera)
                                (worker-render-frame-pixel-scale request)))))
     #:world-width (camera-world-width camera)
     #:center (camera-center camera)
     #:background (camera-background camera)))
  (define rendered-state
    (for/fold ([state (scene-sample loaded-scene time)])
              ([override-datum
                (in-list (worker-render-frame-camera3d-overrides request))])
      (preview-camera3d-override-apply
       state
       (datum->preview-camera3d-override override-datum))))
  (define bitmap
    ;; Freeze both ordinary and spatial flow positions before the renderer
    ;; resolves visual relations.  The renderer then sees only immutable
    ;; samples, never an author ODE callback.
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
             scaled-camera (worker-render-frame-supersample request))
            #:renderers default-pict-renderers)
           'smoothed))))))
  (define output (string->path (worker-render-frame-output-path request)))
  (define parent (path-only output))
  (when parent (make-directory* parent))
  (unless (send bitmap save-file output 'png)
    (raise-arguments-error 'preview-worker
                           "a writable PNG output path" "path" output))
  (send-response
   (worker-frame-complete
    (worker-render-frame-plan-fingerprint request)
    (worker-render-frame-document-generation request)
    (worker-render-frame-render-generation request)
    (worker-render-frame-request-id request)
    (worker-render-frame-output-path request)
    (hasheq 'render-milliseconds
            (- (current-inexact-monotonic-milliseconds) started)))))

(define (datum->sample value)
  (cond
    [(and (list? value) (= (length value) 3) (eq? (car value) 'frame)
          (exact-nonnegative-integer? (cadr value))
          (exact-positive-integer? (caddr value)))
     (frame-sample (cadr value) (caddr value))]
    [(and (list? value) (= (length value) 2) (eq? (car value) 'time)
          (real? (cadr value)) (not (negative? (cadr value))))
     (time-sample (cadr value))]
    [else
     (raise-arguments-error 'preview-worker
                            "a serialized preview sample" "sample" value)]))

(define (camera-with-supersampling camera supersample)
  (if (= supersample 1)
      camera
      (make-camera #:width (* supersample (camera-width camera))
                   #:height (* supersample (camera-height camera))
                   #:world-width (camera-world-width camera)
                   #:center (camera-center camera)
                   #:background (camera-background camera))))

(let loop ()
  (define request (read))
  (cond
    [(eof-object? request) (void)]
    [(worker-shutdown? request)
     (send-response (worker-stopped 'shutdown))]
    [(worker-load-project? request)
     (with-handlers ([exn:fail?
                      (lambda (error)
                        (send-response
                         (worker-log (worker-load-project-plan-fingerprint request)
                                     'error (exn-message error))))])
       (load-source! (worker-load-project-plan-fingerprint request)
                     (worker-load-project-module-path request)
                     (worker-load-project-binding request)
                     (worker-load-project-document-generation request))
       (loop))]
    [(worker-reload? request)
     ;; Reload is intentionally implemented by a new module instantiation in
     ;; a fresh worker process; the supervising parent performs that restart.
     (send-response
      (worker-log (worker-reload-plan-fingerprint request) 'info
                  "reload requested; restart worker to instantiate edited module"))
     (loop)]
    [(worker-cancel? request)
     ;; A single render runs on this process's main thread, so cooperative
     ;; cancellation cannot interrupt arbitrary renderer code here. The parent
     ;; treats this acknowledgement boundary as a reason to replace the worker.
     (send-response
      (worker-log (worker-cancel-plan-fingerprint request) 'info
                  "cancel received; worker replacement may be required"))
     (loop)]
    [(worker-render-frame? request)
     (with-handlers ([exn:fail?
                      (lambda (error)
                        (send-response
                         (worker-frame-failed
                          (worker-render-frame-plan-fingerprint request)
                          (worker-render-frame-document-generation request)
                          (worker-render-frame-render-generation request)
                          (worker-render-frame-request-id request)
                          (exn-message error)))
                        (loop))])
       (render-frame! request)
       (loop))]
    [else
     (send-response (worker-log #f 'error "unknown worker request"))
     (loop)]))
