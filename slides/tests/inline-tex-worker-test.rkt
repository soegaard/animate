#lang racket/base

;;;
;;; Inline TeX Project Worker Tests
;;;

;; Uses Animate's actual source-preparation and subprocess project path.  The
;; workers receive only the recorded prepared Pict artifact, never TeX source.

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         "../../project.rkt"
         "../../render.rkt"
         "../main.rkt"
         "../project.rkt")

(provide tests)

(define-runtime-path fixture "fixtures/inline-tex-worker-source.rkt")

(define tests
  (test-suite
   "inline TeX prepared project workers"
   (test-case "two subprocess workers replay parent-prepared TeX drawings"
     (define temporary (make-temporary-file "slides-inline-tex-worker-~a" 'directory))
     (dynamic-wind
      void
      (lambda ()
        (define source (build-path temporary "inline-tex-worker-source.rkt"))
        (copy-file fixture source)
        (define project
          (animate-project #:id 'slides-inline-tex-worker-test
            #:source (make-storyboard-source source 'film)
            #:render
            (render-spec #:fps 4 #:width 160 #:height 90 #:workers 2
                         #:worker-mode 'subprocess
                         #:theme (slide-theme-colors lecture-dark)
                         #:typography (slide-theme-typography lecture-dark))
            #:output
            (output-spec #:root (build-path temporary "out")
                          #:name "inline-tex" #:format 'png-sequence)
            #:encoder (encoder-spec #:codec 'none)
            #:cache (cache-spec #:policy 'off)))
        (define report (render-project! project #:directory temporary))
        (check-equal? (project-execution-report-rendered-frames report) 2)
        (define diagnostics (project-execution-report-diagnostics report))
        (check-equal? (project-frame-execution-diagnostics-mode diagnostics)
                      'subprocess)
        (check-equal? (project-frame-execution-diagnostics-workers-started diagnostics)
                      2)
        (for ([frame (in-list (hash-ref (project-execution-report-artifact-paths report)
                                        'frames))])
          (check-true (file-exists? frame))))
      (lambda () (delete-directory/files temporary))))))

(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests))
    (error 'inline-tex-worker-test "failed")))
