#lang racket/base

;;;
;;; Inline TeX Content Tests
;;;

;; Exercises the pure parser and normalized content model without loading Pict
;; or the external TeX backend.

(require rackunit
         "../../text-content.rkt")

(provide tests)

(define (run-signature value)
  (for/list ([run (in-list (text-content-runs value))])
    (list (text-run-kind run)
          (text-run-content run)
          (text-run-start run)
          (text-run-end run))))

(define tests
  (test-suite
   "pure inline TeX content"
   (test-case "all documented delimiters preserve source order"
     (check-equal?
      (run-signature
       (parse-inline-text "At $x_0$, \\(y^2\\), $$z$$, and \\[w\\]."))
      '((text "At " 0 3)
        (inline-math "x_0" 3 8)
        (text ", " 8 10)
        (inline-math "y^2" 10 17)
        (text ", " 17 19)
        (display-math "z" 19 24)
        (text ", and " 24 30)
        (display-math "w" 30 35)
        (text "." 35 36))))
   (test-case "literal dollars and TeX comments do not terminate math"
     (define parsed
       (parse-inline-text "Price: \\$5; $x % $ ignored\n+ y$"))
     (check-equal?
      (map (lambda (run) (list (text-run-kind run) (text-run-content run)))
           (text-content-runs parsed))
      '((text "Price: $5; ")
        (inline-math "x % $ ignored\n+ y"))))
   (test-case "adjacent math, escape parity, Unicode prose, and blank lines preserve runs"
     (check-equal?
      (map (lambda (run) (list (text-run-kind run) (text-run-content run)))
           (text-content-runs (parse-inline-text "æøå $x$$y$\n\n\\\\$z$")))
      '((text "æøå ")
        (inline-math "x")
        (inline-math "y")
        (hard-break "")
        (hard-break "")
        (text "\\")
        (inline-math "z"))))
   (test-case "large ordinary prose remains a linear scanner input"
     (define prose (make-string 50000 #\a))
     (define parsed (parse-inline-text (string-append prose "$x_0$" prose)))
     (check-equal? (map text-run-kind (text-content-runs parsed))
                   '(text inline-math text))
     (check-equal? (text-run-content (cadr (text-content-runs parsed))) "x_0"))
   (test-case "explicit construction leaves string pieces literal"
     (define content
       (inline-text "Write $x_0$ literally, then "
                    (tex-span "x_0" #:plain "x zero")
                    "."
                    #:plain "Write x zero literally, then x zero."))
     (check-equal?
      (map (lambda (run) (list (text-run-kind run) (text-run-content run)))
           (text-content-runs content))
      '((text "Write $x_0$ literally, then ")
        (inline-math "x_0")
        (text ".")))
     (check-equal? (text-content->plain content)
                   "Write x zero literally, then x zero."))
   (test-case "literal wrapper disables markup"
     (define content (literal-text "Price: $5; $x_0$"))
     (check-equal?
      (map text-run-kind (text-content-runs content))
      '(text))
     (check-equal? (text-content->plain content) "Price: $5; $x_0$"))
   (test-case "unclosed, empty, mismatched, and nested math are errors"
     (for ([source (in-list '("At $x_0"
                               "$$"
                               "$x\\)"
                               "$x \\( y \\)$"))])
       (check-exn exn:fail:inline-tex?
                  (lambda () (parse-inline-text source)))))))

(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests))
    (error 'inline-tex-content-test "failed")))
