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
     ;; `write` quotes reader-sensitive but portable role symbols with bars.
     ;; The bounded scanner must treat every delimiter in that spelling as
     ;; symbol text and leave the ordinary reader to recover the same datum.
     (define unusual-role-keys
       (map string->symbol
            '("role with space" "role;semicolon" "role#hash" "role(paren)"
              "role|bar" "role\\slash" "роль-色")))
     (define unusual-theme
       (color-theme #:id 'quoted-role-theme #:extends animate-light-theme
                    #:roles
                    (for/hash ([key (in-list unusual-role-keys)])
                      (values key theme-accent))))
     (call-with-output-file
      path
      (lambda (out) (write (theme->datum unusual-theme) out))
      #:exists 'truncate/replace)
     (define unusual-loaded (load-color-theme! path))
     (for ([key (in-list unusual-role-keys)])
       (check-equal? (theme-ref unusual-loaded key) theme-accent))
     ;; The compact grammar has no reader abbreviations or dotted pairs.
     (call-with-output-file path
       (lambda (out) (display "'(animate-color-theme)" out))
       #:exists 'truncate/replace)
     (check-exn exn:fail? (lambda () (load-color-theme! path)))
     (call-with-output-file path
       (lambda (out) (display "(animate-color-theme . 1)" out))
       #:exists 'truncate/replace)
     (check-exn exn:fail? (lambda () (load-color-theme! path)))
     ;; Reader graph syntax is not part of the data format, irrespective of
     ;; ambient reader parameters in a caller.
     (call-with-output-file
     path
      (lambda (out) (display "#0=(animate-color-theme 1)" out))
      #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (load-color-theme! path)))
     ;; Compact reader-dispatch forms can request disproportionate allocation;
     ;; the declarative file grammar rejects them before `read` sees a vector.
     (call-with-output-file
      path
      (lambda (out) (display "#1000000(0)" out))
      #:exists 'truncate/replace)
     (check-exn exn:fail?
                (lambda () (load-color-theme! path))))
   (lambda () (when (file-exists? path) (delete-file path)))))
