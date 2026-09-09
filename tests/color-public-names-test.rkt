#lang racket/base

;;;
;;; Color Public Name Tests
;;;

;; Locks down the public animate/colors surface: aqua is the themeable family,
;; names use hyphens, and role conveniences do not shadow Racket's `error`.

(require rackunit
         racket/runtime-path
         "../colors.rkt")

(define-runtime-path colors-module "../colors.rkt")

(module+ test
  (check-not-exn (lambda () (dynamic-require colors-module #f)))
  (for ([missing (in-list '(error teal teal-a teal-c blue_a aqua_c
                            palette-token? role-token?
                            palette-token-key role-token-key))])
    (check-exn exn:fail? (lambda () (dynamic-require colors-module missing))))

  ;; Reserved physical endpoints are literal values, never palette references.
  (check-equal? black (rgb-color 0 0 0))
  (check-equal? white (rgb-color 255 255 255))
  (check-equal? pure-red (rgb-color 255 0 0))
  (check-equal? pure-green (rgb-color 0 255 0))
  (check-equal? pure-blue (rgb-color 0 0 255))
  (check-equal? pure-cyan (rgb-color 0 255 255))
  (check-equal? pure-magenta (rgb-color 255 0 255))
  (check-equal? pure-yellow (rgb-color 255 255 0))
  (for ([literal (in-list (list black white pure-red pure-green pure-blue
                                pure-cyan pure-magenta pure-yellow))])
    (check-true (literal-color-spec? literal))
    (check-false (color-token? literal))))
