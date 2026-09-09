#lang racket/base

;;;
;;; Effectful Theme File Tests
;;;

(require racket/file
         rackunit
         "../colors.rkt"
         "../render.rkt")

(module+ test
  ;; Keep the destination in its own directory so successful transactional
  ;; replacement can prove that it did not leave a sibling temporary file.
  (define directory (make-temporary-file "animate-theme-~a" 'directory))
  (define path (build-path directory "theme.rktd"))
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
     ;; The public writer always uses the portable, canonical spelling rather
     ;; than inheriting a caller's preferences for braces or long booleans.
     (parameterize ([print-pair-curly-braces #t]
                    [print-boolean-long-form #t])
       (write-color-theme! animate-dark-theme path))
     (define canonically-written (load-color-theme! path))
     (check-equal? (color-theme-fingerprint canonically-written)
                   (color-theme-fingerprint animate-dark-theme))
     (check-false (regexp-match? #rx"#false|#true|[{}]"
                                 (file->string path)))
     ;; Serialization happens before the destination is touched. A failed
     ;; replacement must therefore retain the old complete file byte-for-byte.
     (write-color-theme! animate-light-theme path)
     (define original-bytes (file->bytes path))
     (define oversized-name-theme
       (color-theme #:id 'writer-oversized-name
                    #:extends animate-light-theme
                    #:display-name (make-string 65537 #\x)))
     (check-exn exn:fail:contract?
                (lambda () (write-color-theme! oversized-name-theme path)))
     (check-equal? (file->bytes path) original-bytes)
     (check-equal? (color-theme-fingerprint (load-color-theme! path))
                   (color-theme-fingerprint animate-light-theme))
     ;; A successful replacement publishes the new complete file and consumes
     ;; its sibling temporary file.
     (write-color-theme! animate-dark-theme path)
     (check-equal? (color-theme-fingerprint (load-color-theme! path))
                   (color-theme-fingerprint animate-dark-theme))
     (check-equal? (directory-list directory)
                   (list (string->path "theme.rktd")))
     ;; The reader accepts the ordinary alternate spellings produced by
     ;; Racket's writer.  This snapshot contains both long Booleans and curly
     ;; pairs when their parameters are enabled by a caller.
     (parameterize ([print-pair-curly-braces #t]
                    [print-boolean-long-form #t])
       (call-with-output-file
        path
        (lambda (out) (write (theme->datum animate-dark-theme) out))
        #:exists 'truncate/replace))
     (define alternate-written (load-color-theme! path))
     (check-equal? (color-theme-fingerprint alternate-written)
                   (color-theme-fingerprint animate-dark-theme))
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
                (lambda () (load-color-theme! path)))
     ;; A Boolean spelling must end at a real datum delimiter. Do not mistake
     ;; dispatch-like tokens for the accepted long Boolean forms.
     (call-with-output-file
      path
      (lambda (out) (display "#trueX" out))
      #:exists 'truncate/replace)
     (check-exn #px"reader dispatch forms"
                (lambda () (load-color-theme! path)))
     ;; The scanner tracks actual delimiter kinds, rather than merely a depth
     ;; counter, and rejects malformed input before the general reader sees it.
     (call-with-output-file
      path
      (lambda (out) (display "({])" out))
      #:exists 'truncate/replace)
     (check-exn #px"matching list delimiters"
                (lambda () (load-color-theme! path)))
     ;; Curly pairs are a normal reader spelling and consume the same bounded
     ;; nesting budget as parentheses and square brackets.
     (call-with-output-file
      path
      (lambda (out)
        (for ([ignored (in-range 129)]) (display "{" out))
        (display "theme" out)
        (for ([ignored (in-range 129)]) (display "}" out)))
      #:exists 'truncate/replace)
     (check-exn #px"reader-depth"
                (lambda () (load-color-theme! path))))
   (lambda () (when (directory-exists? directory) (delete-directory/files directory)))))
