#lang racket/base

;;;
;;; Gallery Inspection and Output Preflight Tests
;;;
;; Invokes the real example CLI in independent Racket processes. Inspection and
;; rejected requests must stop before native loading, TeX, or output mutation.

;;;
;;; Imports and Exports
;;;
(require (for-syntax racket/base)
         (only-in racket/runtime-path define-runtime-path)
         (only-in racket/file make-temporary-file delete-directory/files make-directory* file->string)
         (only-in racket/system system*/exit-code)
         "check.rkt")
(provide run-gallery-cli-tests)

; gallery-entry-module : path?
;;   Locates the actual command entry independently of the current working directory.
(define-runtime-path gallery-entry-module "../examples/gallery.rkt")

; run-gallery-cli-tests : -> void?
;;   Runs real command parsing and verifies that pure/invalid modes do not render.
(define (run-gallery-cli-tests)
  (test-group "gallery: real CLI inspection and pre-output rejection"
    (lambda ()
      (define root (make-temporary-file "gallery-cli-~a" 'directory))
      (dynamic-wind void
        (lambda ()
          (define executable (find-executable-path (find-system-path 'exec-file)))
          (define output (build-path root "uncreated"))
          (define preparation-log (build-path root "prepare.txt"))
          (define typeset-log (build-path root "typeset.txt"))
          (define environment (environment-variables-copy (current-environment-variables)))
          (environment-variables-set! environment #"ANIMATE_MATH_PREPARATION_EVENT_LOG" (path->bytes preparation-log))
          (environment-variables-set! environment #"ANIMATE_MATH_TYPESET_EVENT_LOG" (path->bytes typeset-log))
          (define (invoke arguments expected-status pattern)
            (define out (open-output-string))
            (define err (open-output-string))
            (define status
              (parameterize ([current-output-port out] [current-error-port err]
                             [current-environment-variables environment])
                (apply system*/exit-code executable gallery-entry-module arguments)))
            (define message (string-append (get-output-string out) (get-output-string err)))
            (check-equal status expected-status (list 'cli-status arguments))
            (check-true (regexp-match? pattern message) (list 'cli-message arguments message))
            (check-false (directory-exists? output) 'inspection-created-output)
            (check-false (file-exists? preparation-log) 'inspection-prepared)
            (check-false (file-exists? typeset-log) 'inspection-typeset))
          (invoke '("--list-plates") 0 #rx"held-arithmetic.*held")
          (invoke '("--list-chapters") 0 #rx"moves")
          (invoke (list "--chapter" "moves" "--describe" output) 0 #rx"4 plates")
          (invoke (list "--plate" "nested-moves" "--steps" output) 0 #rx"isolate-x")
          (invoke (list "--plate" "missing" "--describe" output) 1 #rx"unknown plate")
          (invoke '("--plate" "history" "--plate" "history" "--describe") 1 #rx"unique")
          (invoke '("--chapter" "held" "--plate" "history" "--describe") 1 #rx"not in")
          (invoke '("--fps" "0" "--describe") 1 #rx"positive integer")
          (invoke '("--worker-mode" "bogus" "--describe") 1 #rx"unknown worker mode")
          (invoke '("--review-stills" "--mp4" "unused.mp4") 1 #rx"review uses a new directory")
          (invoke '("--review-stills" "--supersample" "2") 1 #rx"review uses a new directory")
          (define existing (build-path root "existing"))
          (make-directory* existing)
          (define sentinel (build-path existing "notes.txt"))
          (call-with-output-file sentinel (lambda (out) (display "preserve this file" out)))
          (invoke (list "--replace" existing) 1 #rx"destination exists")
          (call-with-output-file (build-path existing "gallery-index.json")
            (lambda (out) (display "{\"schema\":\"animate-math-gallery-index-v1\"}" out)))
          (invoke (list "--replace" existing) 1 #rx"unowned data")
          (check-equal (file->string sentinel) "preserve this file" 'unowned-output-survives))
        (lambda () (delete-directory/files root))))))
