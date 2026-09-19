#lang racket/base

;; Load the actual complete source modules. No duplicate definitions or video
;; commands are evaluated here. Expensive storyboard preparation is opt-in.
(require racket/cmdline racket/file racket/list racket/path racket/runtime-path
         json
         (prefix-in a: animate)
         (prefix-in s: animate/slides)
         (prefix-in at: animate/authoring)
         (only-in animate/project animate-project?))
(define-runtime-path root "..")
(define-runtime-path entries-path "complete-examples/entries.json")

(module+ main
  (define enabled '())
  (define prepare? #f)
  (command-line #:program "check-complete-examples.rkt"
    #:once-each
    [("--math") "Load the mathematical example (no typesetting unless --prepare)"
                  (set! enabled (cons "math" enabled))]
    [("--geometry") "Load the geometry example"
                      (set! enabled (cons "geometry" enabled))]
    [("--3d") "Load the three-file spatial example"
                (set! enabled (cons "3d" enabled))]
    [("--prepare") "Also prepare enabled storyboards and check known durations"
                     (set! prepare? #t)]
    #:args () (void))
  (define data (call-with-input-file entries-path read-json))
  (unless (equal? (hash-ref data 'schema #f) "animate-complete-examples-v1")
    (raise-user-error 'check-complete-examples "unexpected catalogue schema"))
  (define failures 0)
  (define checked 0)
  (define skipped 0)
  (define (check-duration value expected)
    (unless (and (real? value) (= value expected))
      (raise-user-error 'check-complete-examples
                        "duration mismatch: got ~a; expected ~a" value expected)))
  (parameterize ([current-directory root])
    (for ([entry (in-list (hash-ref data 'entries))])
      (define id (hash-ref entry 'id))
      (cond
        [(ormap (lambda (feature) (not (member feature enabled)))
                 (hash-ref entry 'optional))
         (set! skipped (add1 skipped))
         (printf "SKIP ~a (enable ~a)\n" id (hash-ref entry 'optional))]
        [else
         (for ([probe (in-list (hash-ref entry 'checks))])
           (with-handlers ([exn:fail?
                            (lambda (error)
                              (set! failures (add1 failures))
                              (eprintf "FAIL ~a/~a: ~a\n" id (hash-ref probe 'binding)
                                       (exn-message error)))])
             (define module-path (build-path root (hash-ref probe 'source)))
             (define value (dynamic-require module-path
                                             (string->symbol (hash-ref probe 'binding))))
             (define kind (hash-ref probe 'kind))
             (define expected (hash-ref probe 'duration))
             (define predicate
               (cond [(equal? kind "scene") a:scene?]
                     [(equal? kind "storyboard") s:storyboard?]
                     [(equal? kind "project") animate-project?]
                     [(equal? kind "program") at:scene-program?]
                     [else (raise-user-error 'check-complete-examples "unknown kind: ~a" kind)]))
             (unless (predicate value)
               (raise-user-error 'check-complete-examples "expected a ~a value" kind))
             (when (and (equal? kind "scene") (number? expected))
               (check-duration (a:scene-duration value) expected))
             (when (and prepare? (equal? kind "storyboard"))
               (define prepare (dynamic-require 'animate/slides/render 'prepare-storyboard!))
               (define duration (dynamic-require 'animate/slides/render 'prepared-duration))
               (define prepared (prepare value #:asset-base (path-only module-path)))
               (when (number? expected)
                 (check-duration (duration prepared) expected)))
             (set! checked (add1 checked))
             (printf "PASS ~a/~a\n" id (hash-ref probe 'binding))))])))
  (printf "Complete examples: ~a exported values checked; ~a chapters skipped; ~a failures.\n"
          checked skipped failures)
  (unless prepare?
    (displayln "Storyboard types were checked; storyboard preparation and media rendering were not run."))
  (exit (if (zero? failures) 0 1)))
