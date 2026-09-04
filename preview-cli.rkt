#lang racket/base

;; `raco animate preview FILE BINDING` opens a source-program preview. This
;; module is loaded only by the command, so core `animate` remains headless.

(require racket/cmdline
         racket/file
         racket/path
         racket/runtime-path
         raco/command-name
         "preview.rkt")

(define-runtime-path preview-cli-path "preview-cli.rkt")

(define auto-reload? #t)
(define fps 30)
(define block #f)

(define arguments
  (command-line
   #:program (short-program+command-name)
   #:once-each
   [("--no-auto-reload") "Disable file watching; use reload! or preview-reload! manually."
                         (set! auto-reload? #f)]
   [("--fps") value "Preview frames per second."
               (define parsed (string->number value))
               (unless (and (exact-positive-integer? parsed))
                 (raise-user-error 'raco-animate "--fps expects a positive integer"))
               (set! fps parsed)]
   [("--block") value "Start at a named source block."
                 (set! block (string->symbol value))]
   #:args (command . rest)
   (cons command rest)))

(cond
  [(and (pair? arguments) (equal? (car arguments) "preview")
        (= (length (cdr arguments)) 2))
   ;; A `raco` command normally runs under the non-GUI `racket` executable.
   ;; On macOS and Unix, re-exec the same command with the sibling `gracket`
   ;; launcher.  The child has the GUI runtime from process start, while core
   ;; `animate` itself remains safe to require in the parent/headless process.
   (when (not (preview-available?))
     (relaunch-with-gracket!))
   (define source-path (cadr arguments))
   (define binding (string->symbol (caddr arguments)))
   (define session
     (open-program-preview source-path binding #:auto-reload? auto-reload? #:fps fps))
   (when block (preview-jump-to-block! session block))
   ;; A GUI frame is displayed asynchronously. Keep the command's main thread
   ;; alive until the author closes that frame, then all registered resources
   ;; (watcher, REPL, renderer) are cleaned up by preview-close!.
   (let loop ()
     (when (preview-open? session)
       (sleep 1/10)
       (loop)))]
  [else
   (raise-user-error
    'raco-animate
   "usage: raco animate preview [--fps N] [--block NAME] [--no-auto-reload] FILE.rkt binding")])

(define (relaunch-with-gracket!)
  (define racket-executable (find-system-path 'exec-file))
  (define gracket-executable
    (build-path (or (path-only racket-executable) (current-directory)) "gracket"))
  (unless (file-exists? gracket-executable)
    (raise-user-error
     'raco-animate
     (format "preview needs GRacket, but no sibling launcher was found at ~a"
             gracket-executable)))
  (define-values (process _stdout _stdin _stderr)
    (apply subprocess
           (current-output-port)
           (current-input-port)
           (current-error-port)
           gracket-executable
           (path->string preview-cli-path)
           (vector->list (current-command-line-arguments))))
  (subprocess-wait process)
  (exit (subprocess-status process)))
