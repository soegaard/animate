#lang racket/base
(require rackunit racket/file racket/path racket/runtime-path
         "../../project.rkt" "../../render.rkt"
         "../main.rkt" "../project.rkt")
(provide tests)
(define-runtime-path fixture "fixtures/project-source.rkt")
(define-runtime-path semantic-fixture "fixtures/semantic-source.rkt")
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
       (lambda () (delete-directory/files temp))))
   (test-case "recursive semantic replay renders through two real workers"
     (define temp (make-temporary-file "slides-semantic-project-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define source (build-path temp "semantic-source.rkt"))
         (copy-file semantic-fixture source)
         (define project
           (animate-project #:id 'slides-semantic-worker-test
             #:source (make-storyboard-source source 'film)
             #:render (render-spec #:fps 4 #:width 160 #:height 90 #:workers 2 #:worker-mode 'subprocess
                                   #:theme (slide-theme-colors lecture-light)
                                   #:typography (slide-theme-typography lecture-light))
             #:output (output-spec #:root (build-path temp "out") #:name "semantic" #:format 'png-sequence)
             #:encoder (encoder-spec #:codec 'none) #:cache (cache-spec #:policy 'off)))
         (define report (render-project! project #:directory temp #:target (project-target-range 1/4 3/4)))
         (check-equal? (project-execution-report-rendered-frames report) 2)
         (define paths (hash-ref (project-execution-report-artifact-paths report) 'frames))
         (check-equal? (length paths) 2)
         (for ([path (in-list paths)]) (check-true (file-exists? path))))
       (lambda () (delete-directory/files temp))))
   (test-case "a directional bridge renders through the shared subprocess path"
     (define temp (make-temporary-file "slides-transition-project-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define source (build-path temp "transition-source.rkt"))
         (display-to-file
          "#lang racket/base\n(require animate/slides)\n(provide film)\n(define film (storyboard (storyboard-shot 'a (hold-slide (slide #:layout 'title [title \"A\"]) #:duration 1/4)) (slide-transition #:effect 'wipe #:direction 'up #:duration 1/2 #:easing 'smooth) (storyboard-shot 'b (hold-slide (slide #:layout 'title [title \"B\"]) #:duration 1/4))))\n"
          source #:exists 'error)
         (define project
           (animate-project #:id 'slides-transition-worker-test
             #:source (make-storyboard-source source 'film)
             #:render (render-spec #:fps 4 #:width 160 #:height 90 #:workers 2 #:worker-mode 'subprocess
                                   #:theme (slide-theme-colors lecture-light)
                                   #:typography (slide-theme-typography lecture-light))
             #:output (output-spec #:root (build-path temp "out") #:name "transition" #:format 'png-sequence)
             #:encoder (encoder-spec #:codec 'none) #:cache (cache-spec #:policy 'off)))
         (define report (render-project! project #:directory temp #:target (project-target-range 1/4 3/4)))
         (check-equal? (project-execution-report-rendered-frames report) 2))
       (lambda () (delete-directory/files temp))))))
(module+ test (require rackunit/text-ui) (unless (zero? (run-tests tests)) (error 'project-test "failed")))
