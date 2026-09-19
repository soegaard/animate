#lang racket/base
(require rackunit racket/file racket/runtime-path
         (only-in scribble/core nested-flow?)
         "../private/complete-examples.rkt")
(define-runtime-path root "../..")

(module+ test
  (check-equal? (length complete-example-entries) 8)
  (check-equal? (hash-ref (complete-example-ref "moving-circle") 'title)
                "A moving circle")
  (check-exn exn:fail? (lambda () (complete-example-ref "not-an-example")))
  (check-equal? (select-complete-frames '(a b c d e) '(0 2 4)) '(a c e))
  (check-equal? (select-complete-frames '(a) '(0)) '(a))
  (for ([selection (in-list '(() (1 0) (0 0) (-1) (5) (0 2.0) (0 1)))])
    (check-exn exn:fail?
               (lambda () (select-complete-frames '(a b c d e) selection))))
  ;; The displayed source is the real file, with no stripped comments or
  ;; independently maintained transcription.
  (for* ([entry (in-list complete-example-entries)]
          [source (in-list (hash-ref entry 'sources))])
    (check-equal? (complete-source-text source)
                  (file->string (build-path root source))))
  (check-exn exn:fail? (lambda () (complete-source-text "../outside.rkt")))

  ;; CE1.1: the helper's runtime path contains ../.. before normalization.
  ;; Source lookup must use that normalized module-relative root, not the
  ;; caller's working directory. Recheck all eleven source listings elsewhere.
  (test-case "source listings are independent of the working directory"
    (define expected
      (for*/list ([entry (in-list complete-example-entries)]
                  [source (in-list (hash-ref entry 'sources))])
        (cons source (file->string (build-path root source)))))
    (parameterize ([current-directory (find-system-path 'temp-dir)])
      (for ([source-and-text (in-list expected)])
        (check-equal? (complete-source-text (car source-and-text))
                      (cdr source-and-text)
                      (car source-and-text)))))

  ;; The same root is used by the separate capture-path check. Construct every
  ;; registered stored-frame strip, without running an animation renderer.
  (test-case "stored-frame strips use the normalized repository root"
    (parameterize ([current-directory (find-system-path 'temp-dir)])
      (for* ([entry (in-list complete-example-entries)]
              [strip (in-list (hash-ref entry 'strips))])
        (check-pred nested-flow?
                    (complete-frames (hash-ref entry 'id) (hash-ref strip 'id))
                    (format "~a/~a" (hash-ref entry 'id) (hash-ref strip 'id)))))))
