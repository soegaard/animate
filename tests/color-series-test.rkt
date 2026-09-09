#lang racket/base

;;;
;;; Categorical Series Tests
;;;

(require rackunit
         "../colors.rkt")

(module+ test
  ;; A category is an immutable semantic index, not a color chosen by draw
  ;; order or a mutable process-global counter.
  (define fourth (series-color 3))
  (check-true (color-token? fourth))
  (check-true (series-color? fourth))
  (check-eq? (color-token-kind fourth) 'series)
  (check-equal? (series-color-index fourth) 3)
  (check-exn exn:fail:contract? (lambda () (series-color -1)))

  ;; Built-in series are complete, and out-of-range indexes wrap explicitly.
  (check-equal? (length (theme-series animate-light-theme)) 8)
  (check-equal? (resolve-color (series-color 0) animate-light-theme)
                (car (theme-series animate-light-theme)))
  (check-equal? (resolve-color (series-color 11) animate-light-theme)
                (list-ref (theme-series animate-light-theme) 3))

  ;; The same authored category resolves through each immutable theme.
  (check-not-equal? (resolve-color (series-color 0) animate-light-theme)
                    (resolve-color (series-color 0) animate-dark-theme))
  (check-equal? (datum->color-spec (color-spec->datum (series-color 11)))
                (series-color 11))

  ;; A malformed custom theme cannot silently pick an arbitrary fallback.
  (define no-series
    (color-theme #:id 'no-series #:extends animate-light-theme #:series '()))
  (check-exn #px"nonempty categorical series"
             (lambda () (resolve-color (series-color 0) no-series))))
