#lang racket/base
(require racket/list)

;; Small helpers for the public project execution report's artifact-path hash.
;; Keep the gallery and generic slide runner aligned with animate/project instead
;; of treating the report as a positional list.
(provide project-primary-artifact-path
         project-artifact-path-list)

(define (check-artifact-hash who artifacts)
  (unless (hash? artifacts)
    (raise-argument-error who "hash? from project-execution-report-artifact-paths" artifacts)))

(define (project-primary-artifact-path artifacts)
  (check-artifact-hash 'project-primary-artifact-path artifacts)
  (define primary (hash-ref artifacts 'primary #f))
  (unless (path-string? primary)
    (raise-arguments-error 'project-primary-artifact-path
                           "a project report containing a primary artifact path"
                           "artifact-paths" artifacts))
  primary)

(define (project-artifact-path-list artifacts)
  (check-artifact-hash 'project-artifact-path-list artifacts)
  (define result '())
  (define (add! value)
    (cond
      [(path-string? value) (set! result (append result (list value)))]
      [(list? value) (for-each add! value)]
      [else (void)]))
  ;; Prefer the documented semantic keys and avoid exposing hash iteration order.
  (for ([key (in-list '(primary frame-sequence frames))])
    (when (hash-has-key? artifacts key) (add! (hash-ref artifacts key))))
  (remove-duplicates result equal?))
