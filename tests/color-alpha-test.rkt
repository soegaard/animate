#lang racket/base

;;;
;;; Color Alpha Tests
;;;

(require rackunit
         "../colors.rkt")

(module+ test
  ;; Identity operations do not grow expression trees.
  (check-eq? (color-opacity aqua-c 1) aqua-c)
  (check-equal? (color-with-alpha (rgba-color 1 2 3 1/4) 1/4)
                (rgba-color 1 2 3 1/4))
  (check-equal? (color-opacity (rgba-color 1 2 3 0) 1/2)
                (rgba-color 1 2 3 0))
  (check-equal? (resolve-color (color-with-alpha aqua-c 1/4) animate-light-theme)
                (rgba-color #x19 #xC5 #xCE 1/4))
  (check-equal? (resolve-color (color-opacity (color-with-alpha aqua-c 1/2) 1/2)
                              animate-light-theme)
                (rgba-color #x19 #xC5 #xCE 1/4)))
