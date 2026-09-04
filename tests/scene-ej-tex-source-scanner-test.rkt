#lang racket/base

;;;
;;; SCENE-EJ Conservative TeX Source Scanner Tests
;;;

(require rackunit
         (only-in "../private/source-document.rkt" source-span)
         "../private/tex-source-scanner.rkt")

(module+ test
  (define source "{a+b} + \\alpha % hidden\nx^2")
  (define scan (scan-tex-source source))
  (check-equal? (tex-source-scan-text scan) source)
  (check-equal? (tex-source-scan-diagnostics scan) '())

  ;; Boundaries are character-indexed.  The scanner permits wrapping the whole
  ;; control word `\\alpha`, but never a range starting in its middle.
  (check-true (tex-source-boundary-token-boundary?
               (tex-source-boundary-at scan 8)))
  (check-false (tex-source-boundary-token-boundary?
                (tex-source-boundary-at scan 9)))
  (check-true (tex-source-boundary-token-boundary?
               (tex-source-boundary-at scan 14)))
  (check-equal? (tex-source-boundary-brace-depth
                 (tex-source-boundary-at scan 1))
                1)

  ;; A span may be safely nested within ordinary TeX braces when its start and
  ;; end have the same brace depth.  Partial brace ranges are rejected.
  (check-true (tex-source-span-safe? scan (source-span 1 4))) ; a+b
  (check-true (tex-source-span-safe? scan (source-span 8 14))) ; \alpha
  (check-true (tex-source-span-safe? scan (source-span 24 27))) ; x^2
  (check-false (tex-source-span-safe? scan (source-span 0 2))) ; {a
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 0 2))
   "span crosses an unmatched TeX brace boundary")

  (check-false (tex-source-span-safe? scan (source-span 9 14))) ; alpha
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 9 14))
   "span starts inside a TeX token at source index 9")

  ;; Comments are never a safe wrapper region: a generated closing wrapper
  ;; could otherwise be swallowed by TeX's end-of-line comment behavior.
  (check-false (tex-source-span-safe? scan (source-span 15 24)))
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 15 24))
   "span begins or ends in a TeX comment")
  (check-false (tex-source-span-safe? scan (source-span 0 27)))
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 0 27))
   "span crosses a TeX comment")

  ;; Whitespace and script syntax alone do not designate visible-producing
  ;; material, even though their endpoints are ordinary lexical boundaries.
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 5 6))
   "span contains no visible-producing source")
  (check-equal?
   (tex-source-span-diagnostic scan (source-span 25 26))
   "span contains no visible-producing source")

  ;; Escaped braces are TeX control symbols, not grouping braces.
  (define escaped (scan-tex-source "\\{x\\}"))
  (check-equal? (tex-source-scan-diagnostics escaped) '())
  (check-true
   (tex-source-span-safe? escaped (source-span 0 5)))

  ;; A globally malformed source gets an actionable diagnostic instead of a
  ;; possibly unsafe partial declaration.
  (define unbalanced (scan-tex-source "{x"))
  (check-equal?
   (tex-source-span-diagnostic unbalanced (source-span 1 2))
   "source ends with 1 unmatched opening brace")
  (check-exn exn:fail?
             (lambda ()
               (tex-source-span-diagnostic scan (source-span 0 28)))))
