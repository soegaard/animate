#lang racket/base

;; Build every registered Animate manual and turn unresolved Animate-owned
;; cross-reference warnings into a failure. Scribble keeps external missing
;; documentation non-fatal for downstream package flexibility; references to
;; this package's own public API are under our control and must never silently
;; regress.

(require racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/system)

(provide registered-animate-manuals
         racket-raco-main-arguments
         run-raco-command
         run-documentation-check!)

;; Both the root package and its math subpackage register a Scribble manual.
;; Keep strict owned-reference validation aligned with package setup instead of
;; accidentally checking only the root entry point.
(define registered-animate-manuals
  '("scribblings/animate.scrbl"
    "math/scribblings/math.scrbl"))

;; racket-raco-main-arguments : (listof string?) -> (listof string?)
;; Uses the raco implementation belonging to one exact Racket executable.
;; This avoids guessing a sibling launcher when the runtime came from PATH, an
;; application bundle, or a symlinked installation root.
(define (racket-raco-main-arguments raco-arguments)
  (append (list "-l" "raco/main" "--") raco-arguments))

;; resolve-racket-executable : path-string? -> path?
;; Preserve a supplied symlink: executing it keeps Racket's own installation
;; layout and package configuration intact. `path->complete-path` merely makes
;; diagnostics and subprocess launch independent of the caller's directory.
(define (resolve-racket-executable executable)
  (unless (path-string? executable)
    (raise-argument-error 'check-documentation "path-string?" executable))
  (define complete (path->complete-path executable))
  (unless (file-exists? complete)
    (raise-arguments-error
     'check-documentation
     "an existing Racket executable"
     "racket executable" executable))
  complete)

;; run-raco-command : path-string? (listof string?) -> integer? string?
;; Runs `racket -l raco/main -- ...` without shell interpolation. Both output
;; ports drain concurrently, which prevents a verbose Scribble build from
;; blocking on either pipe before its process has exited.
(define (run-raco-command racket-executable raco-arguments)
  (define executable (resolve-racket-executable racket-executable))
  (define arguments (racket-raco-main-arguments raco-arguments))
  (define-values (process stdout stdin stderr)
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (error 'check-documentation
                   (string-append
                    "could not launch Racket's raco implementation\n"
                    "  racket executable: ~a\n"
                    "  arguments: ~s\n"
                    "  original error: ~a")
                   (path->string executable)
                   arguments
                   (exn-message exception)))])
      (apply subprocess #f #f #f executable arguments)))
  (close-output-port stdin)
  (define stdout-channel (make-channel))
  (define stderr-channel (make-channel))
  (thread (lambda () (channel-put stdout-channel (port->string stdout))))
  (thread (lambda () (channel-put stderr-channel (port->string stderr))))
  (subprocess-wait process)
  (values (subprocess-status process)
          (string-append (channel-get stdout-channel)
                         (channel-get stderr-channel))))

(define (scribble-arguments output-directory manual)
  (list "scribble" "+m" "--htmls" "++convert" "svg" "--dest"
        (path->string output-directory)
        manual))

(define (run-scribble! racket-executable output-directory manual)
  (define arguments (scribble-arguments output-directory manual))
  (define-values (status log)
    (run-raco-command racket-executable arguments))
  (display log)
  (unless (zero? status)
    (error 'check-documentation
           (string-append
            "Scribble failed with exit status ~a\n"
            "  racket executable: ~a\n"
            "  raco arguments: ~s")
           status
           (path->string (resolve-racket-executable racket-executable))
           arguments))
  log)

;; run-documentation-check! : [path-string?]
;;                            [#:racket path-string?]
;;                            [#:manuals (listof string?)] -> void?
;; Builds every registered manual into one output root and rejects only broken
;; Animate-owned links, preserving Scribble's allowance for external packages
;; whose documentation may not be installed locally.
(define (run-documentation-check! [destination #f]
                                  #:racket [racket-executable
                                            (find-system-path 'exec-file)]
                                  #:manuals [manuals registered-animate-manuals])
  (when (and destination (not (path-string? destination)))
    (raise-argument-error 'check-documentation "path-string? or #f" destination))
  (define output-directory
    (if destination
        (simplify-path (path->complete-path destination))
        (make-temporary-file "animate-documentation-~a" 'directory)))
  (unless (directory-exists? output-directory)
    (make-directory* output-directory))
  (define log
    (apply string-append
           (for/list ([manual (in-list manuals)])
             (run-scribble! racket-executable output-directory manual))))
  ;; Warnings commonly occur as one `undefined tags:` heading followed by a
  ;; multi-line list of serialized tags. Match across that block and include
  ;; both library and module-path tag spellings so a changed Scribble formatter
  ;; cannot turn an Animate-owned broken link into a passing build.
  (define animate-owned-unresolved?
    (regexp-match?
     #px"(?s:(?:undefined tag|undefined tags).*?(?:\\(lib[[:space:]]+\\\"animate(?:/|\\\")|\\(mod-path[[:space:]]+\\\"animate(?:/|\\\")|\\(collects[[:space:]]+#\\\"animate(?:\\\"|\\\")|animate/))"
     log))
  (when animate-owned-unresolved?
    (error 'check-documentation
           "Scribble reported an unresolved Animate-owned documentation tag")))

(module+ main
  (define destination #f)
  (command-line
   #:program "check-documentation.rkt"
   #:args arguments
   (cond
     [(null? arguments) (void)]
     [(and (= (length arguments) 1) (path-string? (car arguments)))
      (set! destination (car arguments))]
     [else
      (raise-user-error
       'check-documentation
       "usage: racket tools/check-documentation.rkt [DESTINATION]")]))
  (run-documentation-check! destination))

(module+ test
  (require rackunit)
  ;; Use a symlink in a directory with no `raco` sibling. The old checker
  ;; derived that nonexistent sibling path; `racket -l raco/main` instead uses
  ;; the installation selected by the exact executable, for absolute and
  ;; symlink invocation alike.
  (define runtime (find-system-path 'exec-file))
  (define temporary-root
    (make-temporary-file "animate-documentation-launcher-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define fixture (build-path temporary-root "fixture.scrbl"))
     (define output (build-path temporary-root "output"))
     (define linked-runtime (build-path temporary-root "racket-link"))
     (call-with-output-file
      fixture
      (lambda (port)
        (display "#lang scribble/manual\n@title{Launcher fixture}\n" port)))
     (make-file-or-directory-link runtime linked-runtime)
     (check-false (file-exists? (build-path temporary-root "raco")))
     (for ([executable (in-list (list runtime linked-runtime))])
       (define-values (status log)
         (run-raco-command
          executable
          (list "scribble" "--html" "--dest" (path->string output)
                (path->string fixture))))
       (check-equal? status 0 log))
     (check-not-equal? (directory-list output) '()))
   (lambda () (delete-directory/files temporary-root))))
