#lang racket/base

;; Run with the same Racket executable that launched this file. No dependence
;; on a shell's raco PATH, and the subprocess exit status is preserved.
(require racket/cmdline racket/runtime-path racket/system)
(define-runtime-path tests-directory "tests")

(module+ main
  (define core-only? #f)
  (define library-only? #f)
  (define review-only? #f)
  (define audit-only? #f)
  (command-line
   #:program "geometry/run-tests.rkt"
   #:once-each
   [("--core") "Run only tests that do not import animate." (set! core-only? #t)]
   [("--library") "Run standard-library checks using Racket base only." (set! library-only? #t)]
   [("--review") "Run review planning and bundle checks using Racket base only." (set! review-only? #t)]
   [("--audit") "Run review-driven example audit checks (Racket base only)." (set! audit-only? #t)]
   #:args () (void))
  (when (> (for/sum ([flag (in-list (list core-only? library-only? review-only? audit-only?))]) (if flag 1 0)) 1)
    (error 'geometry/run-tests "choose at most one of --core, --library, --review, and --audit"))
  (when audit-only?
    ((dynamic-require (build-path tests-directory "audit-checks.rkt") 'run-audit-checks))
    (exit 0))
  (when review-only?
    ((dynamic-require (build-path tests-directory "review-checks.rkt") 'run-review-checks))
    (exit 0))
  (when library-only?
    ((dynamic-require (build-path tests-directory "library-checks.rkt") 'run-library-checks))
    (exit 0))
  (define names
    (append '("math-test.rkt" "dsl-test.rkt" "layout-test.rkt"
              "theme-test.rkt" "timeline-test.rkt" "drawing-test.rkt"
              "reveal-test.rkt" "annotation-test.rkt" "library-test.rkt" "review-test.rkt" "audit-test.rkt")
            (if core-only? '() '("animate-test.rkt" "reveal-annotation-render-test.rkt" "library-render-test.rkt" "review-render-test.rkt" "audit-render-test.rkt"))))
  (define executable
    (or (find-executable-path (find-system-path 'exec-file))
        (find-system-path 'exec-file)))
  (exit
   (apply system*/exit-code executable "-l" "raco/main" "--" "test"
          (map (lambda (name) (build-path tests-directory name)) names))))
