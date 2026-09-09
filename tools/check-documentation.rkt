#lang racket/base

;; Build the reference manual and turn unresolved Animate-owned cross-reference
;; warnings into a failure.  Scribble keeps external missing documentation
;; non-fatal for downstream package flexibility; references to this package's
;; own public API are under our control and must never silently regress.

(require racket/cmdline
         racket/file
         racket/path
         racket/port
         racket/system)

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

(define root (simplify-path (current-directory)))
(define output-directory
  (if destination
      (simplify-path (path->complete-path destination))
      (make-temporary-file "animate-documentation-~a" 'directory)))
(unless (directory-exists? output-directory)
  (make-directory* output-directory))

(define racket-executable (find-system-path 'exec-file))
(define raco-executable
  (build-path (or (path-only racket-executable) (current-directory)) "raco"))

(define-values (process stdout stdin stderr)
  (subprocess #f #f #f raco-executable "scribble" "--htmls" "--dest"
              (path->string output-directory) "scribblings/animate.scrbl"))
(close-output-port stdin)
(define stdout-channel (make-channel))
(define stderr-channel (make-channel))
(define stdout-reader
  (thread (lambda () (channel-put stdout-channel (port->string stdout)))))
(define stderr-reader
  (thread (lambda () (channel-put stderr-channel (port->string stderr)))))
(subprocess-wait process)
(define log (string-append (channel-get stdout-channel)
                           (channel-get stderr-channel)))
(display log)

(unless (zero? (subprocess-status process))
  (error 'check-documentation "Scribble failed with exit status ~a"
         (subprocess-status process)))

;; Warnings commonly occur as one `undefined tags:` heading followed by a
;; multi-line list of serialized tags.  Match across that block and include
;; both library and module-path tag spellings so a changed Scribble formatter
;; cannot turn an Animate-owned broken link into a passing build.
(define animate-owned-unresolved?
  (regexp-match?
   #px"(?s:(?:undefined tag|undefined tags).*?(?:\\(lib[[:space:]]+\\\"animate(?:/|\\\")|\\(mod-path[[:space:]]+\\\"animate(?:/|\\\")|animate/))"
   log))

(when animate-owned-unresolved?
  (error 'check-documentation
         "Scribble reported an unresolved Animate-owned documentation tag"))
