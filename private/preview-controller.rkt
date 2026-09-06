#lang racket/base

;;;
;;; Headless Preview Controller
;;;

;; One controller thread owns all mutable preview state.  A single renderer
;; worker produces bitmaps and never mutates the scene or calls UI code.  The
;; controller attaches document and render generations to every job, making a
;; late result from an obsolete source or configuration harmless.

(require racket/async-channel
         racket/class
         racket/draw
         racket/list
         (only-in pict pict->bitmap)
         "authoring-timeline.rkt"
         "camera.rkt"
         "frame-renderer.rkt"
         "ode-flow.rkt"
         (only-in "pict-adapter.rkt" default-pict-renderers scene-state->pict)
         "preview-cache.rkt"
         "preview-cancellation.rkt"
         "preview-diagnostics.rkt"
         "preview-model.rkt"
         "preview-quality.rkt"
         "preview-render-request.rkt"
         "preview-worker-process.rkt"
         "3d/preview-camera3d-override.rkt"
         "3d/ode-flow3d.rkt"
         "3d/software-renderer3d.rkt"
         "scene.rkt")

(provide (struct-out preview-event)
         (struct-out preview-status)
         (struct-out preview-playback-range)
         preview-session?
         open-preview-controller
         preview-open?
         preview-source
         preview-current-frame
         preview-current-time
         preview-current-sample
         preview-displayed-sample
         preview-current-bitmap
         preview-current-quality
         preview-playing?
         preview-session-status
         preview-seek-frame!
         preview-seek!
         preview-scrub-frame!
         preview-scrub!
         preview-step!
         preview-play!
         preview-play-range!
         preview-playback-speed
         preview-set-playback-speed!
         preview-loop-range
         preview-set-loop-range!
         preview-clear-loop-range!
         preview-playback-policy
         preview-set-playback-policy!
         preview-quality-policy
         preview-pause!
         preview-toggle-play!
         preview-jump-to-section!
         preview-current-section
         preview-next-section!
         preview-previous-section!
         preview-jump-to-cue!
         preview-section-names
         preview-refresh!
         preview-set-render-spec!
         preview-camera3d-overrides
         preview-set-camera3d-override!
         preview-clear-camera3d-override!
         preview-set-source!
         preview-report-error!
         preview-canceled-request-count
         preview-session-trace
         preview-session-diagnostics
         preview-write-session-trace!
         preview-add-close-hook!
         preview-close!)


;;;
;;; Public Session Values
;;;

(struct preview-session (commands thread alive? close-hooks)
  #:transparent)

;; Consumers, including the eventual GUI, receive these immutable records via
;; the `#:on-event` callback.  The callback executes on the controller thread;
;; GUI clients must enqueue any widget work onto their eventspace.
(struct preview-event (kind status bitmap error)
  #:transparent)

(struct preview-status (open?
                        source
                        document-generation
                        render-generation
                        sample
                        frame
                        time
                        playing?
                        current-section
                        cache-bytes
                        cache-count
                        pending-count
                        rendering?
                        error
                        canceled-request-count
                        quality
                        worker-mode
                        playback-speed
                        loop-range
                        looping?
                        displayed-sample
                        displayed-frame
                        displayed-time
                        visual-lag-milliseconds
                        last-render-diagnostics)
  #:transparent)

;; A half-open semantic-time range, shared by a timeline selection, a one-shot
;; range playback, and optional looping.  Keeping it as an immutable value
;; prevents the GUI from owning a separate, frame-rounded interpretation.
(struct preview-playback-range (start end)
  #:transparent)


;;;
;;; Private Actor Messages and State
;;;

(struct controller-command (kind arguments reply)
  #:transparent)

(struct controller-reply (ok? value)
  #:transparent)

(struct render-job (request key document sample render-spec)
  #:transparent)

(struct render-result (request key status value bytes diagnostics error)
  #:transparent)

(struct controller-state (document
                          render-spec
                          render-generation
                          cache
                          current-sample
                          current-bitmap
                          displayed-sample
                          quality-policy
                          current-quality
                          worker-mode
                          scrubbing?
                          last-scrub-milliseconds
                          settle-milliseconds
                          playing?
                          playback-policy
                          playback-speed
                          loop-range
                          looping?
                          play-start-index
                          play-end-index
                          play-start-milliseconds
                          high-jobs
                          low-jobs
                          pending
                          active-job
                          next-request-id
                          trace
                          canceled-request-count
                          last-render-diagnostics
                          error
                          event-callback)
  #:mutable
  #:transparent)


;;;
;;; Construction
;;;

;; `producer` receives immutable values in the order document, sample, spec,
;; cancellation-token.  It must treat the token cooperatively: built-in work
;; checks at deterministic semantic boundaries while arbitrary custom code is
;; allowed to finish before its obsolete result is discarded.
;; Tests may inject a controlled fake producer; production defaults to the same
;; scene->pict/pict->bitmap path as ordinary frame rendering.
(define (open-preview-controller source
                                 #:fps [fps 30]
                                 #:start [start #f]
                                 #:section [section #f]
                                 #:camera [camera #f]
                                 #:renderers [renderers default-pict-renderers]
                                 #:pixel-scale [pixel-scale 1]
                                 #:supersample [supersample 1]
                                 #:cache-megabytes [cache-megabytes 128]
                                 #:prefetch [prefetch 3]
                                 #:playback-policy [playback-policy 'realtime]
                                 #:quality-policy [quality-policy 'adaptive]
                                 #:settle-milliseconds [settle-milliseconds 120]
                                 #:worker-mode [worker-mode 'in-process]
                                 #:producer [producer #f]
                                 #:byte-size [byte-size default-bitmap-bytes]
                                 #:on-event [on-event void])
  (define actual-producer (or producer default-frame-producer))
  (unless (procedure-arity-includes? actual-producer 4)
    (raise-argument-error
     'open-preview-controller
     "procedure accepting document, sample, render-spec, and cancellation-token"
     actual-producer))
  (unless (procedure-arity-includes? byte-size 1)
    (raise-argument-error 'open-preview-controller "procedure accepting one bitmap value" byte-size))
  (unless (procedure? on-event)
    (raise-argument-error 'open-preview-controller "procedure?" on-event))
  (unless (and (real? cache-megabytes) (rational? cache-megabytes)
               (positive? cache-megabytes))
    (raise-argument-error 'open-preview-controller "positive finite real?" cache-megabytes))
  (unless (exact-nonnegative-integer? prefetch)
    (raise-argument-error 'open-preview-controller "exact-nonnegative-integer?" prefetch))
  (unless (memq playback-policy '(realtime exact))
    (raise-argument-error 'open-preview-controller "'realtime or 'exact" playback-policy))
  (unless (memq quality-policy '(adaptive full))
    (raise-argument-error 'open-preview-controller "'adaptive or 'full" quality-policy))
  (unless (memq worker-mode '(in-process subprocess))
    (raise-argument-error 'open-preview-controller "'in-process or 'subprocess" worker-mode))
  (unless (and (exact-positive-integer? settle-milliseconds)
               (<= settle-milliseconds 10000))
    (raise-argument-error 'open-preview-controller
                          "exact-positive-integer? no greater than 10000"
                          settle-milliseconds))
  (define spec
    (make-preview-render-spec #:fps fps #:camera camera #:renderers renderers
                              #:pixel-scale pixel-scale #:supersample supersample))
  (define document (make-preview-document source))
  (define initial-sample
    (initial-preview-sample document spec start section))
  (define byte-limit
    (max 1 (inexact->exact (floor (* cache-megabytes 1024 1024)))))
  (define commands (make-async-channel))
  (define completed (make-async-channel))
  (define jobs (make-async-channel))
  (define alive? (box #t))
  (define worker
    (thread (lambda () (renderer-loop jobs completed actual-producer byte-size))))
  (define state
    (controller-state document spec 0 (make-preview-cache byte-limit)
                      initial-sample #f #f quality-policy
                      (full-quality-for spec) worker-mode #f #f settle-milliseconds
                      #f playback-policy 1 #f #f #f #f #f
                      '() '() (make-hash) #f 0 (make-preview-trace) 0 #f #f on-event))
  (define controller
    (thread
     (lambda ()
       (controller-loop state commands jobs completed worker alive? prefetch))))
  (define session (preview-session commands controller alive? (box '())))
  ;; Install the first request after the session exists, without allowing a GUI
  ;; callback to observe a partly initialized actor.
  (async-channel-put commands (controller-command 'request-current '() #f))
  session)


;;;
;;; Public Synchronous Operations
;;;

(define (preview-open? session)
  (check-session 'preview-open? session)
  (unbox (preview-session-alive? session)))

(define (preview-source session)
  (status-field 'preview-source session preview-status-source))

(define (preview-current-frame session)
  (status-field 'preview-current-frame session preview-status-frame))

(define (preview-current-time session)
  (status-field 'preview-current-time session preview-status-time))

(define (preview-current-sample session)
  (status-field 'preview-current-sample session preview-status-sample))

(define (preview-displayed-sample session)
  (status-field 'preview-displayed-sample session preview-status-displayed-sample))

(define (preview-current-bitmap session)
  (send-controller-command 'preview-current-bitmap session 'bitmap '()))

(define (preview-current-quality session)
  (status-field 'preview-current-quality session preview-status-quality))

(define (preview-playing? session)
  (status-field 'preview-playing? session preview-status-playing?))

(define (preview-session-status session)
  (send-controller-command 'preview-session-status session 'status '()))

(define (preview-canceled-request-count session)
  (status-field 'preview-canceled-request-count session
                preview-status-canceled-request-count))

;; Return a datum snapshot so callers cannot mutate controller diagnostics
;; state from a GUI eventspace or REPL thread.
(define (preview-session-trace session)
  (send-controller-command 'preview-session-trace session 'trace '()))

;; An immutable production-monitor snapshot.  It deliberately distinguishes
;; the requested sample from the last bitmap that was actually installed: a
;; scrub can choose a new semantic time while the previous image remains on
;; screen until the current render completes.
(define (preview-session-diagnostics session)
  (send-controller-command 'preview-session-diagnostics session 'diagnostics '()))

(define (preview-write-session-trace! session path)
  (unless (path-string? path)
    (raise-argument-error 'preview-write-session-trace! "path-string?" path))
  (preview-write-trace!
   (send-controller-command 'preview-write-session-trace! session 'trace-object '())
   path))

(define (preview-seek-frame! session frame-index)
  (send-controller-command 'preview-seek-frame! session 'seek-frame (list frame-index)))

(define (preview-seek! session time)
  (send-controller-command 'preview-seek! session 'seek-time (list time)))

(define (preview-scrub-frame! session frame-index)
  (send-controller-command 'preview-scrub-frame! session 'scrub-frame (list frame-index)))

(define (preview-scrub! session time)
  (send-controller-command 'preview-scrub! session 'scrub-time (list time)))

(define (preview-step! session [delta 1])
  (send-controller-command 'preview-step! session 'step (list delta)))

(define (preview-play! session)
  (send-controller-command 'preview-play! session 'play '()))

(define (preview-play-range! session start end)
  (send-controller-command 'preview-play-range! session 'play-range (list start end)))

(define (preview-playback-speed session)
  (send-controller-command 'preview-playback-speed session 'playback-speed '()))

(define (preview-set-playback-speed! session speed)
  (send-controller-command 'preview-set-playback-speed! session
                           'set-playback-speed (list speed)))

(define (preview-loop-range session)
  (send-controller-command 'preview-loop-range session 'loop-range '()))

(define (preview-set-loop-range! session start end)
  (send-controller-command 'preview-set-loop-range! session
                           'set-loop-range (list start end)))

(define (preview-clear-loop-range! session)
  (send-controller-command 'preview-clear-loop-range! session
                           'clear-loop-range '()))

(define (preview-playback-policy session)
  (send-controller-command 'preview-playback-policy session 'playback-policy '()))

(define (preview-set-playback-policy! session policy)
  (send-controller-command 'preview-set-playback-policy! session
                           'set-playback-policy (list policy)))

(define (preview-quality-policy session)
  (send-controller-command 'preview-quality-policy session 'quality-policy '()))

(define (preview-pause! session)
  (send-controller-command 'preview-pause! session 'pause '()))

(define (preview-toggle-play! session)
  (send-controller-command 'preview-toggle-play! session 'toggle-play '()))

(define (preview-jump-to-section! session name)
  (send-controller-command 'preview-jump-to-section! session 'jump-section (list name)))

(define (preview-current-section session)
  (status-field 'preview-current-section session preview-status-current-section))

(define (preview-next-section! session)
  (send-controller-command 'preview-next-section! session 'next-section '()))

(define (preview-previous-section! session)
  (send-controller-command 'preview-previous-section! session 'previous-section '()))

(define (preview-jump-to-cue! session name)
  (send-controller-command 'preview-jump-to-cue! session 'jump-cue (list name)))

(define (preview-section-names session)
  (send-controller-command 'preview-section-names session 'section-names '()))

(define (preview-refresh! session)
  (send-controller-command 'preview-refresh! session 'refresh '()))

(define (preview-set-render-spec! session render-spec)
  (send-controller-command 'preview-set-render-spec! session 'set-render-spec (list render-spec)))

; preview-camera3d-overrides : preview-session? -> immutable-hash?
;;   Returns the preview-only inspection cameras keyed by view3d ID.
(define (preview-camera3d-overrides session)
  (send-controller-command 'preview-camera3d-overrides session
                           'camera3d-overrides '()))

; preview-set-camera3d-override! : preview-session? preview-camera3d-override?
;;                                  -> preview-status?
;;   Installs one inspection camera without mutating the authored scene.
(define (preview-set-camera3d-override! session override)
  (send-controller-command 'preview-set-camera3d-override!
                           session
                           'set-camera3d-override
                           (list override)))

; preview-clear-camera3d-override! : preview-session? symbol? -> preview-status?
;;   Removes one inspection camera and returns immediately to the authored view.
(define (preview-clear-camera3d-override! session view-id)
  (send-controller-command 'preview-clear-camera3d-override!
                           session
                           'clear-camera3d-override
                           (list view-id)))

(define (preview-set-source! session source)
  (send-controller-command 'preview-set-source! session 'set-source (list source)))

;; Used by isolated loaders and REPL transactions.  The controller remains the
;; one owner of user-visible preview status even when validation was performed
;; outside its render loop.
(define (preview-report-error! session error)
  (unless (exn:fail? error)
    (raise-argument-error 'preview-report-error! "exn:fail?" error))
  (send-controller-command 'preview-report-error! session 'report-error (list error)))

;; Internal integrations (watchers, REPLs, program loaders) register cleanup
;; here rather than keeping detached threads alive after a preview is closed.
(define (preview-add-close-hook! session procedure)
  (check-session 'preview-add-close-hook! session)
  (unless (procedure-arity-includes? procedure 0)
    (raise-argument-error 'preview-add-close-hook! "procedure accepting zero arguments" procedure))
  (cond
    [(preview-open? session)
     (set-box! (preview-session-close-hooks session)
               (cons procedure (unbox (preview-session-close-hooks session))))]
    [else
     (procedure)])
  (void))

(define (preview-close! session)
  (check-session 'preview-close! session)
  (when (unbox (preview-session-alive? session))
    (send-controller-command 'preview-close! session 'close '())
    (thread-wait (preview-session-thread session)))
  (define hooks (unbox (preview-session-close-hooks session)))
  (set-box! (preview-session-close-hooks session) '())
  (for ([hook (in-list hooks)])
    (with-handlers ([exn:fail? (lambda (_error) (void))])
      (hook)))
  (void))


;;;
;;; Controller Loop
;;;

(define (controller-loop state commands jobs completed worker alive? prefetch)
  (let loop ()
    ;; Transport commands have priority over a completed bitmap. This matters
    ;; for exact looping with a very cheap renderer: without the zero-wait
    ;; command check, an always-ready completion channel can starve Pause,
    ;; Close, and Scrub indefinitely.
    (define waiting-command (sync/timeout 0 commands))
    ;; A short timeout keeps playback tied to a monotonic clock even when no
    ;; command or renderer completion arrives.
    (define message
      (or (and waiting-command (cons 'command waiting-command))
          (sync/timeout
           1/120
           (handle-evt commands
                       (lambda (command) (cons 'command command)))
           (handle-evt completed
                       (lambda (result) (cons 'result result))))))
    (cond
      [(and message (eq? (car message) 'command))
       (handle-command! state (cdr message) jobs worker alive? prefetch)]
      [(and message (eq? (car message) 'result))
       (handle-render-result! state (cdr message) jobs prefetch)]
      [else
       ;; A slider callback only says that a new position was chosen; it has no
       ;; portable "drag ended" event.  The actor therefore settles a scrub
       ;; after a short idle interval and requests the same semantic frame at
       ;; full configured preview quality.
       (settle-scrub! state jobs prefetch)
       (if (eq? (controller-state-playback-policy state) 'exact)
           ;; Exact mode deliberately advances on a controller tick rather
           ;; than recursively from an immediate cache hit. A loop whose two
           ;; frames are cached must still leave room for Pause and Close.
           (advance-exact-playback! state jobs prefetch)
           (advance-playback! state jobs prefetch))])
    (unless (not (unbox alive?))
      (loop))))

(define (handle-command! state command jobs worker alive? prefetch)
  (define reply (controller-command-reply command))
  (with-handlers
      ([exn:fail?
        (lambda (error)
          (when reply
            (async-channel-put reply (controller-reply #f error)))
          (set-controller-state-error! state error)
          (emit! state 'error #f error))])
    (define value
      (case (controller-command-kind command)
        [(request-current)
         (request-current! state jobs prefetch)
         (void)]
        [(status) (state-status state)]
        [(playback-policy) (controller-state-playback-policy state)]
        [(playback-speed) (controller-state-playback-speed state)]
        [(loop-range) (controller-state-loop-range state)]
        [(quality-policy) (controller-state-quality-policy state)]
        [(set-playback-policy)
         (match-arguments 'set-playback-policy (controller-command-arguments command) 1)
         (define policy (car (controller-command-arguments command)))
         (unless (memq policy '(realtime exact))
           (raise-argument-error 'preview-set-playback-policy! "'realtime or 'exact" policy))
         (set-controller-state-playback-policy! state policy)
         (emit! state 'status #f #f)
         (state-status state)]
        [(set-playback-speed)
         (match-arguments 'set-playback-speed (controller-command-arguments command) 1)
         (define speed (car (controller-command-arguments command)))
         (unless (and (real? speed) (rational? speed) (positive? speed))
           (raise-argument-error
            'preview-set-playback-speed! "positive finite real?" speed))
         ;; Restart the one controller-owned clock at the displayed semantic
         ;; frame. This keeps the image stable while the next real-time tick
         ;; applies the newly requested rate.
         (set-controller-state-playback-speed! state speed)
         (when (controller-state-playing? state)
           (restart-playback-clock! state))
         (emit! state 'status #f #f)
         (state-status state)]
        [(set-loop-range)
         (match-arguments 'set-loop-range (controller-command-arguments command) 2)
         (define range
           (normalize-playback-range
            state
            (car (controller-command-arguments command))
            (cadr (controller-command-arguments command))
            'preview-set-loop-range!))
         (set-controller-state-loop-range! state range)
         ;; Editing in/out points changes the *next* Play operation. It does
         ;; not surprise an author by jumping or restarting playback already
         ;; in progress.
         (emit! state 'status #f #f)
         range]
        [(clear-loop-range)
         (match-arguments 'clear-loop-range (controller-command-arguments command) 0)
         (set-controller-state-loop-range! state #f)
         (set-controller-state-looping?! state #f)
         (emit! state 'status #f #f)
         (state-status state)]
        [(trace) (preview-trace->datum (controller-state-trace state))]
        [(trace-object) (controller-state-trace state)]
        [(diagnostics) (state-diagnostics state)]
        [(bitmap) (controller-state-current-bitmap state)]
        [(seek-frame)
         (match-arguments 'seek-frame (controller-command-arguments command) 1)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-current-quality!
          state (full-quality-for (controller-state-render-spec state)))
         (set-controller-state-current-sample!
          state
          (preview-normalize-frame-sample
           (controller-state-document state)
           (car (controller-command-arguments command))
           (controller-state-render-spec state)))
         (set-controller-state-error! state #f)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(seek-time)
         (match-arguments 'seek-time (controller-command-arguments command) 1)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-current-quality!
          state (full-quality-for (controller-state-render-spec state)))
         (set-controller-state-current-sample!
          state
          (preview-normalize-time-sample
           (controller-state-document state)
           (car (controller-command-arguments command))))
         (set-controller-state-error! state #f)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(scrub-frame)
         (match-arguments 'scrub-frame (controller-command-arguments command) 1)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #t)
         (set-controller-state-last-scrub-milliseconds!
          state (current-inexact-monotonic-milliseconds))
         (set-controller-state-current-quality!
          state (scrub-quality-for state))
         (set-controller-state-current-sample!
          state
          (preview-normalize-frame-sample
           (controller-state-document state)
           (car (controller-command-arguments command))
           (controller-state-render-spec state)))
         (set-controller-state-error! state #f)
         (request-current! state jobs 0)
         (state-status state)]
        [(scrub-time)
         (match-arguments 'scrub-time (controller-command-arguments command) 1)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #t)
         (set-controller-state-last-scrub-milliseconds!
          state (current-inexact-monotonic-milliseconds))
         (set-controller-state-current-quality!
          state (scrub-quality-for state))
         (set-controller-state-current-sample!
          state
          (preview-normalize-time-sample
           (controller-state-document state)
           (car (controller-command-arguments command))))
         (set-controller-state-error! state #f)
         (request-current! state jobs 0)
         (state-status state)]
        [(step)
         (match-arguments 'step (controller-command-arguments command) 1)
         (define delta (car (controller-command-arguments command)))
         (unless (exact-integer? delta)
           (raise-argument-error 'preview-step! "exact-integer?" delta))
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-current-quality!
          state (full-quality-for (controller-state-render-spec state)))
         (set-controller-state-current-sample!
          state
          (preview-normalize-frame-sample
           (controller-state-document state)
           (+ (current-frame-index state) delta)
           (controller-state-render-spec state)))
         (request-current! state jobs prefetch)
         (state-status state)]
        [(play)
         (start-configured-playback! state jobs prefetch)
         (state-status state)]
        [(play-range)
         (match-arguments 'play-range (controller-command-arguments command) 2)
         (define start (car (controller-command-arguments command)))
         (define end (cadr (controller-command-arguments command)))
         (start-playback-range! state start end jobs prefetch)
         (state-status state)]
        [(pause)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-looping?! state #f)
         (set-controller-state-current-quality!
          state (full-quality-for (controller-state-render-spec state)))
         (emit! state 'status #f #f)
         (state-status state)]
        [(toggle-play)
         (if (controller-state-playing? state)
             (begin
               (set-controller-state-playing?! state #f)
               (set-controller-state-looping?! state #f)
               (emit! state 'status #f #f))
             (start-configured-playback! state jobs prefetch))
         (state-status state)]
        [(jump-section)
         (match-arguments 'jump-section (controller-command-arguments command) 1)
         (jump-to-section! state (car (controller-command-arguments command)) jobs prefetch)
         (state-status state)]
        [(next-section)
         (jump-relative-section! state 1 jobs prefetch)
         (state-status state)]
        [(previous-section)
         (jump-relative-section! state -1 jobs prefetch)
         (state-status state)]
        [(jump-cue)
         (match-arguments 'jump-cue (controller-command-arguments command) 1)
         (jump-to-cue! state (car (controller-command-arguments command)) jobs prefetch)
         (state-status state)]
        [(section-names) (preview-document-section-names (controller-state-document state))]
        [(refresh)
         (invalidate-render! state)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(set-render-spec)
         (match-arguments 'set-render-spec (controller-command-arguments command) 1)
         (define spec (car (controller-command-arguments command)))
         (unless (preview-render-spec? spec)
           (raise-argument-error 'preview-set-render-spec! "preview-render-spec?" spec))
         (set-controller-state-render-spec! state spec)
         (set-controller-state-current-quality! state (full-quality-for spec))
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-current-sample!
          state
          (normalize-sample-for-document
           (controller-state-document state)
           (controller-state-current-sample state)
           spec))
         (invalidate-render! state)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(camera3d-overrides)
         (preview-render-spec-camera3d-overrides
          (controller-state-render-spec state))]
        [(set-camera3d-override)
         (match-arguments 'set-camera3d-override
                          (controller-command-arguments command) 1)
         (define override (car (controller-command-arguments command)))
         (unless (preview-camera3d-override? override)
           (raise-argument-error
            'preview-set-camera3d-override!
            "preview-camera3d-override?"
            override))
         (define prior (controller-state-render-spec state))
         (replace-camera3d-overrides!
          state
          (hash-set
           (preview-render-spec-camera3d-overrides prior)
           (preview-camera3d-override-view-id override)
           override)
          jobs prefetch)
         (state-status state)]
        [(clear-camera3d-override)
         (match-arguments 'clear-camera3d-override
                          (controller-command-arguments command) 1)
         (define view-id (car (controller-command-arguments command)))
         (unless (symbol? view-id)
           (raise-argument-error 'preview-clear-camera3d-override! "symbol?" view-id))
         (define prior (controller-state-render-spec state))
         (replace-camera3d-overrides!
          state
          (hash-remove (preview-render-spec-camera3d-overrides prior) view-id)
          jobs prefetch)
         (state-status state)]
        [(set-source)
         (match-arguments 'set-source (controller-command-arguments command) 1)
         (define source (car (controller-command-arguments command)))
         (unless (preview-source? source)
           (raise-argument-error 'preview-set-source! "(or/c scene? authored-timeline?)" source))
         (define old-time
           (preview-sample-time (controller-state-document state)
                                (controller-state-current-sample state)))
         (define next-document
           (make-preview-document source
                                  #:generation
                                  (add1 (preview-document-generation
                                         (controller-state-document state)))
                                  #:label (preview-document-label
                                           (controller-state-document state))))
         (set-controller-state-document! state next-document)
         (set-controller-state-current-sample!
          state
          (preview-normalize-time-sample next-document old-time))
         (set-controller-state-current-bitmap! state #f)
         (set-controller-state-playing?! state #f)
         (set-controller-state-scrubbing?! state #f)
         (set-controller-state-looping?! state #f)
         (set-controller-state-current-quality!
          state (full-quality-for (controller-state-render-spec state)))
         (invalidate-render! state)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(report-error)
         (match-arguments 'report-error (controller-command-arguments command) 1)
         (define error (car (controller-command-arguments command)))
         (unless (exn:fail? error)
           (raise-argument-error 'preview-report-error! "exn:fail?" error))
         (set-controller-state-error! state error)
         (emit! state 'error #f error)
         (state-status state)]
        [(close)
         (set-controller-state-playing?! state #f)
         (cancel-active-job! state 'preview-closed)
         (clear-queued-jobs! state 'preview-closed)
         (set-box! alive? #f)
         (async-channel-put jobs 'close)
         (thread-wait worker)
         (emit! state 'closed #f #f)
         (void)]
        [else
         (raise-arguments-error
          'preview-controller
          "known preview command"
          "command" (controller-command-kind command))]))
    (when reply
      (async-channel-put reply (controller-reply #t value)))))


;;;
;;; Scheduling and Generations
;;;

(define (request-current! state jobs prefetch)
  (define sample (controller-state-current-sample state))
  (define render-spec (active-render-spec state))
  (define key (current-key state))
  (define missing (gensym 'preview-cache-missing))
  (define cached (preview-cache-ref! (controller-state-cache state) key missing))
  (cond
    [(not (eq? cached missing))
     (set-controller-state-current-bitmap! state cached)
     (set-controller-state-displayed-sample! state sample)
     (emit! state 'frame-ready cached #f)
     (schedule-prefetch! state jobs prefetch)
     ;; Exact playback advances on the next actor tick. Deferring it avoids
     ;; recursive cache-hit rendering when a short loop is entirely cached.
     (void)]
    [else
     ;; A new exact request supersedes queued scrub and prefetch work.  An
     ;; already-running in-process producer may only cooperate at its safe
     ;; boundaries, so we cancel it and retain its slot until it reports a
     ;; result.  The newest exact request is then first in the high queue.
     (clear-queued-jobs! state 'superseded)
     (when (and (controller-state-active-job state)
                (not (equal? key
                             (render-job-key
                              (controller-state-active-job state)))))
       (cancel-active-job! state 'superseded))
     (enqueue-job! state (make-render-job! state
                                           key
                                           (controller-state-document state)
                                           sample
                                           render-spec
                                           (if (controller-state-playing? state) 1 0))
                   #:high? #t)
     (start-next-job! state jobs)
     (emit! state 'rendering #f #f)]))

(define (schedule-prefetch! state jobs prefetch)
  (when (and (positive? prefetch)
             (frame-sample? (controller-state-current-sample state)))
    (define sample (controller-state-current-sample state))
    (define fps (frame-sample-fps sample))
    (define document (controller-state-document state))
    (define spec (active-render-spec state))
    (for ([index (in-range (add1 (frame-sample-frame-index sample))
                           (add1 (min (last-frame-index state)
                                      (+ (frame-sample-frame-index sample) prefetch))))])
      (define next-sample (frame-sample index fps))
      (define key
        (make-preview-frame-key document
                                (controller-state-render-generation state)
                                next-sample spec))
      (define missing (gensym 'preview-cache-missing))
      (when (eq? (preview-cache-ref! (controller-state-cache state) key missing) missing)
        (enqueue-job! state (make-render-job! state key document next-sample spec 4)
                      #:high? #f)))
    (start-next-job! state jobs)))

(define (enqueue-job! state job #:high? high?)
  (define key (render-job-key job))
  (unless (hash-has-key? (controller-state-pending state) key)
    (hash-set! (controller-state-pending state) key #t)
    (if high?
        (set-controller-state-high-jobs!
         state
         (append (controller-state-high-jobs state) (list job)))
        (set-controller-state-low-jobs!
         state
         (append (controller-state-low-jobs state) (list job))))))

(define (clear-queued-jobs! state [reason 'superseded])
  (for ([job (in-list (append (controller-state-high-jobs state)
                              (controller-state-low-jobs state)))])
    (cancel! (preview-render-request-cancellation-token (render-job-request job))
             reason)
    (hash-remove! (controller-state-pending state) (render-job-key job)))
  (set-controller-state-high-jobs! state '())
  (set-controller-state-low-jobs! state '()))

;; New job identifiers are controller-local and monotonic.  They allow a
;; renderer, future subprocess worker, and diagnostics trace to distinguish
;; two requests for the same semantic frame after a source reload.
(define (make-render-job! state key document sample render-spec priority)
  (define request-id (add1 (controller-state-next-request-id state)))
  (set-controller-state-next-request-id! state request-id)
  (define request
    (preview-render-request
     #:id request-id
     #:document-generation (preview-frame-key-generation key)
     #:render-generation (preview-frame-key-render-generation key)
     #:sample sample
     #:quality
     (controller-state-current-quality state)
     #:priority priority))
  (render-job request key document sample render-spec))

(define (cancel-active-job! state [reason 'superseded])
  (define active (controller-state-active-job state))
  (when active
    (cancel! (preview-render-request-cancellation-token (render-job-request active))
             reason))
  (void))

(define (start-next-job! state jobs)
  (unless (controller-state-active-job state)
    (define job
      (cond
        [(pair? (controller-state-high-jobs state))
         (define next (car (controller-state-high-jobs state)))
         (set-controller-state-high-jobs! state (cdr (controller-state-high-jobs state)))
         next]
        [(pair? (controller-state-low-jobs state))
         (define next (car (controller-state-low-jobs state)))
         (set-controller-state-low-jobs! state (cdr (controller-state-low-jobs state)))
         next]
        [else #f]))
    (when job
      (set-controller-state-active-job! state job)
      (async-channel-put jobs job))))

(define (handle-render-result! state result jobs prefetch)
  (when (and (controller-state-active-job state)
             (= (preview-render-request-id
                 (render-job-request (controller-state-active-job state)))
                (preview-render-request-id (render-result-request result))))
    (set-controller-state-active-job! state #f))
  (hash-remove! (controller-state-pending state) (render-result-key result))
  (define still-current-generation?
    (and (= (preview-frame-key-generation (render-result-key result))
            (preview-document-generation (controller-state-document state)))
         (= (preview-frame-key-render-generation (render-result-key result))
            (controller-state-render-generation state))))
  (cond
    [(not still-current-generation?)
     ;; Stale work is deliberately neither cached nor displayed.
     (void)]
    [(memq (render-result-status result) '(canceled superseded))
     ;; Cancellation is an expected scheduling outcome.  It is neither an
     ;; author error nor a cacheable render result.
     (set-controller-state-canceled-request-count!
      state (add1 (controller-state-canceled-request-count state)))
     (preview-trace-record!
      (controller-state-trace state)
      (if (eq? (render-result-status result) 'superseded)
          'superseded-request
          'canceled-request)
      (current-inexact-monotonic-milliseconds)
      (hasheq 'request-id (preview-render-request-id (render-result-request result))
              'status (render-result-status result)
              'reason (and (render-result-error result)
                           (exn:fail:preview-canceled-reason
                            (render-result-error result)))))
     (void)]
    [(eq? (render-result-status result) 'timed-out)
     ;; The subprocess supervisor has already started a clean replacement.
     ;; Preserve the last good bitmap and request the current semantic frame
     ;; again. Timeout and restart are separate diagnostic facts.
     (preview-trace-record!
      (controller-state-trace state) 'render-timed-out
      (current-inexact-monotonic-milliseconds)
      (hasheq 'request-id (preview-render-request-id (render-result-request result))))
     (preview-trace-record!
      (controller-state-trace state) 'worker-restarted
      (current-inexact-monotonic-milliseconds)
      (hasheq 'request-id (preview-render-request-id (render-result-request result))
              'reason 'timeout))
     (request-current! state jobs prefetch)]
    [(eq? (render-result-status result) 'worker-restarted)
     ;; The process supervisor has already loaded a clean replacement.  Keep
     ;; the last good bitmap visible and immediately ask it for the still
     ;; current semantic frame.
     (preview-trace-record!
      (controller-state-trace state) 'worker-restarted
      (current-inexact-monotonic-milliseconds)
      (hasheq 'request-id (preview-render-request-id (render-result-request result))))
     (request-current! state jobs prefetch)]
    [(render-result-error result)
     (set-controller-state-error! state (render-result-error result))
     (emit! state 'error #f (render-result-error result))]
    [else
     (preview-cache-set! (controller-state-cache state)
                         (render-result-key result)
                         (render-result-value result)
                         (render-result-bytes result))
     (when (equal? (render-result-key result) (current-key state))
       (set-controller-state-current-bitmap! state (render-result-value result))
       (set-controller-state-displayed-sample!
        state
        (controller-state-current-sample state))
       (set-controller-state-error! state #f)
       (emit! state 'frame-ready (render-result-value result) #f)
       (schedule-prefetch! state jobs prefetch)
       (void))])
  (when (hash? (render-result-diagnostics result))
    (set-controller-state-last-render-diagnostics!
     state
     (make-immutable-hash
      (hash->list (render-result-diagnostics result))))
    (preview-trace-record!
     (controller-state-trace state) 'render-result
     (current-inexact-monotonic-milliseconds)
     (render-result-diagnostics result)))
  (start-next-job! state jobs))

(define (invalidate-render! state)
  (set-controller-state-render-generation!
   state
   (add1 (controller-state-render-generation state)))
  (preview-cache-clear! (controller-state-cache state))
  (cancel-active-job! state 'render-invalidated)
  (clear-queued-jobs! state 'render-invalidated)
  (set-controller-state-current-bitmap! state #f)
  (set-controller-state-displayed-sample! state #f)
  (set-controller-state-error! state #f))


;;;
;;; Playback and Timeline Navigation
;;;

(define (start-configured-playback! state jobs prefetch)
  (define range (controller-state-loop-range state))
  (cond
    [range
     (define fps (preview-render-spec-fps (controller-state-render-spec state)))
     (define start-index (playback-range-start-index range fps))
     (define end-index (min (playback-range-end-index range fps)
                            (last-frame-index state)))
     (define current (current-frame-index state))
     ;; A click on Play within the marked interval continues from the
     ;; playhead. Outside it, playback begins at the in point. After reaching
     ;; the out point, the loop always returns to the in point.
     (start-playback! state
                      (if (<= start-index current end-index) current start-index)
                      end-index
                      #t
                      jobs prefetch)]
    [else
     (start-playback! state (current-frame-index state)
                      (last-frame-index state)
                      #f
                      jobs prefetch)]))

(define (start-playback! state start-index end-index looping? jobs prefetch)
  (cond
    [(negative? end-index)
     (set-controller-state-playing?! state #f)]
    [else
     (define start (min (max start-index 0) end-index))
     (set-controller-state-scrubbing?! state #f)
     (set-controller-state-current-quality!
      state (full-quality-for (controller-state-render-spec state)))
     (set-controller-state-current-sample!
      state
      (frame-sample start (preview-render-spec-fps (controller-state-render-spec state))))
     (set-controller-state-play-start-index! state start)
     (set-controller-state-play-end-index! state end-index)
     (set-controller-state-looping?! state looping?)
     (set-controller-state-play-start-milliseconds! state
                                                     (current-inexact-monotonic-milliseconds))
     (set-controller-state-playing?! state #t)
     (request-current! state jobs prefetch)
     (emit! state 'status #f #f)]))

(define (start-playback-range! state start end jobs prefetch)
  (define range (normalize-playback-range state start end 'preview-play-range!))
  (define fps (preview-render-spec-fps (controller-state-render-spec state)))
  (start-playback! state
                   (playback-range-start-index range fps)
                   (min (playback-range-end-index range fps)
                        (last-frame-index state))
                   #f jobs prefetch))

;; Normalizing timing ranges in one place makes the public loop and one-shot
;; forms agree about clamping and half-open endpoints. The stored range stays
;; in semantic seconds; frame rounding happens only at the controller boundary.
(define (normalize-playback-range state start end who)
  (check-time who "start" start)
  (check-time who "end" end)
  (unless (< start end)
    (raise-arguments-error who "start must be less than end" "start" start "end" end))
  (define duration
    (scene-duration (preview-document-scene (controller-state-document state))))
  (define clamped-start (min (max start 0) duration))
  (define clamped-end (min (max end 0) duration))
  (unless (< clamped-start clamped-end)
    (raise-arguments-error
     who "range intersects the scene"
     "start" start "end" end "duration" duration))
  (preview-playback-range clamped-start clamped-end))

(define (playback-range-start-index range fps)
  (inexact->exact (ceiling (* (preview-playback-range-start range) fps))))

(define (playback-range-end-index range fps)
  ;; As with authored sections, the out point is exclusive.
  (sub1 (inexact->exact (ceiling (* (preview-playback-range-end range) fps)))))

(define (restart-playback-clock! state)
  (set-controller-state-play-start-index! state (current-frame-index state))
  (set-controller-state-play-start-milliseconds!
   state (current-inexact-monotonic-milliseconds)))

(define (advance-playback! state jobs prefetch)
  (when (and (controller-state-playing? state)
             (eq? (controller-state-playback-policy state) 'realtime))
    (define elapsed
      (/ (- (current-inexact-monotonic-milliseconds)
            (controller-state-play-start-milliseconds state))
         1000.0))
    (define fps (preview-render-spec-fps (controller-state-render-spec state)))
    (define desired
      (+ (controller-state-play-start-index state)
         (inexact->exact
          (floor (* fps elapsed (controller-state-playback-speed state))))))
    (cond
      [(> desired (controller-state-play-end-index state))
       (if (controller-state-looping? state)
           (let* ([range (controller-state-loop-range state)]
                  [start-index
                   (playback-range-start-index range fps)]
                  [length (add1 (- (controller-state-play-end-index state)
                                   start-index))]
                  ;; The initial pass may start in the middle of a marked
                  ;; range. Every later pass is anchored at its in point.
                  [wrapped
                   (+ start-index
                      (modulo (- desired
                                 (add1 (controller-state-play-end-index state)))
                              length))])
             (set-controller-state-current-sample! state (frame-sample wrapped fps))
             (request-current! state jobs prefetch))
           (begin
             (set-controller-state-playing?! state #f)
             (set-controller-state-looping?! state #f)
             (set-controller-state-current-sample!
              state
              (frame-sample (controller-state-play-end-index state) fps))
             (request-current! state jobs prefetch)
             (emit! state 'status #f #f)))]
      [(not (equal? (controller-state-current-sample state)
                    (frame-sample desired fps)))
       (set-controller-state-current-sample! state (frame-sample desired fps))
       ;; Slow rendering cannot slow semantic playback.  A newly desired frame
       ;; replaces queued frames that were never displayed.
       (request-current! state jobs prefetch)])))

;; Exact playback advances after the currently requested frame is installed,
;; not after an elapsed wall-clock interval. This intentionally slows down
;; when rendering is expensive, while preserving every discrete frame.
(define (advance-exact-playback! state jobs prefetch)
  (when (controller-state-playing? state)
    (define next-index (add1 (current-frame-index state)))
    (cond
      [(> next-index (controller-state-play-end-index state))
       (if (controller-state-looping? state)
           (let* ([range (controller-state-loop-range state)]
                  [fps (preview-render-spec-fps (controller-state-render-spec state))])
             (set-controller-state-current-sample!
              state
              (frame-sample (playback-range-start-index range fps) fps))
             (request-current! state jobs prefetch))
           (begin
             (set-controller-state-playing?! state #f)
             (set-controller-state-looping?! state #f)
             (emit! state 'status #f #f)))]
      [else
       (set-controller-state-current-sample!
        state
        (frame-sample next-index
                      (preview-render-spec-fps (controller-state-render-spec state))))
       (request-current! state jobs prefetch)])))

(define (jump-to-section! state name jobs prefetch)
  (unless (symbol? name)
    (raise-argument-error 'preview-jump-to-section! "symbol?" name))
  (define document (controller-state-document state))
  (define timeline (preview-document-timeline document))
  (unless timeline
    (raise-arguments-error 'preview-jump-to-section!
                            "preview source has authored sections"
                            "source" (preview-document-source document)))
  (define indices
    (preview-document-section-frame-indices document name (controller-state-render-spec state)))
  (set-controller-state-playing?! state #f)
  (set-controller-state-scrubbing?! state #f)
  (set-controller-state-current-quality!
   state (full-quality-for (controller-state-render-spec state)))
  (set-controller-state-current-sample!
   state
   (if (pair? indices)
       (frame-sample (car indices) (preview-render-spec-fps (controller-state-render-spec state)))
       (time-sample (authoring-section-start (timeline-section timeline name)))))
  (request-current! state jobs prefetch))

(define (jump-relative-section! state direction jobs prefetch)
  (define names (preview-document-section-names (controller-state-document state)))
  (unless (pair? names)
    (raise-arguments-error 'preview-section-navigation "preview source has authored sections"
                           "source" (preview-document-source (controller-state-document state))))
  (define current (current-section-name state))
  (define index
    (or (and current (index-of names current))
        (if (positive? direction) -1 (length names))))
  (jump-to-section! state
                    (list-ref names (modulo (+ index direction) (length names)))
                    jobs prefetch))

(define (jump-to-cue! state name jobs prefetch)
  (unless (symbol? name)
    (raise-argument-error 'preview-jump-to-cue! "symbol?" name))
  (define timeline (preview-document-timeline (controller-state-document state)))
  (unless timeline
    (raise-arguments-error 'preview-jump-to-cue! "preview source has authored cues"
                           "source" (preview-document-source (controller-state-document state))))
  (define cue-value
    (findf (lambda (entry) (eq? (cue-name entry) name))
           (authored-timeline-cues timeline)))
  (unless cue-value
    (raise-arguments-error 'preview-jump-to-cue! "known cue name" "name" name))
  (set-controller-state-playing?! state #f)
  (set-controller-state-scrubbing?! state #f)
  (set-controller-state-current-quality!
   state (full-quality-for (controller-state-render-spec state)))
  (set-controller-state-current-sample!
   state
   (preview-normalize-time-sample (controller-state-document state) (cue-time cue-value)))
  (request-current! state jobs prefetch))


;;;
;;; Rendering
;;;

(define (renderer-loop jobs completed producer byte-size)
  (let loop ()
    (define job (async-channel-get jobs))
    (unless (eq? job 'close)
      (define started (current-inexact-monotonic-milliseconds))
      (define result
        (with-handlers
            ([exn:fail:preview-canceled?
              (lambda (canceled)
                (render-result (render-job-request job)
                               (render-job-key job)
                               (if (eq? (exn:fail:preview-canceled-reason canceled)
                                        'superseded)
                                   'superseded
                                   'canceled)
                               #f 0
                               (hasheq 'render-milliseconds
                                       (- (current-inexact-monotonic-milliseconds) started))
                               canceled))]
             [exn:fail:preview-worker-timed-out?
              (lambda (timed-out)
                (render-result (render-job-request job)
                               (render-job-key job)
                               'timed-out #f 0
                               (hasheq 'render-milliseconds
                                       (- (current-inexact-monotonic-milliseconds) started))
                               timed-out))]
             [exn:fail:preview-worker-restarted?
              (lambda (restarted)
                (render-result (render-job-request job)
                               (render-job-key job)
                               'worker-restarted #f 0
                               (hasheq 'render-milliseconds
                                       (- (current-inexact-monotonic-milliseconds) started))
                               restarted))]
             [exn:fail?
              (lambda (error)
                (render-result (render-job-request job)
                               (render-job-key job)
                               'failed #f 0
                               (hasheq 'render-milliseconds
                                       (- (current-inexact-monotonic-milliseconds) started))
                               error))])
          (define token
            (preview-render-request-cancellation-token
             (render-job-request job)))
          (check-cancellation token)
          (define value
            (producer (render-job-document job)
                      (render-job-sample job)
                      (render-job-render-spec job)
                      token))
          (check-cancellation token)
          (define bytes (byte-size value))
          (unless (exact-nonnegative-integer? bytes)
            (raise-arguments-error
             'preview-frame-producer
             "byte-size procedure returned exact-nonnegative-integer?"
             "bytes" bytes))
          (render-result (render-job-request job)
                         (render-job-key job)
                         'complete value bytes
                         (hasheq 'render-milliseconds
                                 (- (current-inexact-monotonic-milliseconds) started))
                         #f)))
      (async-channel-put completed result)
      (loop))))

;; The production path is intentionally scene->pict followed by pict->bitmap,
;; just as final frame rendering is.  `pixel-scale` changes only the sampled
;; camera raster dimensions; world geometry, scene sampling, and easing remain
;; identical.
(define (default-frame-producer document sample render-spec cancellation-token)
  (check-cancellation cancellation-token)
  (define scene (preview-document-scene document))
  (define time (preview-sample-time document sample))
  (define source-camera
    (or (preview-render-spec-camera render-spec)
        (let-values ([(ignored camera) (scene-sample-with-camera scene time)])
          camera)))
  (check-cancellation cancellation-token)
  (define preview-camera
    (camera-at-pixel-scale source-camera (preview-render-spec-pixel-scale render-spec)))
  (define sampled-state (scene-sample scene time))
  (define rendered-state
    (for/fold ([state sampled-state])
              ([view-id
                (in-list
                 (sort (hash-keys (preview-render-spec-camera3d-overrides render-spec))
                       symbol<?))])
      (preview-camera3d-override-apply
       state
       (hash-ref (preview-render-spec-camera3d-overrides render-spec) view-id))))
  (check-cancellation cancellation-token)
  (parameterize ([current-software-render-cancellation-token cancellation-token])
    ;; The interactive in-process worker has the same contract as an isolated
    ;; renderer: author ODE callbacks run during preparation, not while a
    ;; spatial relation is resolved by the pict adapter.
    (call-with-ode-frame-samples
     (prepare-ode-frame-samples (list rendered-state))
     (lambda ()
       (call-with-ode3d-frame-samples
        (prepare-ode3d-frame-samples (list rendered-state))
        (lambda ()
          (pict->bitmap
           (scene-state->pict rendered-state
                              #:camera
                              (preview-camera-with-supersampling
                               preview-camera
                               (preview-render-spec-supersample render-spec))
                              #:renderers (preview-render-spec-renderers render-spec))
           'smoothed)))))))

(define (camera-at-pixel-scale camera pixel-scale)
  (define (scaled-pixels pixels)
    (max 1 (inexact->exact (round (* pixels pixel-scale)))))
  (make-camera #:width (scaled-pixels (camera-width camera))
               #:height (scaled-pixels (camera-height camera))
               #:world-width (camera-world-width camera)
               #:center (camera-center camera)
   #:background (camera-background camera)))

;; preview-camera-with-supersampling multiplies only raster dimensions after
;; the preview's independent pixel-scale has selected its display resolution.
(define (preview-camera-with-supersampling camera supersample)
  (if (= supersample 1)
      camera
      (make-camera #:width (* supersample (camera-width camera))
                   #:height (* supersample (camera-height camera))
                   #:world-width (camera-world-width camera)
                   #:center (camera-center camera)
                   #:background (camera-background camera))))

(define (default-bitmap-bytes bitmap)
  (unless (is-a? bitmap bitmap%)
    (raise-argument-error 'default-preview-byte-size "bitmap%" bitmap))
  (* 4 (send bitmap get-width) (send bitmap get-height)))


;;;
;;; Status and Helpers
;;;

(define (state-status state)
  (define document (controller-state-document state))
  (define sample (controller-state-current-sample state))
  (define displayed (controller-state-displayed-sample state))
  (define desired-time (preview-sample-time document sample))
  (define displayed-time
    (and displayed (preview-sample-time document displayed)))
  ;; This is semantic visual lag, not a claim about GUI paint latency. It
  ;; answers the production question “how far behind the requested timeline is
  ;; the bitmap currently on screen?” without inventing a value before any
  ;; bitmap exists.
  (define visual-lag
    (and displayed-time
         (* 1000 (max 0 (- desired-time displayed-time)))))
  (preview-status #t
                  (preview-document-source document)
                  (preview-document-generation document)
                  (controller-state-render-generation state)
                  sample
                  (preview-sample-frame-index sample)
                  desired-time
                  (controller-state-playing? state)
                  (current-section-name state)
                  (preview-cache-byte-count (controller-state-cache state))
                  (preview-cache-count (controller-state-cache state))
                  (hash-count (controller-state-pending state))
                  (and (controller-state-active-job state) #t)
                  (controller-state-error state)
                  (controller-state-canceled-request-count state)
                  (controller-state-current-quality state)
                  (controller-state-worker-mode state)
                  (controller-state-playback-speed state)
                  (controller-state-loop-range state)
                  (and (controller-state-playing? state)
                       (controller-state-looping? state))
                  displayed
                  (and displayed (preview-sample-frame-index displayed))
                  displayed-time
                  visual-lag
                  (controller-state-last-render-diagnostics state)))

;; The status record is ideal for a controller/GUI event. This richer immutable
;; datum is convenient for bug reports, a diagnostic pane, and headless tests.
;; It contains only measured or directly known values; #f means “not available”
;; rather than an estimated placeholder.
(define (state-diagnostics state)
  (define status (state-status state))
  (hasheq
   'timeline-time (preview-status-time status)
   'desired-frame (preview-status-frame status)
   'displayed-frame (preview-status-displayed-frame status)
   'displayed-time (preview-status-displayed-time status)
   'visual-lag-milliseconds (preview-status-visual-lag-milliseconds status)
   'preview-quality (preview-quality-name (preview-status-quality status))
   'worker-mode (preview-status-worker-mode status)
   'worker-hard-cancellation?
   (eq? (preview-status-worker-mode status) 'subprocess)
   'rendering? (preview-status-rendering? status)
   'pending-requests (preview-status-pending-count status)
   'cache-bytes (preview-status-cache-bytes status)
   'cache-count (preview-status-cache-count status)
   'canceled-requests (preview-status-canceled-request-count status)
   'recent-render-diagnostics
   (or (preview-status-last-render-diagnostics status) #hasheq())
   'playback-speed (preview-status-playback-speed status)
   'loop-range (preview-status-loop-range status)))

(define (current-key state)
  (make-preview-frame-key (controller-state-document state)
                          (controller-state-render-generation state)
                          (controller-state-current-sample state)
                          (active-render-spec state)))

;; Quality remains a rendering choice only.  All levels retain the configured
;; FPS, camera, renderer collection, and world-space sampling path.  The
;; different immutable render specs merely produce separate bitmap cache keys.
(define (active-render-spec state)
  (define base (controller-state-render-spec state))
  (define quality (controller-state-current-quality state))
  (make-preview-render-spec
   #:fps (preview-render-spec-fps base)
   #:camera (preview-render-spec-camera base)
   #:renderers (preview-render-spec-renderers base)
   #:pixel-scale (preview-quality-pixel-scale quality)
   #:supersample (preview-quality-supersample quality)
   #:camera3d-overrides (preview-render-spec-camera3d-overrides base)))

;; replace-camera3d-overrides! switches only the inspection layer.  Its own
;; render generation keeps bitmap-cache and worker results from an earlier
;; inspection camera out of the currently displayed preview.
(define (replace-camera3d-overrides! state overrides jobs prefetch)
  (define prior (controller-state-render-spec state))
  (define replacement
    (make-preview-render-spec
     #:fps (preview-render-spec-fps prior)
     #:camera (preview-render-spec-camera prior)
     #:renderers (preview-render-spec-renderers prior)
     #:pixel-scale (preview-render-spec-pixel-scale prior)
     #:supersample (preview-render-spec-supersample prior)
     #:camera3d-overrides overrides))
  (set-controller-state-render-spec! state replacement)
  (set-controller-state-current-quality! state (full-quality-for replacement))
  (set-controller-state-scrubbing?! state #f)
  (invalidate-render! state)
  (request-current! state jobs prefetch))

(define (full-quality-for render-spec)
  (preview-quality #:name 'full
                   #:pixel-scale (preview-render-spec-pixel-scale render-spec)
                   #:supersample (preview-render-spec-supersample render-spec)))

(define (scrub-quality-for state)
  (define spec (controller-state-render-spec state))
  (if (eq? (controller-state-quality-policy state) 'full)
      (full-quality-for spec)
      (preview-quality
       #:name 'draft
       #:pixel-scale (* 1/2 (preview-render-spec-pixel-scale spec))
       #:supersample (preview-render-spec-supersample spec))))

(define (settle-scrub! state jobs prefetch)
  (when (and (controller-state-scrubbing? state)
             (>= (- (current-inexact-monotonic-milliseconds)
                    (controller-state-last-scrub-milliseconds state))
                 (controller-state-settle-milliseconds state)))
    (set-controller-state-scrubbing?! state #f)
    (set-controller-state-current-quality!
     state (full-quality-for (controller-state-render-spec state)))
    ;; The draft and settled keys intentionally differ, so a low-resolution
    ;; bitmap cannot masquerade as the paused inspection frame.
    (request-current! state jobs prefetch)
    (emit! state 'status #f #f)))

(define (current-frame-index state)
  (define sample (controller-state-current-sample state))
  (if (frame-sample? sample)
      (frame-sample-frame-index sample)
      (let* ([fps (preview-render-spec-fps (controller-state-render-spec state))]
             [count (preview-document-frame-count (controller-state-document state)
                                                  (controller-state-render-spec state))])
        (if (zero? count)
            0
            (let ([raw-index
                   (inexact->exact
                    (floor (* (preview-sample-time (controller-state-document state) sample)
                              fps)))])
              (min (sub1 count) (max 0 raw-index)))))))

(define (last-frame-index state)
  (sub1 (preview-document-frame-count (controller-state-document state)
                                      (controller-state-render-spec state))))

(define (current-section-name state)
  (define document (controller-state-document state))
  (define timeline (preview-document-timeline document))
  (and timeline
       (let ([time (preview-sample-time document (controller-state-current-sample state))])
         (for/first ([entry (in-list (authored-timeline-sections timeline))]
                     #:when (and (<= (authoring-section-start entry) time)
                                 (< time (authoring-section-end entry))))
           (authoring-section-name entry)))))

(define (normalize-sample-for-document document sample render-spec)
  (cond
    [(frame-sample? sample)
     (preview-normalize-frame-sample document (frame-sample-frame-index sample) render-spec)]
    [else
     (preview-normalize-time-sample document (time-sample-time sample))]))

(define (initial-preview-sample document spec start section)
  (cond
    [section
     (unless (symbol? section)
       (raise-argument-error 'open-preview-controller "(or/c #f symbol?)" section))
     (define timeline (preview-document-timeline document))
     (unless timeline
       (raise-arguments-error 'open-preview-controller
                              "#:section requires an authored timeline"
                              "source" (preview-document-source document)))
     (define indices (preview-document-section-frame-indices document section spec))
     (if (pair? indices)
         (frame-sample (car indices) (preview-render-spec-fps spec))
         (time-sample (authoring-section-start (timeline-section timeline section))))]
    [(not start) (preview-normalize-frame-sample document 0 spec)]
    [else (preview-normalize-time-sample document start)]))

(define (emit! state kind bitmap error)
  (with-handlers ([exn:fail? (lambda (ignored) (void))])
    ((controller-state-event-callback state)
     (preview-event kind (state-status state) bitmap error))))

(define (match-arguments who arguments count)
  (unless (= (length arguments) count)
    (raise-arguments-error who "internal command argument count" "arguments" arguments)))

(define (check-time who label value)
  (unless (and (real? value) (rational? value))
    (raise-arguments-error who "finite real" label value)))

(define (check-session who session)
  (unless (preview-session? session)
    (raise-argument-error who "preview-session?" session)))

(define (status-field who session accessor)
  (accessor (send-controller-command who session 'status '())))

(define (send-controller-command who session kind arguments)
  (check-session who session)
  (unless (unbox (preview-session-alive? session))
    (raise-arguments-error who "open preview session" "session" session))
  (define reply (make-async-channel))
  (async-channel-put (preview-session-commands session)
                     (controller-command kind arguments reply))
  (define received (async-channel-get reply))
  (if (controller-reply-ok? received)
      (controller-reply-value received)
      (raise (controller-reply-value received))))
