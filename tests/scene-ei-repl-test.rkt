#lang racket/base

;; SCENE-EI-3: the embedded REPL evaluates against a session namespace, routes
;; edits through transactions, and receives replacement source exports on reload.

(require rackunit
         racket/file
         "../main.rkt"
         "../preview.rkt")

(define (write-program! path debug-value)
  (call-with-output-file
   path #:exists 'truncate/replace
   (lambda (out)
     (display "#lang racket/base\n(require animate animate/authoring)\n" out)
     (fprintf out "(define debug-value ~a)~n" debug-value)
     (display "(define-scene-program repl-program #:initial (make-scene)\n" out)
     (display "  (scene-block setup (scene) (scene-wait scene 1)))\n" out)
     (display "(provide repl-program debug-value)\n" out))))

(module+ test
  (define temporary-directory (simplify-path (build-path (current-directory) ".." "tmp")))
  (make-directory* temporary-directory)
  (define source-path
    (make-temporary-file "scene-ei-repl-~a.rkt" #f temporary-directory))
  (dynamic-wind
    void
    (lambda ()
      (write-program! source-path 40)
      (define session
        (open-program-preview-controller
         source-path 'repl-program #:fps 2 #:prefetch 0
         #:producer (lambda (_document _sample _spec _cancellation-token) 'bitmap)
         #:byte-size (lambda (_bitmap) 1)))
      (define repl (open-preview-repl! session))
      (check-true (preview-repl-open? repl))
      (check-equal? (preview-repl-evaluate-string! repl "debug-value") 40)
      (check-equal? (preview-repl-evaluate-string! repl "(+ 2 3)") 5)
      (void (preview-repl-evaluate-string! repl "(wait! 1)"))
      (check-equal? (scene-duration (preview-edit-scene session)) 2)

      ;; Running reload from the REPL thread itself must not deadlock. The
      ;; user namespace is atomically replaced, so its exported debug value is
      ;; the new generation rather than a stale top-level binding.
      (write-program! source-path 41)
      (void (preview-repl-evaluate-string! repl "(reload!)"))
      (check-equal? (preview-repl-evaluate-string! repl "debug-value") 41)
      (check-equal? (scene-duration (preview-edit-scene session)) 1)
      (close-preview-repl! repl)
      (check-false (preview-repl-open? repl))
      (preview-close! session))
    (lambda ()
      (when (file-exists? source-path) (delete-file source-path)))))
