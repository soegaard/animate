#lang racket/base

;;;
;;; Color Expression Tests
;;;

;; Verifies that mix and alpha operations remain pure unresolved values until a
;; future theme-aware rendering boundary resolves them.

(require rackunit
         "../colors.rkt")

(module+ test
  ;; Literal strings are normalized immediately so expressions never retain a
  ;; caller-owned mutable string.
  (define mixed (color-mix "#19c5ce" red-c 1/2))
  (check-true (color-expression? mixed))
  (check-true (color-spec? mixed))
  (check-equal?
   (color-spec->datum mixed)
   '(animate-color-spec 1
                        (mix srgb-linear premultiplied 1/2
                             (rgba 25 197 206 1)
                             (palette red-c))))
  (check-exn #px"require a theme resolver"
             (lambda () (color-spec->rgba-color mixed)))

  ;; Exact endpoints return their normalized source or destination rather than
  ;; wrapping them in an avoidable expression.
  (check-equal? (color-mix "#19c5ce" red-c 0)
                (rgb-color 25 197 206))
  (check-eq? (color-mix aqua-c red-c 1) red-c)
  (check-equal? (color-mix aqua-c red-c 1/2 #:space 'srgb #:alpha-mode 'straight)
                (datum->color-spec
                 '(animate-color-spec 1
                                      (mix srgb straight 1/2
                                           (palette aqua-c)
                                           (palette red-c)))))

  (define replaced (color-with-alpha theme-highlight 1/4))
  (define multiplied (color-opacity replaced 1/2))
  (check-true (color-expression? replaced))
  (check-true (color-expression? multiplied))
  (check-equal?
   (color-spec->datum multiplied)
   '(animate-color-spec 1
                        (alpha multiply 1/2
                               (alpha replace 1/4 (role highlight)))))

  ;; The syntax accepts all named future interpolation policies, but does not
  ;; attempt their numerical evaluation in this pure vocabulary slice.
  (check-true (color-expression?
               (color-mix aqua-c red-c 1/2 #:space 'oklab)))
  (for ([bad (in-list (list -1/10 11/10 +inf.0 -inf.0 +nan.0))])
    (check-exn exn:fail:contract? (lambda () (color-mix aqua-c red-c bad)))
    (check-exn exn:fail:contract? (lambda () (color-with-alpha aqua-c bad)))
    (check-exn exn:fail:contract? (lambda () (color-opacity aqua-c bad))))
  (check-exn exn:fail:contract?
             (lambda () (color-mix aqua-c red-c 1/2 #:space 'lab)))
  (check-exn exn:fail:contract?
             (lambda () (color-mix aqua-c red-c 1/2 #:alpha-mode 'source-over))))
