#lang racket/base

;;;
;;; Scientific Color Scale Tests
;;;

(require rackunit
         "../colors.rkt")

(module+ test
  (define sequential
    (sequential-color-scale #:minimum 10 #:maximum 20
                            #:low aqua-c #:high gold-c
                            #:missing theme-muted))
  (check-true (scientific-color-scale? sequential))
  (check-eq? (scientific-color-scale-kind sequential) 'sequential)
  (check-equal? (scientific-color-scale-minimum sequential) 10)
  (check-equal? (scientific-color-scale-maximum sequential) 20)
  (check-false (scientific-color-scale-midpoint sequential))
  (check-eq? (scientific-color-scale-at sequential 10) aqua-c)
  (check-eq? (scientific-color-scale-at sequential 20) gold-c)
  (check-eq? (scientific-color-scale-at sequential +nan.0) theme-muted)

  (define diverging
    (diverging-color-scale #:minimum -2 #:maximum 6 #:midpoint 0
                           #:low aqua-c #:middle gray-c #:high red-c
                           #:outside 'error))
  (check-eq? (scientific-color-scale-kind diverging) 'diverging)
  (check-equal? (scientific-color-scale-midpoint diverging) 0)
  (check-eq? (scientific-color-scale-at diverging 0) gray-c)
  (check-exn exn:fail:contract?
             (lambda () (scientific-color-scale-at diverging -3)))
  (check-exn exn:fail:contract?
             (lambda ()
               (diverging-color-scale #:minimum 0 #:maximum 1 #:midpoint 2))))
