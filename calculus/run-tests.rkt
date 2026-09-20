#lang racket/base

;;;
;;; Calculus Release-gate Runner
;;;

;; Runs the independently useful calculus verification gates without relying
;; on a shell-specific line continuation.  The core tests remain headless; the
;; native gate is the real Pict/Visual raster suite; the documentation gate
;; delegates to the repository's authoritative Scribble checker.


;;;
;;; Imports
;;;

(require racket/cmdline
         racket/file
         racket/path
         racket/runtime-path
         racket/system)

(define-runtime-path core-test "tests/core-smoke-test.rkt")
(define-runtime-path guide-test "tests/guide-lessons-test.rkt")
(define-runtime-path component-test "tests/component-declaration-test.rkt")
(define-runtime-path external-function-test "tests/external-function-test.rkt")
(define-runtime-path public-api-test "tests/public-api-test.rkt")
(define-runtime-path native-test "tests/render-smoke-test.rkt")
(define-runtime-path review-test "tests/review-examples-test.rkt")
(define-runtime-path process-test "tests/process-render-test.rkt")
(define-runtime-path calculus-reference "../scribblings/reference/calculus.scrbl")


;;;
;;; Gate Selection
;;;

(define run-core? #f)
(define run-native? #f)
(define run-docs? #f)
(define run-process? #f)
(define process-workers 10)

;; parse-process-workers : string? -> exact-positive-integer?
;;   Validates the explicit worker capacity recorded by the process gate.
(define (parse-process-workers text)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-arguments-error
     'calculus/run-tests "an exact positive worker count" "workers" text))
  value)

(command-line
 #:program "calculus/run-tests.rkt"
 #:once-each
 [("--core") "Run declaration, mathematics, presentation, and timeline checks."
              (set! run-core? #t)]
 [("--native") "Run shared Pict/Visual/scene preparation and raster checks."
                (set! run-native? #t)]
 [("--docs") "Build and validate the repository's Scribble documentation."
              (set! run-docs? #t)]
 [("--process") "Run the ten-worker reconstructible project-rendering check."
                 (set! run-process? #t)]
 [("--workers") count "Process worker capacity; the certification fixture requires 10."
                (set! process-workers (parse-process-workers count))]
 [("--all") "Run every available calculus gate (the default)."
             (set! run-core? #t)
             (set! run-native? #t)
             (set! run-docs? #t)
             (set! run-process? #t)]
 #:args ()
 (when (not (or run-core? run-native? run-docs? run-process?))
   (set! run-core? #t)
   (set! run-native? #t)
   (set! run-docs? #t)
   (set! run-process? #t)))


;;;
;;; Gate Execution
;;;

;; run-test-module! : path? -> void?
;;   Invokes a module's RackUnit test submodule in this process.  A test failure
;; raises normally and therefore gives the runner its nonzero exit status.
(define (run-test-module! path)
  (dynamic-require (list 'submod path 'test) #f))

;; run-documentation-gate! : -> void?
;;   Builds the calculus reference into an owned temporary destination and
;; removes it after a successful or failed Scribble invocation.  Building the
;; whole project manual remains the root documentation suite's responsibility;
;; this gate keeps the calculus API manual independently runnable.
(define (run-documentation-gate!)
  (define destination (make-temporary-file "animate-calculus-docs-~a" 'directory))
  (define current-racket (find-system-path 'exec-file))
  (define raco-executable
    (or (and (path-only current-racket)
             (build-path (path-only current-racket) "raco"))
        (find-executable-path "raco")
        (build-path (current-directory) "raco")))
  (dynamic-wind
   void
   (lambda ()
     (unless (system* raco-executable "scribble" "--html" "--dest"
                      (path->string destination) calculus-reference)
       (error 'calculus/run-tests "documentation gate failed")))
   (lambda ()
     (when (directory-exists? destination)
       (delete-directory/files destination)))))

;; version-at-least? : string? string? -> boolean?
;;   Compares numeric version fields without assuming a specific Racket helper.
(define (version-at-least? actual required)
  (define (parts text)
    (map string->number (regexp-match* #px"[0-9]+" text)))
  (let loop ([left (parts actual)] [right (parts required)])
    (cond [(and (null? left) (null? right)) #t]
          [(null? left) (loop '(0) right)]
          [(null? right) #t]
          [(> (car left) (car right)) #t]
          [(< (car left) (car right)) #f]
          [else (loop (cdr left) (cdr right))])))

;; require-process-toolchain! : -> void?
;;   The host project worker protocol selected by the plan is certified under
;; Racket 9.3.0.2.  A mixed compiled-artifact runtime is not a valid fallback:
;; running it would turn a process failure into an ambiguous toolchain error.
(define (require-process-toolchain!)
  (unless (version-at-least? (version) "9.3.0.2")
    (raise-user-error
     'calculus/run-tests
     "--process requires Racket 9.3.0.2 or later; current runtime is ~a"
     (version))))

(when run-process?
  (require-process-toolchain!))

(when (and run-process? (not (= process-workers 10)))
  (raise-user-error
   'calculus/run-tests
   "the certification fixture requires --workers 10; received ~a"
   process-workers))

(when run-core?
  (for ([test-module (in-list (list core-test guide-test component-test
                                     external-function-test public-api-test))])
    (run-test-module! test-module)))

(when run-native?
  (for ([test-module (in-list (list native-test review-test))])
    (run-test-module! test-module)))

(when run-docs?
  (run-documentation-gate!))

(when run-process?
  (run-test-module! process-test))
