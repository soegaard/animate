#lang racket/base

;;;
;;; Interactive Preview (headless model surface)
;;;

;; GUI support is loaded lazily by later preview-session operations.  Requiring
;; this module is safe in headless processes and does not load racket/gui.

(require racket/gui/dynamic
         racket/runtime-path
         (only-in "private/pict-adapter.rkt" default-pict-renderers)
         "project.rkt"
         "private/preview-model.rkt"
         "private/preview-controller.rkt"
         "private/preview-transaction.rkt"
         "private/preview-repl.rkt"
         "private/program-preview.rkt"
         "private/program-loader.rkt"
         "private/animation-inspection.rkt"
         "private/inspector-document.rkt"
         "private/preview-cancellation.rkt"
         "private/preview-quality.rkt"
         "private/preview-render-request.rkt"
         "private/preview-clock.rkt"
         "private/preview-timeline-model.rkt"
         "private/audio-plan.rkt"
         "private/audio-filter-graph.rkt"
         "private/audio-proxy.rkt"
         "private/waveform.rkt"
         "private/preview-audio-backend.rkt"
         "private/preview-audio-monitor.rkt"
         "private/fake-audio-backend.rkt"
         "private/ffplay-audio-backend.rkt"
         "private/preview-diagnostics.rkt"
         "private/preview-worker-protocol.rkt"
         "private/preview-worker-process.rkt"
         "private/scene-program.rkt")

(provide (all-from-out "private/preview-model.rkt"
                       "private/preview-controller.rkt"
                       "private/preview-transaction.rkt"
                       "private/animation-inspection.rkt"
                       "private/inspector-document.rkt"
                       "private/preview-cancellation.rkt"
                       "private/preview-quality.rkt"
                       "private/preview-render-request.rkt"
                       "private/preview-clock.rkt"
                       "private/preview-timeline-model.rkt"
                       "private/audio-plan.rkt"
                       "private/audio-filter-graph.rkt"
                       "private/audio-proxy.rkt"
                       "private/waveform.rkt"
                       "private/preview-audio-backend.rkt"
                       "private/preview-audio-monitor.rkt"
                       "private/fake-audio-backend.rkt"
                       "private/ffplay-audio-backend.rkt"
                       "private/preview-diagnostics.rkt"
                       "private/preview-worker-protocol.rkt"
                       "private/preview-worker-process.rkt"
                       "private/program-preview.rkt")
         preview-available?
         open-scene-preview
         open-project-preview
         open-program-preview
         preview-reset-to-source!
         preview-audio-available?
         preview-audio-muted?
         preview-set-audio-muted!
         open-preview-repl!
         close-preview-repl!
         preview-repl-open?
         preview-repl-evaluate!
         preview-repl-evaluate-string!)

;; A project owns its audio monitor for exactly the lifetime of its preview
;; session.  The weak table deliberately keeps this optional output device out
;; of the generic controller state: a direct Scene preview remains headless
;; and effect-free, while project audio can still be controlled through the
;; same public session value.
(define session-audio-monitors (make-weak-hasheq))

(define (preview-audio-available? session)
  (check-preview-session 'preview-audio-available? session)
  (and (hash-ref session-audio-monitors session #f) #t))

(define (preview-audio-muted? session)
  (check-preview-session 'preview-audio-muted? session)
  (define monitor (hash-ref session-audio-monitors session #f))
  (and monitor (preview-audio-monitor-muted? monitor)))

;; Muting affects only optional audio output.  The controller's status remains
;; the one source of truth for time, frame selection, and bitmap scheduling.
(define (preview-set-audio-muted! session muted?)
  (check-preview-session 'preview-set-audio-muted! session)
  (unless (boolean? muted?)
    (raise-argument-error 'preview-set-audio-muted! "boolean?" muted?))
  (define monitor (hash-ref session-audio-monitors session #f))
  (unless monitor
    (raise-arguments-error 'preview-set-audio-muted!
                           "a preview session with an available audio monitor"
                           "session" session))
  (define status (preview-session-status session))
  (preview-audio-monitor-set-muted!
   monitor muted?
   (preview-status-time status)
   (preview-status-playing? status)
   (preview-status-playback-speed status))
  (void))

(define (check-preview-session who value)
  (unless (preview-session? value)
    (raise-argument-error who "preview-session?" value)))

;; Requiring animate/preview remains safe in CI and other headless processes.
;; The GUI implementation itself is loaded only by this operation.
(define (preview-available?)
  ;; In Racket 9.3 on macOS, GRacket can already be the active launcher while
  ;; `gui-available?` still reports #f until racket/gui/base is demanded. The
  ;; executable name is the reliable non-initializing signal here.  We retain
  ;; gui-available? for launchers that have already registered the GUI runtime.
  (or (gui-available?)
      (regexp-match? #rx"(?i:gracket)"
                     (path->string (find-system-path 'exec-file)))))

(define-runtime-path preview-window-path "private/preview-window.rkt")

(define (ensure-preview-gui who)
  ;; Keeping this non-initializing check avoids a headless worker crashing while
  ;; it tries to initialize Cocoa/GTK. The CLI relaunches itself with GRacket
  ;; when needed; a direct script should use the `gracket` executable.
  (unless (preview-available?)
    (raise-arguments-error
     who
     "a GUI-capable Racket runtime"
     "reason"
     "this process was not started as GRacket; run it with the Racket 9.3 `gracket` executable instead of `racket`")))

(define (open-scene-preview source
                            #:fps [fps 30]
                            #:start [start #f]
                            #:section [section #f]
                            #:camera [camera #f]
                            #:renderers [renderers default-pict-renderers]
                            #:pixel-scale [pixel-scale 1]
                            #:cache-megabytes [cache-megabytes 128]
                            #:prefetch [prefetch 3]
                            #:worker-mode [worker-mode 'in-process]
                            #:producer [producer #f]
                            #:waveform [wave #f]
                            #:audio-mute-available? [audio-mute-available? (lambda () #f)]
                            #:audio-muted? [audio-muted? (lambda () #f)]
                            #:set-audio-muted! [set-audio-muted! (lambda (_muted?) (void))]
                            #:on-preview-event [on-preview-event void]
                            #:title [title "Animate"])
  (ensure-preview-gui 'open-scene-preview)
  (define session
    ((dynamic-require preview-window-path 'open-preview-window)
     source #:fps fps #:start start #:section section #:camera camera
     #:renderers renderers #:pixel-scale pixel-scale
     #:cache-megabytes cache-megabytes #:prefetch prefetch
     #:worker-mode worker-mode #:producer producer #:waveform wave
     #:audio-mute-available? audio-mute-available?
     #:audio-muted? audio-muted?
     #:set-audio-muted! set-audio-muted!
     #:on-preview-event on-preview-event #:title title))
  (attach-preview-transactions!
   session #:initial-scene (preview-source-scene source))
  session)

;; `open-project-preview` uses the same immutable project declaration as final
;; output.  Planning and preparation happen before the GUI is created, so an
;; invalid source, target, or capability cannot leave a half-owned window.
;; Direct scene/timeline projects run in the cooperative in-process worker.
;; A module binding gets an isolated renderer process: it recreates the same
;; prepared scene semantics from the declared binding, and an unresponsive
;; renderer can therefore be replaced without interrupting the GUI process.
(define (open-project-preview project
                              #:target [target (project-target-all)]
                              #:directory [directory (current-directory)]
                              #:title [title #f])
  (ensure-preview-gui 'open-project-preview)
  (unless (animate-project? project)
    (raise-argument-error 'open-project-preview "animate-project?" project))
  (define plan (plan-project project #:target target #:directory directory))
  (define report (check-project! plan))
  (unless (project-check-report-ok? report)
    (raise-arguments-error
     'open-project-preview "a project whose required capabilities are available"
     "failures" (project-check-report-failures report)))
  (define preview-specification (animate-project-preview (project-plan-project plan)))
  (define source-specification (animate-project-source (project-plan-project plan)))
  (define project-title
    (or title (format "Animate: ~a" (animate-project-id (project-plan-project plan)))))
  (define requested-start
    (project-preview-target-start plan))
  (define prepared (prepare-project! plan))
  ;; Audio preparation is deliberately best-effort for an interactive
  ;; preview.  A missing file, FFmpeg, or optional ffplay backend must not
  ;; prevent the project from opening visually; the returned immutable
  ;; waveform and backend are simply absent in that case. Final rendering and
  ;; `check-project!` retain their own explicit capability/error reports.
  (define audio-runtime
    (prepare-project-preview-audio plan
                                   (prepared-project-timeline prepared)
                                   preview-specification))
  (define worker-producer
    (and (module-binding-source? source-specification)
         (make-project-worker-producer
          (module-binding-source-module-path source-specification)
          (module-binding-source-binding source-specification)
          ;; The configuration plan is pure and deterministic; its printed
          ;; datum gives a restarted worker an identity without serializing
          ;; arbitrary scene procedures.
          #:fingerprint (format "~s" (project-plan->datum plan)))))
  ;; `open-scene-preview` creates GUI controls before returning its session.
  ;; Keep the audio-control closure independent of the still-uninitialized
  ;; `session` binding during that construction window.
  (define session-box (box #f))
  (define session
    (open-scene-preview
     (or (prepared-project-timeline prepared) (prepared-project-scene prepared))
     #:fps (preview-spec-fps preview-specification)
     #:start requested-start
     #:section (and (prepared-project-timeline prepared)
                     (eq? (project-target-kind target) 'section)
                     (project-target-value target))
     #:pixel-scale (preview-spec-pixel-scale preview-specification)
     #:cache-megabytes (preview-spec-cache-megabytes preview-specification)
     #:prefetch (preview-spec-prefetch preview-specification)
     #:worker-mode (if worker-producer 'subprocess 'in-process)
     #:waveform (project-preview-audio-runtime-waveform audio-runtime)
     #:audio-mute-available?
     (lambda ()
       (and (project-preview-audio-runtime-monitor audio-runtime) #t))
     #:audio-muted?
     (lambda ()
       (define monitor (project-preview-audio-runtime-monitor audio-runtime))
       (and monitor (preview-audio-monitor-muted? monitor)))
     #:set-audio-muted!
     (lambda (muted?)
       (define monitor (project-preview-audio-runtime-monitor audio-runtime))
       (define active-session (unbox session-box))
       (when (and monitor active-session)
         (define status (preview-session-status active-session))
         (preview-audio-monitor-set-muted!
          monitor muted?
          (preview-status-time status)
          (preview-status-playing? status)
          (preview-status-playback-speed status))))
     #:on-preview-event
     (project-preview-audio-event-synchronizer
      (project-preview-audio-runtime-monitor audio-runtime))
     #:producer
     (and worker-producer
          (lambda (document sample render-spec cancellation-token)
            (project-worker-producer-produce
             worker-producer document sample render-spec cancellation-token)))
     #:title project-title))
  (set-box! session-box session)
  (when worker-producer
    ;; The session, not the caller, owns the subprocess. Closing the window
    ;; cannot leave an ffmpeg-like renderer orphaned in the background.
    (preview-add-close-hook!
     session
     (lambda () (project-worker-producer-close! worker-producer))))
  (define audio-monitor (project-preview-audio-runtime-monitor audio-runtime))
  (when audio-monitor
    (hash-set! session-audio-monitors session audio-monitor)
    (preview-add-close-hook!
     session
     (lambda ()
       (hash-remove! session-audio-monitors session)))
    ;; The preview session owns the optional backend just as it owns a project
    ;; renderer process.  Closing a window cannot leave ffplay running.
    (preview-add-close-hook!
     session
     (lambda ()
       (audio-backend-close (project-preview-audio-runtime-backend audio-runtime)))))
  session)

;; A production project may request audio monitoring, while a direct Scene or
;; Timeline preview stays completely effect-free until an author supplies an
;; audio backend.  The cache locations come from the immutable output plan;
;; this is the first point at which those declared paths are materialized.
(struct project-preview-audio-runtime (backend monitor waveform diagnostic)
  #:transparent)

(define (prepare-project-preview-audio plan timeline specification)
  (cond
    [(or (not (preview-spec-audio? specification))
         (not timeline))
     (project-preview-audio-runtime #f #f #f #f)]
    [else
     (with-handlers
         ([exn:fail?
           (lambda (error)
             (project-preview-audio-runtime #f #f #f (exn-message error)))])
       (define paths (project-plan-path-plan plan))
       (define audio-plan
         (make-preview-audio-plan
          timeline
          #:proxy-path
          (build-path (project-path-plan-audio-root paths) "preview.wav")
          #:waveform-path
          (build-path (project-path-plan-waveform-root paths) "preview.rktd")))
       (define report (prepare-preview-audio-proxy! audio-plan))
       (define wave
         (and (audio-proxy-report-waveform-path report)
              (read-waveform-file (audio-proxy-report-waveform-path report))))
       (define backend
         (and (audio-proxy-report-proxy-path report)
              (ffplay-audio-backend-available?)
              (let ([candidate (ffplay-audio-backend)])
                (audio-backend-open candidate audio-plan))))
       (project-preview-audio-runtime
        backend
        (and backend (preview-audio-monitor backend #f #f #f))
        wave
        (audio-proxy-report-diagnostics report)))]))

;; The controller's status is the source of truth for semantic time. FFplay's
;; own position is only an estimate, so it is used merely to repair a visible
;; restart/seek drift and never to move the Scene's playhead.
(define (project-preview-audio-event-synchronizer monitor)
  (if (not monitor)
      void
      (lambda (event)
        (define status (preview-event-status event))
        (when status
          (preview-audio-monitor-sync!
           monitor
           (preview-status-time status)
           (preview-status-playing? status)
           (preview-status-playback-speed status))))))

;; Preview targets select an initial semantic point; they do not alter scene
;; sampling or create a second, cropped Scene. Frame targets use the render
;; grid because that is the project target's documented coordinate system.
(define (project-preview-target-start plan)
  (define project (project-plan-project plan))
  (define target (project-plan-target plan))
  (case (project-target-kind target)
    [(all section block) #f]
    [(range) (project-target-start target)]
    [(frame) (/ (project-target-value target)
                 (render-spec-fps (animate-project-render project)))]
    [else (error 'open-project-preview "unreachable project target")]))

(define (preview-reset-to-source! session)
  (if (program-preview-session? session)
      (preview-program-reset-to-source! session)
      (preview-reset-to-initial-source! session)))

(define (open-preview-repl! session)
  (define source-program? (program-preview-session? session))
  (open-preview-repl/internal!
   session
   #:loader (and source-program? (preview-program-loader session))
   #:callbacks
   (hash
    'reset! (lambda () (preview-reset-to-source! session))
    'reload! (lambda ()
               (if source-program?
                   (preview-reload! session)
                   (raise-arguments-error 'reload! "a source-program preview session"
                                          "session" session)))
    'rerun-block! (lambda (id)
                    (if source-program?
                        (preview-rerun-block! session id)
                        (raise-arguments-error 'rerun-block!
                                               "a source-program preview session"
                                               "session" session))))))

;; Loads and compiles the source program before opening the GUI.  The program
;; attachment is installed only after the normal preview session exists, so a
;; failed load never opens a half-connected window.
(define (open-program-preview module-path binding
                              #:auto-reload? [auto-reload? #t]
                              #:fps [fps 30]
                              #:start [start #f]
                              #:start-block [start-block #f]
                              #:section [section #f]
                              #:camera [camera #f]
                              #:renderers [renderers default-pict-renderers]
                              #:pixel-scale [pixel-scale 1]
                              #:cache-megabytes [cache-megabytes 128]
                              #:prefetch [prefetch 3]
                              #:repl? [repl? #f]
                              #:open-source [open-source #f]
                              #:title [title "Animate"])
  (ensure-preview-gui 'open-program-preview)
  (unless (or (not start-block) (symbol? start-block))
    (raise-argument-error 'open-program-preview "(or/c #f symbol?)" start-block))
  (unless (boolean? repl?)
    (raise-argument-error 'open-program-preview "boolean?" repl?))
  (unless (or (not open-source) (procedure? open-source))
    (raise-argument-error 'open-program-preview "(or/c #f procedure?)" open-source))
  (when (and start start-block)
    (raise-arguments-error 'open-program-preview
                           "at most one of #:start and #:start-block"
                           "start" start "start-block" start-block))
  (define loader (load-scene-program module-path binding))
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (scene-program-loader-close! loader)
          (raise error))])
    (define compiled (scene-program-loader-compiled loader))
    (define actual-start
      (and start-block (compiled-program-block-start compiled start-block)))
    (define session
      (open-scene-preview
       (compiled-scene-program-scene compiled)
       #:fps fps #:start (or actual-start start) #:section section #:camera camera
       #:renderers renderers #:pixel-scale pixel-scale
       #:cache-megabytes cache-megabytes #:prefetch prefetch #:title title))
    (attach-program-preview! session loader
                             #:auto-reload? auto-reload?
                             #:open-source open-source)
    ;; The window is deliberately created before program attachment, so the
    ;; GUI remains a thin client of the controller.  Configure its optional
    ;; source-block navigator only after the program context exists.
    ((dynamic-require preview-window-path 'configure-preview-block-navigation!)
     session)
    (when repl? (open-preview-repl! session))
    session))
