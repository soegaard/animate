#lang racket/base
(require rackunit racket/file racket/path racket/runtime-path
         "../../project.rkt" "../../render.rkt"
         "../main.rkt" "../project.rkt")
(provide tests)
(define-runtime-path fixture "fixtures/project-source.rkt")
(define tests
  (test-suite
   "actual shared-worker project execution"
   (test-case "two frames with two subprocess workers"
     (define temp (make-temporary-file "slides-project-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define source (build-path temp "project-source.rkt"))
         (copy-file fixture source)
         (define project
           (animate-project #:id 'slides-worker-test
             #:source (make-storyboard-source source 'film)
             #:render (render-spec #:fps 4 #:width 160 #:height 90 #:workers 2 #:worker-mode 'subprocess
                                   #:theme (slide-theme-colors lecture-light)
                                   #:typography (slide-theme-typography lecture-light))
             #:output (output-spec #:root (build-path temp "out") #:name "worker-test" #:format 'png-sequence)
             #:encoder (encoder-spec #:codec 'none)
             #:cache (cache-spec #:policy 'off)))
         (define report (render-project! project #:directory temp))
         (check-true (project-execution-report? report))
         (check-equal? (project-execution-report-rendered-frames report) 2))
       (lambda () (delete-directory/files temp))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'project-test "failed")))
