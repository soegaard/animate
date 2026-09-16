#lang racket/base
;; Core suites do not invoke TeX or FFmpeg; optional integration suites are explicit.
(require racket/cmdline racket/runtime-path racket/list rackunit/text-ui)
(module+ main
(define-runtime-path tests-directory "tests")
(define optional '())
(command-line #:program "slides/run-tests.rkt"
 #:once-each
 [("--math") "Include actual TeX/math adapter integration" (set! optional (cons "math-test.rkt" optional))]
 [("--geometry") "Include native geometry integration" (set! optional (cons "geometry-test.rkt" optional))]
 [("--media") "Include actual audio probing with ffprobe" (set! optional (cons "media-test.rkt" optional))]
 [("--project") "Include subprocess project rendering" (set! optional (cons "project-test.rkt" optional))]
 #:args () (void))
(define suites (append '("model-test.rkt" "layout-test.rkt" "timing-test.rkt" "native-test.rkt" "codec-test.rkt")
                       (reverse optional)))
(define failed 0)
(for ([name (in-list suites)])
  (printf "\n=== ~a ===\n" name)
  (with-handlers ([exn:fail? (lambda (e) (eprintf "~a\n" (exn-message e)) (set! failed (add1 failed)))])
    (define suite (dynamic-require (build-path tests-directory name) 'tests))
    (set! failed (+ failed (run-tests suite 'verbose)))))
(printf "\nSuite files: ~a; failed/error checks: ~a\n" (length suites) failed)
(exit (if (zero? failed) 0 1))

)
