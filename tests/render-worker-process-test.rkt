#lang racket/base

;;;
;;; Shared Render-worker Process Tests
;;;

;; Exercises the real child process and framed wire protocol used by preview.
;; The temporary source deliberately has a space and non-ASCII path segment,
;; writes ordinary output, and starts a descendant so ownership evidence stays
;; local to the test process.


;;;
;;; Imports and Runtime Paths
;;;

;; Imports
(require rackunit
         racket/file
         racket/path
         racket/port
         racket/runtime-path
         racket/string
         racket/system
         "../private/color-theme.rkt"
         "../private/preview-model.rkt"
         "../private/render-worker-process.rkt"
         "../private/render-worker-protocol.rkt"
         "../private/typography-theme.rkt")

(define-runtime-path animate-main "../main.rkt")
(define-runtime-path builder-fixture "fixtures/project-builder-source.rkt")
(define-runtime-path value-fixture "fixtures/preview-worker-scene.rkt")


;;;
;;; Shared Test Values
;;;

; test-render-spec : preview-render-spec?
;;   Supplies one complete current appearance snapshot to each child request.
(define test-render-spec
  (make-preview-render-spec #:fps 2 #:pixel-scale 1/2))

; test-source-fingerprint : symbol?
;;   Identifies test-only source instances without affecting scene semantics.
(define test-source-fingerprint 'render-worker-process-test)


;;;
;;; Process Helpers
;;;

; render-test-frame! : render-worker-process? exact-nonnegative-integer?
;                       -> bytes? immutable-hash?
;;   Performs one current preview request through the real shared worker.
(define (render-test-frame! worker request-id)
  (render-worker-render-preview-frame!
   worker
   request-id
   '(frame 0 2)
   1/2
   1
   (theme->datum (preview-render-spec-theme test-render-spec))
   (typography-theme->datum (preview-render-spec-typography test-render-spec))
   '()))

; stop-and-check-resources! : render-worker-process? -> void?
;;   Stops one owned child and verifies parent-visible ports and readers close.
(define (stop-and-check-resources! worker)
  (render-worker-stop! worker)
  (define status (render-worker-resource-status worker))
  (check-false (hash-ref status 'open?))
  (check-true (hash-ref status 'input-closed?))
  (check-true (hash-ref status 'output-closed?))
  (check-true (hash-ref status 'error-closed?))
  (check-true (hash-ref status 'reader-dead?))
  (check-true (hash-ref status 'error-reader-dead?)))

; process-id-alive? : exact-positive-integer? -> boolean?
;;   Checks a test-owned local PID without inspecting unrelated processes.
(define (process-id-alive? pid)
  (parameterize ([current-output-port (open-output-nowhere)]
                 [current-error-port (open-output-nowhere)])
    (zero? (system*/exit-code "/bin/kill" "-0" (number->string pid)))))

; wait-until-dead? : exact-positive-integer? -> boolean?
;;   Gives the local process table a bounded interval to report a terminated child.
(define (wait-until-dead? pid)
  (let loop ([remaining 40])
    (cond
      [(not (process-id-alive? pid)) #t]
      [(zero? remaining) #f]
      [else
       (sleep 1/20)
       (loop (sub1 remaining))])))

; wait-for-noisy-log : render-worker-process? -> bytes?
;;   Lets the independently draining stderr reader retain the source's final lines.
(define (wait-for-noisy-log worker)
  (let loop ([remaining 100])
    (define log-bytes (render-worker-log-bytes worker))
    (define log-text (bytes->string/utf-8 log-bytes))
    (if (or (and (regexp-match? #rx"source stdout noise" log-text)
                 (regexp-match? #rx"source stderr noise" log-text))
            (zero? remaining))
        log-bytes
        (begin
          (sleep 1/50)
          (loop (sub1 remaining))))))

; write-temporary-source! : path? path? -> void?
;;   Writes a real module whose author output and child process must be contained.
(define (write-temporary-source! module-path descendant-pid-path)
  (call-with-output-file
   module-path
   #:exists 'truncate/replace
   (lambda (output)
     (fprintf output "#lang racket/base\n")
     (fprintf output "(require (file ~s))\n"
              (path->string (path->complete-path animate-main)))
     (fprintf output
              "(define-values (descendant ignored-out ignored-in ignored-err)\n  (subprocess #f #f #f (find-system-path 'exec-file) \"-e\" \"(sleep 30)\"))\n")
     (fprintf output "(call-with-output-file ~s #:exists 'truncate/replace\n"
              (path->string descendant-pid-path))
     (fprintf output
              "  (lambda (out) (display (subprocess-pid descendant) out)))\n")
     (fprintf output "(display (make-string 70000 #\\x))\n")
     (fprintf output "(displayln \"source stdout noise\")\n")
     (fprintf output "(eprintf \"source stderr noise\\n\")\n")
     (fprintf output "(provide temporary-scene)\n")
     (fprintf output
              "(define temporary-scene\n  (scene-wait\n   (scene-add (make-scene)\n              (circle #:id 'temporary-dot #:radius 1 #:fill \"tomato\"))\n   1))\n"))))

; make-builder-worker-source : -> render-worker-module-builder-source?
;;   Encodes a PR-A builder/preparer declaration without a second source loader.
(define (make-builder-worker-source)
  (define asset-base
    (path->string (or (path-only builder-fixture) (current-directory))))
  (render-worker-module-builder-source
   (path->string builder-fixture)
   'build-test-source!
   #hasheq((case . process-worker))
   'prepare-test-inputs!
   19
   (render-worker-build-context
    asset-base
    '()
    80
    50
    #hasheq()
    (theme->datum (preview-render-spec-theme test-render-spec))
    (typography-theme->datum (preview-render-spec-typography test-render-spec))
    2
    'preview
    19
    "process-worker-builder")
   #f))


;;;
;;; Framed Protocol and Inert Entry Points
;;;

(module+ test
  ;; Neither module starts a loop merely because a parent requires its API.
  (dynamic-require "../private/render-worker-main.rkt" #f)
  (dynamic-require "../private/preview-worker-main.rkt" #f)
  (check-exn exn:fail:render-worker-protocol?
             (lambda ()
               (read-render-worker-message
                (open-input-bytes #"0000000A"))))
  (check-exn exn:fail:render-worker-protocol?
             (lambda ()
               (read-render-worker-message
                (open-input-bytes #"02000001"))))
  (check-exn exn:fail:render-worker-protocol?
             (lambda ()
               (read-render-worker-message
                (open-input-bytes #"00000001x"))))
  (check-exn exn:fail:render-worker-protocol?
             (lambda ()
               (write-render-worker-message!
                (open-output-bytes)
                (render-worker-hello 5 "session" 'source 0 0 "" ""))))
  (check-false
   (render-worker-message-matches?
    (render-worker-frame-complete 1 "stale-session" 'source 0 3 #"" #hasheq())
    "current-session"
    'source
    0
    3)))


;;;
;;; Real Source Process, Logs, and Descendant Ownership
;;;

(module+ test
  (define temporary-root (make-temporary-file "animate-render-worker-test-~a" 'directory))
  (define source-directory (build-path temporary-root "source directory Ω"))
  (define source-path (build-path source-directory "noisy scene Ω.rkt"))
  (define descendant-pid-path (build-path temporary-root "descendant.pid"))
  (make-directory* source-directory)
  (dynamic-wind
   void
   (lambda ()
     (write-temporary-source! source-path descendant-pid-path)
     (define worker
       (start-render-worker!
        (render-worker-module-value-source (path->string source-path)
                                           'temporary-scene)
        #:source-fingerprint test-source-fingerprint))
     (define descendant-pid #f)
     (dynamic-wind
      void
      (lambda ()
        (check-true (render-worker-open? worker))
        (check-true (exact-positive-integer? (render-worker-pid worker)))
        (define-values (png-bytes diagnostics) (render-test-frame! worker 1))
        (check-true (positive? (bytes-length png-bytes)))
        (check-true (hash-has-key? diagnostics 'render-milliseconds))
        (define log-bytes (wait-for-noisy-log worker))
        (check-true (<= (bytes-length log-bytes) (* 64 1024)))
        (define logs (bytes->string/utf-8 log-bytes))
        (check-true (regexp-match? #rx"source stdout noise" logs))
        (check-true (regexp-match? #rx"source stderr noise" logs))
        (set! descendant-pid
              (string->number (string-trim (file->string descendant-pid-path))))
        (check-true (exact-positive-integer? descendant-pid))
        (check-true (process-id-alive? descendant-pid)))
      (lambda () (stop-and-check-resources! worker)))
     ;; This is direct local evidence for the test-owned descendant only.
     (check-true (wait-until-dead? descendant-pid)))
   (lambda ()
     (when (directory-exists? temporary-root)
       (delete-directory/files temporary-root)))))


;;;
;;; Startup, Crash, Cancellation, Restart, and Builder Source
;;;

(module+ test
  (check-exn
   exn:fail:render-worker-startup?
   (lambda ()
     (start-render-worker!
      (render-worker-module-value-source (path->string value-fixture) 'worker-scene)
      #:racket "/definitely/not-an-animate-racket"
      #:startup-timeout-milliseconds 500)))
  (check-exn
   exn:fail:render-worker-startup?
   (lambda ()
     (start-render-worker!
      (render-worker-module-value-source (path->string value-fixture) 'not-exported))))
  (define worker
    (start-render-worker!
     (render-worker-module-value-source (path->string value-fixture) 'worker-scene)
     #:source-fingerprint 'lifecycle))
  (dynamic-wind
   void
   (lambda ()
     (check-exn
      exn:fail:render-worker-timeout?
      (lambda ()
        (render-worker-render-preview-frame!
         worker
         1
         '(frame 0 2)
         1/2
         1
         (theme->datum (preview-render-spec-theme test-render-spec))
         (typography-theme->datum (preview-render-spec-typography test-render-spec))
         '()
         #:timeout-milliseconds 1)))
     (render-worker-restart! worker #:generation 1)
     (check-exn
      exn:fail:render-worker-canceled?
      (lambda ()
        (render-worker-render-preview-frame!
         worker
         2
         '(frame 0 2)
         1/2
         1
         (theme->datum (preview-render-spec-theme test-render-spec))
         (typography-theme->datum (preview-render-spec-typography test-render-spec))
         '()
         #:canceled? (lambda () #t))))
     (render-worker-cancel! worker 2 'test-canceled)
     (render-worker-restart! worker #:generation 2)
     (define-values (recovered _diagnostics) (render-test-frame! worker 3))
     (check-true (positive? (bytes-length recovered)))
     ;; A malformed framed command causes a real child protocol failure, and
     ;; the supervisor maps the resulting EOF to the crash outcome.
     (render-worker-write-raw-for-test! worker #"00000001x")
     (check-exn
      exn:fail:render-worker-crashed?
      (lambda () (render-test-frame! worker 4))))
   (lambda () (stop-and-check-resources! worker)))
  (define builder-worker
    (start-render-worker!
     (make-builder-worker-source)
     #:source-fingerprint 'builder-source))
  (dynamic-wind
   void
   (lambda ()
     (define-values (png-bytes _diagnostics) (render-test-frame! builder-worker 5))
     (check-true (positive? (bytes-length png-bytes))))
   (lambda () (stop-and-check-resources! builder-worker))))
