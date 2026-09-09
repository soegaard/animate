#lang racket/base

;;;
;;; Effectful Theme File Tests
;;;

(require racket/file
         rackunit
         "../colors.rkt"
         "../render.rkt")

(module+ test
  (define path (make-temporary-file "animate-theme-~a.rktd"))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file
      path
      (lambda (out) (write (theme->datum animate-dark-theme) out))
      #:exists 'truncate/replace)
     (define loaded (load-color-theme! path))
     (check-equal? (color-theme-fingerprint loaded)
                   (color-theme-fingerprint animate-dark-theme))
     (check-true (regexp-match? #rx"sha1"
                                (color-theme-provenance loaded)))
     ;; The effectful boundary feeds the datum decoder, so malformed input is
     ;; rejected without evaluating any file content.
     (call-with-output-file
      path
      (lambda (out) (write '(not-a-theme) out))
      #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (load-color-theme! path)))
     ;; A data file is one bounded snapshot, not a stream of declarations.
     ;; The reader accepts comments/whitespace but must reject a trailing form.
     (call-with-output-file
      path
      (lambda (out)
        (write (theme->datum animate-dark-theme) out)
        (newline out)
        (write '(trailing-datum) out))
      #:exists 'truncate/replace)
     (check-exn #px"exactly one theme datum"
                (lambda () (load-color-theme! path)))
     ;; Reader graph syntax is not part of the data format, irrespective of
     ;; ambient reader parameters in a caller.
     (call-with-output-file
      path
      (lambda (out) (display "#0=(animate-color-theme 1)" out))
      #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (load-color-theme! path))))
   (lambda () (when (file-exists? path) (delete-file path)))))
