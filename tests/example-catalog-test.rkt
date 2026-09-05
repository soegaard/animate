#lang racket/base

;;;
;;; SCENE-EM Canonical Example Catalogue Tests
;;;

(require rackunit
         racket/file
         racket/list
         racket/runtime-path
         racket/string
         "../private/example-catalog.rkt")

(define-runtime-path repository-root "..")
(define-runtime-path readme-path "../README.md")

(define generated-readme-start "<!-- BEGIN GENERATED: canonical examples -->")
(define generated-readme-end "<!-- END GENERATED: canonical examples -->")

(module+ test
  (define entries canonical-example-catalog)
  (define ids (map example-entry-id entries))
  (check-equal? (length ids) (length (remove-duplicates ids)))
  (for ([entry (in-list entries)])
    (check-true (symbol? (example-entry-id entry)))
    (check-true (string? (example-entry-title entry)))
    (check-true (pair? (example-entry-categories entry)))
    (check-true (pair? (example-entry-requirements entry)))
    (check-true (positive? (example-entry-expected-duration entry)))
    (check-true
     (file-exists?
      (build-path repository-root (example-entry-source entry))))
    (check-eq? (example-entry-by-id (example-entry-id entry)) entry)
    (check-true
     (regexp-match?
      #rx"^\\[.+\\]\\(.+\\)$"
      (example-entry->markdown-link entry))))
  (check-false (example-entry-by-id 'not-a-canonical-example))
  ;; README is a checked-in rendering of the one catalogue, not an independent
  ;; hand-curated subset.  Its exact block is deliberately easy to regenerate
  ;; from `example-catalog->readme-section` when an entry changes.
  (define expected-readme-block
    (string-append generated-readme-start "\n"
                   (example-catalog->readme-section entries)
                   generated-readme-end))
  (define readme-text (file->string readme-path))
  (check-true (string-contains? readme-text expected-readme-block))
  (check-equal?
   (length (regexp-match* (regexp (regexp-quote generated-readme-start))
                          readme-text))
   1))
