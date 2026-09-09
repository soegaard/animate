#lang racket/base

;;;
;;; Public Color Serializer API Tests
;;;

(require rackunit
         "../colors.rkt")

(define (check-no-keywords procedure)
  (define-values (required allowed) (procedure-keywords procedure))
  (check-equal? required '())
  (check-equal? allowed '()))

(define absent (gensym 'absent))

(define (public-binding name)
  (dynamic-require "../colors.rkt" name (lambda () absent)))

(module+ test
  ;; Ordinary public calls retain their complete, versioned round trips.
  (check-equal? (datum->color-spec (color-spec->datum theme-accent))
                theme-accent)
  (check-equal? (datum->palette (palette->datum animate-palette))
                animate-palette)
  (check-equal? (datum->theme (theme->datum animate-light-theme))
                animate-light-theme)

  ;; Shared serialization accounting belongs to private composition helpers.
  ;; Public serializers do not accept an escape-hatch keyword.
  (check-no-keywords color-spec->datum)
  (check-no-keywords palette->datum)
  (check-no-keywords theme->datum)
  (check-eq? (public-binding 'color-spec->datum/budget) absent)
  (check-eq? (public-binding 'palette->datum/budget) absent))
