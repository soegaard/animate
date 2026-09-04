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
         (only-in "pict-adapter.rkt" default-pict-renderers)
         "preview-cache.rkt"
         "preview-model.rkt"
         "scene.rkt")

(provide (struct-out preview-event)
         (struct-out preview-status)
         preview-session?
         open-preview-controller
         preview-open?
         preview-source
         preview-current-frame
         preview-current-time
         preview-current-sample
         preview-current-bitmap
         preview-playing?
         preview-session-status
         preview-seek-frame!
         preview-seek!
         preview-step!
         preview-play!
         preview-play-range!
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
         preview-set-source!
         preview-report-error!
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
                        error)
  #:transparent)


;;;
;;; Private Actor Messages and State
;;;

(struct controller-command (kind arguments reply)
  #:transparent)

(struct controller-reply (ok? value)
  #:transparent)

(struct render-job (key document sample render-spec)
  #:transparent)

(struct render-result (key value bytes error)
  #:transparent)

(struct controller-state (document
                          render-spec
                          render-generation
                          cache
                          current-sample
                          current-bitmap
                          playing?
                          play-start-index
                          play-end-index
                          play-start-milliseconds
                          high-jobs
                          low-jobs
                          pending
                          active-key
                          error
                          event-callback)
  #:mutable
  #:transparent)


;;;
;;; Construction
;;;

;; `producer` receives immutable values in the order document, sample, spec.
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
                                 #:producer [producer default-frame-producer]
                                 #:byte-size [byte-size default-bitmap-bytes]
                                 #:on-event [on-event void])
  (unless (procedure? producer)
    (raise-argument-error 'open-preview-controller "procedure?" producer))
  (unless (procedure? byte-size)
    (raise-argument-error 'open-preview-controller "procedure?" byte-size))
  (unless (procedure? on-event)
    (raise-argument-error 'open-preview-controller "procedure?" on-event))
  (unless (and (real? cache-megabytes) (rational? cache-megabytes)
               (positive? cache-megabytes))
    (raise-argument-error 'open-preview-controller "positive finite real?" cache-megabytes))
  (unless (exact-nonnegative-integer? prefetch)
    (raise-argument-error 'open-preview-controller "exact-nonnegative-integer?" prefetch))
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
    (thread (lambda () (renderer-loop jobs completed producer byte-size))))
  (define state
    (controller-state document spec 0 (make-preview-cache byte-limit)
                      initial-sample #f #f #f #f #f
                      '() '() (make-hash) #f #f on-event))
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

(define (preview-current-bitmap session)
  (send-controller-command 'preview-current-bitmap session 'bitmap '()))

(define (preview-playing? session)
  (status-field 'preview-playing? session preview-status-playing?))

(define (preview-session-status session)
  (send-controller-command 'preview-session-status session 'status '()))

(define (preview-seek-frame! session frame-index)
  (send-controller-command 'preview-seek-frame! session 'seek-frame (list frame-index)))

(define (preview-seek! session time)
  (send-controller-command 'preview-seek! session 'seek-time (list time)))

(define (preview-step! session [delta 1])
  (send-controller-command 'preview-step! session 'step (list delta)))

(define (preview-play! session)
  (send-controller-command 'preview-play! session 'play '()))

(define (preview-play-range! session start end)
  (send-controller-command 'preview-play-range! session 'play-range (list start end)))

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
    ;; A short timeout keeps playback tied to a monotonic clock even when no
    ;; command or renderer completion arrives.
    (define message
      (sync/timeout
       1/120
       (handle-evt commands
                   (lambda (command) (cons 'command command)))
       (handle-evt completed
                   (lambda (result) (cons 'result result)))))
    (cond
      [(and message (eq? (car message) 'command))
       (handle-command! state (cdr message) jobs worker alive? prefetch)]
      [(and message (eq? (car message) 'result))
       (handle-render-result! state (cdr message) jobs prefetch)]
      [else (advance-playback! state jobs prefetch)])
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
        [(bitmap) (controller-state-current-bitmap state)]
        [(seek-frame)
         (match-arguments 'seek-frame (controller-command-arguments command) 1)
         (set-controller-state-playing?! state #f)
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
         (set-controller-state-current-sample!
          state
          (preview-normalize-time-sample
           (controller-state-document state)
           (car (controller-command-arguments command))))
         (set-controller-state-error! state #f)
         (request-current! state jobs prefetch)
         (state-status state)]
        [(step)
         (match-arguments 'step (controller-command-arguments command) 1)
         (define delta (car (controller-command-arguments command)))
         (unless (exact-integer? delta)
           (raise-argument-error 'preview-step! "exact-integer?" delta))
         (set-controller-state-playing?! state #f)
         (set-controller-state-current-sample!
          state
          (preview-normalize-frame-sample
           (controller-state-document state)
           (+ (current-frame-index state) delta)
           (controller-state-render-spec state)))
         (request-current! state jobs prefetch)
         (state-status state)]
        [(play)
         (start-playback! state (current-frame-index state)
                          (last-frame-index state) jobs prefetch)
         (state-status state)]
        [(play-range)
         (match-arguments 'play-range (controller-command-arguments command) 2)
         (define start (car (controller-command-arguments command)))
         (define end (cadr (controller-command-arguments command)))
         (start-playback-range! state start end jobs prefetch)
         (state-status state)]
        [(pause)
         (set-controller-state-playing?! state #f)
         (emit! state 'status #f #f)
         (state-status state)]
        [(toggle-play)
         (if (controller-state-playing? state)
             (begin
               (set-controller-state-playing?! state #f)
               (emit! state 'status #f #f))
             (start-playback! state (current-frame-index state)
                              (last-frame-index state) jobs prefetch))
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
         (set-controller-state-current-sample!
          state
          (normalize-sample-for-document
           (controller-state-document state)
           (controller-state-current-sample state)
           spec))
         (invalidate-render! state)
         (request-current! state jobs prefetch)
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
  (define key (current-key state))
  (define missing (gensym 'preview-cache-missing))
  (define cached (preview-cache-ref! (controller-state-cache state) key missing))
  (cond
    [(not (eq? cached missing))
     (set-controller-state-current-bitmap! state cached)
     (emit! state 'frame-ready cached #f)
     (schedule-prefetch! state jobs prefetch)]
    [else
     ;; A new exact request supersedes queued scrub and prefetch work.  An
     ;; already-running worker cannot safely be interrupted, but its late result
     ;; will only be displayed if it still matches this key.
     (clear-queued-jobs! state)
     (enqueue-job! state (render-job key
                                     (controller-state-document state)
                                     sample
                                     (controller-state-render-spec state))
                   #:high? #t)
     (start-next-job! state jobs)
     (emit! state 'rendering #f #f)]))

(define (schedule-prefetch! state jobs prefetch)
  (when (and (positive? prefetch)
             (frame-sample? (controller-state-current-sample state)))
    (define sample (controller-state-current-sample state))
    (define fps (frame-sample-fps sample))
    (define document (controller-state-document state))
    (define spec (controller-state-render-spec state))
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
        (enqueue-job! state (render-job key document next-sample spec) #:high? #f)))
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

(define (clear-queued-jobs! state)
  (for ([job (in-list (append (controller-state-high-jobs state)
                              (controller-state-low-jobs state)))])
    (hash-remove! (controller-state-pending state) (render-job-key job)))
  (set-controller-state-high-jobs! state '())
  (set-controller-state-low-jobs! state '()))

(define (start-next-job! state jobs)
  (unless (controller-state-active-key state)
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
      (set-controller-state-active-key! state (render-job-key job))
      (async-channel-put jobs job))))

(define (handle-render-result! state result jobs prefetch)
  (when (equal? (controller-state-active-key state) (render-result-key result))
    (set-controller-state-active-key! state #f))
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
       (set-controller-state-error! state #f)
       (emit! state 'frame-ready (render-result-value result) #f)
       (schedule-prefetch! state jobs prefetch))])
  (start-next-job! state jobs))

(define (invalidate-render! state)
  (set-controller-state-render-generation!
   state
   (add1 (controller-state-render-generation state)))
  (preview-cache-clear! (controller-state-cache state))
  (clear-queued-jobs! state)
  (set-controller-state-current-bitmap! state #f)
  (set-controller-state-error! state #f))


;;;
;;; Playback and Timeline Navigation
;;;

(define (start-playback! state start-index end-index jobs prefetch)
  (cond
    [(negative? end-index)
     (set-controller-state-playing?! state #f)]
    [else
     (define start (min (max start-index 0) end-index))
     (set-controller-state-current-sample!
      state
      (frame-sample start (preview-render-spec-fps (controller-state-render-spec state))))
     (set-controller-state-play-start-index! state start)
     (set-controller-state-play-end-index! state end-index)
     (set-controller-state-play-start-milliseconds! state
                                                     (current-inexact-monotonic-milliseconds))
     (set-controller-state-playing?! state #t)
     (request-current! state jobs prefetch)
     (emit! state 'status #f #f)]))

(define (start-playback-range! state start end jobs prefetch)
  (check-time 'preview-play-range! "start" start)
  (check-time 'preview-play-range! "end" end)
  (unless (< start end)
    (raise-arguments-error
     'preview-play-range!
     "start must be less than end"
     "start" start "end" end))
  (define document (controller-state-document state))
  (define duration (scene-duration (preview-document-scene document)))
  (define clamped-start (min (max start 0) duration))
  (define clamped-end (min (max end 0) duration))
  (unless (< clamped-start clamped-end)
    (raise-arguments-error
     'preview-play-range!
     "range intersects the scene"
     "start" start "end" end "duration" duration))
  (define fps (preview-render-spec-fps (controller-state-render-spec state)))
  (define start-index (inexact->exact (ceiling (* clamped-start fps))))
  ;; The endpoint is exclusive, exactly like authored sections.
  (define end-index (sub1 (inexact->exact (ceiling (* clamped-end fps)))))
  (start-playback! state start-index (min end-index (last-frame-index state)) jobs prefetch))

(define (advance-playback! state jobs prefetch)
  (when (controller-state-playing? state)
    (define elapsed
      (/ (- (current-inexact-monotonic-milliseconds)
            (controller-state-play-start-milliseconds state))
         1000.0))
    (define fps (preview-render-spec-fps (controller-state-render-spec state)))
    (define desired
      (+ (controller-state-play-start-index state)
         (inexact->exact (floor (* fps elapsed)))))
    (cond
      [(> desired (controller-state-play-end-index state))
       (set-controller-state-playing?! state #f)
       (set-controller-state-current-sample!
        state
        (frame-sample (controller-state-play-end-index state) fps))
       (request-current! state jobs prefetch)
       (emit! state 'status #f #f)]
      [(not (equal? (controller-state-current-sample state)
                    (frame-sample desired fps)))
       (set-controller-state-current-sample! state (frame-sample desired fps))
       ;; Slow rendering cannot slow semantic playback.  A newly desired frame
       ;; replaces queued frames that were never displayed.
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
      (define result
        (with-handlers
            ([exn:fail?
              (lambda (error)
                (render-result (render-job-key job) #f 0 error))])
          (define value
            (producer (render-job-document job)
                      (render-job-sample job)
                      (render-job-render-spec job)))
          (define bytes (byte-size value))
          (unless (exact-nonnegative-integer? bytes)
            (raise-arguments-error
             'preview-frame-producer
             "byte-size procedure returned exact-nonnegative-integer?"
             "bytes" bytes))
          (render-result (render-job-key job) value bytes #f)))
      (async-channel-put completed result)
      (loop))))

;; The production path is intentionally scene->pict followed by pict->bitmap,
;; just as final frame rendering is.  `pixel-scale` changes only the sampled
;; camera raster dimensions; world geometry, scene sampling, and easing remain
;; identical.
(define (default-frame-producer document sample render-spec)
  (define scene (preview-document-scene document))
  (define time (preview-sample-time document sample))
  (define source-camera
    (or (preview-render-spec-camera render-spec)
        (let-values ([(ignored camera) (scene-sample-with-camera scene time)])
          camera)))
  (define preview-camera
    (camera-at-pixel-scale source-camera (preview-render-spec-pixel-scale render-spec)))
  (pict->bitmap
   (scene->pict scene time
                #:camera preview-camera
                #:renderers (preview-render-spec-renderers render-spec)
                #:supersample (preview-render-spec-supersample render-spec))
   'smoothed))

(define (camera-at-pixel-scale camera pixel-scale)
  (define (scaled-pixels pixels)
    (max 1 (inexact->exact (round (* pixels pixel-scale)))))
  (make-camera #:width (scaled-pixels (camera-width camera))
               #:height (scaled-pixels (camera-height camera))
               #:world-width (camera-world-width camera)
               #:center (camera-center camera)
               #:background (camera-background camera)))

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
  (preview-status #t
                  (preview-document-source document)
                  (preview-document-generation document)
                  (controller-state-render-generation state)
                  sample
                  (preview-sample-frame-index sample)
                  (preview-sample-time document sample)
                  (controller-state-playing? state)
                  (current-section-name state)
                  (preview-cache-byte-count (controller-state-cache state))
                  (preview-cache-count (controller-state-cache state))
                  (hash-count (controller-state-pending state))
                  (and (controller-state-active-key state) #t)
                  (controller-state-error state)))

(define (current-key state)
  (make-preview-frame-key (controller-state-document state)
                          (controller-state-render-generation state)
                          (controller-state-current-sample state)
                          (controller-state-render-spec state)))

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
