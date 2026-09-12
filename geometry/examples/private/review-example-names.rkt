#lang racket/base
(require "library-example-names.rkt")
(provide review-example-names select-review-examples)

;; Explicit registry: helpers and command-line scripts are never treated as
;; example movies by a filesystem glob. All names export make-demo-timeline.
(define review-example-names
  (append '("equilateral-triangle" "perpendicular-bisector" "perpendicular-through-point")
          library-example-names '("transformations" "semantic-labels" "gallery")))
(define (select-review-examples selection)
  (cond [(eq? selection 'all) review-example-names]
        [(eq? selection 'library) library-example-names]
        [(and (string? selection) (member selection review-example-names)) (list selection)]
        [else (raise-arguments-error 'review-examples
                 "choose --all, --library, or --example NAME (use --list for names)"
                 "selection" selection)]))
