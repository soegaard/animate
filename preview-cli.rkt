#lang racket/base

;; `raco animate preview FILE BINDING` opens a source-program preview. This
;; module is loaded only by the command, so core `animate` remains headless.

(require racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/string
         raco/command-name
         "private/doctor.rkt"
         "private/repository-check.rkt"
         "project.rkt"
         "render.rkt"
         "preview.rkt"
         "version.rkt")

(define-runtime-path preview-cli-path "preview-cli.rkt")

(define auto-reload? #t)
(define fps 30)
(define block #f)
(define section #f)
(define frame #f)
(define range #f)

;; `racket/cmdline` stops option parsing once it reaches #:args, whereas the
;; useful command spelling is `cache clear --domain segments PROJECT BINDING`.
;; Extract that one command-local option before the ordinary global preview
;; options are parsed.  Other commands never receive a cache-domain value.
(define-values (command-line-arguments cache-domain)
  (let ([raw (vector->list (current-command-line-arguments))])
    (cond
      [(and (>= (length raw) 4)
            (equal? (car raw) "cache")
            (equal? (cadr raw) "clear")
            (equal? (caddr raw) "--domain"))
       (define parsed (string->symbol (cadddr raw)))
       (unless (memq parsed '(formula frames segments audio waveform source-program))
         (raise-user-error
          'raco-animate
          "--domain expects formula, frames, segments, audio, waveform, or source-program"))
       (values (list->vector (append (take raw 2) (drop raw 4))) parsed)]
      [else (values (list->vector raw) #f)])))

(define arguments
  (command-line
   #:program (short-program+command-name)
   #:argv command-line-arguments
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
   [("--section") value "Select one authored timeline section."
                   (set! section (string->symbol value))]
   [("--frame") value "Select one zero-based source frame."
                 (define parsed (string->number value))
                 (unless (exact-nonnegative-integer? parsed)
                   (raise-user-error 'raco-animate "--frame expects a nonnegative integer"))
                 (set! frame parsed)]
   [("--range") value "Select a half-open scene-time range START:END."
                 (define pieces (string-split value ":"))
                 (unless (= (length pieces) 2)
                   (raise-user-error 'raco-animate "--range expects START:END"))
                 (define start (string->number (car pieces)))
                 (define end (string->number (cadr pieces)))
                 (unless (and (real? start) (real? end) (<= 0 start) (< start end))
                 (raise-user-error 'raco-animate "--range expects finite START:END with 0 <= START < END"))
                 (set! range (cons start end))]
   #:args (command . rest)
   (cons command rest)))

(define (load-project-argument module-path binding-string)
  (define binding (string->symbol binding-string))
  (define value (dynamic-require module-path binding))
  (unless (animate-project? value)
    (raise-arguments-error 'raco-animate "a binding whose value is animate-project?"
                           "binding" binding "value" value))
  value)

(define (requested-target)
  (define choices
    (filter values
            (list (and block (project-target-block block))
                  (and section (project-target-section section))
                  (and frame (project-target-frame frame))
                  (and range (project-target-range (car range) (cdr range))))))
  (unless (<= (length choices) 1)
    (raise-user-error 'raco-animate "choose at most one of --section, --block, --frame, and --range"))
  (if (null? choices) (project-target-all) (car choices)))

(cond
  [(equal? arguments '("version"))
   (printf "animate ~a (~a)\n" animate-version animate-stage)]
  [(equal? arguments '("doctor"))
   (for ([line (in-list (doctor-report->lines (collect-doctor-report)))])
     (displayln line))]
  [(equal? arguments '("check-repo"))
   (define report
     (check-repository!))
   (for ([entry (in-list (repository-check-report-checks report))])
     (printf "~a: ~a — ~a\n"
             (repository-check-name entry)
             (if (repository-check-ok? entry) "ok" "failed")
             (repository-check-detail entry)))
   (unless (andmap repository-check-ok?
                   (repository-check-report-checks report))
     (exit 1))]
  [(and (pair? arguments) (equal? (car arguments) "plan")
        (= (length (cdr arguments)) 2))
   (define module-path (cadr arguments))
   (define binding (string->symbol (caddr arguments)))
   (define project
     (dynamic-require module-path binding))
   (unless (animate-project? project)
     (raise-arguments-error
      'raco-animate
      "a binding whose value is animate-project?"
      "binding" binding
      "value" project))
   (write (project-plan->datum (plan-project project)))
   (newline)]
  [(and (pair? arguments) (equal? (car arguments) "check")
        (= (length (cdr arguments)) 2))
   (define project (load-project-argument (cadr arguments) (caddr arguments)))
   (define report (check-project! (plan-project project)))
   (write (hasheq 'ok? (project-check-report-ok? report)
                  'requirements (project-check-report-requirements report)
                  'warnings (project-check-report-warnings report)
                  'failures (project-check-report-failures report)))
   (newline)
   (unless (project-check-report-ok? report) (exit 1))]
  [(and (pair? arguments) (equal? (car arguments) "render")
        (= (length (cdr arguments)) 2))
   (define project (load-project-argument (cadr arguments) (caddr arguments)))
   (define report (render-project! project #:target (requested-target)))
   (write (hasheq 'artifact-paths (project-execution-report-artifact-paths report)
                  'elapsed-milliseconds (project-execution-report-elapsed-milliseconds report)
                  'rendered-frames (project-execution-report-rendered-frames report)
                  'reused-frames (project-execution-report-reused-frames report)))
   (newline)]
  [(and (>= (length arguments) 4) (equal? (car arguments) "cache")
        (member (cadr arguments) '("list" "clear")))
   (define mode (cadr arguments))
   (unless (= (length arguments) 4)
     (raise-user-error 'raco-animate "cache expects list|clear PROJECT.rkt BINDING"))
   (define project (load-project-argument (caddr arguments) (cadddr arguments)))
   (define paths (project-plan-path-plan (plan-project project)))
   (cond
     [(equal? mode "list")
     (write (hasheq 'frames-root (project-path-plan-frames-root paths)
                     'segments-root (project-path-plan-segments-root paths)
                     'formula-root (project-path-plan-formula-root paths)
                     'audio-root (project-path-plan-audio-root paths)
                     'waveform-root (project-path-plan-waveform-root paths)
                     'source-program-root
                     (project-path-plan-cache-domain-root paths 'source-program)))
      (newline)]
     [else
      ;; This is an explicitly requested destructive command. Its exact root
      ;; comes from the normalized project path plan, never a shell glob.  A
      ;; requested domain stays target-specific; omitting it is the explicit
      ;; whole-project-cache operation.
      (define root
        (if cache-domain
            (project-path-plan-cache-domain-root paths cache-domain)
            (cache-spec-root
             (animate-project-cache
              (project-plan-project (plan-project project))))))
      (when (directory-exists? root) (delete-directory/files root))
      (printf "cleared ~a\n" root)])]
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
   (define value (dynamic-require source-path binding))
   (define session
     (if (animate-project? value)
         (open-project-preview value #:target (requested-target))
         (open-program-preview source-path binding #:auto-reload? auto-reload? #:fps fps)))
   (when (and block (not (animate-project? value))) (preview-jump-to-block! session block))
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
   "usage: raco animate version | raco animate doctor | raco animate check-repo | raco animate plan|check PROJECT.rkt binding | raco animate render [--section NAME|--block NAME|--frame N|--range START:END] PROJECT.rkt binding | raco animate cache list PROJECT.rkt binding | raco animate cache clear [--domain formula|frames|segments|audio|waveform|source-program] PROJECT.rkt binding | raco animate preview [--fps N] [--section NAME|--block NAME|--frame N|--range START:END] PROJECT.rkt binding")])

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
