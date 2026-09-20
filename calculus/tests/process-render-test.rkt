#lang racket/base

;;;
;;; Calculus Process-rendering Tests
;;;

;; Certifies the real project subprocess path for a module-owned calculus
;; lesson.  It compares all published raster bytes against an in-process
;; oracle; temporary output and cache roots are removed on every exit path.


;;;
;;; Imports and Runtime Paths
;;;

(require rackunit
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         "../../colors.rkt"
         "../../main.rkt"
         "../../project.rkt"
         "../../typography.rkt"
         "../../private/process-frame-executor.rkt"
         "../../private/render-frame-job.rkt"
         "../../private/render-worker-protocol.rkt"
         "../../private/project-execution.rkt")

(define-runtime-path scene-fixture "fixtures/calculus-process-scene.rkt")
(define-runtime-path collection-parent "../../..")


;;;
;;; Project Helpers
;;;

;; make-process-project : path? symbol? render-spec? path? -> animate-project?
;;   Declares one disposable PNG project whose restartable source is the test
;; fixture module, never a direct Scene containing native closures.
(define (make-process-project root identifier render cache-root)
  (animate-project
   #:id identifier
   #:source (module-binding-source scene-fixture 'calculus-process-scene)
   #:render render
   #:output (output-spec #:root (build-path root "media")
                         #:name (symbol->string identifier)
                         #:format 'png-sequence
                         #:overwrite-policy 'replace
                         #:open-after? #f)
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root cache-root #:policy 'read-write)))

;; rendered-frame-bytes : project-execution-report? -> (listof bytes?)
;;   Reads the ordered, atomically published PNG result of one completed render.
(define (rendered-frame-bytes report)
  (define diagnostics (project-execution-report-diagnostics report))
  (for/list ([path (in-list (project-frame-execution-diagnostics-paths diagnostics))])
    (file->bytes path)))

;; rendered-frame-byte-map : project-execution-report? -> immutable-hash?
;;   Associates every semantic source frame with its published PNG bytes.  The
;;   project report, rather than the caller's request order, owns this mapping.
(define (rendered-frame-byte-map report)
  (define diagnostics (project-execution-report-diagnostics report))
  (for/hasheq ([frame-index
                (in-list
                 (project-frame-execution-diagnostics-source-frame-indices
                  diagnostics))]
               [frame-bytes (in-list (rendered-frame-bytes report))])
    (values frame-index frame-bytes)))

;; checkout-worker-environment : -> environment-variables?
;;   Lets a source-checkout child find the `animate` collection without relying
;; on a machine-specific package installation.  An installed package simply
;; remains on the inherited collection search path after this entry.
(define (checkout-worker-environment)
  (define environment (environment-variables-copy (current-environment-variables)))
  (define inherited (environment-variables-ref environment #"PLTCOLLECTS"))
  (define separator (if (eq? (system-type 'os) 'windows) ";" ":"))
  (define collection-list
    (string-append (path->string (simplify-path collection-parent)) separator
                   (if inherited (bytes->string/utf-8 inherited) "")))
  (environment-variables-set! environment #"PLTCOLLECTS"
                              (string->bytes/utf-8 collection-list))
  environment)

;; calculus-process-camera : camera?
;;   Freezes the raster contract used by direct worker-boundary regression cases.
(define calculus-process-camera
  (make-camera #:width 320 #:height 180 #:world-width 10))

;; make-calculus-worker-jobs : (listof exact-nonnegative-integer?) string?
;;                              -> (listof final-render-frame-job?)
;;   Builds direct final-worker requests for the calculus fixture without
;; introducing a second, test-only scene implementation.
(define (make-calculus-worker-jobs source-indices session-id)
  (for/list ([source-index (in-list source-indices)]
             [output-index (in-naturals)])
    (make-final-render-frame-job
     session-id
     'calculus-process-worker-boundary
     0
     (add1 output-index)
     source-index
     output-index
     10
     #:camera calculus-process-camera
     #:theme-datum (theme->datum animate-light-theme)
     #:typography-datum (typography-theme->datum animate-typography-theme))))

;; canonical-frame-files : path? -> (listof path?)
;;   Lists only the atomically published public PNG names in slot order.
(define (canonical-frame-files directory)
  (sort
   (for/list ([entry (in-list (directory-list directory))]
              #:when (regexp-match? #px"^frame-[0-9]{6,}\\.png$"
                                   (path->string entry)))
     (build-path directory entry))
   path<?))

;; process-failure-report : (-> any/c) -> process-frame-execution-report?
;;   Captures the closed report carried by one expected worker-session failure.
(define (process-failure-report thunk)
  (define report #f)
  (check-exn
   exn:fail:process-frame-execution?
   (lambda ()
     (with-handlers ([exn:fail:process-frame-execution?
                      (lambda (error)
                        (set! report
                              (exn:fail:process-frame-execution-report error))
                        (raise error))])
       (thunk))))
  report)


;;;
;;; Tests
;;;

(module+ test
  (define root (make-temporary-file "animate-calculus-process-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-environment-variables (checkout-worker-environment)])
       (define local-report
         (render-project!
          (make-process-project
           root 'calculus-process-local
           (render-spec #:fps 10 #:width 320 #:height 180
                        #:workers 1 #:worker-mode 'in-process)
           (build-path root "local-cache"))
          #:directory root))
       (define worker-report
         (render-project!
          (make-process-project
           root 'calculus-process-workers
           (render-spec #:fps 10 #:width 320 #:height 180
                        #:workers 10 #:worker-mode 'subprocess)
           (build-path root "worker-cache"))
          #:directory root))
       (define worker-diagnostics
         (project-execution-report-diagnostics worker-report))
       (check-eq? (project-frame-execution-diagnostics-mode worker-diagnostics)
                  'subprocess)
       (check-equal? (project-frame-execution-diagnostics-workers-started worker-diagnostics)
                     10)
       (check-equal? (rendered-frame-bytes local-report)
                     (rendered-frame-bytes worker-report))
       ;; The full serial render is the oracle for individual requests.  Ask
       ;; for a sparse set in reverse source order: a frame renderer must not
       ;; replay or inherit state from the preceding request.
       (define expected-frames (rendered-frame-byte-map local-report))
       (define available-frame-indices (sort (hash-keys expected-frames) <))
       (define final-frame-index (last available-frame-indices))
       (define sparse-frame-indices
         (remove-duplicates
          (list 0
                (list-ref available-frame-indices
                          (quotient (length available-frame-indices) 2))
                final-frame-index)))
       (for ([frame-index (in-list (reverse sparse-frame-indices))]
             [request-index (in-naturals)])
         (define frame-report
           (render-project-frame!
            (make-process-project
             root
             (string->symbol
              (format "calculus-process-reverse-~a" request-index))
             (render-spec #:fps 10 #:width 320 #:height 180
                          #:workers 1 #:worker-mode 'in-process)
             (build-path root "reverse-cache"))
            frame-index
            #:directory root))
         (check-equal? (rendered-frame-bytes frame-report)
                       (list (hash-ref expected-frames frame-index))))
       ;; A repeated request is also a cold/warm cache test.  The host owns
       ;; cache materialization, but neither a warm cache nor output reuse may
       ;; change one published frame's raster result.
       (define cache-project
         (make-process-project
          root 'calculus-process-cache
          (render-spec #:fps 10 #:width 320 #:height 180
                       #:workers 1 #:worker-mode 'in-process)
          (build-path root "repeat-cache")))
       (define cold-report
         (render-project-frame! cache-project final-frame-index #:directory root))
       (define warm-report
         (render-project-frame! cache-project final-frame-index #:directory root))
       (check-equal? (rendered-frame-bytes cold-report)
                     (list (hash-ref expected-frames final-frame-index)))
       (check-equal? (rendered-frame-bytes warm-report)
                     (rendered-frame-bytes cold-report))
       (check-true (positive? (project-execution-report-reused-frames warm-report)))))
   (lambda ()
     (when (directory-exists? root)
       (delete-directory/files root)))))


;;;
;;; Failure and Cancellation Boundaries
;;;

(module+ test
  (define boundary-root
    (make-temporary-file "animate-calculus-process-boundary-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-environment-variables (checkout-worker-environment)])
       ;; An invalid binding is discovered by real child source loading.  No
       ;; staging sibling can become a public frame, and a normal calculus
       ;; request can reuse the same empty root immediately afterward.
       (define failed-output (build-path boundary-root "failed"))
       (define failed-report
         (process-failure-report
          (lambda ()
            (render-final-frame-jobs!
             (render-worker-module-value-source
              (path->string scene-fixture)
              'calculus-process-scene-not-exported)
             (make-calculus-worker-jobs '(0 5) "calculus-invalid-source")
             failed-output
             #:workers 2))))
       (check-eq? (process-frame-failure-phase
                   (process-frame-execution-report-failure failed-report))
                  'startup)
       (check-equal? (directory-list failed-output) '())
       (check-equal? (canonical-frame-files failed-output) '())
       (check-true
        (andmap (lambda (status) (not (hash-ref status 'open?)))
                (process-frame-execution-report-worker-resource-statuses
                 failed-report)))
       (define recovered-report
         (render-final-frame-jobs!
          (render-worker-module-value-source (path->string scene-fixture)
                                             'calculus-process-scene)
          (make-calculus-worker-jobs '(0 5) "calculus-recover-after-failure")
          failed-output
          #:workers 2))
       (check-equal? (process-frame-execution-report-completed-frame-count
                      recovered-report)
                     2)
       (check-equal? (length (canonical-frame-files failed-output)) 2)

       ;; Scheduler cancellation occurs before assignment, removes its staging
       ;; root, and leaves the intended output directory usable by a new
       ;; worker session.  This test deliberately uses the same exact
       ;; calculus module rather than a synthetic host-only source.
       (define canceled-output (build-path boundary-root "canceled"))
       (define canceled-report
         (process-failure-report
          (lambda ()
            (render-final-frame-jobs!
             (render-worker-module-value-source (path->string scene-fixture)
                                                'calculus-process-scene)
             (make-calculus-worker-jobs '(0 5) "calculus-canceled")
             canceled-output
             #:workers 2
             #:canceled? (lambda () #t)))))
       (check-true (process-frame-execution-report-canceled? canceled-report))
       (check-eq? (process-frame-failure-phase
                   (process-frame-execution-report-failure canceled-report))
                  'canceled)
       (check-equal? (directory-list canceled-output) '())
       (check-equal? (canonical-frame-files canceled-output) '())
       (define retry-report
         (render-final-frame-jobs!
          (render-worker-module-value-source (path->string scene-fixture)
                                             'calculus-process-scene)
          (make-calculus-worker-jobs '(0 5) "calculus-retry-after-cancel")
          canceled-output
          #:workers 2))
       (check-equal? (process-frame-execution-report-completed-frame-count
                      retry-report)
                     2)
       (check-equal? (length (canonical-frame-files canceled-output)) 2)))
   (lambda ()
     (when (directory-exists? boundary-root)
       (delete-directory/files boundary-root)))))
