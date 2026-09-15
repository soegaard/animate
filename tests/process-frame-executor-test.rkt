#lang racket/base

;;;
;;; Subprocess Final Frame Executor Tests
;;;

;; Exercises the PR-C final PNG path with real Racket children. The tests keep
;; all staging and final output below owned temporary directories.


;;;
;;; Imports and Runtime Paths
;;;

;; Imports
(require rackunit
         racket/class
         racket/draw
         racket/file
         racket/list
         racket/path
         racket/port
         racket/runtime-path
         "../colors.rkt"
         "../main.rkt"
         "../project.rkt"
         "../typography.rkt"
         "../private/frame-renderer.rkt"
         "../private/process-frame-executor.rkt"
         "../private/render-frame-job.rkt"
         "../private/render-worker-process.rkt"
         "../private/render-worker-protocol.rkt")

(define-runtime-path final-fixture "fixtures/final-render-worker-scene.rkt")


;;;
;;; Shared Test Data
;;;

; test-camera : camera?
;;   Fixes an odd explicit raster size so supersampling dimensions are observable.
(define test-camera
  (make-camera #:width 71 #:height 43 #:world-width 10))

; test-source : render-worker-module-value-source?
;;   Reconstructs the moving fixture in each child process.
(define test-source
  (render-worker-module-value-source (path->string final-fixture)
                                     'final-render-scene))

; test-fingerprint : symbol?
;;   Names this test session without changing fixture construction.
(define test-fingerprint 'process-frame-executor-test)


;;;
;;; Job and Pixel Helpers
;;;

; make-test-jobs : (listof exact-nonnegative-integer?) string? color-theme?
;                  typography-theme? camera? exact-positive-integer?
;                  -> (listof final-render-frame-job?)
;;   Builds a local-output sequence whose source indices remain explicit.
(define (make-test-jobs source-indices session-id theme typography camera supersample)
  (for/list ([source-index (in-list source-indices)]
             [output-index (in-naturals 0)])
    (make-final-render-frame-job
     session-id
     test-fingerprint
     0
     (add1 output-index)
     source-index
     output-index
     2
     #:camera camera
     #:supersample supersample
     #:theme-datum (theme->datum theme)
     #:typography-datum (typography-theme->datum typography))))

; bitmap->argb-bytes : bitmap% -> bytes?
;;   Returns canonical decoded pixels for fixed-environment PNG equivalence.
(define (bitmap->argb-bytes bitmap)
  (define bytes
    (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0
        (send bitmap get-width) (send bitmap get-height)
        bytes)
  bytes)

; png->argb-bytes : path? -> bytes?
;;   Decodes one completed test PNG only for regression comparison.
(define (png->argb-bytes path)
  (bitmap->argb-bytes (read-bitmap path)))

; local-reference-pixels : (listof exact-nonnegative-integer?) camera?
;                           exact-positive-integer? color-theme? typography-theme?
;                           -> (listof bytes?)
;;   Uses the existing in-process authoritative frame adapter as the reference.
(define (local-reference-pixels source-indices camera supersample theme typography)
  (define scene (dynamic-require final-fixture 'final-render-scene))
  (for/list ([source-index (in-list source-indices)])
    (bitmap->argb-bytes
     (scene-frame->bitmap scene source-index
                          #:fps 2
                          #:camera camera
                          #:supersample supersample
                          #:theme theme
                          #:typography typography))))

; frame-files : path? -> (listof path?)
;;   Lists only canonical public final frame files in deterministic order.
(define (frame-files directory)
  (sort
   (for/list ([entry (in-list (directory-list directory))]
              #:when (regexp-match? #px"^frame-[0-9]{6,}\\.png$"
                                   (path->string entry)))
     (build-path directory entry))
   path<?))

; status-closed? : immutable-hash? -> boolean?
;;   Confirms the parent-visible resources owned by one stopped worker are gone.
(define (status-closed? status)
  (and (not (hash-ref status 'open?))
       (hash-ref status 'input-closed?)
       (hash-ref status 'output-closed?)
       (hash-ref status 'error-closed?)
       (hash-ref status 'reader-dead?)
       (hash-ref status 'error-reader-dead?)))


;;;
;;; Real Subprocess Rendering and Scheduling
;;;

(module+ test
  (define render-root
    (make-temporary-file "animate-process-frame-executor-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define source-indices '(3 7 11))
     (define reference-pixels
       (local-reference-pixels source-indices test-camera 1
                               animate-light-theme animate-typography-theme))
     (define one-output (build-path render-root "one worker"))
     (define two-output (build-path render-root "two workers Ω"))
     (define one-report
       (render-final-frame-jobs!
        test-source
        (make-test-jobs source-indices "one-worker" animate-light-theme
                        animate-typography-theme test-camera 1)
        one-output
        #:workers 1))
     (define two-report
       (render-final-frame-jobs!
        test-source
        (make-test-jobs source-indices "two-workers" animate-light-theme
                        animate-typography-theme test-camera 1)
        two-output
        #:workers 2))
     ;; Source indices 3, 7, and 11 become local slots 0, 1, and 2.
     (check-equal?
      (map (lambda (path) (path->string (file-name-from-path path)))
           (process-frame-execution-report-output-paths two-report))
      '("frame-000000.png" "frame-000001.png" "frame-000002.png"))
     (check-equal? (process-frame-execution-report-source-frame-indices two-report)
                   source-indices)
     (check-equal? (process-frame-execution-report-output-frame-indices two-report)
                   '(0 1 2))
     (check-equal? (map png->argb-bytes (frame-files one-output)) reference-pixels)
     (check-equal? (map png->argb-bytes (frame-files two-output)) reference-pixels)
     (check-equal? (map png->argb-bytes (frame-files one-output))
                   (map png->argb-bytes (frame-files two-output)))
     (check-equal? (process-frame-execution-report-workers-started one-report) 1)
     (check-equal? (process-frame-execution-report-workers-started two-report) 2)
     (check-equal? (process-frame-execution-report-workers-completing two-report) 2)
     (check-equal? (length (remove-duplicates
                            (process-frame-execution-report-worker-pids two-report)))
                   2)
     (check-true
      (andmap status-closed?
              (process-frame-execution-report-worker-resource-statuses two-report)))
     ;; Parent-observed timing evidence remains ordered by worker startup and
     ;; separates launch/ready work from the all-ready raster and publication phases.
     (define two-worker-timings
       (process-frame-execution-report-worker-timings two-report))
     (check-equal? (map (lambda (timing) (hash-ref timing 'pid)) two-worker-timings)
                   (process-frame-execution-report-worker-pids two-report))
     (check-true
      (andmap
       (lambda (timing)
         (and (real? (hash-ref timing 'spawn-milliseconds))
              (real? (hash-ref timing 'hello-milliseconds))
              (real? (hash-ref timing 'source-ready-milliseconds))
              (real? (hash-ref timing 'ready-latency-milliseconds))
              (real? (hash-ref timing 'raster-execution-span-milliseconds))
              (>= (hash-ref timing 'spawn-milliseconds) 0)
              (>= (hash-ref timing 'hello-milliseconds) 0)
              (>= (hash-ref timing 'source-ready-milliseconds) 0)))
       two-worker-timings))
     (check-true (real? (process-frame-execution-report-startup-milliseconds two-report)))
     (check-true (real? (process-frame-execution-report-raster-execution-milliseconds two-report)))
     (check-true (real? (process-frame-execution-report-publication-milliseconds two-report)))
     ;; Staging is session-private and completely removed after publication.
     (check-false
      (for/or ([entry (in-list (directory-list two-output))])
        (regexp-match? #px"^\\.animate-process-frame-" (path->string entry))))

     ;; A capacity greater than the job count starts only useful process slots.
     (define fewer-output (build-path render-root "fewer jobs"))
     (define fewer-report
       (render-final-frame-jobs!
        test-source
        (make-test-jobs '(3) "fewer-jobs" animate-light-theme
                        animate-typography-theme test-camera 1)
        fewer-output
        #:workers 4))
     (check-equal? (process-frame-execution-report-workers-started fewer-report) 1)
     (check-equal? (process-frame-execution-report-workers-completing fewer-report) 1)
     (check-equal? (length (frame-files fewer-output)) 1)

     ;; A zero plan neither starts a child nor creates an output directory.
     (define zero-output (build-path render-root "zero jobs"))
     (define zero-report
       (render-final-frame-jobs! test-source '() zero-output #:workers 3))
     (check-equal? (process-frame-execution-report-workers-started zero-report) 0)
     (check-false (directory-exists? zero-output))

     ;; A pre-existing directory is an occupied output slot, not a destination.
     (define occupied-output (build-path render-root "occupied directory"))
     (make-directory* occupied-output)
     (make-directory (build-path occupied-output "frame-000000.png"))
     (check-exn
      exn:fail:process-frame-execution?
      (lambda ()
        (render-final-frame-jobs!
         test-source
         (make-test-jobs '(3) "occupied-directory" animate-light-theme
                         animate-typography-theme test-camera 1)
         occupied-output
         #:workers 1))))
   (lambda ()
     (when (directory-exists? render-root)
       (delete-directory/files render-root)))))


;;;
;;; Appearance and Builder Initialization
;;;

(module+ test
  (define appearance-root
    (make-temporary-file "animate-process-frame-appearance-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define alternate-typography
       (typography-theme #:id 'final-render-test-typography
                         #:extends animate-typography-theme
                         #:display-name "Final render test typography"))
     (define light-output (build-path appearance-root "light"))
     (define dark-output (build-path appearance-root "dark"))
     (define light-report
       (render-final-frame-jobs!
        test-source
        (make-test-jobs '(3) "light" animate-light-theme
                        alternate-typography test-camera 2)
        light-output))
     (define dark-report
       (render-final-frame-jobs!
        test-source
        (make-test-jobs '(3) "dark" animate-dark-theme
                        alternate-typography test-camera 2)
        dark-output))
     (define light-bitmap (read-bitmap (car (process-frame-execution-report-output-paths light-report))))
     (define dark-bitmap (read-bitmap (car (process-frame-execution-report-output-paths dark-report))))
     (check-equal? (send light-bitmap get-width) 142)
     (check-equal? (send light-bitmap get-height) 86)
     (check-equal? (send dark-bitmap get-width) 142)
     (check-equal? (send dark-bitmap get-height) 86)
     (check-false (equal? (bitmap->argb-bytes light-bitmap)
                          (bitmap->argb-bytes dark-bitmap)))

     (define builder-root (build-path appearance-root "builder observations"))
     (make-directory* builder-root)
     (define builder-source
       (render-worker-module-builder-source
        (path->string final-fixture)
        'build-final-render-source!
        #hasheq()
        'prepare-final-render-source!
        17
        (render-worker-build-context
         (path->string builder-root)
         '()
         71
         43
         #hasheq()
         (theme->datum animate-light-theme)
         (typography-theme->datum alternate-typography)
         2
         'final
         17
         "final-render-builder")
        #f))
     (define builder-output (build-path appearance-root "builder frames"))
     (define builder-report
       (render-final-frame-jobs!
        builder-source
        (make-test-jobs '(3 7 11) "builder" animate-light-theme
                        alternate-typography test-camera 1)
        builder-output
        #:workers 2))
     (define initialization-lines
       (file->lines (build-path builder-root "final-render-initialization.log")))
     ;; Each of two child generations prepared and built once, despite three jobs.
     (check-equal? (length initialization-lines) 4)
     (check-equal? (sort initialization-lines string<?)
                   '("build" "build" "prepare" "prepare"))
     (check-equal? (process-frame-execution-report-completed-frame-count builder-report) 3))
   (lambda ()
     (when (directory-exists? appearance-root)
       (delete-directory/files appearance-root)))))


;;;
;;; Failure, Cancellation, and Protocol Boundaries
;;;

(module+ test
  (define failure-root
    (make-temporary-file "animate-process-frame-failure-test-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     ;; A timed-out final job is fail-fast and leaves no public PNG output.
     (define timeout-output (build-path failure-root "timeout"))
     (define timeout-report #f)
     (check-exn
      exn:fail:process-frame-execution?
      (lambda ()
        (with-handlers ([exn:fail:process-frame-execution?
                         (lambda (error)
                           (set! timeout-report
                                 (exn:fail:process-frame-execution-report error))
                           (raise error))])
          (render-final-frame-jobs!
           test-source
           (make-test-jobs '(3) "timeout" animate-light-theme
                           animate-typography-theme
                           (make-camera #:width 1200 #:height 800 #:world-width 10)
                           1)
           timeout-output
           #:frame-timeout-milliseconds 1))))
     (check-eq? (process-frame-failure-phase
                 (process-frame-execution-report-failure timeout-report))
                'timeout)
     (check-equal? (frame-files timeout-output) '())
     (check-true
      (andmap status-closed?
              (process-frame-execution-report-worker-resource-statuses timeout-report)))

     ;; Cancellation reaches the scheduler before a slot can publish output.
     (define canceled-output (build-path failure-root "canceled"))
     (define canceled-report #f)
     (check-exn
      exn:fail:process-frame-execution?
      (lambda ()
        (with-handlers ([exn:fail:process-frame-execution?
                         (lambda (error)
                           (set! canceled-report
                                 (exn:fail:process-frame-execution-report error))
                           (raise error))])
          (render-final-frame-jobs!
           test-source
           (make-test-jobs '(3 7) "canceled" animate-light-theme
                           animate-typography-theme test-camera 1)
           canceled-output
           #:workers 2
           #:canceled? (lambda () #t)))))
     (check-true (process-frame-execution-report-canceled? canceled-report))
     (check-equal? (frame-files canceled-output) '())

     ;; A child cannot turn a parent-owned root into a traversal or arbitrary name.
     (define valid-job
       (car (make-test-jobs '(3) "protocol" animate-light-theme
                            animate-typography-theme test-camera 1)))
     (check-exn
      exn:fail:render-worker-protocol?
      (lambda ()
        (write-render-worker-message!
         (open-output-bytes)
         (render-worker-render-final-frame
          render-worker-protocol-version
          (final-render-frame-job-session-id valid-job)
          (final-render-frame-job-source-fingerprint valid-job)
          0
          (final-render-frame-job-request-id valid-job)
          (final-render-frame-job-source-frame-index valid-job)
          (final-render-frame-job-output-frame-index valid-job)
          (final-render-frame-job-fps valid-job)
          (final-render-frame-job-camera-datum valid-job)
          (final-render-frame-job-supersample valid-job)
          (final-render-frame-job-theme-datum valid-job)
          (final-render-frame-job-typography-datum valid-job)
          'default
          #hasheq()
          "../escape.png"))))
     (check-false
      (render-worker-message-matches?
       (render-worker-final-frame-complete
        1 "old-session" test-fingerprint 0 1 3 0 "frame-000000.png" 71 43 1 #hasheq())
       "current-session" test-fingerprint 0 1))

     ;; A bad module export fails during real child source loading before output.
     (define invalid-output (build-path failure-root "invalid export"))
     (check-exn
      exn:fail:process-frame-execution?
      (lambda ()
        (render-final-frame-jobs!
         (render-worker-module-value-source (path->string final-fixture)
                                            'not-an-export)
         (make-test-jobs '(3) "invalid-export" animate-light-theme
                         animate-typography-theme test-camera 1)
         invalid-output)))
     (check-equal? (frame-files invalid-output) '())

     ;; A worker-side publication failure removes its temporary sibling file.
     (define write-root (build-path failure-root "write failure"))
     (make-directory* write-root)
     (make-directory (build-path write-root "frame-000000.png"))
     (define write-worker
       (start-render-worker!
        test-source
        #:session-id "write-failure"
        #:source-fingerprint test-fingerprint
        #:final-output-root write-root))
     (dynamic-wind
      void
      (lambda ()
        (check-exn
         exn:fail:render-worker-failed?
         (lambda ()
           (render-worker-render-final-frame!
            write-worker
            (car (make-test-jobs '(3) "write-failure" animate-light-theme
                                 animate-typography-theme test-camera 1))))))
     (lambda () (render-worker-stop! write-worker)))
     (check-false
      (for/or ([entry (in-list (directory-list write-root))]
               #:when (regexp-match? #px"^\\.animate-final-render-"
                                    (path->string entry)))
        entry))

     ;; A malformed command causes the real final-worker child to close; the
     ;; shared supervisor maps the following final request to a crash outcome.
     (define crash-root (build-path failure-root "malformed worker"))
     (make-directory* crash-root)
     (define crash-worker
       (start-render-worker!
        test-source
        #:session-id "malformed-worker"
        #:source-fingerprint test-fingerprint
        #:final-output-root crash-root))
     (dynamic-wind
      void
      (lambda ()
        (render-worker-write-raw-for-test! crash-worker #"00000001x")
        (check-exn
         exn:fail:render-worker-crashed?
         (lambda ()
           (render-worker-render-final-frame!
            crash-worker
            (car (make-test-jobs '(3) "malformed-worker" animate-light-theme
                                 animate-typography-theme test-camera 1))))))
      (lambda () (render-worker-stop! crash-worker)))
     (check-false (file-exists? (build-path crash-root "frame-000000.png")))
     )
   (lambda ()
     (when (directory-exists? failure-root)
       (delete-directory/files failure-root)))))
