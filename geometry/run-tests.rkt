#lang racket/base

;; Run with the same Racket executable that launched this file. No dependence
;; on a shell's raco PATH, and the subprocess exit status is preserved.
(require racket/cmdline racket/runtime-path racket/system)
(define-runtime-path tests-directory "tests")

(module+ main
  (define core-only? #f)
  (command-line
   #:program "geometry/run-tests.rkt"
   #:once-each
   [("--core") "Run only tests that do not import animate." (set! core-only? #t)]
   #:args () (void))
  (define names
    (append '("math-test.rkt" "dsl-test.rkt" "layout-test.rkt"
              "theme-test.rkt" "timeline-test.rkt" "drawing-test.rkt")
            (if core-only? '() '("animate-test.rkt"))))
  (define executable
    (or (find-executable-path (find-system-path 'exec-file))
        (find-system-path 'exec-file)))
  (exit
   (apply system*/exit-code executable "-l" "raco/main" "--" "test"
          (map (lambda (name) (build-path tests-directory name)) names))))
