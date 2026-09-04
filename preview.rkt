#lang racket/base

;;;
;;; Interactive Preview (headless model surface)
;;;

;; GUI support is loaded lazily by later preview-session operations.  Requiring
;; this module is safe in headless processes and does not load racket/gui.

(require racket/gui/dynamic
         racket/runtime-path
         (only-in "private/pict-adapter.rkt" default-pict-renderers)
         "private/preview-model.rkt"
         "private/preview-controller.rkt"
         "private/preview-transaction.rkt"
         "private/preview-repl.rkt"
         "private/program-preview.rkt"
         "private/program-loader.rkt"
         "private/scene-program.rkt")

(provide (all-from-out "private/preview-model.rkt"
                       "private/preview-controller.rkt"
                       "private/preview-transaction.rkt"
                       "private/program-preview.rkt")
         preview-available?
         open-scene-preview
         open-program-preview
         preview-reset-to-source!
         open-preview-repl!
         close-preview-repl!
         preview-repl-open?
         preview-repl-evaluate!
         preview-repl-evaluate-string!)

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
                            #:pixel-scale [pixel-scale 1/2]
                            #:cache-megabytes [cache-megabytes 128]
                            #:prefetch [prefetch 3]
                            #:title [title "animate preview"])
  (ensure-preview-gui 'open-scene-preview)
  (define session
    ((dynamic-require preview-window-path 'open-preview-window)
     source #:fps fps #:start start #:section section #:camera camera
     #:renderers renderers #:pixel-scale pixel-scale
     #:cache-megabytes cache-megabytes #:prefetch prefetch #:title title))
  (attach-preview-transactions!
   session #:initial-scene (preview-source-scene source))
  session)

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
                              #:pixel-scale [pixel-scale 1/2]
                              #:cache-megabytes [cache-megabytes 128]
                              #:prefetch [prefetch 3]
                              #:repl? [repl? #f]
                              #:open-source [open-source #f]
                              #:title [title "animate preview"])
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
