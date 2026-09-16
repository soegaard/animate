#lang racket/base

;; Real module-backed preparation, native rendering and subprocess workers.
;; Opt in with slides/run-tests.rkt --geometry --project. No fake workers or
;; alternate renderer: compare actual published PNG bytes across worker counts.
(require rackunit racket/file racket/list racket/path racket/port racket/runtime-path json
         "../../project.rkt" "../../render.rkt"
         "../main.rkt" "../project.rkt" "../gallery.rkt"
         "../private/gallery/render.rkt")
(provide tests mixed-tests)
(define-runtime-path fixture "fixtures/geometry-worker-source.rkt")
(define-runtime-path mixed-fixture "fixtures/geometry-math-worker-source.rkt")
(define (with-temp thunk)
  (define temp (make-temporary-file "slides-geometry-workers-~a" 'directory))
  (dynamic-wind void (lambda () (thunk temp)) (lambda () (delete-directory/files temp))))
(define (events path)
  (if (file-exists? path) (call-with-input-file path (lambda (in) (port->list read in))) '()))
(define (with-event-log path thunk)
  (define env (environment-variables-copy (current-environment-variables)))
  (environment-variables-set! env #"ANIMATE_GEOMETRY_PREPARATION_EVENT_LOG" (path->bytes path))
  (parameterize ([current-environment-variables env]) (thunk)))
(define (check-parent-only! path)
  (define log (events path))
  (check-equal? (count (lambda (e) (and (pair? e) (eq? (car e) 'realize))) log) 1)
  (check-equal? (count (lambda (e) (and (pair? e) (eq? (car e) 'layout))) log) 1))
(define (execute temp source binding suffix workers mode theme width height
                 #:from [from 0] #:to [to 3/2])
  (define log (build-path temp (string-append suffix ".log")))
  (define project
    (animate-project #:id (string->symbol suffix)
      #:source (make-storyboard-source source binding)
      #:render (render-spec #:fps 12 #:width width #:height height #:workers workers #:worker-mode mode
                            #:theme (slide-theme-colors theme) #:typography (slide-theme-typography theme))
      #:output (output-spec #:root (build-path temp suffix) #:name suffix #:format 'png-sequence
                            #:open-after? #f)
      #:encoder (encoder-spec #:codec 'none)
      #:cache (cache-spec #:root (build-path temp (string-append suffix "-cache")) #:policy 'off)))
  (define report
    (with-event-log log
      (lambda () (render-project! project #:directory temp #:target (project-target-range from to)))))
  (check-parent-only! log)
  (define diagnostics (project-execution-report-diagnostics report))
  (check-equal? (project-frame-execution-diagnostics-mode diagnostics) mode)
  (check-equal? (project-frame-execution-diagnostics-requested-worker-capacity diagnostics) workers)
  (when (eq? mode 'subprocess)
    ;; These ranges have at least 12 independently rasterized frames, enough to
    ;; start all ten workers. Capacity alone is not a concurrency assertion.
    (check-equal? (project-frame-execution-diagnostics-workers-started diagnostics) workers))
  (define paths (hash-ref (project-execution-report-artifact-paths report) 'frames))
  (check-equal? (length paths) (* 12 (- to from)))
  (map file->bytes paths))
(define tests
  (test-suite
   "geometry in the shared slide worker pool"
   (test-case "ordinary geometry-content matches one and two worker rendering"
     (with-temp
      (lambda (temp)
        (define local (execute temp fixture 'ordinary "ordinary-local" 1 'in-process lecture-light 160 90))
        (define remote (execute temp fixture 'ordinary "ordinary-two" 2 'subprocess lecture-light 160 90))
        (check-equal? remote local))))
   (test-case "semantic geometry replay is byte-identical with one two and ten workers"
     (with-temp
      (lambda (temp)
        (define local (execute temp fixture 'semantic "semantic-local" 1 'in-process lecture-light 160 90))
        (check-true (> (length (remove-duplicates local bytes=?)) 1))
        (for ([workers (in-list '(2 10))])
          (check-equal?
           (execute temp fixture 'semantic (format "semantic-~a" workers) workers 'subprocess lecture-light 160 90)
           local)))))
   (test-case "dark portrait geometry retains identical framing across workers"
     (with-temp
      (lambda (temp)
        (check-equal?
         (execute temp fixture 'dark-portrait "portrait-two" 2 'subprocess lecture-dark 90 160)
         (execute temp fixture 'dark-portrait "portrait-local" 1 'in-process lecture-dark 90 160)))))
   (test-case "gallery geometry MP4 reports actual subprocess use and parent-only preparation"
     (with-temp
      (lambda (temp)
        (define output (build-path temp "gallery"))
        (define log (build-path temp "gallery.log"))
        (check-equal?
         (with-event-log log
           (lambda ()
             (render-slide-gallery!
              (select-slide-gallery-entries #:entries '(semantic-geometry)) output
              #:theme 'dark #:videos? #t #:workers 2 #:fps 2 #:width 160 #:repeat 1 #:zip? #f)))
         0)
        (check-parent-only! log)
        (define manifest (call-with-input-file (build-path output "manifest.json") read-json))
        (check-equal? (hash-ref manifest 'errors) 0)
        (define entry (car (hash-ref manifest 'entries)))
        (check-equal? (hash-ref entry 'mode) "subprocess")
        (check-equal? (hash-ref entry 'requested-workers) 2)
        (check-equal? (hash-ref entry 'workers-started) 2)
        (check-true (file-exists? (build-path output (hash-ref entry 'video))))
        (check-true (directory-exists? (build-path output "_work" "cache"))))))))
(define mixed-tests
  (test-suite
   "mixed mathematical and geometry workers"
   (test-case "two domain clocks survive one versus ten process rendering"
     (with-temp
      (lambda (temp)
        ;; Sample the interior of the six-second bridge, not only endpoint holds.
        (check-equal?
         (execute temp mixed-fixture 'film "mixed-ten" 10 'subprocess lecture-dark 160 90 #:from 2 #:to 3)
         (execute temp mixed-fixture 'film "mixed-local" 1 'in-process lecture-dark 160 90 #:from 2 #:to 3)))))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests)) (error 'geometry-worker-test "failed")))
