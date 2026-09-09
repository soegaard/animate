#lang racket/base

;;;
;;; Color Theme Fingerprint Tests
;;;

;; Confirms appearance identity is derived from canonical resolved content, not
;; hash insertion order, names, or provenance text.

(require rackunit
         "../colors.rkt")

(module+ test
  (define ordered
    (hash 'accent aqua-d 'foreground gray-e))
  (define reversed
    (let ([result (make-hash)])
      (hash-set! result 'foreground gray-e)
      (hash-set! result 'accent aqua-d)
      result))
  (define first
    (color-theme #:id 'same-content
                 #:display-name "First display name"
                 #:extends animate-light-theme
                 #:roles ordered
                 #:provenance "first provenance"))
  (define second
    (color-theme #:id 'same-content
                 #:display-name "Another display name"
                 #:extends animate-light-theme
                 #:roles reversed
                 #:provenance "another provenance"))
  (check-equal? (color-theme-fingerprint first)
                (color-theme-fingerprint second))
  (define changed
    (color-theme #:id 'same-content
                 #:extends animate-light-theme
                 #:roles (hash 'accent red-d)))
  (check-false (equal? (color-theme-fingerprint first)
                       (color-theme-fingerprint changed)))
  (check-false (equal? (color-theme-fingerprint animate-light-theme)
                       (color-theme-fingerprint animate-dark-theme))))
