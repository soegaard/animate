#lang racket/base

;; Presentation only: read real source files and previously captured frames.
;; Never require an example module, a GUI, a typesetter, or an Animate renderer.
(require (for-syntax racket/base)
         racket/file racket/list racket/path racket/runtime-path racket/string
         json
         (only-in compiler/cm-accomplice register-external-file)
         scribble/manual
         (only-in scribble/core make-style)
         (only-in scribble/html-properties css-addition)
         (only-in scribble/latex-properties tex-addition)
         "frame-style.rkt")
(provide complete-source complete-source-text complete-frames complete-command
         complete-requirements complete-example-entries complete-example-ref
         select-complete-frames)

;; A runtime path can be complete without being in simple form. In particular,
;; "../.." is retained by define-runtime-path. Both source and frame containment
;; checks below use find-relative-path, which requires a simplified base.
(define-runtime-path repository-root/raw "../..")
(define repository-root (simple-form-path repository-root/raw))
(define-runtime-path entries-path "../complete-examples/entries.json")
(define-runtime-path source-css "complete-examples.css")
(define-runtime-path source-tex "complete-examples.tex")
(define source-style
  (make-style "AnimCompleteSource"
              (list (css-addition source-css) (tex-addition source-tex))))

(define (read-data path)
  (register-external-file (path->complete-path path))
  (call-with-input-file path read-json))
(define catalogue (read-data entries-path))
(unless (equal? (hash-ref catalogue 'schema #f) "animate-complete-examples-v1")
  (raise-user-error 'complete-examples "unknown complete-example catalogue schema"))
(define complete-example-entries (hash-ref catalogue 'entries))

(define (complete-example-ref id)
  (or (findf (lambda (entry) (equal? id (hash-ref entry 'id)))
             complete-example-entries)
      (raise-argument-error 'complete-example-ref "known complete-example ID" id)))

(define (inside-repository name)
  (unless (and (string? name) (relative-path? name)
               (not (regexp-match? #px"(^|/)\\.\\.(/|$)" name)))
    (raise-argument-error 'complete-examples "repository-relative path without .." name))
  (define path (simplify-path (build-path repository-root name)))
  (define relative (find-relative-path repository-root path))
  (unless (and (relative-path? relative)
               (not (memq 'up (explode-path relative))))
    (raise-argument-error 'complete-examples "path inside the repository" name))
  path)

(define (complete-source-text name)
  (unless (for/or ([entry (in-list complete-example-entries)])
            (member name (hash-ref entry 'sources)))
    (raise-argument-error 'complete-source "source registered by a complete example" name))
  (define path (inside-repository name))
  (unless (file-exists? path)
    (raise-user-error 'complete-source "missing source file: ~a" name))
  (register-external-file path)
  ;; Keep #lang, require, provide, comments, and every definition. No extraction
  ;; markers are removed and no second copy of the program is maintained here.
  (file->string path))

;; Capture the calling chapter's for-label context, not this helper's context.
;; codeblock0 preserves the source text and uses DrRacket's syntax coloring.
(define-syntax (complete-source stx)
  (syntax-case stx ()
    [(_ name) #'(complete-source/proc name (quote-syntax name))]))
(define (complete-source/proc name context)
  (nested #:style source-style
          (filebox (tt name)
                   (codeblock0 #:context context #:expand #f
                               (complete-source-text name)))))

(define (select-complete-frames frames indices)
  (unless (and (list? frames) (pair? frames))
    (raise-argument-error 'select-complete-frames "nonempty frame list" frames))
  (unless (and (list? indices) (pair? indices)
               (memq (length indices) '(1 3 5))
               (andmap exact-nonnegative-integer? indices)
               (= (length indices) (length (remove-duplicates indices)))
               (equal? indices (sort indices <))
               (andmap (lambda (i) (< i (length frames))) indices))
    (raise-argument-error 'select-complete-frames
                          "increasing, distinct, in-range frame indices" indices))
  (map (lambda (i) (list-ref frames i)) indices))

(define (complete-frames id strip-id #:select [indices #f] #:columns [columns #f])
  (define entry (complete-example-ref id))
  (define spec
    (or (findf (lambda (s) (equal? strip-id (hash-ref s 'id)))
               (hash-ref entry 'strips))
        (raise-argument-error 'complete-frames "known strip ID for this example" strip-id)))
  (define family
    (hash-ref (hash-ref catalogue 'families)
              (string->symbol (hash-ref spec 'family))))
  (define manifest (inside-repository (hash-ref family 'manifest)))
  (unless (file-exists? manifest)
    (raise-user-error 'complete-frames "missing capture manifest: ~a" manifest))
  (define data (read-data manifest))
  (unless (equal? (hash-ref data 'schema #f) (hash-ref family 'schema))
    (raise-user-error 'complete-frames "unexpected capture schema in ~a" manifest))
  (define key (string->symbol (hash-ref spec 'key)))
  (define strip (hash-ref (hash-ref data 'strips) key))
  (define selected
    (select-complete-frames (hash-ref strip 'frames)
                            (or indices (hash-ref spec 'select))))
  (define frames
    (for/list ([frame (in-list selected)])
      (define path (simplify-path (build-path (path-only manifest) (hash-ref frame 'file))))
      (define relative (find-relative-path repository-root path))
      (unless (and (relative-path? relative) (not (memq 'up (explode-path relative))))
        (raise-user-error 'complete-frames "capture path leaves repository: ~a" path))
      (register-external-file path)
      (manual-frame path (hash-ref frame 'width) (hash-ref frame 'height)
                    (hash-ref frame 'caption))))
  (manual-frame-strip frames #:columns columns
                      #:label (format "~a: ~a" (hash-ref entry 'title) strip-id)
                      #:note (hash-ref spec 'note)))

(define (complete-requirements id)
  (define entry (complete-example-ref id))
  (para (bold "Requirements: ")
        (string-join (hash-ref entry 'requirements) "; ") "."))

(define (complete-command id run-id)
  (define entry (complete-example-ref id))
  (define run
    (or (findf (lambda (r) (equal? run-id (hash-ref r 'id)))
               (hash-ref entry 'runs))
        (raise-argument-error 'complete-command "known run ID for this example" run-id)))
  (define output (hash-ref run 'output #f))
  (list (verbatim (hash-ref run 'command))
        (para (hash-ref run 'note))
        (if (string? output)
            (para "Expected output: " (filepath output) ".")
            (para "This command opens a preview; it does not write a movie."))))
