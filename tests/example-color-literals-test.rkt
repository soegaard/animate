#lang racket/base

;; Every direct color literal in a shipped source example must be accepted by
;; Animate's deterministic color vocabulary. This intentionally checks source
;; text rather than a platform drawing API, so a missing name fails before a
;; GUI backend happens to interpret it differently on another machine.

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         "../private/color-style.rkt")

(define-runtime-path examples-directory "../examples")

(define color-keyword-literal-rx
  #px"#:(?:fill|stroke|color|background|border-color)\\s*\"([^\"]*)\"")

(define (example-source-paths)
  (sort
   (for/list ([path (in-list (find-files file-exists? examples-directory))]
              #:when (member (path-get-extension path) '(#".rkt" #".rhombus")))
     path)
   path<?))

(define (source-color-literals path)
  (for/list ([match (in-list (regexp-match* color-keyword-literal-rx
                                             (file->string path)
                                             #:match-select cadr))])
    match))

(module+ test
  (define paths (example-source-paths))
  (check-true (pair? paths))
  (for* ([path (in-list paths)]
         [literal (in-list (source-color-literals path))])
    (check-not-exn
     (lambda () (color-spec->rgba-color literal))
     (format "~a uses unsupported literal color ~s" path literal))))
